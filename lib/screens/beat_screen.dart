import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/beat_synth.dart';
import '../models/beat_pattern.dart';
import '../models/beat_presets.dart';
import '../models/chord.dart';
import '../theme.dart';
import 'compose_screen.dart';

/// Beat 格仔 — a step sequencer. Tap cells to build a groove, hear it loop,
/// then hand it to the AI composer as a style prompt.
///
/// Audio is rendered to a WAV by [BeatSynth] and looped by a normal audio
/// player, so hit timing is sample-exact; the playhead is driven by a
/// ticker clock started alongside playback.
class BeatScreen extends StatefulWidget {
  const BeatScreen({super.key});

  @override
  State<BeatScreen> createState() => _BeatScreenState();
}

class _BeatScreenState extends State<BeatScreen>
    with SingleTickerProviderStateMixin {
  BeatPattern _p = BeatPresets.cityPop();
  final _player = AudioPlayer();
  late final Ticker _ticker = createTicker(_onTick);
  final _clock = Stopwatch();
  double _clockOffset = 0;
  bool _playing = false;
  int _playStep = -1;
  Timer? _rerender;

  @override
  void dispose() {
    _rerender?.cancel();
    _ticker.dispose();
    _player.dispose();
    super.dispose();
  }

  double get _elapsed => _clockOffset + _clock.elapsedMicroseconds / 1e6;

  void _onTick(Duration _) {
    final s = BeatSynth.stepAt(_p, _elapsed);
    if (s != _playStep) setState(() => _playStep = s);
  }

  Future<void> _start({double offset = 0}) async {
    final wav = BeatSynth.renderWav(_p);
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(
      BytesSource(wav, mimeType: 'audio/wav'),
      position: Duration(microseconds: (offset * 1e6).round()),
    );
    _clockOffset = offset;
    _clock
      ..reset()
      ..start();
    if (!_ticker.isActive) _ticker.start();
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _stop() async {
    _rerender?.cancel();
    await _player.stop();
    _clock.stop();
    _ticker.stop();
    if (mounted) {
      setState(() {
        _playing = false;
        _playStep = -1;
      });
    }
  }

  /// Every edit goes through here: repaint now, re-render the loop shortly
  /// after (debounced) if it's playing, resuming from the same spot.
  void _edit(VoidCallback change) {
    setState(change);
    if (!_playing) return;
    _rerender?.cancel();
    _rerender = Timer(const Duration(milliseconds: 250), () {
      _start(offset: _elapsed % BeatSynth.loopSeconds(_p));
    });
  }

  Future<void> _pickBassNote(int step) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(StudioSpacing.lg),
          child: Wrap(
            spacing: StudioSpacing.sm,
            runSpacing: StudioSpacing.sm,
            children: [
              for (final n in noteNames)
                ChoiceChip(
                  label: Text(n),
                  selected: _p.bassNotes[step] == n,
                  onSelected: (_) => Navigator.pop(context, n),
                ),
              ActionChip(
                label: const Text('清除'),
                onPressed: () => Navigator.pop(context, ''),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    _edit(() {
      if (picked.isEmpty) {
        _p.bassNotes.remove(step);
      } else {
        _p.bassNotes[step] = picked;
      }
    });
  }

  Future<void> _pickChord(int slot) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => _ChordDialog(initial: _p.chords[slot]),
    );
    if (picked == null) return;
    _edit(() => _p.chords[slot] = picked);
  }

  void _loadPreset(BeatPattern Function() build) {
    _edit(() {
      _p = build();
      _playStep = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Beat 格仔 · ${_p.name}'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '範例',
            icon: const Icon(Icons.library_music_outlined),
            onSelected: (label) => _loadPreset(
              BeatPresets.all.firstWhere((e) => e.label == label).build,
            ),
            itemBuilder: (_) => [
              for (final e in BeatPresets.all)
                PopupMenuItem(value: e.label, child: Text(e.label)),
            ],
          ),
          IconButton(
            tooltip: '清除格仔',
            icon: const Icon(Icons.layers_clear_outlined),
            onPressed: () => _edit(_p.clear),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: StudioSpacing.lg),
        children: [
          _Controls(
            pattern: _p,
            playing: _playing,
            onPlay: _playing ? _stop : () => _start(),
            onBpm: (v) => _edit(() => _p.bpm = v.round()),
            onSwing: (v) => _edit(() => _p.swing = v),
          ),
          const SizedBox(height: StudioSpacing.lg),
          _Grid(
            pattern: _p,
            playStep: _playStep,
            onTap: (t, s) => _edit(() => _p.toggle(t, s)),
            onBassLongPress: _pickBassNote,
            onChordTap: _pickChord,
          ),
          const SizedBox(height: StudioSpacing.md),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: StudioSpacing.lg),
            child: Text(
              '撳格仔開／關。Bass 撳一下用嗰段和弦嘅根音，長撳揀音。'
              '撳上面嘅和弦名改和弦。',
              style: TextStyle(color: StudioColors.textSecondary),
            ),
          ),
          const SizedBox(height: StudioSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: StudioSpacing.lg),
            child: FilledButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('用呢個 beat 作歌'),
              onPressed: () async {
                await _stop();
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(
                      initialTitle: _p.name,
                      initialStyle: _p.toPrompt(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.pattern,
    required this.playing,
    required this.onPlay,
    required this.onBpm,
    required this.onSwing,
  });

  final BeatPattern pattern;
  final bool playing;
  final VoidCallback onPlay;
  final ValueChanged<double> onBpm;
  final ValueChanged<double> onSwing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: StudioSpacing.lg),
      child: Row(
        children: [
          IconButton.filled(
            iconSize: 36,
            tooltip: playing ? '停' : '播',
            onPressed: onPlay,
            icon: Icon(playing ? Icons.stop : Icons.play_arrow),
          ),
          const SizedBox(width: StudioSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${pattern.bpm} BPM'),
                Slider(
                  min: 60,
                  max: 180,
                  divisions: 120,
                  value: pattern.bpm.toDouble(),
                  onChanged: onBpm,
                ),
                Text('Swing ${(pattern.swing * 100).round()}%'),
                Slider(
                  min: 0.5,
                  max: 0.75,
                  divisions: 25,
                  value: pattern.swing,
                  onChanged: onSwing,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.pattern,
    required this.playStep,
    required this.onTap,
    required this.onBassLongPress,
    required this.onChordTap,
  });

  final BeatPattern pattern;
  final int playStep;
  final void Function(BeatTrack track, int step) onTap;
  final void Function(int step) onBassLongPress;
  final void Function(int slot) onChordTap;

  static const cell = 30.0;
  static const rowHeight = 36.0;
  static const gap = 2.0;
  static const beatGap = 6.0;
  static const labelWidth = 84.0;

  /// Extra space after every beat (4 steps) so the grid reads in beats.
  static double _gapAfter(int step) => (step + 1) % 4 == 0 ? beatGap : gap;

  static Color trackColor(BeatTrack t) => switch (t) {
    BeatTrack.kick || BeatTrack.snare || BeatTrack.hats => StudioColors.neon,
    BeatTrack.bass => StudioColors.teal,
    BeatTrack.keys || BeatTrack.guitar => StudioColors.amber,
    BeatTrack.horns => StudioColors.brass,
  };

  @override
  Widget build(BuildContext context) {
    final steps = pattern.steps;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Column(
            children: [
              const SizedBox(height: rowHeight + 20 + gap),
              for (final t in BeatTrack.values)
                Container(
                  height: rowHeight,
                  margin: const EdgeInsets.only(bottom: gap),
                  padding: const EdgeInsets.only(left: StudioSpacing.lg),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t.label,
                    style: TextStyle(
                      color: trackColor(t),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: StudioSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Chord per half bar.
                Row(
                  children: [
                    for (var slot = 0; slot < pattern.chordSlots; slot++)
                      Padding(
                        padding: const EdgeInsets.only(right: beatGap),
                        child: SizedBox(
                          width:
                              _spanWidth(
                                slot * BeatPattern.stepsPerChord,
                                BeatPattern.stepsPerChord,
                              ) -
                              beatGap,
                          height: rowHeight,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  StudioRadius.input,
                                ),
                              ),
                            ),
                            onPressed: () => onChordTap(slot),
                            child: Text(pattern.chords[slot]),
                          ),
                        ),
                      ),
                  ],
                ),
                // Step numbers.
                SizedBox(
                  height: 20,
                  child: Row(
                    children: [
                      for (var s = 0; s < steps; s++)
                        Container(
                          width: cell,
                          margin: EdgeInsets.only(right: _gapAfter(s)),
                          alignment: Alignment.center,
                          child: Text(
                            '${s + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              color: s == playStep
                                  ? StudioColors.textPrimary
                                  : StudioColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: gap),
                for (final t in BeatTrack.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: gap),
                    child: Row(
                      children: [
                        for (var s = 0; s < steps; s++)
                          Padding(
                            padding: EdgeInsets.only(right: _gapAfter(s)),
                            child: _Cell(
                              on: pattern.isOn(t, s),
                              color: trackColor(t),
                              onBeat: s % 4 == 0,
                              playing: s == playStep,
                              label: _label(t, s),
                              onTap: () => onTap(t, s),
                              onLongPress: t == BeatTrack.bass
                                  ? () => onBassLongPress(s)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  double _spanWidth(int from, int count) {
    var w = 0.0;
    for (var s = from; s < from + count; s++) {
      w += cell + _gapAfter(s);
    }
    return w;
  }

  String? _label(BeatTrack t, int s) {
    if (!pattern.isOn(t, s)) return null;
    if (t == BeatTrack.bass) return pattern.bassNotes[s];
    // Name the chord on the first hit of each chord slot.
    if (t.isChordal) {
      final slotStart = s - s % BeatPattern.stepsPerChord;
      final firstInSlot = pattern
          .stepsOf(t)
          .firstWhere((x) => x >= slotStart, orElse: () => -1);
      if (firstInSlot == s) return pattern.chordAt(s);
    }
    return null;
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.on,
    required this.color,
    required this.onBeat,
    required this.playing,
    required this.onTap,
    this.label,
    this.onLongPress,
  });

  final bool on;
  final Color color;
  final bool onBeat;
  final bool playing;
  final String? label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final fill = on
        ? color.withValues(alpha: playing ? 1 : 0.85)
        : (onBeat ? StudioColors.divider : StudioColors.surfaceHigh);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: _Grid.cell,
        height: _Grid.rowHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
          border: playing
              ? Border.all(color: StudioColors.textPrimary, width: 2)
              : null,
        ),
        child: label == null
            ? null
            : FittedBox(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    label!,
                    style: const TextStyle(
                      color: StudioColors.background,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ChordDialog extends StatefulWidget {
  const _ChordDialog({required this.initial});
  final String initial;

  @override
  State<_ChordDialog> createState() => _ChordDialogState();
}

class _ChordDialogState extends State<_ChordDialog> {
  late final _text = TextEditingController(text: widget.initial);

  static const _common = [
    'C', 'Dm', 'Em', 'F', 'G', 'Am', 'Bm', 'B7', //
    'Cmaj7', 'Fmaj7', 'G7', 'Am7', 'Dm7', 'Dm9', 'Em7', 'E7',
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = isValidChord(_text.text);
    return AlertDialog(
      title: const Text('改和弦'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '例如 Am7、Dm9、Cmaj7',
              errorText: valid ? null : '睇唔明呢個和弦',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) {
              if (isValidChord(v)) Navigator.pop(context, v.trim());
            },
          ),
          const SizedBox(height: StudioSpacing.md),
          Wrap(
            spacing: StudioSpacing.xs,
            runSpacing: StudioSpacing.xs,
            children: [
              for (final c in _common)
                ActionChip(
                  label: Text(c),
                  onPressed: () => Navigator.pop(context, c),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, _text.text.trim())
              : null,
          child: const Text('確定'),
        ),
      ],
    );
  }
}
