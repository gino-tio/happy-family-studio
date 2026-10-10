import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../models/style_preset.dart';
import '../services/songs_service.dart';
import '../theme.dart';
import 'song_screen.dart';

/// 作新歌 — title + style prompt + lyrics → generate-song Edge Function.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _style = TextEditingController();
  final _lyrics = TextEditingController();
  bool _instrumental = false;
  double _seconds = 120;
  bool _busy = false;

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
