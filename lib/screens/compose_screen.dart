import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../models/style_preset.dart';
import '../services/songs_service.dart';
import '../theme.dart';
import 'song_screen.dart';

/// 作新歌 — title + style prompt + lyrics → studio-generate-song Edge Function.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.initialTitle, this.initialStyle});

  /// Prefill from the beat grid ("用呢個 beat 作歌").
  final String? initialTitle;
  final String? initialStyle;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initialTitle);
  late final _style = TextEditingController(text: widget.initialStyle);
  final _lyrics = TextEditingController();
  bool _instrumental = false;
  double _seconds = 120;
  bool _busy = false;
  bool _writing = false;

  @override
  void dispose() {
    _title.dispose();
    _style.dispose();
    _lyrics.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final song = await context.read<SongsService>().generate(
        SongDraft(
          title: _title.text,
          style: _style.text,
          lyrics: _lyrics.text,
          instrumental: _instrumental,
          lengthMs: (_seconds * 1000).round(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SongScreen(songId: song.id)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('生成失敗：$e')));
    }
  }

  /// 「AI 寫歌詞」: ask what the song is about, then fill the lyrics (and the
  /// title if it is empty) with what AI writes. The member edits it after.
  Future<void> _aiLyrics() async {
    final topic = await showDialog<String>(
      context: context,
      builder: (_) => const _TopicDialog(),
    );
    if (topic == null || topic.trim().isEmpty || !mounted) return;
    setState(() => _writing = true);
    try {
      final r = await context.read<SongsService>().writeLyrics(
        topic: topic.trim(),
        style: _style.text,
        title: _title.text.trim(),
        seconds: _seconds.round(),
      );
      if (!mounted) return;
      setState(() {
        _lyrics.text = r.lyrics;
        if (_title.text.trim().isEmpty) _title.text = r.title;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作新歌')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(StudioSpacing.lg),
          children: [
            TextFormField(
              controller: _title,
              maxLength: 120,
              decoration: const InputDecoration(labelText: '歌名'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '要有歌名' : null,
            ),
            const SizedBox(height: StudioSpacing.md),
            Wrap(
              spacing: StudioSpacing.sm,
              runSpacing: StudioSpacing.sm,
              children: [
                for (final p in StylePreset.all)
                  ActionChip(
                    label: Text(p.label),
                    onPressed: () => setState(() => _style.text = p.style),
                  ),
              ],
            ),
            const SizedBox(height: StudioSpacing.md),
            TextFormField(
              controller: _style,
              maxLength: 1000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '風格 / prompt',
                hintText: '例如：90年代芬達結他搖滾，男聲，120 BPM',
              ),
              validator: (v) =>
                  ((v ?? '').trim().isEmpty &&
                      (_instrumental || _lyrics.text.trim().isEmpty))
                  ? '寫低風格或者歌詞'
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('純音樂（冇人聲）'),
              value: _instrumental,
              onChanged: (v) => setState(() => _instrumental = v),
            ),
            if (!_instrumental)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _writing || _busy ? null : _aiLyrics,
                  icon: _writing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_note),
                  label: Text(_writing ? 'AI 寫緊…（大約半分鐘）' : 'AI 寫歌詞'),
                ),
              ),
            if (!_instrumental) const SizedBox(height: StudioSpacing.sm),
            if (!_instrumental)
              TextFormField(
                controller: _lyrics,
                maxLength: 6000,
                minLines: 6,
                maxLines: 20,
                decoration: const InputDecoration(
                  labelText: '歌詞（廣東話）',
                  hintText: '[Verse 1]\n…\n[Chorus]\n…',
                  alignLabelWithHint: true,
                ),
              ),
            const SizedBox(height: StudioSpacing.md),
            Text('長度：${_seconds.round()} 秒'),
            Slider(
              min: 30,
              max: 300,
              divisions: 27,
              value: _seconds,
              label: '${_seconds.round()}s',
              onChanged: (v) => setState(() => _seconds = v),
            ),
            const SizedBox(height: StudioSpacing.lg),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: const Text('生成'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks what the song is about, in the member's own words.
class _TopicDialog extends StatefulWidget {
  const _TopicDialog();

  @override
  State<_TopicDialog> createState() => _TopicDialogState();
}

class _TopicDialogState extends State<_TopicDialog> {
  final _topic = TextEditingController();

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 寫歌詞'),
      content: TextField(
        controller: _topic,
        autofocus: true,
        maxLength: 500,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: '首歌講咩？咩感覺？',
          hintText: '例如：叮叮第一日返學，有啲驚又有啲興奮，溫暖少少搞笑',
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _topic.text),
          child: const Text('寫'),
        ),
      ],
    );
  }
}
