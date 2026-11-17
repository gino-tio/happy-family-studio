import 'audio_engine_native.dart'
    if (dart.library.js_interop) 'audio_engine_web.dart';

/// What the lock screen / control centre shows for the current song.
class NowPlaying {
  const NowPlaying({required this.title, required this.artist, this.artUrl});

  final String title;
  final String artist;

  /// A raster picture (png/jpeg/webp); lock screens don't draw SVG.
  final String? artUrl;
}

/// Buttons pressed outside the app: lock screen, control centre, headphones,
/// car. The engine calls them; the controller decides what they mean.
class RemoteCommands {
  const RemoteCommands({
    required this.play,
    required this.pause,
    required this.next,
    required this.previous,
    required this.seek,
  });

  final void Function() play;
  final void Function() pause;
  final void Function() next;
  final void Function() previous;
  final void Function(Duration to) seek;
}

/// The one audio output of the app. The web build plays through a single
/// `<audio>` element (no Web Audio graph, which iOS suspends when the screen
/// locks) and talks to the Media Session API; other platforms use
/// audioplayers.
abstract class AudioEngine {
  factory AudioEngine() => createAudioEngine();

  Stream<Duration> get onPosition;
  Stream<Duration> get onDuration;
  Stream<bool> get onPlaying;
  Stream<void> get onComplete;

  /// Whether a song is loaded (play can resume without a new URL).
  bool get hasSource;

  Future<void> play(String url);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration to);

  /// Lock-screen title and picture; null clears them.
  void setNowPlaying(NowPlaying? item);

  void setRemoteCommands(RemoteCommands commands);

  void dispose();
}
