import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../services/library_store.dart';
import '../services/player_controller.dart';
import '../theme.dart';
import 'cover_art.dart';

String formatDuration(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Shuffle · previous · play/pause · next · repeat.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    this.song,
    this.context_ = const [],
    this.compact = false,
  });

  /// The song this row controls; null = whatever is playing.
  final Song? song;

  /// Queue to start when [song] isn't the current one.
  final List<Song> context_;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final target = song ?? p.current;
    final isCurrent = target != null && p.isCurrent(target.id);
    final playing = isCurrent && p.playing;
    final loading = isCurrent && p.loading;
    const dim = StudioColors.textSecondary;
    final small = compact ? 20.0 : 22.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact)
          IconButton(
            tooltip: '隨機播放',
            iconSize: small,
            color: p.shuffle ? StudioColors.neon : dim,
            onPressed: p.toggleShuffle,
            icon: const Icon(Icons.shuffle_rounded),
          ),
        IconButton(
          tooltip: '上一首',
          iconSize: small + 4,
          onPressed: isCurrent ? p.previous : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        SizedBox.square(
          dimension: compact ? 44 : 52,
          child: IconButton.outlined(
            tooltip: playing ? '暫停' : '播放',
            style: IconButton.styleFrom(
              side: const BorderSide(color: StudioColors.divider),
              backgroundColor: StudioColors.surfaceHigh,
            ),
            onPressed: target == null || !target.isPlayable
                ? null
                : () => p.playOrToggle(target, context_),
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: compact ? 24 : 28,
                  ),
          ),
        ),
        IconButton(
          tooltip: '下一首',
          iconSize: small + 4,
          onPressed: isCurrent && p.hasNext ? p.next : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        if (!compact)
          IconButton(
            tooltip: switch (p.repeat) {
              LoopMode.off => '重播：關',
              LoopMode.all => '重播：全部',
              LoopMode.one => '重播：單曲',
            },
            iconSize: small,
            color: p.repeat == LoopMode.off ? dim : StudioColors.neon,
            onPressed: p.cycleRepeat,
            icon: Icon(
              p.repeat == LoopMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
            ),
          ),
      ],
    );
  }
}

/// Seek bar with times, for the song that is playing.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, this.songId});

  /// Only shows live progress when this song is the current one.
  final String? songId;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final live = songId == null || p.isCurrent(songId!);
    final pos = live ? p.position : Duration.zero;
    final dur = live ? p.duration : Duration.zero;
    final max = dur.inMilliseconds.toDouble();
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            formatDuration(pos),
            style: const TextStyle(
              color: StudioColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            max: max > 0 ? max : 1,
            value: pos.inMilliseconds.clamp(0, max > 0 ? max : 1).toDouble(),
            onChanged: live && max > 0
                ? (v) => p.seek(Duration(milliseconds: v.round()))
                : null,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            formatDuration(dur),
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: StudioColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

/// Pill with the like count and a heart.
class LikeButton extends StatelessWidget {
  const LikeButton({super.key, required this.songId});
  final String songId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final liked = store.likedByMe(songId);
    final n = store.likeCount(songId);
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: liked ? StudioColors.neon : StudioColors.textPrimary,
        side: const BorderSide(color: StudioColors.divider),
        shape: const StadiumBorder(),
      ),
      onPressed: () => store.toggleLike(songId).catchError((Object e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('撳唔到心：$e')));
        }
      }),
      icon: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: 18,
      ),
      label: Text(n == 0 ? '鍾意' : '$n'),
    );
  }
}

/// The bar at the bottom of every screen while something is loaded.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onOpen});

  /// Opens the song screen of the current song.
  final void Function(Song song) onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final store = context.watch<LibraryStore>();
    final queued = p.current;
    if (queued == null) return const SizedBox.shrink();
    final song = store.song(queued.id) ?? queued;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final dur = p.duration.inMilliseconds;
    final progress = dur > 0
        ? (p.position.inMilliseconds / dur).clamp(0.0, 1.0)
        : 0.0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          wide ? StudioSpacing.xl : StudioSpacing.sm,
          0,
          wide ? StudioSpacing.xl : StudioSpacing.sm,
          StudioSpacing.sm,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Material(
              color: StudioColors.glass,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(StudioRadius.panel),
                side: const BorderSide(color: StudioColors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpen(song),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(StudioSpacing.sm),
                      child: Row(
                        children: [
                          CoverArt(song: song, size: 52, radius: 10),
                          const SizedBox(width: StudioSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  store.member(song.createdBy).name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: StudioColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (wide)
                            const PlayerControls()
                          else
                            const PlayerControls(compact: true),
                          if (wide) ...[
                            const SizedBox(width: StudioSpacing.md),
                            LikeButton(songId: song.id),
                          ],
                          IconButton(
                            tooltip: '收起',
                            iconSize: 20,
                            color: StudioColors.textSecondary,
                            onPressed: p.close,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: StudioColors.neon,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
