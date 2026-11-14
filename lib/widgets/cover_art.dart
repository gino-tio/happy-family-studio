import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../services/songs_service.dart';
import '../theme.dart';

/// A song's cover: the picture in `studio-covers` (MusicGPT's .jpg or Claude's
/// .svg), or a colour gradient made from the song id while there is none.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.song,
    this.size,
    this.radius = StudioRadius.cover,
    this.showPending = true,
  });

  final Song song;

  /// Square size; null = fill the parent.
  final double? size;
  final double radius;
  final bool showPending;

  @override
  Widget build(BuildContext context) {
    final path = song.coverPath;
    Widget child = path == null
        ? _Placeholder(song: song)
        : _CoverImage(key: ValueKey(path), path: path, song: song);
    if (showPending && song.status.isPending) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          child,
          const ColoredBox(color: Color(0x88000000)),
          const Center(child: CircularProgressIndicator(strokeWidth: 3)),
        ],
      );
    }
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: child,
    );
    if (size == null) return clipped;
    return SizedBox.square(dimension: size, child: clipped);
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({super.key, required this.path, required this.song});
  final String path;
  final Song song;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: context.read<SongsService>().coverUrl(path),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) return _Placeholder(song: song, quiet: true);
        if (path.endsWith('.svg')) {
          return SvgPicture.network(
            url,
            fit: BoxFit.cover,
            placeholderBuilder: (_) => _Placeholder(song: song, quiet: true),
            errorBuilder: (_, _, _) => _Placeholder(song: song),
          );
        }
        return Image.network(
          url,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) => frame == null && !sync
              ? _Placeholder(song: song, quiet: true)
              : child,
          errorBuilder: (_, _, _) => _Placeholder(song: song),
        );
      },
    );
  }
}

/// Gradient from the song id, with a note icon (or nothing while loading).
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.song, this.quiet = false});
  final Song song;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final (a, b) = coverGradient(song.id);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ),
      ),
      child: quiet
          ? const SizedBox.expand()
          : LayoutBuilder(
              builder: (context, c) => Center(
                child: Icon(
                  Icons.music_note_rounded,
                  size: c.biggest.shortestSide * 0.36,
                  color: const Color(0xCCFFFFFF),
                ),
              ),
            ),
    );
  }
}

/// Two colours picked from the id, so a song without a cover keeps its look.
(Color, Color) coverGradient(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final hue = (h % 360).toDouble();
  final a = HSLColor.fromAHSL(1, hue, 0.65, 0.52).toColor();
  final b = HSLColor.fromAHSL(1, (hue + 50) % 360, 0.7, 0.32).toColor();
  return (a, b);
}
