import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'keyed_route.dart';
import 'comments_page.dart';
import 'glass.dart';
import 'locate_current.dart';
import 'singer_page.dart';
import 'smooth_scroll.dart';
import 'song_tile.dart';
import 'widgets.dart';

class AlbumPage extends StatelessWidget {
  const AlbumPage({super.key, required this.mid, required this.name});

  final String mid;
  final String name;

  static Route<void> route(String mid, String name) =>
      keyedPage('album:$mid', (_) => AlbumPage(mid: mid, name: name));

  @override
  Widget build(BuildContext context) {
    return GlassBackScaffold(
      body: AsyncView<AlbumDetail>(
        load: () => api.getAlbumDetail(mid: mid),
        builder: (context, d) =>
            SmoothScroll(builder: (context, scroll) => _Body(d, scroll)),
      ),
    );
  }
}

/// 头部 + 歌曲列表。歌曲那段每行一样高，定位按钮才能直接算出某一首的位置。
class _Body extends StatefulWidget {
  const _Body(this.d, this.scroll);

  final AlbumDetail d;
  final ScrollController scroll;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _listKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    // 和原来的 ListView 一样，上下让出系统栏和播放条的高度
    final padding = MediaQuery.paddingOf(context);
    return LocateCurrentSong(
      controller: widget.scroll,
      listKey: _listKey,
      songs: d.songs,
      child: CustomScrollView(
        controller: widget.scroll,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(top: padding.top),
            sliver: SliverToBoxAdapter(child: _Head(d)),
          ),
          if (d.songs.isNotEmpty)
            SliverPrototypeExtentList.builder(
              key: _listKey,
              prototypeItem: SongTile(songs: d.songs, index: 0),
              itemCount: d.songs.length,
              itemBuilder: (context, i) => LocateHighlight(
                index: i,
                child: SongTile(songs: d.songs, index: i),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: padding.bottom)),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.d);

  final AlbumDetail d;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final grey = TextStyle(fontSize: 13, color: scheme.onSurfaceVariant);
    // 和歌单详情同一种头部：居中大封面 + 标题 + 一排按钮
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        24,
        GlassBackScaffold.topInset,
        24,
        12,
      ),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 40,
                  offset: Offset(0, 20),
                ),
              ],
            ),
            child: Cover(d.coverUrl, size: 196, radius: 20),
          ),
          const SizedBox(height: 18),
          Text(
            d.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              for (final s in d.singers)
                InkWell(
                  onTap: s.mid.isEmpty
                      ? null
                      : () =>
                            openPage(context, SingerPage.route(s.mid, s.name)),
                  child: Text(
                    s.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (d.publishDate.isNotEmpty) l.publishedOn(d.publishDate),
              d.company,
            ].where((s) => s.isNotEmpty).join(' · '),
            style: grey,
          ),
          if (d.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              d.description,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: grey.copyWith(fontSize: 12, height: 1.5),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: d.songs.isEmpty
                      ? null
                      : () => context.read<PlayerController>().playList(
                          d.songs,
                          0,
                        ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(l.playAll(d.songs.length)),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: l.comments,
                style: IconButton.styleFrom(
                  fixedSize: const Size(46, 46),
                  backgroundColor: scheme.surfaceContainerHigh,
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                onPressed: d.id == 0
                    ? null
                    : () => Navigator.of(context).push(CommentsPage.album(d)),
                icon: const Icon(Icons.comment_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
