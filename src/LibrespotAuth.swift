//
//  LibrespotAuth.swift
//  LibrespotSwift
//
//  Created by Luis Finke on 3/9/25.
//

import Foundation

@objc
public class LibrespotAuth: NSObject {
	typealias RefreshCompletion = (onResolve: (_ renewed: Bool) -> Void, onReject: (_ error: LibrespotError) -> Void);

	var sessionUserDefaultsKey: String?
	var clientID: String?
	var tokenRefreshURL: URL?
	public private(set) var session: LibrespotSession?
	
	var isLoggedIn: Bool {
		return session != nil;
	}
	
	var isSessionValid: Bool {
		return session?.isValid ?? false;
	}
	
	var hasStreamingScope: Bool {
		return session?.scopes.contains("streaming") ?? false;
	}
	
	var canRefreshSession: Bool {
		return session?.refreshToken != nil && tokenRefreshURL != nil;
	}
	
	private var sessionRenewalTask: Task<Bool,Error>? = nil;
	private var sessionRenewalUntilCompleteTask: Task<Bool,Error>? = nil;
	private var lastSessionRenewalTime: DispatchTime? = nil
	
	override init() {
		session = nil;
		super.init();
	}
	
	func load(options: LibrespotLoginOptions) {
		guard let sessionUserDefaultsKey = sessionUserDefaultsKey else {
			return;
		}
		let prefs = UserDefaults.standard
		self.session = LibrespotSession.fromUserDefaults(prefs, key: sessionUserDefaultsKey)
		
		if session != nil {
			self.clientID = options.clientID
			self.tokenRefreshURL = options.tokenRefreshURL
		}
	}
	
	func save() {
		guard let sessionUserDefaultsKey = sessionUserDefaultsKey else { return }
		let prefs = UserDefaults.standard
		if let session = session {
			session.saveToUserDefaults(prefs, key: sessionUserDefaultsKey)
		} else {
			prefs.removeObject(forKey: sessionUserDefaultsKey)
		}
	}
	
	func startSession(_ session: LibrespotSession, options: LibrespotLoginOptions) {
		self.session = session
		self.clientID = options.clientID
		self.tokenRefreshURL = options.tokenRefreshURL
		self.save()
	}
	
	func clearSession() {
		session = nil
		clientID = nil
		tokenRefreshURL = nil
		self.save()
	}
	
	func clearCookies(_ completion: (() -> Void)? = nil) {
		DispatchQueue.global(qos: .default).async {
			let storage = HTTPCookieStorage.shared
			for cookie in storage.cookies ?? [] {
				storage.deleteCookie(cookie)
			}
			UserDefaults.standard.synchronize()
			
			DispatchQueue.main.async {
				completion?()
			}
		}
	}
	
	func renewSessionIfNeeded(waitForDefinitiveResponse: Bool) async throws -> Bool {
		guard let session = self.session, !session.isValid else {
			return false
		}
		guard session.refreshToken != nil || self.tokenRefreshURL == nil else {
			// TODO clear the session maybe?
			throw LibrespotError(kind: "SessionExpired", message: "The session has expired")
		}
		return try await self.renewSession(waitForDefinitiveResponse: waitForDefinitiveResponse);
	}
	
	func renewSession(waitForDefinitiveResponse: Bool) async throws -> Bool {
		guard let session = self.session, self.canRefreshSession,
			let refreshToken = session.refreshToken,
			let tokenRefreshURL = self.tokenRefreshURL else {
			return false;
		}
		if waitForDefinitiveResponse {
			if let renewSessionUntilCompleteTask = self.sessionRenewalUntilCompleteTask {
				return try await renewSessionUntilCompleteTask.value;
			}
			self.sessionRenewalUntilCompleteTask = Task {
				while true {
					do {
						return try await self.renewSession(waitForDefinitiveResponse: false);
					} catch let error {
						if Self.isErrorDefinitive(error) {
							throw error
						}
					}
					// retry session renewal in 10s
					try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
				}
			}
		} else {
			if let currentRefreshTask = self.sessionRenewalTask {
				return try await currentRefreshTask.value;
			}
		}
		
		let scopes = session.scopes;
		let refreshTask = Task<Bool,Error> {
			let session = try await Self.refreshSession(withToken:refreshToken, scopes:scopes, url:tokenRefreshURL);
			self.session = session;
			self.save();
			return true
		}
		self.sessionRenewalTask = refreshTask;
		defer {
			self.sessionRenewalTask = nil;
		}
		
		return try await refreshTask.value
	}
	
	static func isErrorDefinitive(_ error: Error) -> Bool {
		guard let error = error as? LibrespotError else {
			return true
		}
		let errorKind = error.kind.toString()
		return !(errorKind == LibrespotError.httpErrorKind(status: 0)
		   || errorKind == LibrespotError.httpErrorKind(status: 408)
		   || errorKind == LibrespotError.httpErrorKind(status: 504)
		   || errorKind == LibrespotError.httpErrorKind(status: 598)
		   || errorKind == LibrespotError.httpErrorKind(status: 599));
	}
	
	static func performTokenURLRequest(to url: URL, params: [String: Any]) async throws -> [String:Any]? {
		let body = LibrespotUtils.makeQueryString(params)
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.httpBody = body.data(using: .utf8)
		
		let (data, response) = try await URLSession.shared.data(for: request)
		
		if let response = response as? HTTPURLResponse {
			if response.statusCode < 200 || response.statusCode >= 300 {
				throw LibrespotError.httpError(status: response.statusCode)
			}
		}
		
		do {
			if let responseObj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
				if let errorCode = responseObj["error"] as? String {
					throw LibrespotError(
						kind: errorCode,
						message: responseObj["error_description"] as? String ?? "");
				}
				return responseObj;
			}
		} catch {
			throw LibrespotError.badResponse(message: error.localizedDescription)
		}
		return nil;
	}
	
	private static func refreshSession(withToken refreshToken: String, scopes: [String], url: URL) async throws -> LibrespotSession {
		let result = try await self.performTokenURLRequest(to: url, params: [
			"refresh_token": refreshToken
		]);
		guard let accessToken = result?["access_token"] as? String,
			  let expireSeconds = result?["expires_in"] as? Int else {
			throw LibrespotError.badResponse(message: "Missing expected response parameters")
		}
		return LibrespotSession(
			accessToken: accessToken,
			expireDate: LibrespotSession.expireDateFromSeconds(expireSeconds),
			refreshToken: refreshToken,
			scopes: scopes);
	}
	
	static func retrieveAccessTokenFrom(code: String, url: URL) async throws -> LibrespotSession {
		let params = ["code": code]
		
		let result = try await self.performTokenURLRequest(to: url, params: params)
		guard let accessToken = result?["access_token"] as? String,
			  let expireSeconds = result?["expires_in"] as? Int else {
			throw LibrespotError.badResponse(message: "Missing expected response parameters")
		}
		
		let scope = result?["scope"] as? String
		let session = LibrespotSession(
			accessToken: accessToken,
			expireDate: LibrespotSession.expireDateFromSeconds(expireSeconds),
			refreshToken: result?["refresh_token"] as? String,
			scopes: scope?.components(separatedBy: " ") ?? [])
		
		return session
	}
}

