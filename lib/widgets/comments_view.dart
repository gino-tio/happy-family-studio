import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/social.dart';
import '../services/library_store.dart';
import '../services/songs_service.dart';
import '../theme.dart';

/// "3 分鐘前" style times.
String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return '啱啱';
  if (d.inHours < 1) return '${d.inMinutes} 分鐘前';
  if (d.inDays < 1) return '${d.inHours} 個鐘前';
  if (d.inDays < 30) return '${d.inDays} 日前';
  return '${t.year}年${t.month}月${t.day}日';
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.member, this.radius = 16});
  final Member member;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = member.avatarUrl;
    final initial = member.name.isEmpty ? '?' : member.name.characters.first;
    return CircleAvatar(
      radius: radius,
      backgroundColor: StudioColors.surfaceHigh,
      foregroundImage: url == null ? null : NetworkImage(url),
      child: Text(
        initial,
        style: TextStyle(fontSize: radius * 0.85, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Family comments on one song: a box to write in, then threads (newest
/// first) with one level of replies.
class CommentsView extends StatefulWidget {
  const CommentsView({super.key, required this.songId, this.onCount});
  final String songId;

  /// Reports the number of comments (for the tab label).
  final ValueChanged<int>? onCount;

  @override
  State<CommentsView> createState() => _CommentsViewState();
}

class _CommentsViewState extends State<CommentsView> {
  late final Stream<List<SongComment>> _stream = context
      .read<SongsService>()
      .watchComments(widget.songId);
  final _text = TextEditingController();
  final _focus = FocusNode();
  SongComment? _replyTo;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await context.read<SongsService>().addComment(
        widget.songId,
        body,
        parentId: _replyTo?.id,
      );
      _text.clear();
      setState(() => _replyTo = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('留唔到言：$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(SongComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除留言？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<SongsService>().deleteComment(c.id);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final me = store.member(store.me ?? '');
    return StreamBuilder<List<SongComment>>(
      stream: _stream,
      builder: (context, snap) {
        final all = snap.data ?? const <SongComment>[];
        if (snap.hasData) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => widget.onCount?.call(all.length),
          );
        }
        final threads = threadComments(all);
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, StudioSpacing.md, 0, 120),
          children: [
            _composer(me),
            const SizedBox(height: StudioSpacing.md),
            if (snap.hasError)
              Text('載入失敗：${snap.error}')
            else if (!snap.hasData)
              const Center(child: CircularProgressIndicator())
            else if (threads.isEmpty)
              const Padding(
                padding: EdgeInsets.all(StudioSpacing.xl),
                child: Center(
                  child: Text(
                    '未有留言，做第一個講兩句啦',
                    style: TextStyle(color: StudioColors.textSecondary),
                  ),
                ),
              ),
            for (final t in threads) ...[
              _comment(store, t.comment, isReply: false),
              for (final r in t.replies) _comment(store, r, isReply: true),
            ],
          ],
        );
      },
    );
  }

  Widget _composer(Member me) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_replyTo != null)
          Padding(
            padding: const EdgeInsets.only(left: 48, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '回覆 ${context.read<LibraryStore>().member(_replyTo!.userId).name}',
                    style: const TextStyle(
                      color: StudioColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _replyTo = null),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            MemberAvatar(member: me, radius: 18),
            const SizedBox(width: StudioSpacing.md),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                maxLength: 1000,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: '加留言…',
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              tooltip: '送出',
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_rounded, color: StudioColors.neon),
            ),
          ],
        ),
      ],
    );
  }

  Widget _comment(LibraryStore store, SongComment c, {required bool isReply}) {
    final who = store.member(c.userId);
    final mine = c.userId == store.me;
    return Padding(
      padding: EdgeInsets.only(
        left: isReply ? 48 : 0,
        top: StudioSpacing.sm,
        bottom: StudioSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberAvatar(member: who, radius: isReply ? 14 : 18),
          const SizedBox(width: StudioSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      who.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: StudioSpacing.sm),
                    Text(
                      timeAgo(c.createdAt),
                      style: const TextStyle(
                        color: StudioColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                SelectableText(c.body, style: const TextStyle(height: 1.35)),
                Row(
                  children: [
                    if (!isReply)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: StudioColors.textSecondary,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 32),
                        ),
                        onPressed: () {
                          setState(() => _replyTo = c);
                          _focus.requestFocus();
                        },
                        child: const Text('回覆'),
                      ),
                    if (mine)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: StudioColors.textSecondary,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 32),
                        ),
                        onPressed: () => _delete(c),
                        child: const Text('刪除'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
