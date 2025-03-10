import Foundation

@objc
public class Librespot: NSObject {
	private static let oauthPort = 5165;
	private static let loginCallbackURL: URL = URL(
		string: "http://127.0.0.1:\(oauthPort)/login")!;
	
	private var core: LibrespotCore;
	private var eventReceiver: LibrespotPlayerEventReceiver? = nil;
	private var authorizationState = LibrespotUtils.randomURLSafe(length: 128);
	private var codeVerifier: String;
	private var codeChallenge: String;
	
	@objc
	public override init() {
		self.codeVerifier = LibrespotUtils.randomURLSafe(length: 128)
		self.codeChallenge = LibrespotUtils.makeCodeChallenge(codeVerifier: codeVerifier)
		
		let fileManager = FileManager.default;
		let credentialsPath = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)
			.first?.appendingPathComponent("Preferences/librespot_session").absoluteString;
			let audioCachePath = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
			.first?.appendingPathComponent("librespot_audio_cache").absoluteString;
		
		self.core = LibrespotCore(
			credentialsPath,
			audioCachePath);
		super.init()
	}
	
	@objc(authenticateWithClientId:scopes:redirectURL:tokenSwapURL:showDialog:completionHandler:)
	public func authenticate(
		clientId: String?,
		scopes: [String],
		redirectURL: URL?,
		tokenSwapURL: URL?,
		showDialog: Bool) async throws {
		//
	}
	
	@MainActor
	public func authenticate(_ options: LibrespotLoginOptions) async throws -> LibrespotSession? {
		#if os(iOS)
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
		
		var done = false;
		return try await withCheckedThrowingContinuation { continuation in
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
		throw LibrespotError(kind: "NotImplemented", message: "Sorry");
		#endif
	}

	@objc(loginWithAccessToken:storeCredentials:completionHandler:)
	public func login(accessToken: String, storeCredentials: Bool) async throws {
		try await core.login_with_accesstoken(accessToken, storeCredentials);
	}

	@objc
	public func logout() {
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
