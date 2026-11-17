import 'package:audioplayers/audioplayers.dart';

import 'audio_engine.dart';

AudioEngine createAudioEngine() => _NativeAudioEngine();

/// iOS / Android: audioplayers. Background play needs `UIBackgroundModes:
/// audio` (ios/Runner/Info.plist) and the playback session category, which is
/// audioplayers' default; Android keeps a wake lock while playing.
class _NativeAudioEngine implements AudioEngine {
  _NativeAudioEngine() {
    _player
        .setAudioContext(AudioContextConfig(stayAwake: true).build())
        .ignore();
  }

  final _player = AudioPlayer();

  @override
  Stream<Duration> get onPosition => _player.onPositionChanged;

  @override
  Stream<Duration> get onDuration => _player.onDurationChanged;

  @override
  Stream<bool> get onPlaying =>
      _player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  bool get hasSource => _player.source != null;

  @override
  Future<void> play(String url) async {
    await _player.stop();
    await _player.play(UrlSource(url));
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration to) => _player.seek(to);

  @override
  void setNowPlaying(NowPlaying? item) {}

  @override
  void setRemoteCommands(RemoteCommands commands) {}

  @override
  void dispose() => _player.dispose();
}
