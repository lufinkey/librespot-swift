
@objc
public class Librespot: NSObject {
	
	private var core: LibrespotCore;
	private var eventReceiver: LibrespotPlayerEventReceiver? = nil;
  
	@objc
	public override init() {
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

	@objc
	public func doAThing() -> Void {
		NSLog("We're calling a swift function!!!!");
	}

	@objc
	public func login(accessToken: String, storeCredentials: Bool) async throws {
		try await core.login_with_accesstoken(accessToken, storeCredentials);
	}

	@objc
	public func logout() {
		core.logout();
	}

	@objc
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

	@objc
	public func seekTo(_ position_ms: UInt32) {
		core.player_seek(position_ms);
	}
}
