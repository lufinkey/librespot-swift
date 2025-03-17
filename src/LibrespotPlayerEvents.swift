import Foundation

@objc public protocol LibrespotPlayerEventListener {
	@objc(onEventPlayingForRequestId:trackURI:position:)
	func onEventPlaying(playRequestId: UInt64, trackURI: String, position: UInt32)

	@objc(onEventPausedForRequestId:trackURI:position:)
	func onEventPaused(playRequestId: UInt64, trackURI: String, position: UInt32)

	@objc(onEventStoppedForRequestId:trackURI:)
	func onEventStopped(playRequestId: UInt64, trackURI: String)

	@objc(onEventSeekedForRequestId:trackURI:position:)
	func onEventSeeked(playRequestId: UInt64, trackURI: String, position: UInt32)

	@objc(onEventLoadingForRequestId:trackURI:position:)
	func onEventLoading(playRequestId: UInt64, trackURI: String, position: UInt32)

	@objc(onEventPreloadingForTrackURI:)
	func onEventPreloading(trackURI: String)
	
	@objc(onEventTimeToPreloadNextTrackForRequestId:trackURI:)
	func onEventTimeToPreloadNextTrack(playRequestId: UInt64, trackURI: String)

	@objc(onEventEndOfTrackForRequestId:trackURI:)
	func onEventEndOfTrack(playRequestId: UInt64, trackURI: String)

	@objc(onEventVolumeChangedTo:)
	func onEventVolumeChanged(volume: UInt16)

	@objc(onEventPositionCorrectionForRequestId:trackURI:position:)
	func onEventPositionCorrection(playRequestId: UInt64, trackURI: String, position: UInt32)

	@objc(onEventTrackChangedForTrackURI:duration:)
	func onEventTrackChanged(trackURI: String, duration: UInt32)

	@objc(onEventShuffleChangedTo:)
	func onEventShuffleChanged(shuffle: Bool)

	@objc(onEventRepeatChangedForContext:track:)
	func onEventRepeatChanged(context: Bool, track: Bool)

	@objc(onEventAutoPlayChangedTo:)
	func onEventAutoPlayChanged(autoPlay: Bool)

	@objc(onEventFilterExplicitContentChangedTo:)
	func onEventFilterExplicitContentChanged(filter: Bool)

	@objc(onEventPlayRequestIdChangedTo:)
	func onEventPlayRequestIdChanged(playRequestId: UInt64)

	@objc(onEventSessionConnectedForConnectionId:username:)
	func onEventSessionConnected(connectionId: String, username: String)

	@objc(onEventSessionDisconnectedForConnectionId:username:)
	func onEventSessionDisconnected(connectionId: String, username: String)

	@objc(onEventSessionClientChangedToClientId:clientName:clientBrandName:clientModelName:)
	func onEventSessionClientChanged(clientId: String, clientName: String, clientBrandName: String, clientModelName: String)

	@objc(onEventUnavailableForRequestId:trackURI:)
	func onEventUnavailable(playRequestId: UInt64, trackURI: String)
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
				self.listener.onEventPlaying(
					playRequestId: playRequestId,
					trackURI: trackURI.toString(),
					position: position);
			case .Paused(let playRequestId, let trackURI, let position):
				self.listener.onEventPaused(
					playRequestId: playRequestId,
					trackURI: trackURI.toString(),
					position: position);
			case .Stopped(let playRequestId, let trackURI):
				self.listener.onEventStopped(
					playRequestId: playRequestId,
					trackURI: trackURI.toString());
			case .Seeked(let playRequestId, let trackURI, let positionMs):
				self.listener.onEventSeeked(
					playRequestId: playRequestId,
					trackURI: trackURI.toString(),
					position: positionMs);
			case .Loading(let playRequestId, let trackURI, let positionMs):
				self.listener.onEventLoading(
					playRequestId: playRequestId,
					trackURI: trackURI.toString(),
					position: positionMs);
			case .Preloading(let trackURI):
				self.listener.onEventPreloading(
					trackURI: trackURI.toString());
			case .TimeToPreloadNextTrack(let playRequestId, let trackURI):
				self.listener.onEventTimeToPreloadNextTrack(
					playRequestId: playRequestId,
					trackURI: trackURI.toString());
			case .EndOfTrack(let playRequestId, let trackURI):
				self.listener.onEventEndOfTrack(
					playRequestId: playRequestId,
					trackURI: trackURI.toString());
			case .VolumeChanged(let volume):
				self.listener.onEventVolumeChanged(
					volume: volume);
			case .PositionCorrection(let playRequestId, let trackURI, let position):
				self.listener.onEventPositionCorrection(
					playRequestId: playRequestId,
					trackURI: trackURI.toString(),
					position: position);
			case .TrackChanged(let trackURI, let duration):
				self.listener.onEventTrackChanged(
					trackURI: trackURI.toString(),
					duration: duration);
			case .ShuffleChanged(let shuffle):
				self.listener.onEventShuffleChanged(
					shuffle: shuffle);
			case .RepeatChanged(let context, let track):
				self.listener.onEventRepeatChanged(
					context: context,
					track: track);
			case .AutoPlayChanged(let autoPlay):
				self.listener.onEventAutoPlayChanged(
					autoPlay: autoPlay);
			case .FilterExplicitContentChanged(let filter):
				self.listener.onEventFilterExplicitContentChanged(
					filter: filter);
			case .PlayRequestIdChanged(let playRequestId):
				self.listener.onEventPlayRequestIdChanged(
					playRequestId: playRequestId);
			case .SessionConnected(let connectionId, let userName):
				self.listener.onEventSessionConnected(
					connectionId: connectionId.toString(),
					username: userName.toString());
			case .SessionDisconnected(let connectionId, let userName):
				self.listener.onEventSessionDisconnected(
					connectionId: connectionId.toString(),
					username: userName.toString());
			case .SessionClientChanged(let clientId, let clientName, let clientBrandName, let clientModelName):
				self.listener.onEventSessionClientChanged(
					clientId: clientId.toString(),
					clientName: clientName.toString(),
					clientBrandName: clientBrandName.toString(),
					clientModelName: clientModelName.toString());
			case .Unavailable(let playRequestId, let trackURI):
				self.listener.onEventUnavailable(
					playRequestId: playRequestId,
					trackURI: trackURI.toString());
			}
		}
	}
}
