import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'album_page.dart';
import 'comments_page.dart';
import 'mv_page.dart';
import 'player_bar_page.dart';
import 'sheet.dart';
import 'singer_page.dart';
import 'song_actions.dart';
import 'song_list_page.dart';
import 'widgets.dart';

void openSinger(BuildContext context, Song song) {
  final singers = song.singers.where((s) => s.mid.isNotEmpty).toList();
  if (singers.length == 1) {
    pushFromPlayer(
      context,
      SingerPage.route(singers.first.mid, singers.first.name),
    );
    return;
  }
  showKanadeSheet<void>(
    context: context,
    builder: (sheet) => SheetGroup(
      children: [
        for (final s in singers)
          SheetRow(
            leading: const Icon(Icons.person_outline_rounded),
            title: s.name,
            chevron: true,
            onTap: () {
              Navigator.pop(sheet);
              pushFromPlayer(context, SingerPage.route(s.mid, s.name));
            },
          ),
      ],
    ),
  );
}

/// 歌曲的更多操作：上排快捷操作，下方为 MV、相似歌曲、歌手和专辑。
/// 在自己的歌单里打开时传入 [onRemove]，多出“从歌单中删除”。
Future<void> showSongActions(
  BuildContext context,
  Song song, {
  VoidCallback? onRemove,
}) {
  final l = AppLocalizations.of(context);
  return showKanadeSheet<void>(
    context: context,
    builder: (sheet) {
      final liked = sheet.watch<LibraryController>().isLiked(song);
      // 正在放的这首（比如从播放页打开）没必要“下一首播放”
      final isCurrent = sheet.select<PlayerController, bool>(
        (p) => p.current?.mid == song.mid,
      );
      // 先关掉面板，再用外层 context 执行，面板关闭后 sheet 就失效了
      void run(void Function() action) {
        Navigator.pop(sheet);
        action();
      }

      final hasSinger = song.singers.any((s) => s.mid.isNotEmpty);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            leading: Cover(song.coverUrl, size: 48, radius: 10),
            title: song.name,
            subtitle: singerNames(song),
          ),
          SheetQuickActions(
            children: [
              if (!isCurrent)
                SheetQuickAction(
                  icon: Icons.queue_play_next_rounded,
                  label: l.playNext,
                  onTap: () => run(() => playNext(context, song)),
                ),
              SheetQuickAction(
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                iconColor: liked ? Theme.of(sheet).colorScheme.primary : null,
                label: liked ? l.likedShort : l.likeShort,
                onTap: () => run(() => toggleLike(context, song)),
              ),
              SheetQuickAction(
                icon: Icons.playlist_add_rounded,
                label: l.addToPlaylist,
                onTap: () => run(() => addToPlaylist(context, song)),
              ),
              SheetQuickAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: l.comments,
                onTap: () => run(
                  () => Navigator.of(context).push(CommentsPage.song(song)),
                ),
              ),
            ],
          ),
          SheetGroup(
            children: [
              if (song.mvVid.isNotEmpty)
                SheetRow(
                  leading: const Icon(Icons.music_video_rounded),
                  title: l.watchMv,
                  chevron: true,
                  onTap: () => run(
                    () =>
                        Navigator.of(context)
                            .push(MvPage.route(song.mvVid, song.name)),
                  ),
                ),
              SheetRow(
                leading: const Icon(Icons.manage_search_rounded),
                title: l.findSimilarSongs,
                chevron: true,
                onTap: () => run(
                  () => pushFromPlayer(
                    context,
                    SongListPage.similar(song, l.similarSongsTitle(song.name)),
                  ),
                ),
              ),
              if (hasSinger)
                SheetRow(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: l.singerNamed(singerNames(song)),
                  chevron: true,
                  onTap: () => run(() => openSinger(context, song)),
                ),
              if (song.albumMid.isNotEmpty)
                SheetRow(
                  leading: const Icon(Icons.album_outlined),
                  title: l.albumNamed(song.albumName),
                  chevron: true,
                  onTap: () => run(
                    () => pushFromPlayer(
                      context,
                      AlbumPage.route(song.albumMid, song.albumName),
                    ),
                  ),
                ),
              if (onRemove != null)
                SheetRow(
                  leading: const Icon(Icons.playlist_remove_rounded),
                  title: l.removeFromPlaylist,
                  destructive: true,
                  onTap: () => run(onRemove),
                ),
            ],
          ),
        ],
      );
    },
  );
}
