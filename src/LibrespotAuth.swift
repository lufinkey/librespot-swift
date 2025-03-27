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
	
	@objc
	public static let defaultTokenRefreshEarliness: Double = 300.0;

	var options: LibrespotAuthOptions
	var tokenRefreshEarliness: Double
	var sessionUserDefaultsKey: String?
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
		return session?.refreshToken != nil && self.options.tokenRefreshURL != nil;
	}
	
	var onSessionRenewed: ((LibrespotAuth, LibrespotSession) async throws -> Void)? = nil
	
	private var sessionRenewalTask: Task<Bool,Error>? = nil;
	private var sessionRenewalUntilCompleteTask: Task<Bool,Error>? = nil;
	private var lastSessionRenewalTime: DispatchTime? = nil
	private var authRenewalTimer: Timer? = nil
	
	init(options: LibrespotAuthOptions, tokenRefreshEarliness: Double = defaultTokenRefreshEarliness, sessionUserDefaultsKey: String?) {
		self.options = options;
		self.tokenRefreshEarliness = tokenRefreshEarliness;
		self.sessionUserDefaultsKey = sessionUserDefaultsKey;
		self.session = nil;
		super.init();
	}
	
	@discardableResult
	func load() -> LibrespotSession? {
		guard let sessionUserDefaultsKey = sessionUserDefaultsKey else {
			return nil;
		}
		let prefs = UserDefaults.standard
		let session = LibrespotSession.fromUserDefaults(prefs, key: sessionUserDefaultsKey)
		guard let session = session else {
			return nil;
		}
		self.startSession(session, save:false);
		return session;
	}
	
	func save() {
		guard let sessionUserDefaultsKey = sessionUserDefaultsKey else { return }
		let prefs = UserDefaults.standard
		if let session = session {
			session.saveToUserDefaults(prefs, key: sessionUserDefaultsKey);
		} else {
			prefs.removeObject(forKey: sessionUserDefaultsKey);
		}
	}
	
	func startSession(_ session: LibrespotSession, save: Bool = true) {
		self.session = session;
		if save {
			self.save();
		}
		self.stopAuthRenewalTimer();
		self.scheduleAuthRenewalTimer();
	}
	
	func clearSession(save: Bool = true) {
		self.stopAuthRenewalTimer();
		self.session = nil;
		if save {
			self.save();
		}
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
	
	@discardableResult
	private func scheduleAuthRenewalTimer() -> Bool {
		guard self.canRefreshSession, let session = self.session else {
			// Can't perform token refresh
			return false
		}

		let now = Date().timeIntervalSince1970
		let expirationTime = session.expireDate.timeIntervalSince1970
		let timeDiff = expirationTime - now
		let renewalTimeDiff = (expirationTime - self.tokenRefreshEarliness) - now
		
		if timeDiff <= 30.0 || timeDiff <= (self.tokenRefreshEarliness + 30.0) || renewalTimeDiff <= 0.0 {
			authRenewalTimerDidFire()
		} else {
			self.authRenewalTimer?.invalidate()
			let timer = Timer(
				timeInterval: renewalTimeDiff,
				target: self,
				selector: #selector(authRenewalTimerDidFire),
				userInfo: nil,
				repeats: false)
			RunLoop.current.add(timer, forMode: .common)
			self.authRenewalTimer = timer
		}
		return true;
	}

	@objc
	private func authRenewalTimerDidFire() {
		Task { [weak self] in
			do {
				let _ = try await self?.renewSession(waitForDefinitiveResponse: true);
			} catch let error {
				NSLog("Librespot session refresh failed: \(error.localizedDescription)")
			}
		}
	}

	func stopAuthRenewalTimer() {
		self.authRenewalTimer?.invalidate()
		self.authRenewalTimer = nil
	}
	
	func renewSessionIfNeeded(waitForDefinitiveResponse: Bool) async throws -> Bool {
		guard let session = self.session, !session.isValid else {
			return false
		}
		guard session.refreshToken != nil || self.options.tokenRefreshURL == nil else {
			// TODO clear the session maybe?
			throw LibrespotError(kind: "SessionExpired", message: "The session has expired")
		}
		return try await self.renewSession(waitForDefinitiveResponse: waitForDefinitiveResponse);
	}
	
	func renewSession(waitForDefinitiveResponse: Bool) async throws -> Bool {
		guard let session = self.session, self.canRefreshSession,
			let refreshToken = session.refreshToken,
			let tokenRefreshURL = self.options.tokenRefreshURL
		else {
			return false;
		}
		if waitForDefinitiveResponse {
			if let renewalTask = self.sessionRenewalUntilCompleteTask {
				return try await renewalTask.value;
			}
			let renewalTask = Task { [weak self] in
				while true {
					do {
						return try await self?.renewSession(waitForDefinitiveResponse: false) ?? false;
					} catch let error {
						if Self.isErrorDefinitive(error) {
							throw error;
						}
					}
					if self == nil {
						break;
					}
					// retry session renewal in 10s
					try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
				}
				return false;
			};
			self.sessionRenewalUntilCompleteTask = renewalTask;
			defer {
				self.sessionRenewalUntilCompleteTask = nil;
			}
			return try await renewalTask.value
		} else {
			if let currentRefreshTask = self.sessionRenewalTask {
				return try await currentRefreshTask.value;
			}
		}
		
		let refreshTask = Task<Bool,Error> { [weak self] in
			let newSession = try await Self.refreshSession(
				withToken: refreshToken,
				clientID: session.clientID,
				scopes: session.scopes,
				url: tokenRefreshURL);
			if let self = self {
				try await self.onSessionRenewed?(self, newSession)
				self.startSession(newSession)
			}
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
	
	private static func refreshSession(withToken refreshToken: String, clientID: String, scopes: [String], url: URL) async throws -> LibrespotSession {
		let params = [
			"grant_type": "refresh_token",
			"client_id": clientID,
			"refresh_token": refreshToken
		];
		let result = try await self.performTokenURLRequest(to: url, params: params);
		guard let accessToken = result?["access_token"] as? String,
			  let expireSeconds = result?["expires_in"] as? Int else {
			throw LibrespotError.badResponse(message: "Missing expected response parameters")
		}
		return LibrespotSession(
			clientID: clientID,
			accessToken: accessToken,
			expireDate: LibrespotSession.expireDateFromSeconds(expireSeconds),
			refreshToken: refreshToken,
			scopes: scopes);
	}
	
	static func retrieveAccessTokenFrom(code: String, codeVerifier: String?, clientID: String, redirectURI: String?, url: URL) async throws -> LibrespotSession {
		var params = [
			"grant_type": "authorization_code",
			"code": code,
			"client_id": clientID,
		]
		if let codeVerifier = codeVerifier {
			params["code_verifier"] = codeVerifier;
		}
		if let redirectURI = redirectURI {
			params["redirect_uri"] = redirectURI
		}
		
		let result = try await self.performTokenURLRequest(to: url, params: params)
		guard let accessToken = result?["access_token"] as? String,
			  let expireSeconds = result?["expires_in"] as? Int else {
			throw LibrespotError.badResponse(message: "Missing expected response parameters")
		}
		
		let scope = result?["scope"] as? String
		let session = LibrespotSession(
			clientID: clientID,
			accessToken: accessToken,
			expireDate: LibrespotSession.expireDateFromSeconds(expireSeconds),
			refreshToken: result?["refresh_token"] as? String,
			scopes: scope?.components(separatedBy: " ") ?? [])
		
		return session
	}
	
	
	
	@MainActor
	public static func authenticateViaOAuth(_ options: LibrespotAuthOptions) async throws -> LibrespotSession? {
		#if os(iOS) || os(macOS)
		var done = false;
		return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LibrespotSession?,Error>) in
			let authViewController = LibrespotAuthViewController(options);
			
			weak var weakAuthController = authViewController;
			let dismiss: ((_ onComplete: @escaping () -> Void) -> Void) = { (onComplete) in
				if let authController = weakAuthController {
					authController.hide() {
						onComplete();
					};
				} else {
					onComplete()
				}
			}
			
			#if os(iOS)
			authViewController.onCancel = {
				if !done {
					done = true;
					dismiss {
						continuation.resume(returning: nil);
					}
				}
			};
			#endif
			authViewController.onDismissed = {
				if !done {
					done = true;
					continuation.resume(returning: nil);
				}
			};
			authViewController.onAuthenticated = { (session) in
				if !done {
					done = true;
					dismiss {
						continuation.resume(returning: session);
					}
				}
			};
			authViewController.onError = { (error) in
				if !done {
					done = true;
					dismiss {
						continuation.resume(throwing: error);
					}
				}
			};
			authViewController.onDenied = {
				if !done {
					done = true;
					dismiss {
						continuation.resume(returning: nil)
					}
				}
			};
			
			guard authViewController.show() else {
				continuation.resume(throwing: LibrespotError(kind:"UIError", message: "Can't display login screen"))
				return;
			}
		}
		#else
		let scopesVec = RustVec<RustString>();
		for scope in options.scopes {
			scopesVec.push(value: RustString(scope));
		}
		// TODO show a cancel popup?
		let sessionData = try await librespot_authenticate(RustString(options.clientID), RustString(options.redirectURL.absoluteString), scopesVec);
		return LibrespotSession(
			clientID: options.clientID,
			accessToken: sessionData.access_token.toString(),
			expireDate: Date(timeIntervalSince1970: sessionData.expires_in),
			refreshToken: sessionData.refresh_token.toString(),
			scopes: sessionData.scopes.map({ $0.as_str().toString() }));
		#endif
	}
}

