import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'sheet.dart';
import 'smooth_scroll.dart';
import 'toast.dart';
import 'widgets.dart';

bool _requireLogin(BuildContext context) {
  if (context.read<AuthController>().loggedIn) return true;
  showToast(context, AppLocalizations.of(context).loginRequired);
  return false;
}

Future<void> toggleLike(BuildContext context, Song song) async {
  if (!_requireLogin(context)) return;
  final l = AppLocalizations.of(context);
  try {
    final liked = await context.read<LibraryController>().toggleLike(song);
    if (context.mounted) {
      showToast(
        context,
        liked ? l.liked : l.unliked,
        kind: liked ? ToastKind.liked : ToastKind.info,
      );
    }
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
  }
}

Future<void> addToPlaylist(BuildContext context, Song song) async {
  if (!_requireLogin(context)) return;
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  final picked = await showKanadeSheet<MyPlaylist>(
    context: context,
    builder: (_) => _PlaylistPicker(load: library.myPlaylists),
  );
  if (picked == null || !context.mounted) return;
  try {
    await library.addToPlaylist(picked, song);
    if (context.mounted) {
      showToast(
        context,
        l.addedToPlaylist(picked.name),
        kind: ToastKind.success,
      );
    }
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
  }
}

void playNext(BuildContext context, Song song) {
  final l = AppLocalizations.of(context);
  switch (context.read<PlayerController>().playNext(song)) {
    case PlayNextResult.queued:
      showToast(context, l.queuedNext, kind: ToastKind.success);
    case PlayNextResult.current:
      showToast(context, l.alreadyPlaying);
    case PlayNextResult.started:
      break;
  }
}

/// 从自己的歌单删歌，成功返回 true。
Future<bool> removeFromPlaylist(
  BuildContext context,
  MyPlaylist playlist,
  Song song,
) async {
  if (!_requireLogin(context)) return false;
  final l = AppLocalizations.of(context);
  try {
    await context.read<LibraryController>().removeFromPlaylist(playlist, song);
    if (context.mounted) {
      showToast(
        context,
        l.removedFromPlaylist(playlist.name),
        kind: ToastKind.success,
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
    return false;
  }
}

/// 选一个自己的歌单。加载中和出错时只占一小块，免得卡片先撑满再缩回去。
class _PlaylistPicker extends StatefulWidget {
  const _PlaylistPicker({required this.load});

  final Future<List<MyPlaylist>> Function() load;

  @override
  State<_PlaylistPicker> createState() => _PlaylistPickerState();
}

class _PlaylistPickerState extends State<_PlaylistPicker> {
  late Future<List<MyPlaylist>> _future = widget.load();

  Widget _placeholder(Widget child) =>
      SizedBox(height: 140, child: Center(child: child));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: l.addToPlaylist),
        Flexible(
          child: FutureBuilder<List<MyPlaylist>>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return _placeholder(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.loadFailed(errorText(l, snap.error!)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () =>
                            setState(() => _future = widget.load()),
                        child: Text(l.retry),
                      ),
                    ],
                  ),
                );
              }
              final lists = snap.data;
              if (lists == null) {
                return _placeholder(const CircularProgressIndicator());
              }
              if (lists.isEmpty) return _placeholder(Text(l.noMyPlaylists));
              // 歌单多的时候会很长，滚轮也要平滑
              return SmoothScroll(
                builder: (_, scroll) => SheetGroup(
                  controller: scroll,
                  children: [
                    for (final p in lists)
                      SheetRow(
                        leading: Cover(p.coverUrl, size: 40),
                        title: p.name,
                        subtitle: l.songCount(p.songCount),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
