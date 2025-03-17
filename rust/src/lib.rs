// code adapted from https://github.com/jariz/Speck/blob/master/src/lib.rs

use env_logger::Env;
use std::path::Path;
use librespot::core::spotify_id::{SpotifyId, SpotifyItemType};
use librespot::core::cache::Cache;
use librespot::playback::audio_backend;
use librespot::playback::config::AudioFormat;
use librespot::playback::player::{PlayerEvent, PlayerEventChannel};
use librespot::{
	core::{config::SessionConfig, session::Session},
	discovery::Credentials,
	playback::{
		config::PlayerConfig,
		mixer::{softmixer::SoftMixer, Mixer, MixerConfig},
		player::Player,
	},
};
use log::debug;
use std::sync::Arc;

#[swift_bridge::bridge]
mod ffi {
	#[swift_bridge(swift_repr = "struct")]
	struct LibrespotError {
		kind: String,
		message: String,
	}

	// This is basically a redefinition of librespot's PlayerEvent beacuse of ✨ bridge reasons ✨
	enum LibrespotPlayerEvent {
		// Fired when the player is stopped (e.g. by issuing a "stop" command to the player).
		Stopped {
			play_request_id: u64,
			track_uri: String,
		},
		// The player is delayed by loading a track.
		Loading {
			play_request_id: u64,
			track_uri: String,
			position_ms: u32,
		},
		// The player is preloading a track.
		Preloading {
			track_uri: String,
		},
		// The player is playing a track.
		// This event is issued at the start of playback of whenever the position must be communicated
		// because it is out of sync. This includes:
		// start of a track
		// un-pausing
		// after a seek
		// after a buffer-underrun
		Playing {
			play_request_id: u64,
			track_uri: String,
			position_ms: u32,
		},
		// The player entered a paused state.
		Paused {
			play_request_id: u64,
			track_uri: String,
			position_ms: u32,
		},
		// The player thinks it's a good idea to issue a preload command for the next track now.
		// This event is intended for use within spirc.
		TimeToPreloadNextTrack {
			play_request_id: u64,
			track_uri: String,
		},
		// The player reached the end of a track.
		// This event is intended for use within spirc. Spirc will respond by issuing another command.
		EndOfTrack {
			play_request_id: u64,
			track_uri: String,
		},
		// The player was unable to load the requested track.
		Unavailable {
			play_request_id: u64,
			track_uri: String,
		},
		// The mixer volume was set to a new level.
		VolumeChanged {
			volume: u16,
		},
		PositionCorrection {
			play_request_id: u64,
			track_uri: String,
			position_ms: u32,
		},
		Seeked {
			play_request_id: u64,
			track_uri: String,
			position_ms: u32,
		},
		TrackChanged {
			// TODO richer track info
			// audio_item: Box<AudioItem>,
			track_uri: String,
			duration_ms: u32,
		},
		SessionConnected {
			connection_id: String,
			user_name: String,
		},
		SessionDisconnected {
			connection_id: String,
			user_name: String,
		},
		SessionClientChanged {
			client_id: String,
			client_name: String,
			client_brand_name: String,
			client_model_name: String,
		},
		ShuffleChanged {
			shuffle: bool,
		},
		RepeatChanged {
			//context: bool,
			//track: bool,
			repeating: bool,
		},
		AutoPlayChanged {
			auto_play: bool,
		},
		FilterExplicitContentChanged {
			filter: bool,
		},
		PlayRequestIdChanged {
			play_request_id: u64,
		},
	}

	#[swift_bridge(swift_repr = "struct")]
	struct LibrespotPlayerEventResult {
		event: Option<LibrespotPlayerEvent>,
	}

	extern "Rust" {
		type LibrespotCore;

		pub fn librespot_default_client_id() -> String;

		#[swift_bridge(init)]
		fn new(
			client_id: String,
			audio_cache_path: Option<String>,
		) -> LibrespotCore;

		async fn login_with_accesstoken(&mut self, access_token: String) -> Result<(),LibrespotError>;
		async fn logout(&mut self);

		async fn player_init(&mut self) -> bool;
		async fn player_deinit(&mut self);

		async fn player_get_event(&mut self) -> LibrespotPlayerEventResult;

		fn player_load(&mut self, track_id: String, start_playing: bool, position_ms: u32);
		fn player_preload(&mut self, track_id: String);
		fn player_pause(&self);
		fn player_play(&self);
		fn player_stop(&self);
		fn player_seek(&self, position_ms: u32);
	}
}

#[derive(Debug, Clone, Default)]
struct LibrespotOptions {
	client_id: String,
	audio_cache_path: Option<String>,
}

fn create_session(options: &LibrespotOptions) -> Session {
	let mut session_config = SessionConfig::default();
	session_config.client_id = options.client_id.clone();
	let cache = if options.audio_cache_path.is_some() {
		Cache::new(
			None,
			None,
			Some(Path::new(options.audio_cache_path.as_ref().unwrap().as_str())),
			None)
			.map_err(|e| dbg!(e))
			.ok()
	} else { None };
	let session = Session::new(session_config, cache);
	return session;
}

pub fn librespot_default_client_id() -> String {
	return SessionConfig::default().client_id;
}

pub struct LibrespotCore {
	options: LibrespotOptions,
	session: Option<Session>,
	player: Option<Arc<Player>>,
	channel: Option<PlayerEventChannel>
}

impl LibrespotCore {

	fn new(
		client_id: String,
		audio_cache_path: Option<String>,
	) -> Self {
		env_logger::Builder::from_env(
			Env::default().default_filter_or("libreact_native_librespot=debug,librespot=debug"),
		)
		.init();

		let options = LibrespotOptions {
			client_id: client_id,
			audio_cache_path: audio_cache_path,
		};

		LibrespotCore {
			options: options,
			session: None,
			player: None,
			channel: None,
		}
	}

	async fn login_with_accesstoken(&mut self, access_token: String) -> Result<(), ffi::LibrespotError> {
		let credentials = Credentials::with_access_token(access_token);
		let session = create_session(&self.options);
		session.connect(credentials, false)
			.await
			.map_err(|err| ffi::LibrespotError {
				kind: err.kind.to_string(),
				message: format!("{:?}", err),
			})?;
		if let Some(ref mut player) = self.player {
			player.set_session(session.clone());
		}
		self.session = Some(session);
		Ok(())
	}

	async fn logout(&mut self) {
		let new_session = create_session(&self.options);
		if let Some(ref mut player) = self.player {
			player.set_session(new_session.clone());
		}
		self.session = Some(new_session);
	}

	async fn player_init(&mut self) -> bool {
		if !self.player.is_none() {
			debug!("player_init called multiple times");
			return false;
		}
		let mixer = SoftMixer::open(MixerConfig::default());
		let player = Player::new(
			PlayerConfig::default(),
			if self.session.is_some() { self.session.as_ref().unwrap().clone() } else { create_session(&self.options) },
			mixer.get_soft_volume(),
			move || {
				// only rodio supported for now
				let backend = audio_backend::find(Some("rodio".to_string())).unwrap();
				backend(None, AudioFormat::default())
			},
		);

		let channel = player.get_player_event_channel();
		self.player = Some(player);
		self.channel = Some(channel);
		return true;
	}

	async fn player_deinit(&mut self) {
		if let Some(ref mut player) = self.player {
			player.stop();
		}
		self.player = None;
		self.channel = None;
	}

	async fn player_get_event(&mut self) -> ffi::LibrespotPlayerEventResult {
		let Some(recv_event) = self.channel.as_mut() else {
			return ffi::LibrespotPlayerEventResult { event: None };
		};
		let Some(event) = recv_event.recv().await else {
			return ffi::LibrespotPlayerEventResult { event: None };
		};
		debug!("librespot got event: {:?}", event);
		ffi::LibrespotPlayerEventResult {
			event: Some(match event {
				// this code was brought to you by github copilot
				PlayerEvent::Playing {
					play_request_id,
					track_id,
					position_ms,
				} => ffi::LibrespotPlayerEvent::Playing {
					play_request_id,
					position_ms,
					track_uri: track_id.to_uri().unwrap(),
				},
				PlayerEvent::Paused {
					play_request_id,
					track_id,
					position_ms,
				} => ffi::LibrespotPlayerEvent::Paused {
					play_request_id,
					position_ms,
					track_uri: track_id.to_uri().unwrap(),
				},
				PlayerEvent::TimeToPreloadNextTrack {
					play_request_id,
					track_id,
				} => ffi::LibrespotPlayerEvent::TimeToPreloadNextTrack {
					play_request_id,
					track_uri: track_id.to_uri().unwrap(),
				},
				PlayerEvent::EndOfTrack {
					play_request_id,
					track_id,
				} => ffi::LibrespotPlayerEvent::EndOfTrack {
					play_request_id,
					track_uri: track_id.to_uri().unwrap(),
				},
				PlayerEvent::TrackChanged { audio_item } => ffi::LibrespotPlayerEvent::TrackChanged {
					track_uri: audio_item.track_id.to_uri().unwrap(),
					duration_ms: audio_item.duration_ms,
				},
				PlayerEvent::SessionConnected {
					connection_id,
					user_name,
				} => ffi::LibrespotPlayerEvent::SessionConnected {
					connection_id,
					user_name,
				},
				PlayerEvent::SessionDisconnected {
					connection_id,
					user_name,
				} => ffi::LibrespotPlayerEvent::SessionDisconnected {
					connection_id,
					user_name,
				},
				PlayerEvent::VolumeChanged { volume } => {
					ffi::LibrespotPlayerEvent::VolumeChanged { volume }
				}
				PlayerEvent::RepeatChanged {
					//context,
					//track,
					repeat,
				} => ffi::LibrespotPlayerEvent::RepeatChanged {
					//context: context,
					//track: track,
					repeating: repeat,
				},
				PlayerEvent::ShuffleChanged { shuffle } => {
					ffi::LibrespotPlayerEvent::ShuffleChanged { shuffle }
				}
				PlayerEvent::FilterExplicitContentChanged { filter } => {
					ffi::LibrespotPlayerEvent::FilterExplicitContentChanged { filter }
				}
				PlayerEvent::AutoPlayChanged { auto_play } => {
					ffi::LibrespotPlayerEvent::AutoPlayChanged { auto_play }
				}
				PlayerEvent::Stopped {
					play_request_id,
					track_id,
				} => ffi::LibrespotPlayerEvent::Stopped {
					play_request_id,
					track_uri: track_id.to_uri().unwrap(),
				},
				PlayerEvent::Loading {
					play_request_id,
					track_id,
					position_ms,
				} => ffi::LibrespotPlayerEvent::Loading {
					play_request_id,
					track_uri: track_id.to_uri().unwrap(),
					position_ms,
				},
				PlayerEvent::Seeked {
					play_request_id,
					track_id,
					position_ms,
				} => ffi::LibrespotPlayerEvent::Seeked {
					play_request_id,
					track_uri: track_id.to_uri().unwrap(),
					position_ms,
				},
				PlayerEvent::PositionCorrection {
					play_request_id,
					track_id,
					position_ms,
				} => ffi::LibrespotPlayerEvent::PositionCorrection {
					play_request_id,
					track_uri: track_id.to_uri().unwrap(),
					position_ms,
				},
				PlayerEvent::Preloading { track_id } => ffi::LibrespotPlayerEvent::Preloading {
					track_uri: track_id.to_uri().unwrap(),
				},
				PlayerEvent::SessionClientChanged {
					client_id,
					client_name,
					client_brand_name,
					client_model_name,
				} => ffi::LibrespotPlayerEvent::SessionClientChanged {
					client_id,
					client_name,
					client_brand_name,
					client_model_name,
				},
				PlayerEvent::Unavailable {
					play_request_id,
					track_id,
				} => ffi::LibrespotPlayerEvent::Unavailable {
					play_request_id,
					track_uri: track_id.to_uri().unwrap(),
				},
				PlayerEvent::PlayRequestIdChanged { play_request_id } => {
					ffi::LibrespotPlayerEvent::PlayRequestIdChanged { play_request_id }
				}
			})
		}
	}

	fn player_load(&mut self, track_uri: String, start_playing: bool, position_ms: u32) {
		let mut id = SpotifyId::from_uri(&track_uri).unwrap();
		id.item_type = SpotifyItemType::Track;
		self.player.as_mut().unwrap().load(id, start_playing, position_ms);
	}

	fn player_preload(&mut self, track_uri: String) {
		let mut id = SpotifyId::from_uri(&track_uri).unwrap();
		id.item_type = SpotifyItemType::Track;
		self.player.as_mut().unwrap().preload(id);
	}

	fn player_pause(&self) {
		self.player.as_ref().unwrap().pause();
	}

	fn player_play(&self) {
		self.player.as_ref().unwrap().play();
	}

	fn player_stop(&self) {
		self.player.as_ref().unwrap().stop();
	}

	fn player_seek(&self, position_ms: u32) {
		self.player.as_ref().unwrap().seek(position_ms);
	}
}
