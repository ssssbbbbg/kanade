import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'glass.dart';
import 'keyed_route.dart';
import 'singer_page.dart';
import 'smooth_scroll.dart';
import 'song_list_page.dart';
import 'song_tile.dart';
import 'toast.dart';
import 'video_tile.dart';
import 'widgets.dart';

enum _Kind { song, album, playlist, book, radar, video }

/// 云端最近播放：歌曲、专辑、歌单、视频、有声分开看，顶上一排胶囊切换。
class RecentPage extends StatefulWidget {
  const RecentPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const RecentPage());

  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
  _Kind _kind = _Kind.song;

  // 两份数据都在打开页面时开始取，胶囊上的数量随到随显示。
  late final Future<List<Song>> _songs = api.getRecentPlays();
  late final Future<RecentCollections> _collections = api
      .getRecentCollections();
  List<Song>? _songList;
  RecentCollections? _loaded;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  void _watch() {
    _songs.then(
      (v) => mounted ? setState(() => _songList = v) : null,
      onError: (_) {},
    );
    _collections.then(
      (v) => mounted ? setState(() => _loaded = v) : null,
      onError: (_) {},
    );
  }

  int? _count(_Kind kind) => switch (kind) {
    _Kind.song => _songList?.length,
    _Kind.album => _loaded?.albums.length,
    _Kind.playlist => _loaded?.playlists.length,
    _Kind.video => _loaded?.videos.length,
    _Kind.book => _loaded?.books.length,
    _Kind.radar => _loaded?.radios.length,
  };

  String _label(AppLocalizations l, _Kind kind) {
    final name = switch (kind) {
      _Kind.song => l.searchKindSong,
      _Kind.album => l.searchKindAlbum,
      _Kind.playlist => l.searchKindPlaylist,
      _Kind.video => l.searchKindVideo,
      _Kind.book => l.recentKindAudiobook,
      _Kind.radar => l.recentKindRadar,
    };
    final count = _count(kind);
    return count == null ? name : '$name $count';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return GlassBackScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左边让出浮着的玻璃返回钮
          Padding(
            padding: EdgeInsets.fromLTRB(76, top + 8, 16, 0),
            child: SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l.recentPlays,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                for (final kind in _Kind.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Pill(
                      label: _label(l, kind),
                      selected: kind == _kind,
                      onTap: () => setState(() => _kind = kind),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _kind == _Kind.song
                ? AsyncView<List<Song>>(
                    key: ValueKey(_songs),
                    load: () => _songs,
                    builder: (context, songs) => _SongsView(songs),
                  )
                : AsyncView<RecentCollections>(
                    key: ValueKey((_collections, _kind)),
                    load: () => _collections,
                    builder: (context, c) => _list(l, c),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _list(AppLocalizations l, RecentCollections c) {
    final count = _count(_kind)!;
    if (count == 0) return Center(child: Text(l.noItems));
    return SmoothScroll(
      builder: (context, scroll) => ListView.builder(
        key: ValueKey(_kind),
        controller: scroll,
        itemCount: count + 1,
        itemBuilder: (context, i) =>
            i == count ? const BottomSpacer() : _item(l, c, i),
      ),
    );
  }

  /// 和首页的猜你喜欢一样当电台放，快放完时自动续取下一批。
  Future<void> _playRadio(AppLocalizations l, int id) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await context.read<PlayerController>().playRadio(RadioSource.station(id));
    } catch (e) {
      Toast.show(
        overlay,
        l.radioFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
  }

  Widget _item(AppLocalizations l, RecentCollections c, int i) {
    switch (_kind) {
      case _Kind.album:
        return AlbumTile(c.albums[i]);
      case _Kind.playlist:
        final p = c.playlists[i];
        return ListTile(
          leading: Cover(p.coverUrl, size: 52, radius: 12),
          title: Text(
            p.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              l.songCount(p.songCount),
              if (p.creator.isNotEmpty) p.creator,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => openPage(context, SongListPage.playlist(p.id, p.title)),
        );
      case _Kind.video:
        return VideoTile(c.videos[i]);
      case _Kind.book:
        final b = c.books[i];
        final episode = b.episode;
        return ListTile(
          leading: Cover(b.coverUrl, size: 52, radius: 12),
          title: Text(
            b.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: episode == null
              ? null
              : Text(
                  episode.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          // 播放上次听到的那一集
          onTap: episode == null
              ? null
              : () => context.read<PlayerController>().playList([episode], 0),
        );
      case _Kind.radar:
        final r = c.radios[i];
        return ListTile(
          leading: Cover(r.coverUrl, size: 52, radius: 12),
          title: Text(
            r.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          onTap: () => _playRadio(l, r.id),
        );
      case _Kind.song:
        throw StateError('songs use _SongsView');
    }
  }
}

/// 歌曲分类：播放全部、按歌名歌手筛选。
class _SongsView extends StatefulWidget {
  const _SongsView(this.songs);

  final List<Song> songs;

  @override
  State<_SongsView> createState() => _SongsViewState();
}

class _SongsViewState extends State<_SongsView> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<Song> get _shown {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.songs;
    return [
      for (final s in widget.songs)
        if (s.name.toLowerCase().contains(q) ||
            s.singers.any((e) => e.name.toLowerCase().contains(q)))
          s,
    ];
  }

  void _search(bool on) {
    setState(() {
      _searching = on;
      if (!on) _query.clear();
    });
    on ? _focus.requestFocus() : _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final shown = _shown;
    if (widget.songs.isEmpty) return Center(child: Text(l.noItems));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: SizedBox(
            height: 48,
            child: _searching
                ? Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _query,
                            focusNode: _focus,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(
                              hintText: l.filterSongsHint,
                              filled: true,
                              fillColor: scheme.surfaceContainerHigh,
                              contentPadding: EdgeInsets.zero,
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onSurface,
                        ),
                        onPressed: () => _search(false),
                        child: Text(l.cancel),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => context
                            .read<PlayerController>()
                            .playList(widget.songs, 0),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(l.playAll(widget.songs.length)),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: l.filterSongsHint,
                        onPressed: () => _search(true),
                        icon: const Icon(Icons.search_rounded),
                      ),
                    ],
                  ),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text(l.searchNoResults))
              : SmoothScroll(
                  builder: (context, scroll) => ListView.builder(
                    controller: scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: shown.length + 1,
                    itemBuilder: (context, i) => i == shown.length
                        ? const BottomSpacer()
                        : SongTile(songs: shown, index: i),
                  ),
                ),
        ),
      ],
    );
  }
}
