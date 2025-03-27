import Foundation

@objc
public class Librespot: NSObject {
	@objc
	public static let defaultAudioCachePath = FileManager.default
		.urls(for: .cachesDirectory, in: .userDomainMask)
		.first?.appendingPathComponent("librespot_audio_cache").absoluteString;
	
	@objc
	public static let defaultAudioCacheSize: UInt64 = 1024 * 1024 * 100; // 100mb
	
	private let core: LibrespotCore;
	private let auth: LibrespotAuth;
	private var eventReceiver: LibrespotPlayerEventReceiver? = nil;
	private var authorizationState = LibrespotUtils.randomURLSafe(length: 128);
	
	@objc
	public override convenience init() {
		self.init(authOptions: .default);
	}
	
	@objc
	public convenience init(
		clientID: String?,
		scopes: [String]?,
		redirectURL: URL?,
		redirectHookURL: URL? = nil,
		tokenSwapURL: URL? = nil,
		tokenRefreshURL: URL? = nil,
		tokenRefreshEarliness: Double = LibrespotAuth.defaultTokenRefreshEarliness,
		loginUserAgent: String? = nil,
		params: [String:String]? = nil,
		sessionUserDefaultsKey: String? = nil,
		audioCachePath: String? = nil,
		limitAudioCacheSize: Bool = false,
		audioCacheSize: UInt64 = defaultAudioCacheSize) {
		let defaultAuthOptions = LibrespotAuthOptions.default;
		self.init(
			authOptions: LibrespotAuthOptions(
				clientID: clientID ?? defaultAuthOptions.clientID,
				redirectURL: redirectURL ?? defaultAuthOptions.redirectURL,
				redirectHookURL: redirectHookURL ?? defaultAuthOptions.redirectHookURL,
				scopes: scopes ?? defaultAuthOptions.scopes,
				tokenSwapURL: tokenSwapURL ?? defaultAuthOptions.tokenSwapURL,
				tokenRefreshURL: tokenRefreshURL ?? defaultAuthOptions.tokenRefreshURL,
				loginUserAgent: loginUserAgent ?? defaultAuthOptions.loginUserAgent,
				params: params ?? defaultAuthOptions.params),
			tokenRefreshEarliness: tokenRefreshEarliness,
			sessionUserDefaultsKey: sessionUserDefaultsKey,
			audioCachePath: audioCachePath);
	}
	
	public init(authOptions: LibrespotAuthOptions,
		tokenRefreshEarliness: Double = LibrespotAuth.defaultTokenRefreshEarliness,
		sessionUserDefaultsKey: String? = nil,
		audioCachePath: String? = nil,
		audioCacheSizeLimit: UInt64? = nil) {
		self.core = LibrespotCore(LibrespotCoreOptions(
			client_id: RustString(authOptions.clientID),
			cache_audio: audioCachePath != nil,
			audio_cache_path: RustString(audioCachePath ?? ""),
			limit_audio_cache_size: audioCacheSizeLimit != nil,
			audio_cache_size_limit: audioCacheSizeLimit ?? .zero));
		self.auth = LibrespotAuth(
			options: authOptions,
			tokenRefreshEarliness: tokenRefreshEarliness,
			sessionUserDefaultsKey: sessionUserDefaultsKey);
		super.init()
		self.auth.onSessionRenewed = { [weak self] (auth, session) in
			guard let self else { return }
			try await self.loginPlayer(session: session)
		};
	}
	
	@objc
	public func loadStoredSession() async throws {
		if let session = self.auth.load() {
			try await self.core.login_with_accesstoken(session.accessToken);
		}
	}
	
	@objc(authenticateViaOAuthWithClientID:scopes:redirectURL:followRedirect:tokenSwapURL:loginUserAgent:params:completionHandler:)
	public static func authenticateViaOAuth(
		clientID: String,
		scopes: [String],
		redirectURL: URL,
		redirectHookURL: URL,
		tokenSwapURL: URL? = nil,
		loginUserAgent: String? = nil,
		params: [String:String]? = nil) async throws -> LibrespotSession? {
		return try await Self.authenticateViaOAuth(LibrespotAuthOptions(
			clientID: clientID,
			redirectURL: redirectURL,
			redirectHookURL: redirectHookURL,
			scopes: scopes,
			tokenSwapURL: tokenSwapURL,
			loginUserAgent: loginUserAgent,
			params: params));
	}
	
	@MainActor
	public static func authenticateViaOAuth(_ options: LibrespotAuthOptions) async throws -> LibrespotSession? {
		return try await LibrespotAuth.authenticateViaOAuth(options);
	}
	
	@objc
	public static func authenticateViaOAuth() async throws -> LibrespotSession? {
		return try await Self.authenticateViaOAuth(.default);
	}
	
	@objc
	public func loginViaOAuth() async throws -> LibrespotSession? {
		let session = try await Self.authenticateViaOAuth(self.auth.options)
		if let session = session {
			try await core.login_with_accesstoken(session.accessToken);
			self.auth.startSession(session);
		}
		return session;
	}
	
	@objc(loginWithSession:completionHandler:)
	public func login(session: LibrespotSession) async throws {
		try await self.loginPlayer(session: session)
		self.auth.startSession(session);
	}
	
	private func loginPlayer(session: LibrespotSession) async throws {
		try await core.login_with_accesstoken(session.accessToken);
	}
	
	@objc
	public func logout() async {
		self.auth.clearSession();
		await core.logout();
	}
	
	@objc(initPlayer:completionHandler:)
	public func initPlayer(_ listener: LibrespotPlayerEventListener) async {
		let initted = await core.player_init();
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
	public func deinitPlayer() async {
		self.eventReceiver?.dispose();
		self.eventReceiver = nil;
		await core.player_deinit();
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
	
	func onAuthSessionRenewed(auth: LibrespotAuth, session: LibrespotSession) async throws {
		try await self.loginPlayer(session: session)
	}
}
