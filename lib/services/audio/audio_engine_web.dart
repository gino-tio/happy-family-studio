import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'audio_engine.dart';

AudioEngine createAudioEngine() => _WebAudioEngine();

/// Web: one `<audio>` element for the whole session, played directly.
///
/// audioplayers routes its element through an AudioContext (for panning),
/// and iOS Safari suspends that context when the screen locks or the user
/// switches app, so the music stopped. A plain element keeps playing like any
/// web radio. Reusing the same element also matters: iOS lets an element that
/// was started by a tap play again later (the next song in the queue) without
/// another tap, even in the background.
class _WebAudioEngine implements AudioEngine {
  _WebAudioEngine() {
    _el.preload = 'auto';
    _subs
      ..add(
        _el.onTimeUpdate.listen((_) {
          _position.add(_secs(_el.currentTime));
          _syncPosition();
        }),
      )
      ..add(
        _el.onDurationChange.listen((_) {
          final d = _el.duration;
          if (d.isFinite && d > 0) _duration.add(_secs(d));
          _syncPosition();
        }),
      )
      ..add(_el.onPlaying.listen((_) => _setPlaying(true)))
      ..add(_el.onPlay.listen((_) => _setPlaying(true)))
      ..add(_el.onPause.listen((_) => _setPlaying(false)))
      ..add(
        _el.onEnded.listen((_) {
          _setPlaying(false);
          _complete.add(null);
        }),
      );
  }

  final web.HTMLAudioElement _el = web.HTMLAudioElement();
  final _subs = <StreamSubscription<web.Event>>[];
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _complete = StreamController<void>.broadcast();
  String? _src;

  static Duration _secs(num s) => Duration(milliseconds: (s * 1000).round());

  web.MediaSession? get _session {
    final nav = web.window.navigator as JSObject;
    return nav.has('mediaSession') ? web.window.navigator.mediaSession : null;
  }

  void _setPlaying(bool v) {
    _playing.add(v);
    _session?.playbackState = v ? 'playing' : 'paused';
  }

  void _syncPosition() {
    final s = _session;
    final d = _el.duration;
    if (s == null || !d.isFinite || d <= 0) return;
    try {
      s.setPositionState(
        web.MediaPositionState(
          duration: d,
          playbackRate: _el.playbackRate,
          position: _el.currentTime.clamp(0, d),
        ),
      );
    } catch (_) {
      // Older Safari lacks setPositionState; the rest still works.
    }
  }

  @override
  Stream<Duration> get onPosition => _position.stream;

  @override
  Stream<Duration> get onDuration => _duration.stream;

  @override
  Stream<bool> get onPlaying => _playing.stream;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  bool get hasSource => _src != null;

  @override
  Future<void> play(String url) async {
    _src = url;
    _el.src = url;
    await _el.play().toDart;
  }

  @override
  Future<void> pause() async => _el.pause();

  @override
  Future<void> resume() async {
    if (_src == null) return;
    await _el.play().toDart;
  }

  @override
  Future<void> stop() async {
    _el.pause();
    _el.removeAttribute('src');
    _el.load();
    _src = null;
    _session?.playbackState = 'none';
  }

  @override
  Future<void> seek(Duration to) async {
    _el.currentTime = to.inMilliseconds / 1000;
  }

  @override
  void setNowPlaying(NowPlaying? item) {
    final s = _session;
    if (s == null) return;
    if (item == null) {
      s.metadata = null;
      return;
    }
    final art = <web.MediaImage>[
      if (item.artUrl case final url?) web.MediaImage(src: url),
      web.MediaImage(
        src: Uri.base.resolve('icons/Icon-512.png').toString(),
        sizes: '512x512',
        type: 'image/png',
      ),
    ];
    s.metadata = web.MediaMetadata(
      web.MediaMetadataInit(
        title: item.title,
        artist: item.artist,
        artwork: art.toJS,
      ),
    );
  }

  @override
  void setRemoteCommands(RemoteCommands c) {
    final s = _session;
    if (s == null) return;
    void on(String action, void Function(JSObject details) f) {
      try {
        s.setActionHandler(action, f.toJS);
      } catch (_) {
        // The browser doesn't know this action.
      }
    }

    on('play', (_) => c.play());
    on('pause', (_) => c.pause());
    on('nexttrack', (_) => c.next());
    on('previoustrack', (_) => c.previous());
    on('seekto', (d) {
      final t = d.getProperty<JSNumber?>('seekTime'.toJS)?.toDartDouble;
      if (t != null) c.seek(_secs(t));
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _el.pause();
    _position.close();
    _duration.close();
    _playing.close();
    _complete.close();
  }
}
