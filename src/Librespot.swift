import Foundation

@objc
public class Librespot: NSObject {
	private let core: LibrespotCore;
	private let auth: LibrespotAuth;
	private var eventReceiver: LibrespotPlayerEventReceiver? = nil;
	private var authorizationState = LibrespotUtils.randomURLSafe(length: 128);
	
	@objc
	public convenience init(
		clientID: String?,
		scopes: [String]?,
		redirectURL: URL?,
		tokenSwapURL: URL? = nil,
		tokenRefreshURL: URL? = nil,
		tokenRefreshEarliness: Double = LibrespotAuth.DefaultTokenRefreshEarliness,
		loginUserAgent: String? = nil,
		params: [String:String]? = nil,
		sessionUserDefaultsKey: String? = nil) {
		let defaultAuthOptions = LibrespotAuthOptions.default;
		self.init(
			authOptions: LibrespotAuthOptions(
				clientID: clientID ?? defaultAuthOptions.clientID,
				redirectURL: redirectURL ?? defaultAuthOptions.redirectURL,
				scopes: scopes ?? defaultAuthOptions.scopes,
				tokenSwapURL: tokenSwapURL ?? defaultAuthOptions.tokenSwapURL,
				tokenRefreshURL: tokenRefreshURL ?? defaultAuthOptions.tokenRefreshURL,
				loginUserAgent: loginUserAgent ?? defaultAuthOptions.loginUserAgent,
				params: params ?? defaultAuthOptions.params),
			tokenRefreshEarliness: tokenRefreshEarliness,
			sessionUserDefaultsKey: sessionUserDefaultsKey);
	}
	
	public init(authOptions: LibrespotAuthOptions,
		tokenRefreshEarliness: Double = LibrespotAuth.DefaultTokenRefreshEarliness,
		sessionUserDefaultsKey: String? = nil) {
		let fileManager = FileManager.default;
		let audioCachePath = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
			.first?.appendingPathComponent("librespot_audio_cache").absoluteString;
		
		self.core = LibrespotCore(audioCachePath);
		self.auth = LibrespotAuth(
			options: authOptions,
			tokenRefreshEarliness: tokenRefreshEarliness,
			sessionUserDefaultsKey: sessionUserDefaultsKey);
		super.init()
	}
	
	@objc(authenticateWithClientId:scopes:redirectURL:tokenSwapURL:loginUserAgent:params:completionHandler:)
	public static func authenticate(
		clientID: String,
		scopes: [String],
		redirectURL: URL,
		tokenSwapURL: URL? = nil,
		loginUserAgent: String? = nil,
		params: [String:String]? = nil) async throws -> LibrespotSession? {
		return try await Self.authenticate(LibrespotAuthOptions(
			clientID: clientID,
			redirectURL: redirectURL,
			scopes: scopes,
			tokenSwapURL: tokenSwapURL,
			loginUserAgent: loginUserAgent,
			params: params));
	}
	
	@MainActor
	public static func authenticate(_ options: LibrespotAuthOptions) async throws -> LibrespotSession? {
		#if os(iOS)
		var done = false;
		return try await withCheckedThrowingContinuation { continuation in
			let authViewController = LibrespotIOSAuthViewController(options)
			
			weak var weakAuthController = authViewController;
			let dismiss: ((_ onComplete: @escaping () -> Void) -> Void) = { (onComplete) in
				if let authController = weakAuthController, let presentingVC = authController.presentingViewController {
					presentingVC.dismiss(animated:true) {
						onComplete();
					};
				} else {
					onComplete()
				}
			}
			
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
			authViewController.onCancel = {
				if !done {
					done = true;
					dismiss {
						continuation.resume(returning: nil)
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
			authViewController.onDismissed = {
				if !done {
					done = true;
					continuation.resume(returning: nil)
				}
			};
			
			guard let topController = LibrespotIOSAuthViewController.findTopViewController() else {
				continuation.resume(throwing: LibrespotError(kind:"UIError", message: "No top controller to display login view"))
				return;
			}
			topController.present(authViewController, animated: true, completion: nil);
		}
		#else
		// TODO implement macOS flow
		throw LibrespotError(kind: "NotImplemented", message: "Sorry");
		#endif
	}
	
	@objc
	public static func authenticate() async throws -> LibrespotSession? {
		return try await Self.authenticate(.default);
	}
	
	@objc
	public func login() async throws -> LibrespotSession? {
		let session = try await Self.authenticate(self.auth.options)
		if let session = session {
			try await core.login_with_accesstoken(session.accessToken);
			self.auth.startSession(session);
		}
		return session;
	}
	
	@objc(loginWithSession:completionHandler:)
	public func login(session: LibrespotSession) async throws {
		try await core.login_with_accesstoken(session.accessToken);
		self.auth.startSession(session);
	}
	
	@objc
	public func logout() {
		self.auth.clearSession();
		core.logout();
	}
	
	@objc(initPlayer:)
	public func initPlayer(_ listener: LibrespotPlayerEventListener) {
		let initted = core.player_init();
		if(!initted) {
			return;
		}
		let evtReceiver = LibrespotPlayerEventReceiver(self.core, listener);
		self.eventReceiver = evtReceiver;
		Task {
			await evtReceiver.pollEvents();
		}
	}
	
	@objc
	public func deinitPlayer() {
		self.eventReceiver?.dispose();
		self.eventReceiver = nil;
		core.player_deinit();
	}
	
	@objc(loadTrackURI:startPlaying:position:)
	public func load(trackURI: String, startPlaying: Bool, position: UInt32) {
		core.player_load(trackURI,startPlaying,position);
	}
	
	@objc(preloadTrackURI:)
	public func preload(trackURI: String) {
		core.player_preload(trackURI);
	}

	@objc
	public func stop() {
		core.player_stop();
	}

	@objc
	public func play() {
		core.player_play();
	}

	@objc
	public func pause() {
		core.player_pause();
	}

	@objc(seekTo:)
	public func seekTo(_ position_ms: UInt32) {
		core.player_seek(position_ms);
	}
}
