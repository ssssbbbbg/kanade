import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'album_page.dart';
import 'mv_page.dart';
import 'player_bar_page.dart';
import 'smooth_scroll.dart';
import 'song_action_sheet.dart';
import 'song_actions.dart';
import 'song_list_page.dart';
import 'widgets.dart';

/// 列表顶上渐隐的高度。
const _fade = 16.0;

/// 相关歌单一次显示几个（3×2）。
const _playlistCount = 6;

/// 播放页右滑出来的歌曲信息页：发行信息、标签、AI 解读、精选视频、也在听、相关歌单。
/// 接口见 docs/qqmusic-player-detail-android-capture.md，哪一栏没内容就不显示。
class SongDetailView extends StatefulWidget {
  const SongDetailView({super.key});

  @override
  State<SongDetailView> createState() => _SongDetailViewState();
}

class _SongDetailViewState extends State<SongDetailView> {
  // 翻回主页面时面板会拆掉，再翻过来同一首歌不重新请求
  static String? _loadedMid;
  static Future<SongPage>? _future;

  /// 换一批之后的歌单；为空时用 [SongPage.playlists]。
  RelatedPlaylists? _playlists;
  final _seen = <String>{};
  bool _swapping = false;

  Future<SongPage> _load(Song song) {
    if (_loadedMid != song.mid || _future == null) {
      _loadedMid = song.mid;
      _future = api.getSongPage(songId: song.id, songMid: song.mid);
      _playlists = null;
      _seen.clear();
    }
    return _future!;
  }

  void _retry() => setState(() => _future = null);

  /// 服务端只对部分歌曲排除已显示的歌单，别的歌照样返回原来那几个；
  /// 没见过的排在前面，一个新的都没有就不再显示「换一批」。
  Future<void> _swap(Song song, RelatedPlaylists current) async {
    if (_swapping) return;
    _seen.addAll(current.playlists.take(_playlistCount).map((p) => p.id));
    setState(() => _swapping = true);
    try {
      final next = await api.getRelatedPlaylists(
        songId: song.id,
        exclude: _seen.toList(),
      );
      if (!mounted || _loadedMid != song.mid) return;
      final fresh = next.playlists.where((p) => !_seen.contains(p.id)).toList();
      setState(() {
        _playlists = fresh.isEmpty
            ? RelatedPlaylists(playlists: current.playlists, hasMore: false)
            : RelatedPlaylists(
                playlists: [
                  ...fresh,
                  ...next.playlists.where((p) => _seen.contains(p.id)),
                ],
                hasMore: next.hasMore,
              );
      });
    } catch (_) {
      // 换不了就留着这一批
    } finally {
      if (mounted) setState(() => _swapping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = context.select<PlayerController, Song?>((p) => p.current);
    if (song == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return FutureBuilder<SongPage>(
      future: _load(song),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.loadFailed(errorText(l, snap.error!)),
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _retry, child: Text(l.retry)),
              ],
            ),
          );
        }
        final page = snap.data;
        if (page == null) return const PageLoading();
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          // 顶上渐隐固定 [_fade] 高，内容从它下面开始，没滚动时第一行不会被淡掉
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0, _fade / r.height, 0.92, 1],
          ).createShader(r),
          child: _Content(
            key: ValueKey(song.mid),
            song: song,
            page: page,
            playlists: _playlists ?? page.playlists,
            swapping: _swapping,
            onSwap: (current) => _swap(song, current),
          ),
        );
      },
    );
  }
}

class _Content extends StatefulWidget {
  const _Content({
    super.key,
    required this.song,
    required this.page,
    required this.playlists,
    required this.swapping,
    required this.onSwap,
  });

  final Song song;
  final SongPage page;
  final RelatedPlaylists playlists;
  final bool swapping;
  final ValueChanged<RelatedPlaylists> onSwap;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final song = widget.song;
    final page = widget.page;
    final similarTitle = l.alsoListening(
      page.similarFrom.isEmpty ? singerNames(song) : page.similarFrom,
    );
    final playlists = widget.playlists.playlists.take(_playlistCount).toList();
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, _fade + 4, 24, 40),
      children: [
        Text(
          [
            if (page.publishDate.isNotEmpty) l.publishedOn(page.publishDate),
            song.albumName,
          ].where((x) => x.isNotEmpty).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Colors.white60),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                leading: ClipOval(
                  child: Cover(
                    singerAvatar(song.singers.firstOrNull?.mid ?? ''),
                    size: 30,
                    radius: 0,
                  ),
                ),
                label: l.searchKindSinger,
                value: singerNames(song),
                onTap: song.singers.any((s) => s.mid.isNotEmpty)
                    ? () => openSinger(context, song)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoCard(
                leading: Cover(song.coverUrl, size: 30, radius: 6),
                label: l.searchKindAlbum,
                value: song.albumName,
                onTap: song.albumMid.isEmpty
                    ? null
                    : () => pushFromPlayer(
                        context,
                        AlbumPage.route(song.albumMid, song.albumName),
                      ),
              ),
            ),
          ],
        ),
        if (page.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final t in page.tags) _Chip(t)],
          ),
        ],
        if (page.aiContent.isNotEmpty) ...[
          const SizedBox(height: 18),
          _AiCard(title: page.aiTitle, content: page.aiContent),
        ],
        if (page.videos.isNotEmpty) ...[
          _Header(l.featuredVideos),
          SizedBox(
            height: 112 + 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: page.videos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _VideoCard(page.videos[i]),
            ),
          ),
        ],
        if (page.similarSongs.isNotEmpty) ...[
          _Header(
            similarTitle,
            action: l.seeAll,
            onAction: () => pushFromPlayer(
              context,
              SongListPage.songs(similarTitle, page.similarSongs),
            ),
          ),
          _SongPager(page.similarSongs),
        ],
        if (playlists.isNotEmpty) ...[
          _Header(
            l.relatedPlaylists,
            action: widget.playlists.hasMore ? l.anotherBatch : null,
            busy: widget.swapping,
            onAction: () => widget.onSwap(widget.playlists),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
              childAspectRatio: 0.7,
            ),
            itemCount: playlists.length,
            itemBuilder: (_, i) {
              final p = playlists[i];
              return PlaylistCard(
                title: p.title,
                coverUrl: p.coverUrl,
                badge: p.playCount > BigInt.zero
                    ? '▶ ${formatCount(l, p.playCount.toInt())}'
                    : null,
                onTap: () => pushFromPlayer(
                  context,
                  SongListPage.playlist(p.id, p.title),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, {this.action, this.onAction, this.busy = false});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          if (action != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: busy ? null : onAction,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  action!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: busy ? 0.3 : 0.6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.leading,
    required this.label,
    required this.value,
    this.onTap,
  });

  final Widget leading;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.tag);

  final SongTag tag;

  @override
  Widget build(BuildContext context) {
    const icon = 14.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tag.iconUrl.isNotEmpty) ...[
            Image.network(
              httpsUrl(tag.iconUrl),
              width: icon,
              height: icon,
              cacheWidth: (icon * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            tag.text,
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// AI 解读：默认三行，点一下展开全文。
class _AiCard extends StatefulWidget {
  const _AiCard({required this.title, required this.content});

  final String title;
  final String content;

  @override
  State<_AiCard> createState() => _AiCardState();
}

class _AiCardState extends State<_AiCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'AI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.content,
                  maxLines: _open ? null : 3,
                  overflow: _open ? null : TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.65,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _open ? l.showLess : l.showMore,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard(this.video);

  final VideoBrief video;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () => pushFromPlayer(context, MvPage.route(video.vid, video.name)),
      child: SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 112,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Cover(video.coverUrl, radius: 10),
                  if (video.playCount > BigInt.zero)
                    Positioned(
                      left: 8,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '▶ ${formatCount(l, video.playCount.toInt())}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              video.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 和 QQ 音乐一样每列三首，左右滑动换列，右边露出下一列的一截。
class _SongPager extends StatefulWidget {
  const _SongPager(this.songs);

  final List<Song> songs;

  @override
  State<_SongPager> createState() => _SongPagerState();
}

class _SongPagerState extends State<_SongPager> {
  static const _rows = 3, _rowHeight = 60.0;
  final _pages = PageController(viewportFraction: 0.9);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.songs;
    final columns = (songs.length + _rows - 1) ~/ _rows;
    return SizedBox(
      height: _rows * _rowHeight,
      child: PageView.builder(
        controller: _pages,
        padEnds: false,
        itemCount: columns,
        itemBuilder: (_, c) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            children: [
              for (final s in songs.skip(c * _rows).take(_rows))
                SizedBox(height: _rowHeight, child: _SongRow(s)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 点一下插到当前歌后面并马上播放，队列里其他歌不动。
class _SongRow extends StatelessWidget {
  const _SongRow(this.song);

  final Song song;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        final p = context.read<PlayerController>();
        if (p.playNext(song) == PlayNextResult.queued) p.next();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Cover(song.coverUrl, size: 46, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    singerNames(song),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.white60),
                  ),
                ],
              ),
            ),
            _RowLike(song),
          ],
        ),
      ),
    );
  }
}

/// 行尾的红心，和播放页的红心同一个收藏状态。
class _RowLike extends StatelessWidget {
  const _RowLike(this.song);

  final Song song;

  @override
  Widget build(BuildContext context) {
    final liked = context.select<LibraryController, bool>(
      (lib) => lib.isLiked(song),
    );
    final l = AppLocalizations.of(context);
    return IconButton(
      tooltip: liked ? l.unlike : l.like,
      onPressed: () => toggleLike(context, song),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.elasticOut,
        transitionBuilder: (child, a) =>
            ScaleTransition(scale: a, child: child),
        child: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(liked),
          size: 20,
          color: liked ? const Color(0xFFFF4D6D) : Colors.white60,
        ),
      ),
    );
  }
}
