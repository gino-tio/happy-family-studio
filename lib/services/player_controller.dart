import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'songs_service.dart';

enum LoopMode { off, all, one }

/// The one audio player of the app: a queue of songs with next / previous,
/// shuffle and repeat. The mini player, the song screen and the lyrics all
/// listen to it.
class PlayerController extends ChangeNotifier {
  PlayerController(this._service) {
    _subs.add(
      _player.onPositionChanged.listen((p) {
        position = p;
        notifyListeners();
      }),
    );
    _subs.add(
      _player.onDurationChanged.listen((d) {
        duration = d;
        notifyListeners();
      }),
    );
    _subs.add(
      _player.onPlayerStateChanged.listen((s) {
        playing = s == PlayerState.playing;
        notifyListeners();
      }),
    );
    _subs.add(_player.onPlayerComplete.listen((_) => _onComplete()));
  }

  final SongsService _service;
  final _player = AudioPlayer();
  final _subs = <StreamSubscription<dynamic>>[];
  final _random = Random();

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
    try {
      final url = await _service.signedAudioUrl(song.audioPath!);
      if (current?.id != song.id) return; // skipped meanwhile
      await _player.stop();
      await _player.play(UrlSource(url));
    } catch (e) {
      error = '播唔到：$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (current == null) return;
    if (playing) {
      await _player.pause();
    } else if (_player.source == null) {
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
    _history.add(index);
    if (shuffle && queue.length > 1) {
      var n = index;
      while (n == index) {
        n = _random.nextInt(queue.length);
      }
      return _load(n);
    }
    if (index < queue.length - 1) return _load(index + 1);
    if (repeat == LoopMode.all) return _load(0);
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
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = LoopMode.values[(repeat.index + 1) % LoopMode.values.length];
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
    final i = fresh.indexWhere((s) => s.id == cur);
    if (i >= 0) {
      index = i;
    } else {
      index = -1;
      _player.stop();
    }
    _history.clear();
    notifyListeners();
  }

  /// Closes the mini player.
  Future<void> close() async {
    await _player.stop();
    queue = const [];
    index = -1;
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
