
@objc struct LibrespotPlaybackStateEvent {
	let playRequestId: UInt64;
	let trackURI: String;
	let position: UInt32;
}

@objc struct LibrespotPlaybackStopEvent {
	let playRequestId: UInt64;
	let trackURI: String;
}

@objc struct LibrespotPreloadEvent {
	let trackURI: String;
}

@objc struct LibrespotTrackTimeEvent {
	let playRequestId: UInt64;
	let trackURI: String;
}

@objc struct LibrespotTrackChangeEvent {
	let trackURI: String;
	let duration: UInt32;
}

@objc struct LibrespotVolumeEvent {
	let volume: UInt16;
}

@objc struct LibrespotShuffleChangeEvent {
	let shuffle: Bool;
}

@objc struct LibrespotRepeatChangeEvent {
	//let context: Bool;
	//let track: Bool;
	let repeat: Bool;
}

@objc struct LibrespotAutoPlayChangeEvent {
	let autoPlay: Bool;
}

@objc struct LibrespotFilterExplicitContentChangeEvent {
	let filter: Bool;
}

@objc struct LibrespotPlayRequestIdChangeEvent {
	let playRequestId: UInt64;
}

@objc struct LibrespotSessionConnectionEvent {
	let connectionId: String;
	let username: String;
}

@objc struct LibrespotSessionClientChangeEvent {
	let clientId: String;
	let clientName: String;
	let clientBrandName: String;
	let clientModelName: String;
}

@objc struct LibrespotUnavailableEvent {
	let playRequestId: UInt64;
	let trackURI: String;
}

@objc public protocol LibrespotPlayerEventListener {
	func onEventPlaying(_ evt: LibrespotPlaybackStateEvent);
	func onEventPaused(_ evt: LibrespotPlaybackStateEvent);
	func onEventStopped(_ evt: LibrespotPlaybackStopEvent);
	func onEventSeeked(_ evt: LibrespotPlaybackStateEvent);
	func onEventLoading(_ evt: LibrespotPlaybackStateEvent);
	func onEventPreloading(_ evt: LibrespotPreloadEvent);
	func onEventTimeToPreloadNextTrack(_ evt: LibrespotTrackTimeEvent);
	func onEventEndOfTrack(_ evt: LibrespotTrackTimeEvent);
	func onEventVolumeChanged(_ evt: LibrespotVolumeEvent);
	func onEventPositionCorrection(_ evt: LibrespotPlaybackStateEvent);
	func onEventTrackChanged(_ evt: LibrespotTrackChangeEvent);
	func onEventShuffleChanged(_ evt: LibrespotShuffleChangeEvent);
	func onEventRepeatChanged(_ evt: LibrespotRepeatChangeEvent);
	func onEventAutoPlayChanged(_ data: LibrespotAutoPlayChangeEvent);
	func onEventFilterExplicitContentChanged(_ evt: LibrespotFilterExplicitContentChangeEvent);
	func onEventPlayRequestIdChanged(_ evt: LibrespotPlayRequestIdChangeEvent);
	func onEventSessionConnected(_ evt: LibrespotSessionConnectionEvent);
	func onEventSessionDisconnected(_ evt: LibrespotSessionConnectionEvent);
	func onEventSessionClientChanged(_ evt: LibrespotSessionClientChangeEvent);
	func onEventUnavailable(_ evt: LibrespotUnavailableEvent);
}

class LibrespotPlayerEventReceiver {
	private var disposed: Bool = false;
	private var core: LibrespotCore;
	private var listener: LibrespotPlayerEventListener;

  init(_ core: LibrespotCore, _ listener: LibrespotPlayerEventListener) {
		self.core = core;
		self.listener = listener;
	}

	func dispose() {
		self.disposed = true;
	}
	
	func pollEvents() async {
		while (!self.disposed) {
			guard let evt = await self.core.player_get_event().event else {
				continue;
			}
			switch evt {
			case .Playing(let playRequestId, let trackURI, let position):
				self.listener.onEventPlaying(LibrespotPlaybackStateEvent(
					playRequestId: playRequestId,
					trackURI: trackURI.toString(),
					position: position
				));
			case .Paused(let playRequestId, let trackURI, let positionMs):
				self.listener.onEventPaused(LibrespotPlaybackStateEvent(
					playRequestId: playRequestId,
					trackURI: trackURI.toString(),
					position: positionMs
				));
			case .Stopped(let playRequestId, let trackURI):
				self.listener.onEventStopped(LibrespotPlaybackStopEvent(
					playRequestId: playRequestId,
					trackURI: trackURI.toString()
				));
			case .Seeked(let playRequestId, let trackURI, let positionMs):
				self.listener.onEventSeeked(LibrespotPlaybackStateEvent(
					playRequestId: playRequestId,
					trackURI: trackURI.toString(),
					position: positionMs
				));
			case .Loading(let playRequestId, let trackURI, let positionMs):
				self.listener.onEventLoading(LibrespotPlaybackStateEvent(
					playRequestId: playRequestId,
					trackURI: trackURI.toString(),
					position: positionMs
				));
			case .Preloading(let trackURI):
				self.listener.onEventPreloading(LibrespotPreloadEvent(
					trackURI: trackURI.toString()
				));
			case .TimeToPreloadNextTrack(let playRequestId, let trackURI):
				self.listener.onEventTimeToPreloadNextTrack(LibrespotTrackTimeEvent(
					playRequestId: playRequestId,
					trackURI: trackURI.toString()
				));
			case .EndOfTrack(let playRequestId, let trackURI):
				self.listener.onEventEndOfTrack(LibrespotTrackTimeEvent(
					playRequestId: playRequestId,
					trackURI: trackURI.toString()
				));
			case .VolumeChanged(let volume):
				self.listener.onEventVolumeChanged(LibrespotVolumeEvent(
					volume: volume
				));
			case .PositionCorrection(let playRequestId, let trackURI, let positionMs):
				self.listener.onEventPositionCorrection(LibrespotPlaybackStateEvent(
					playRequestId: playRequestId,
					trackURI: trackURI.toString(),
					position: positionMs
				));
			case .TrackChanged(let trackURI, let durationMs):
				self.listener.onEventTrackChanged(LibrespotTrackChangeEvent(
					trackURI: trackURI.toString(),
					duration: durationMs
				));
			case .ShuffleChanged(let shuffle):
				self.listener.onEventShuffleChanged(LibrespotShuffleChangeEvent(
					shuffle: shuffle
				));
			case .RepeatChanged(_, let track):
				self.listener.onEventRepeatChanged(LibrespotRepeatChangeEvent(
					repeat: track
				));
			case .AutoPlayChanged(let autoPlay):
				self.listener.onEventAutoPlayChanged(LibrespotAutoPlayChangeEvent(
					autoPlay: autoPlay
				));
			case .FilterExplicitContentChanged(let filter):
				self.listener.onEventFilterExplicitContentChanged(LibrespotFilterExplicitContentChangeEvent(
					filter: filter
				));
			case .PlayRequestIdChanged(let playRequestId):
				self.listener.onEventPlayRequestIdChanged(LibrespotPlayRequestIdChangeEvent(
					playRequestId: playRequestId
				));
			case .SessionConnected(let connectionId, let userName):
				self.listener.onEventSessionConnected(LibrespotSessionConnectionEvent(
					connectionId: connectionId.toString(),
					username: userName.toString()
				));
			case .SessionDisconnected(let connectionId, let userName):
				self.listener.onEventSessionDisconnected(LibrespotSessionConnectionEvent(
					connectionId: connectionId.toString(),
					username: userName.toString()
				));
			case .SessionClientChanged(let clientId, let clientName, let clientBrandName, let clientModelName):
				self.listener.onEventSessionClientChanged(LibrespotSessionClientChangeEvent(
					clientId: clientId.toString(),
					clientName: clientName.toString(),
					clientBrandName: clientBrandName.toString(),
					clientModelName: clientModelName.toString()
				));
			case .Unavailable(let playRequestId, let trackURI):
				self.listener.onEventUnavailable(LibrespotUnavailableEvent(
					playRequestId: playRequestId,
					trackURI: trackURI.toString()
				));
			}
		}
	}
}
