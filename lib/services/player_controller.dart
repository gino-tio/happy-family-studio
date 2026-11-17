import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'audio/audio_engine.dart';
import 'songs_service.dart';

enum LoopMode { off, all, one }

/// The one audio player of the app: a queue of songs with next / previous,
/// shuffle and repeat. The mini player, the song screen and the lyrics all
/// listen to it, and so do the lock screen and headphone buttons.
class PlayerController extends ChangeNotifier {
  PlayerController(this._service) {
    _subs.add(
      _player.onPosition.listen((p) {
        position = p;
        notifyListeners();
      }),
    );
    _subs.add(
      _player.onDuration.listen((d) {
        duration = d;
        notifyListeners();
      }),
    );
    _subs.add(
      _player.onPlaying.listen((p) {
        playing = p;
        notifyListeners();
      }),
    );
    _subs.add(_player.onComplete.listen((_) => _onComplete()));
    _player.setRemoteCommands(
      RemoteCommands(
        play: () => _player.hasSource ? _player.resume() : toggle(),
        pause: () => _player.pause(),
        next: () => next(),
        previous: () => previous(),
        seek: (to) => seek(to),
      ),
    );
  }

  final SongsService _service;
  final AudioEngine _player = AudioEngine();

  /// Signed URLs by audio path. Fetched ahead for the next song, so that when
  /// a song ends with the screen locked the next one starts at once, without
  /// waiting on the network while the browser may be throttling the page.
  final _urls = <String, ({DateTime at, Future<String> url})>{};

  /// The queue position chosen to play after the current one (picked early
  /// when shuffling, so its URL can be fetched ahead).
  int? _upNext;
  final _subs = <StreamSubscription<dynamic>>[];
  final _random = Random();

  static const _band = '開心家庭大樂隊';

  List<Song> queue = const [];
  int index = -1;
  bool playing = false;
  bool loading = false;
  bool shuffle = false;
  LoopMode repeat = LoopMode.off;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  String? error;

  /// Songs played so far, for "previous" while shuffling.
  final _history = <int>[];

  Song? get current => index >= 0 && index < queue.length ? queue[index] : null;

  bool isCurrent(String songId) => current?.id == songId;

  /// Plays [songs] (only finished ones are kept) starting at [start].
  Future<void> playQueue(List<Song> songs, {String? startId}) async {
    final list = songs.where((s) => s.isPlayable).toList();
    if (list.isEmpty) return;
    var i = startId == null ? 0 : list.indexWhere((s) => s.id == startId);
    if (i < 0) i = 0;
    if (startId == null && shuffle) i = _random.nextInt(list.length);
    queue = list;
    _history.clear();
    await _load(i);
  }

  /// Plays [song] in the context of [context] (its section or playlist), or
  /// toggles play/pause when it is already the current song.
  Future<void> playOrToggle(Song song, List<Song> context) async {
    if (isCurrent(song.id)) return toggle();
    final ctx = context.any((s) => s.id == song.id) ? context : [song];
    await playQueue(ctx, startId: song.id);
  }

  Future<void> _load(int i) async {
    index = i;
    position = Duration.zero;
    duration = current?.lengthMs != null
        ? Duration(milliseconds: current!.lengthMs!)
        : Duration.zero;
    loading = true;
    error = null;
    notifyListeners();
    final song = queue[i];
    _upNext = null;
    _showNowPlaying(song);
    try {
      final url = await _url(song.audioPath!);
      if (current?.id != song.id) return; // skipped meanwhile
      await _player.play(url);
      _prepareNext();
    } catch (e) {
      error = '播唔到：$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String> _url(String path) {
    final hit = _urls[path];
    // Signed for an hour; renew after 45 minutes.
    if (hit != null &&
        DateTime.now().difference(hit.at) < const Duration(minutes: 45)) {
      return hit.url;
    }
    final url = _service.signedAudioUrl(path);
    _urls[path] = (at: DateTime.now(), url: url);
    url.catchError((Object _) {
      _urls.remove(path);
      return '';
    });
    return url;
  }

  int? _pickNext() {
    if (queue.isEmpty) return null;
    if (shuffle && queue.length > 1) {
      var n = index;
      while (n == index) {
        n = _random.nextInt(queue.length);
      }
      return n;
    }
    if (index < queue.length - 1) return index + 1;
    if (repeat == LoopMode.all) return 0;
    return null;
  }

  void _prepareNext() {
    final n = _upNext = _pickNext();
    if (n == null) return;
    final path = queue[n].audioPath;
    if (path != null) _url(path).ignore();
  }

  void _showNowPlaying(Song song) {
    _player.setNowPlaying(NowPlaying(title: song.title, artist: _band));
    final cover = song.coverPath;
    if (cover == null || cover.toLowerCase().endsWith('.svg')) return;
    _service.coverUrl(cover).then((url) {
      if (current?.id != song.id) return;
      _player.setNowPlaying(
        NowPlaying(title: song.title, artist: _band, artUrl: url),
      );
    }).ignore();
  }

  Future<void> toggle() async {
    if (current == null) return;
    if (playing) {
      await _player.pause();
    } else if (!_player.hasSource) {
      await _load(index);
    } else {
      await _player.resume();
    }
  }

  Future<void> seek(Duration to) async {
    position = to;
    notifyListeners();
    await _player.seek(to);
  }

  bool get hasNext =>
      queue.isNotEmpty &&
      (shuffle || repeat == LoopMode.all || index < queue.length - 1);

  Future<void> next() async {
    if (queue.isEmpty) return;
    final up = _upNext;
    final n = up != null && up < queue.length && up != index ? up : _pickNext();
    if (n != null) {
      _history.add(index);
      return _load(n);
    }
    await _player.stop();
    await seek(Duration.zero);
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    if (position > const Duration(seconds: 3)) return seek(Duration.zero);
    if (_history.isNotEmpty) return _load(_history.removeLast());
    if (index > 0) return _load(index - 1);
    if (repeat == LoopMode.all) return _load(queue.length - 1);
    await seek(Duration.zero);
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    if (current != null) _prepareNext();
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = LoopMode.values[(repeat.index + 1) % LoopMode.values.length];
    if (current != null) _prepareNext();
    notifyListeners();
  }

  Future<void> _onComplete() async {
    if (repeat == LoopMode.one) {
      await _player.seek(Duration.zero);
      await _player.resume();
      return;
    }
    if (hasNext) {
      await next();
    } else {
      playing = false;
      position = Duration.zero;
      notifyListeners();
    }
  }

  /// Keeps queue entries fresh (title or cover changed) and drops deleted songs.
  void refreshFrom(List<Song> songs) {
    if (queue.isEmpty) return;
    final byId = {for (final s in songs) s.id: s};
    final cur = current?.id;
    final fresh = [
      for (final s in queue)
        if (byId[s.id] case final f? when f.isPlayable) f,
    ];
    if (fresh.length == queue.length) {
      queue = fresh;
      return;
    }
    queue = fresh;
    _upNext = null;
    final i = fresh.indexWhere((s) => s.id == cur);
    if (i >= 0) {
      index = i;
    } else {
      index = -1;
      _player.stop();
      _player.setNowPlaying(null);
    }
    _history.clear();
    notifyListeners();
  }

  /// Closes the mini player.
  Future<void> close() async {
    await _player.stop();
    _player.setNowPlaying(null);
    queue = const [];
    index = -1;
    _upNext = null;
    _history.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
