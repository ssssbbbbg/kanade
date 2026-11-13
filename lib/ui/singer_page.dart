import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'keyed_route.dart';
import 'album_page.dart';
import 'follow_button.dart';
import 'glass.dart';
import 'profile_layout.dart';
import 'smooth_scroll.dart';
import 'video_tile.dart';
import 'song_tile.dart';
import 'widgets.dart';

/// 歌手页：顶部大图，下面是精选、歌曲、专辑、视频、详情五个分类。
class SingerPage extends StatelessWidget {
  const SingerPage({super.key, required this.mid, required this.name});

  final String mid;
  final String name;

  static Route<void> route(String mid, String name) =>
      keyedPage('singer:$mid', (_) => SingerPage(mid: mid, name: name));

  @override
  Widget build(BuildContext context) {
    return GlassBackScaffold(
      body: AsyncView<SingerDetail>(
        load: () => api.getSingerDetail(mid: mid),
        builder: (context, d) => _SingerBody(d),
      ),
    );
  }
}

enum _Tab { featured, songs, albums, videos, about }

class _SingerBody extends StatefulWidget {
  const _SingerBody(this.d);

  final SingerDetail d;

  @override
  State<_SingerBody> createState() => _SingerBodyState();
}

class _SingerBodyState extends State<_SingerBody> {
  static const _heroHeight = 280.0;
  static const _barHeight = 56.0;

  final _scroll = SmoothScrollController();
  final _marker = GlobalKey();
  var _tab = _Tab.featured;

  late final _songs = Pager<Song>(
    (_, offset) async {
      final next = await api.getSingerSongs(
        mid: widget.d.mid,
        begin: offset,
        num: 30,
      );
      return (next, offset + next.length < widget.d.songTotal);
    },
    initial: widget.d.songs,
    hasMore: widget.d.songs.length < widget.d.songTotal,
  );
  late final _albums = Pager<AlbumBrief>(
    (_, offset) async {
      final next = await api.getSingerAlbums(
        mid: widget.d.mid,
        begin: offset,
        num: 30,
      );
      return (next, offset + next.length < widget.d.albumTotal);
    },
    initial: widget.d.albums,
    hasMore: widget.d.albums.length < widget.d.albumTotal,
  );

  late final Future<List<VideoTag>> _tags = api.getSingerVideoTags(
    mid: widget.d.mid,
  );
  VideoTag? _tag;
  int _order = 0;
  Pager<VideoBrief>? _videos;

  String? _account;
  Future<SingerSocial>? _social;
  bool? _followed;

  @override
  void dispose() {
    _scroll.dispose();
    _songs.dispose();
    _albums.dispose();
    _videos?.dispose();
    super.dispose();
  }

  void _select(_Tab tab) {
    keepPinned(
      _scroll,
      _marker,
      MediaQuery.paddingOf(context).top + _barHeight,
    );
    setState(() => _tab = tab);
  }

  Pager<VideoBrief> _videoPager(int tag) {
    final d = widget.d;
    final order = _order;
    return _videos ??= Pager<VideoBrief>((_, offset) async {
      final page = await api.getSingerVideos(
        mid: d.mid,
        name: d.name,
        tag: tag,
        order: order,
        begin: offset,
        num: 40,
      );
      return (page.videos, offset + page.videos.length < page.total);
    });
  }

  void _filterVideos(VoidCallback change) {
    keepPinned(
      _scroll,
      _marker,
      MediaQuery.paddingOf(context).top + _barHeight,
    );
    setState(() {
      change();
      _videos?.dispose();
      _videos = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = widget.d;
    // 换了账号要重新取关注状态
    final account = context.select<AuthController, String?>((a) => a.user?.uin);
    if (_social == null || account != _account) {
      _account = account;
      _social = api.getSingerSocial(mid: d.mid);
      _followed = null;
    }
    final top = MediaQuery.paddingOf(context).top;
    return FutureBuilder<SingerSocial>(
      future: _social,
      builder: (context, snap) {
        final social = snap.data;
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _Hero(
                d: d,
                subtitle: social == null
                    ? ''
                    : [
                        l.userFans(formatCount(l, social.fansCount.toInt())),
                        social.guardTitle,
                      ].where((s) => s.isNotEmpty).join(' · '),
                top: top,
                maxHeight: top + _heroHeight,
                minHeight: top + _barHeight,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 46),
                        ),
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
                    if (social != null) ...[
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 46,
                        child: FollowButton(
                          followed: _followed ?? social.followed,
                          onChanged: (value) async {
                            await api.setSingerFollowed(
                              mid: d.mid,
                              followed: value,
                            );
                            if (mounted) setState(() => _followed = value);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(key: _marker),
            SliverPersistentHeader(
              pinned: true,
              delegate: PinnedBox(
                height: 56,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: PillRow(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    spacing: 12,
                    children: [
                      for (final (tab, label) in [
                        (_Tab.featured, l.singerFeatured),
                        (_Tab.songs, l.tabSongs),
                        (_Tab.albums, l.tabAlbums),
                        (_Tab.videos, l.searchKindVideo),
                        (_Tab.about, l.singerAbout),
                      ])
                        UnderlineTab(
                          label: label,
                          selected: _tab == tab,
                          onTap: () => _select(tab),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            ...switch (_tab) {
              _Tab.featured => _featured(l),
              _Tab.songs => [
                PagedSliver(
                  pager: _songs,
                  itemBuilder: (_, items, i) =>
                      SongTile(songs: items, index: i),
                ),
              ],
              _Tab.albums => [
                PagedSliver(
                  pager: _albums,
                  itemBuilder: (_, items, i) => AlbumTile(items[i]),
                ),
              ],
              _Tab.videos => [_videoSlivers(l)],
              _Tab.about => _about(l, social),
            },
            PinFiller(marker: _marker, pinnedAbove: top + _barHeight),
          ],
        );
      },
    );
  }

  List<Widget> _featured(AppLocalizations l) {
    final d = widget.d;
    return [
      SliverToBoxAdapter(
        child: SectionHeader(
          l.tabSongs,
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
          onMore: d.songTotal > 10 ? () => _select(_Tab.songs) : null,
        ),
      ),
      SliverList.builder(
        itemCount: d.songs.length < 10 ? d.songs.length : 10,
        itemBuilder: (_, i) => SongTile(songs: d.songs, index: i),
      ),
      if (d.selectedAlbums.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            l.singerSelectedAlbums,
            padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
            onMore: () => _select(_Tab.albums),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: d.selectedAlbums.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _AlbumCard(d.selectedAlbums[i]),
            ),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: BottomSpacer()),
    ];
  }

  Widget _videoSlivers(AppLocalizations l) {
    return FutureBuilder<List<VideoTag>>(
      future: _tags,
      builder: (context, snap) {
        if (snap.hasError) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  l.loadFailed(errorText(l, snap.error!)),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final tags = snap.data;
        if (tags == null) {
          return const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(32), child: PageLoading()),
          );
        }
        if (tags.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(l.noItems)),
            ),
          );
        }
        final tag = (_tag ?? tags.first).id;
        final scheme = Theme.of(context).colorScheme;
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: PillRow(
                        padding: const EdgeInsets.only(left: 20, right: 8),
                        spacing: 4,
                        children: [
                          for (final t in tags)
                            Pill(
                              label: t.name,
                              selected: tag == t.id,
                              small: true,
                              onTap: () => _filterVideos(() => _tag = t),
                            ),
                        ],
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _filterVideos(() => _order = 1 - _order),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.swap_vert_rounded,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _order == 0 ? l.newest : l.hottest,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
            PagedSliver(
              pager: _videoPager(tag),
              itemBuilder: (_, items, i) => VideoTile(items[i]),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _about(AppLocalizations l, SingerSocial? social) {
    final d = widget.d;
    final scheme = Theme.of(context).colorScheme;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _StatCard(
                    value: social == null
                        ? '-'
                        : formatCount(l, social.fansCount.toInt()),
                    label: l.statFans,
                  ),
                  const SizedBox(width: 8),
                  _StatCard(value: '${d.songTotal}', label: l.tabSongs),
                  const SizedBox(width: 8),
                  _StatCard(value: '${d.albumTotal}', label: l.tabAlbums),
                ],
              ),
              if (social != null && social.guardTitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 22,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.singerGuard,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                social.guardTitle,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
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
              const SizedBox(height: 22),
              Text(
                l.singerBio,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                d.description.isEmpty ? l.noItems : d.description,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.75,
                  color: scheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
      const SliverToBoxAdapter(child: BottomSpacer()),
    ];
  }
}

/// 顶部大图；往上滚时缩成一条，左边让出返回按钮，显示小头像和名字。
class _Hero extends SliverPersistentHeaderDelegate {
  _Hero({
    required this.d,
    required this.subtitle,
    required this.top,
    required this.maxHeight,
    required this.minHeight,
  });

  final SingerDetail d;
  final String subtitle;
  final double top;
  final double maxHeight;
  final double minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  double get minExtent => minHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final t = (shrinkOffset / (maxHeight - minHeight)).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        Cover(d.photoUrl, radius: 0),
        // 底部压暗好放字；收起时整张盖住
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.4, 1],
              colors: [
                scheme.surface.withValues(alpha: t),
                scheme.surface,
              ],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 12,
          child: Opacity(
            opacity: (1 - t * 2).clamp(0.0, 1.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Positioned(
          left: 72,
          right: 20,
          top: top,
          height: minHeight - top,
          child: Opacity(
            opacity: ((t - 0.6) / 0.4).clamp(0.0, 1.0),
            child: Row(
              children: [
                ClipOval(child: Cover(d.avatarUrl, size: 32, radius: 0)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(_Hero old) =>
      old.d != d ||
      old.subtitle != subtitle ||
      old.top != top ||
      old.maxHeight != maxHeight ||
      old.minHeight != minHeight;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard(this.album);

  final AlbumBrief album;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 120,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openPage(context, AlbumPage.route(album.mid, album.name)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Cover(album.coverUrl, size: 120, radius: 12),
            const SizedBox(height: 8),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              album.publishDate,
              maxLines: 1,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class AlbumTile extends StatelessWidget {
  const AlbumTile(this.album, {super.key});

  final AlbumBrief album;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Cover(album.coverUrl, size: 52, radius: 12),
      title: Text(
        album.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          album.singerName,
          album.publishDate,
        ].where((s) => s.isNotEmpty).join(' · '),
      ),
      onTap: () => openPage(context, AlbumPage.route(album.mid, album.name)),
    );
  }
}
