import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'keyed_route.dart';
import 'follow_button.dart';
import 'glass.dart';
import 'profile_layout.dart';
import 'singer_page.dart' show AlbumTile;
import 'smooth_scroll.dart';
import 'song_list_page.dart';
import 'video_tile.dart';
import 'song_tile.dart';
import 'widgets.dart';

/// 用户主页：头像、数字和简介，下面是创建的歌单、我喜欢（歌曲 / 歌单 / 专辑 / 视频）。
class UserPage extends StatelessWidget {
  const UserPage({super.key, required this.euin, required this.name});

  final String euin;
  final String name;

  static Route<void> route(String euin, String name) =>
      keyedPage('user:$euin', (_) => UserPage(euin: euin, name: name));

  @override
  Widget build(BuildContext context) {
    final account = context.select<AuthController, String?>((a) => a.user?.uin);
    return GlassBackScaffold(
      body: AsyncView<UserProfile>(
        key: ValueKey((euin, account)),
        load: () => api.getUserProfile(euin: euin),
        builder: (context, p) => _ProfileBody(p),
      ),
    );
  }
}

class _ProfileBody extends StatefulWidget {
  const _ProfileBody(this.profile);

  final UserProfile profile;

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  static const _barHeight = 56.0;

  final _scroll = SmoothScrollController();
  final _marker = GlobalKey();
  bool _likes = false;
  UserAssetKind _kind = UserAssetKind.song;
  late bool _followed = widget.profile.followed;

  late final _playlists = Pager<PlaylistBrief>(
    (page, _) async {
      final p = widget.profile;
      final r = await api.getUserPublicPlaylists(
        euin: p.euin,
        creator: p.name,
        page: page,
        pageSize: 30,
      );
      return (r.playlists, r.hasMore);
    },
    hasMore:
        widget.profile.playlistCount > 0 && !widget.profile.playlistsHidden,
  );
  final _assets = <UserAssetKind, Pager<UserAssetPage>>{};
  final _hidden = <UserAssetKind>{};

  @override
  void dispose() {
    _scroll.dispose();
    _playlists.dispose();
    for (final p in _assets.values) {
      p.dispose();
    }
    super.dispose();
  }

  void _select(VoidCallback change) {
    keepPinned(
      _scroll,
      _marker,
      MediaQuery.paddingOf(context).top + _barHeight,
    );
    setState(change);
  }

  /// 一页结果当成一个条目存，四类资产共用一个 [Pager]。
  Pager<UserAssetPage> _assetPager(UserAssetKind kind) =>
      _assets[kind] ??= Pager((page, _) async {
        final r = await api.getUserAssets(
          euin: widget.profile.euin,
          kind: kind,
          page: page,
          pageSize: 30,
        );
        if (r.hidden && mounted) setState(() => _hidden.add(kind));
        final empty =
            r.songs.isEmpty &&
            r.playlists.isEmpty &&
            r.albums.isEmpty &&
            r.videos.isEmpty;
        return (empty ? <UserAssetPage>[] : [r], r.hasMore);
      });

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final l = AppLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: PinnedBox(
            height: top + _barHeight,
            child: Padding(
              padding: EdgeInsets.only(top: top, left: 72, right: 20),
              // 头部滚出去以后才显示名字
              child: ListenableBuilder(
                listenable: _scroll,
                builder: (context, child) => Opacity(
                  opacity: _scroll.hasClients
                      ? ((_scroll.offset - 70) / 50).clamp(0.0, 1.0)
                      : 0,
                  child: child,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Head(
            p,
            followed: _followed,
            onFollow: (value) async {
              await api.setUserFollowed(euin: p.euin, followed: value);
              if (mounted) setState(() => _followed = value);
            },
          ),
        ),
        SliverToBoxAdapter(key: _marker),
        SliverPersistentHeader(
          pinned: true,
          delegate: PinnedBox(
            height: _likes ? 100 : 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PillRow(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  spacing: 12,
                  children: [
                    UnderlineTab(
                      label: l.playlistsCreated,
                      selected: !_likes,
                      onTap: () => _select(() => _likes = false),
                    ),
                    UnderlineTab(
                      label: l.userLikes,
                      selected: _likes,
                      onTap: () => _select(() => _likes = true),
                    ),
                  ],
                ),
                if (_likes) ...[
                  const SizedBox(height: 10),
                  PillRow(
                    spacing: 4,
                    children: [
                      for (final (kind, label) in [
                        (UserAssetKind.song, l.tabSongs),
                        (UserAssetKind.playlist, l.searchKindPlaylist),
                        (UserAssetKind.album, l.tabAlbums),
                        (UserAssetKind.video, l.searchKindVideo),
                      ])
                        Pill(
                          label: label,
                          selected: _kind == kind,
                          small: true,
                          onTap: () => _select(() => _kind = kind),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!_likes)
          PagedSliver(
            pager: _playlists,
            emptyText: p.playlistsHidden ? l.userPrivate : l.userNoPlaylists,
            itemBuilder: (context, items, i) => _PlaylistTile(items[i]),
          )
        else
          _assetsSliver(l),
        PinFiller(marker: _marker, pinnedAbove: top + _barHeight),
      ],
    );
  }

  Widget _assetsSliver(AppLocalizations l) {
    final kind = _kind;
    final pager = _assetPager(kind);
    return ListenableBuilder(
      listenable: pager,
      builder: (context, _) {
        // 把各页摊平成一个列表，歌曲要整张列表才能连着播
        final pages = pager.items;
        final songs = [for (final r in pages) ...r.songs];
        final playlists = [for (final r in pages) ...r.playlists];
        final albums = [for (final r in pages) ...r.albums];
        final videos = [for (final r in pages) ...r.videos];
        final count =
            songs.length + playlists.length + albums.length + videos.length;
        return SliverMainAxisGroup(
          slivers: [
            SliverList.builder(
              itemCount: count,
              itemBuilder: (context, i) => switch (kind) {
                UserAssetKind.song => SongTile(songs: songs, index: i),
                UserAssetKind.video => VideoTile(videos[i]),
                UserAssetKind.album => AlbumTile(albums[i]),
                UserAssetKind.playlist => _PlaylistTile(playlists[i]),
              },
            ),
            // 只用来显示加载 / 出错 / 空，条目都在上面
            PagedSliver<UserAssetPage>(
              key: ValueKey(kind),
              pager: pager,
              emptyText: _hidden.contains(kind) ? l.userPrivate : l.noItems,
              itemBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile(this.p);

  final PlaylistBrief p;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: Cover(p.coverUrl, size: 52, radius: 12),
      title: Text(
        p.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: p.songCount > 0 ? Text(l.songCount(p.songCount)) : null,
      onTap: () => openPage(context, SongListPage.playlist(p.id, p.title)),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.p, {required this.followed, required this.onFollow});

  final UserProfile p;
  final bool followed;
  final Future<void> Function(bool) onFollow;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipOval(child: Cover(p.avatarUrl, size: 84, radius: 0)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _Stat(formatCount(l, p.fansCount.toInt()), l.statFans),
                        const SizedBox(width: 20),
                        _Stat(
                          formatCount(l, p.followCount.toInt()),
                          l.statFollows,
                        ),
                        const SizedBox(width: 20),
                        _Stat('${p.playlistCount}', l.statPlaylists),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (p.intro.isNotEmpty) ...[
            const SizedBox(height: 16),
            IntroText(p.intro),
          ],
          if (!p.isSelf) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: FollowButton(followed: followed, onChanged: onFollow),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

/// 简介默认两行，放不下才出现“展开”。
class IntroText extends StatefulWidget {
  const IntroText(this.text, {super.key});

  final String text;

  @override
  State<IntroText> createState() => _IntroTextState();
}

class _IntroTextState extends State<IntroText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 14,
      height: 1.6,
      color: scheme.onSurface.withValues(alpha: 0.8),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 2,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: _open ? null : 2,
              overflow: _open ? null : TextOverflow.ellipsis,
              style: style,
            ),
            if (overflows)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(fontSize: 13),
                ),
                onPressed: () => setState(() => _open = !_open),
                iconAlignment: IconAlignment.end,
                icon: Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(_open ? l.showLess : l.showMore),
              ),
          ],
        );
      },
    );
  }
}
