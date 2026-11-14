import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/social.dart';
import '../models/song.dart';
import 'songs_service.dart';

/// The band's whole library, live over Realtime: songs, likes, playlists and
/// members. One subscription each for the whole app, so every screen reads the
/// same state (and a rename or a new cover shows everywhere at once).
class LibraryStore extends ChangeNotifier {
  LibraryStore(this._service);

  final SongsService _service;
  final _subs = <StreamSubscription<dynamic>>[];
  bool _started = false;

  List<Song> songs = const [];
  bool songsLoaded = false;
  Object? error;
  List<({String songId, String userId})> _likes = const [];
  List<Playlist> playlists = const [];
  List<PlaylistEntry> _entries = const [];
  Map<String, Member> _members = const {};

  /// Starts the subscriptions once the member is signed in (idempotent).
  void start() {
    if (_started) return;
    _started = true;
    _subs.add(
      _service.watchSongs().listen((v) {
        songs = v;
        songsLoaded = true;
        notifyListeners();
      }, onError: _onError),
    );
    _subs.add(
      _service.watchLikes().listen((v) {
        _likes = v;
        notifyListeners();
      }, onError: _onError),
    );
    _subs.add(
      _service.watchPlaylists().listen((v) {
        playlists = v;
        notifyListeners();
      }, onError: _onError),
    );
    _subs.add(
      _service.watchPlaylistEntries().listen((v) {
        _entries = v;
        notifyListeners();
      }, onError: _onError),
    );
    _service.members().then((m) {
      _members = {for (final x in m) x.userId: x};
      notifyListeners();
    }, onError: (_) {});
  }

  void _onError(Object e) {
    error = e;
    notifyListeners();
  }

  String? get me => _service.currentUserId;

  Song? song(String id) {
    for (final s in songs) {
      if (s.id == id) return s;
    }
    return null;
  }

  Member member(String userId) => _members[userId] ?? Member.unknown;

  List<Song> get playable => songs.where((s) => s.isPlayable).toList();

  List<Song> get pending => songs.where((s) => s.status.isPending).toList();

  List<Song> songsBy(String userId) =>
      songs.where((s) => s.createdBy == userId && s.isPlayable).toList();

  int likeCount(String songId) =>
      _likes.where((l) => l.songId == songId).length;

  bool likedByMe(String songId) =>
      _likes.any((l) => l.songId == songId && l.userId == me);

  /// "我鍾意": songs I liked, latest like first (stream order is insert order).
  List<Song> get myLikes {
    final ids = [
      for (final l in _likes.reversed)
        if (l.userId == me) l.songId,
    ];
    return [
      for (final id in ids)
        if (song(id) case final s? when s.isPlayable) s,
    ];
  }

  Playlist? playlist(String id) {
    for (final p in playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Songs of a playlist in order.
  List<Song> playlistSongs(String playlistId) {
    final entries = _entries.where((e) => e.playlistId == playlistId).toList()
      ..sort((a, b) {
        final c = a.position.compareTo(b.position);
        return c != 0 ? c : a.addedAt.compareTo(b.addedAt);
      });
    return [for (final e in entries) ?song(e.songId)];
  }

  bool inPlaylist(String playlistId, String songId) =>
      _entries.any((e) => e.playlistId == playlistId && e.songId == songId);

  int nextPosition(String playlistId) {
    var max = 0;
    for (final e in _entries) {
      if (e.playlistId == playlistId && e.position > max) max = e.position;
    }
    return max + 1;
  }

  /// Optimistic like toggle; the Realtime echo confirms it.
  Future<void> toggleLike(String songId) async {
    final liked = likedByMe(songId);
    final uid = me;
    if (uid == null) return;
    _likes = liked
        ? _likes.where((l) => !(l.songId == songId && l.userId == uid)).toList()
        : [..._likes, (songId: songId, userId: uid)];
    notifyListeners();
    try {
      await _service.setLiked(songId, !liked);
    } catch (e) {
      _likes = liked
          ? [..._likes, (songId: songId, userId: uid)]
          : _likes
                .where((l) => !(l.songId == songId && l.userId == uid))
                .toList();
      notifyListeners();
      rethrow;
    }
  }

  /// Fills the store without a backend (widget tests and design previews).
  @visibleForTesting
  void seed({
    required List<Song> songs,
    List<({String songId, String userId})> likes = const [],
    List<Playlist> playlists = const [],
    List<PlaylistEntry> entries = const [],
    List<Member> members = const [],
  }) {
    _started = true;
    this.songs = songs;
    songsLoaded = true;
    _likes = likes;
    this.playlists = playlists;
    _entries = entries;
    _members = {for (final m in members) m.userId: m};
    notifyListeners();
  }

  /// Drops everything (sign-out), so the next member starts fresh.
  void reset() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _started = false;
    songs = const [];
    songsLoaded = false;
    error = null;
    _likes = const [];
    playlists = const [];
    _entries = const [];
    _members = const {};
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
