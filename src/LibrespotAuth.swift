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
	var session: LibrespotSession?
	
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
	
	private var renewingSession = false;
	private var retryRenewalUntilResponse = false;
	private var renewCallbacks = [RefreshCompletion]();
	private var renewUntilResponseCallbacks = [RefreshCompletion]();
	private var lock: NSLock = NSLock();
	
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
	
	func renewSessionIfNeeded(
		waitForDefinitiveResponse: Bool,
		onResolve: @escaping (_ refreshed: Bool) -> Void,
		onReject: @escaping (_ error: LibrespotError) -> Void
	) {
		guard let session = session, session.isValid else {
			onResolve(false)
			return
		}
		
		guard let refreshToken = session.refreshToken else {
			onReject(LibrespotError(kind: "SessionExpired", message: "The session has expired"))
			return;
		}
		self.renewSession(
			waitForDefinitiveResponse: waitForDefinitiveResponse,
			completion: (onResolve: { refreshed in
				onResolve(refreshed)
			}, onReject:onReject));
	}
	
	func renewSession(
		waitForDefinitiveResponse: Bool,
		completion: RefreshCompletion?
	) {
		guard let session = self.session, self.canRefreshSession else {
			self.handleRenewCallbacks(
				error: nil,
				renewed: false);
			completion?.onResolve(false);
			return;
		}
		let refreshToken = session.refreshToken;
		let scopes = session.scopes;
		
		if let completion = completion {
			if waitForDefinitiveResponse {
				self.lock.lock();
				self.renewUntilResponseCallbacks.append(completion);
				self.lock.unlock();
			} else {
				self.lock.lock();
				self.renewCallbacks.append(completion);
				self.lock.unlock();
			}
		}
		
		DispatchQueue.main.async {
			// determine whether to retry renewal if a definitive response isn't given
			if waitForDefinitiveResponse {
				self.retryRenewalUntilResponse = true;
			}
			
			// if we're already in the process of renewing the session, don't continue
			if self.renewingSession {
				return;
			}
			self.renewingSession = true;
			
			// create request body
			let params: [String: Any] = ["refresh_token": refreshToken as Any];
			
			// perform token refresh
			Self.performTokenURLRequest(to: self.tokenRefreshURL!, params: params,
				onResolve: { (result) in
					DispatchQueue.main.async {
						self.renewingSession = false
						
						// determine if session was renewed
						var error: LibrespotError? = nil
						var renewed = false
						if let newAccessToken = result["access_token"] as? String,
						   let expireSeconds = result["expires_in"] as? Int {
							var newSession = LibrespotSession(
								accessToken: newAccessToken,
								expireDate: LibrespotSession.expireDateFromSeconds(expireSeconds),
								refreshToken: refreshToken,
								scopes: scopes);
							self.save();
							renewed = true;
						} else {
							error = LibrespotError.badResponse(message: "Missing expected response parameters");
						}
						
						// call renewal callbacks
						self.handleRenewCallbacks(error: error, renewed: renewed)
						
						// call renewal until response callbacks
						self.retryRenewalUntilResponse = false;
						self.handleRenewUntilResponseCallbacks(
							error: nil,
							renewed: renewed);
					}
				},
				onReject: { (error) in
					// call renewal callbacks
					self.handleRenewCallbacks(
						error: error,
						renewed: false);
					
					// ensure an actual session renewal error (a reason to be logged out)
					var isTrueError = true
					let errorKind = error.kind.toString()
					if(errorKind == LibrespotError.httpErrorKind(status: 0)
					   || errorKind == LibrespotError.httpErrorKind(status: 408)
					   || errorKind == LibrespotError.httpErrorKind(status: 504)
					   || errorKind == LibrespotError.httpErrorKind(status: 598)
					   || errorKind == LibrespotError.httpErrorKind(status: 599)) {
						isTrueError = false;
					}
					DispatchQueue.main.async {
						if isTrueError {
							self.retryRenewalUntilResponse = false;
							self.handleRenewUntilResponseCallbacks(
								error: error,
								renewed: false);
							return;
						}
						if waitForDefinitiveResponse {
							// retry session renewal in 10s
							DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
								self.renewSession(waitForDefinitiveResponse: true, completion: nil)
							}
						}
					}
				});
		};
	}
	
	private func handleRenewCallbacks(error: LibrespotError?, renewed: Bool) {
		var tmpRenewCallbacks: [RefreshCompletion] = []
		lock.lock();
		tmpRenewCallbacks = Array(renewCallbacks)
		renewCallbacks.removeAll()
		lock.unlock()
		
		for callback in tmpRenewCallbacks {
			if let error = error {
				callback.onReject(error)
			} else {
				callback.onResolve(renewed)
			}
		}
	}
	
	private func handleRenewUntilResponseCallbacks(error: LibrespotError?, renewed: Bool) {
		var tmpRenewUntilResponseCallbacks: [RefreshCompletion] = []
		lock.lock();
		tmpRenewUntilResponseCallbacks = Array(renewUntilResponseCallbacks)
		renewUntilResponseCallbacks.removeAll()
		lock.unlock()
		
		for callback in tmpRenewUntilResponseCallbacks {
			if let error = error {
				callback.onReject(error)
			} else {
				callback.onResolve(renewed)
			}
		}
	}
	
	static func performTokenURLRequest(to url: URL, params: [String: Any],
		onResolve: @escaping (_ response: [String:Any]) -> Void,
		onReject: @escaping (_ error: LibrespotError) -> Void
	) {
		let body = LibrespotUtils.makeQueryString(params)
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.httpBody = body.data(using: .utf8)
		
		let dataTask = URLSession.shared.dataTask(with: request) { data, response, error in
			if let error = error {
				onReject(LibrespotError.httpError(status: 0, message: error.localizedDescription))
				return
			}
			
			guard let data = data else {
				onReject(LibrespotError.badResponse(message: "No data"))
				return
			}
			
			do {
				if let responseObj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
					if let errorCode = responseObj["error"] as? String {
						onReject(LibrespotError(
							kind: errorCode,
							message: responseObj["error_description"] as? String ?? ""));
					} else {
						onResolve(responseObj);
					}
				}
			} catch {
				onReject(LibrespotError.badResponse(message: error.localizedDescription))
			}
		}
		
		dataTask.resume()
	}
	
	static func swapCodeForToken(code: String, url: URL,
		onResolve: @escaping (_ session: LibrespotSession) -> Void,
		onReject: @escaping (_ error: LibrespotError
	) -> Void) {
		let params = ["code": code]
		
		self.performTokenURLRequest(to: url, params: params, onResolve: { (result) in
			guard let accessToken = result["access_token"] as? String,
				  let expireSeconds = result["expires_in"] as? Int else {
				onReject(LibrespotError.badResponse(message: "Missing expected response parameters"))
				return
			}
			
			let scope = result["scope"] as? String
			let session = LibrespotSession(
				accessToken: accessToken,
				expireDate: LibrespotSession.expireDateFromSeconds(expireSeconds),
				refreshToken: result["refresh_token"] as? String,
				scopes: scope?.components(separatedBy: " ") ?? [])
			
			onResolve(session)
		}, onReject: onReject);
	}
}

