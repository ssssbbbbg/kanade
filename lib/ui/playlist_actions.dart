import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../src/rust/api/types.dart';
import 'kanade_dialog.dart';
import 'sheet.dart';
import 'toast.dart';
import 'widgets.dart';

/// 歌单菜单做了什么，详情页据此改标题或退出。
sealed class PlaylistEdit {}

class PlaylistRenamed extends PlaylistEdit {
  PlaylistRenamed(this.name);

  final String name;
}

class PlaylistDeleted extends PlaylistEdit {}

/// “我喜欢”不能改名也不能删。
bool canEditPlaylist(MyPlaylist? p) => p != null && !isLikedPlaylist(p);

/// 自建歌单的更多操作：重命名、删除。没有改动时返回 null。
Future<PlaylistEdit?> showPlaylistActions(
  BuildContext context,
  MyPlaylist playlist,
) async {
  final l = AppLocalizations.of(context);
  final action = await showKanadeSheet<String>(
    context: context,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          leading: Cover(playlist.coverUrl, size: 48, radius: 10),
          title: playlist.name,
          subtitle: l.songCount(playlist.songCount),
        ),
        SheetGroup(
          children: [
            SheetRow(
              leading: const Icon(Icons.edit_outlined),
              title: l.renamePlaylist,
              onTap: () => Navigator.pop(sheet, 'rename'),
            ),
            SheetRow(
              leading: const Icon(Icons.delete_outline_rounded),
              title: l.deletePlaylist,
              destructive: true,
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ],
    ),
  );
  if (!context.mounted) return null;
  return switch (action) {
    'rename' => _rename(context, playlist),
    'delete' => _delete(context, playlist),
    _ => null,
  };
}

Future<PlaylistEdit?> _rename(BuildContext context, MyPlaylist playlist) async {
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  final name = await _playlistName(
    context,
    l.renamePlaylist,
    action: l.ok,
    initial: playlist.name,
  );
  if (name == null || name == playlist.name || !context.mounted) return null;
  try {
    await library.renamePlaylist(playlist, name);
    if (context.mounted) {
      showToast(context, l.playlistRenamed, kind: ToastKind.success);
    }
    return PlaylistRenamed(name);
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
    return null;
  }
}

Future<PlaylistEdit?> _delete(BuildContext context, MyPlaylist playlist) async {
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  final ok = await showKanadeDialog<bool>(
    context,
    builder: (context) => KanadeDialog(
      icon: Icons.delete_outline_rounded,
      danger: true,
      title: l.deletePlaylist,
      message: l.deletePlaylistConfirm(playlist.name),
      actions: [
        KanadeDialogAction(
          label: l.delete,
          primary: true,
          danger: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        KanadeDialogAction(
          label: l.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  try {
    await library.deletePlaylist(playlist);
    if (context.mounted) {
      showToast(context, l.playlistDeleted, kind: ToastKind.success);
    }
    return PlaylistDeleted();
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
    return null;
  }
}

Future<String?> _playlistName(
  BuildContext context,
  String title, {
  required String action,
  String initial = '',
}) => showKanadeSheet<String>(
  context: context,
  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
  builder: (_) =>
      _PlaylistNameSheet(title: title, action: action, initial: initial),
);

/// 新建和重命名共用：标题 + 一行输入框，确认按钮在输入框右边，下滑或点空白处取消。
class _PlaylistNameSheet extends StatefulWidget {
  const _PlaylistNameSheet({
    required this.title,
    required this.action,
    required this.initial,
  });

  final String title;
  final String action;
  final String initial;

  @override
  State<_PlaylistNameSheet> createState() => _PlaylistNameSheetState();
}

class _PlaylistNameSheetState extends State<_PlaylistNameSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (_, fill) = sheetColors(scheme);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.outline),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(title: widget.title, subtitle: l.playlistSyncHint),
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (_, value, _) => Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLength: 40,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: l.playlistNameHint,
                    filled: true,
                    fillColor: fill,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    counterText: '',
                    suffixText: '${value.text.characters.length}/40',
                    suffixStyle: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border.copyWith(
                      borderSide: BorderSide(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                // 白底黑字（亮色模式反过来），抗色只留给播放相关
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.onSurface,
                  foregroundColor: scheme.surface,
                  minimumSize: const Size(64, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: value.text.trim().isEmpty ? null : _submit,
                child: Text(widget.action),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<MyPlaylist?> createPlaylist(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final library = context.read<LibraryController>();
  final name = await _playlistName(context, l.createPlaylist, action: l.create);
  if (name == null || !context.mounted) return null;
  try {
    final playlist = await library.createPlaylist(name);
    if (context.mounted) {
      showToast(context, l.playlistCreated, kind: ToastKind.success);
    }
    return playlist;
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        l.actionFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
    return null;
  }
}
