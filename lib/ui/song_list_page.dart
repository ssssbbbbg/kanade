import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/app_localizations.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'keyed_route.dart';
import 'glass.dart';
import 'locate_current.dart';
import 'playlist_actions.dart';
import 'smooth_scroll.dart';
import 'song_actions.dart';
import 'song_tile.dart';
import 'widgets.dart';

/// period 只有榜单有，用来显示“更新于 …”。owned 是自己的歌单时才有，可以删歌。
typedef ListData = ({
  String title,
  String cover,
  String creator,
  String period,
  String description,
  List<Song> songs,
  MyPlaylist? owned,
});

/// 歌单详情 / 榜单详情共用的页面。
class SongListPage extends StatelessWidget {
  const SongListPage({
    super.key,
    required this.title,
    required this.load,
    this.ranked = false,
    this.searchable = false,
  });

  final String title;
  final Future<ListData> Function() load;

  /// 显示名次。
  final bool ranked;

  /// 头部有搜索钮，点开后顶栏变成搜索框，按歌名、歌手筛选。
  final bool searchable;

  static Route<void> playlist(String id, String title) => keyedPage(
    'playlist:$id',
    (context) => SongListPage(
      title: title,
      searchable: true,
      load: () async {
        final mine = context.read<LibraryController>().ownPlaylist(id);
        final d = await api.getPlaylistDetail(id: id);
        final owned = await mine;
        // “我喜欢”自带的封面是一张固定的红心图，铺满头部不好看，换成第一首歌的封面
        final liked =
            owned != null && isLikedPlaylist(owned) && d.songs.isNotEmpty;
        return (
          title: d.title,
          cover: liked ? d.songs.first.coverUrl : d.coverUrl,
          creator: d.creator,
          period: '',
          description: d.description,
          songs: d.songs,
          owned: owned,
        );
      },
    ),
  );

  /// 已经拿到的歌曲列表，比如推荐页某个区块的“查看全部”。
  static Route<void> songs(String title, List<Song> songs) => MaterialPageRoute(
    builder: (_) => SongListPage(
      title: title,
      load: () async => (
        title: title,
        cover: songs.isEmpty ? '' : songs.first.coverUrl,
        creator: '',
        period: '',
        description: '',
        songs: songs,
        owned: null,
      ),
    ),
  );

  /// 当前歌曲的相似推荐，加载与重试复用歌曲列表页。
  static Route<void> similar(Song song, String title) => keyedPage(
    'similar:${song.mid}',
    (_) => SongListPage(
      title: title,
      load: () async => (
        title: title,
        cover: song.coverUrl,
        creator: '',
        period: '',
        description: '',
        songs: await api.getSimilarSongs(songId: song.id),
        owned: null,
      ),
    ),
  );

  static Route<void> toplist(int topId, String period, String title) =>
      MaterialPageRoute(
        builder: (_) => SongListPage(
          title: title,
          ranked: true,
          load: () async {
            final d = await api.getToplistDetail(topId: topId, period: period);
            return (
              title: d.title,
              cover: d.coverUrl,
              creator: '',
              period: d.period,
              description: d.description,
              songs: d.songs,
              owned: null,
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    // 标题放在下面的大封面头部里，左上角只浮一颗返回钮
    return GlassBackScaffold(
      body: AsyncView<ListData>(
        load: load,
        builder: (context, d) =>
            _Body(d, ranked: ranked, searchable: searchable),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body(this.d, {required this.ranked, required this.searchable});

  final ListData d;
  final bool ranked;
  final bool searchable;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> with SingleTickerProviderStateMixin {
  static const _heroHeight = 300.0;
  static const _barHeight = 56.0;

  /// 删歌成功后从这里去掉，不用重新加载整个歌单。
  late final List<Song> _songs = List.of(widget.d.songs);

  /// 改名后就地更新，不重新加载。
  late MyPlaylist? _owned = widget.d.owned;
  late String _title = widget.d.title;

  Future<void> _remove(Song song) async {
    if (await removeFromPlaylist(context, _owned!, song) && mounted) {
      setState(() => _songs.remove(song));
    }
  }

  Future<void> _edit() async {
    final owned = _owned!;
    switch (await showPlaylistActions(context, owned)) {
      case PlaylistRenamed(:final name):
        if (!mounted) return;
        setState(() {
          _title = name;
          _owned = MyPlaylist(
            dirId: owned.dirId,
            tid: owned.tid,
            name: name,
            coverUrl: owned.coverUrl,
            songCount: owned.songCount,
          );
        });
      case PlaylistDeleted():
        if (mounted) Navigator.of(context).pop();
      case null:
    }
  }

  final _query = TextEditingController();
  final _scroll = SmoothScrollController();
  final _listKey = GlobalKey();

  final _focus = FocusNode();

  /// 搜索时大封面收成顶栏、按钮行收起，标题淡出、搜索框淡入。
  bool _searching = false;
  late final _searchAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  late final _searchCurve = CurvedAnimation(
    parent: _searchAnim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInOutCubic,
  );

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    _focus.dispose();
    _searchCurve.dispose();
    _searchAnim.dispose();
    super.dispose();
  }

  void _search(bool on) {
    if (on == _searching) return;
    setState(() {
      _searching = on;
      if (!on) _query.clear();
    });
    if (on) {
      // 列表回到顶上，封面和按钮行一起收起来，看到的就是筛选结果的开头
      if (_scroll.hasClients && _scroll.offset > 0) {
        _scroll.animateTo(
          0,
          duration: _searchAnim.duration!,
          curve: Curves.easeOutCubic,
        );
      }
      _searchAnim.forward();
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      _searchAnim.reverse();
    }
  }

  /// 按歌名或歌手筛选，不区分大小写。点歌时只播筛出来的这些。
  List<Song> get _shown {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return _songs;
    return [
      for (final s in _songs)
        if (s.name.toLowerCase().contains(q) ||
            s.singers.any((e) => e.name.toLowerCase().contains(q)))
          s,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = widget.d;
    final top = MediaQuery.paddingOf(context).top;
    final shown = _searching ? _shown : _songs;
    final filtered = _searching && _query.text.trim().isNotEmpty;
    final onEdit = canEditPlaylist(_owned) ? _edit : null;
    return PopScope(
      // 搜索时返回先退出搜索
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _search(false);
      },
      child: LocateCurrentSong(
        controller: _scroll,
        listKey: _listKey,
        songs: shown,
        child: CustomScrollView(
          controller: _scroll,
          // 拖动列表时收起键盘
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            // 只有头部跟着动画每帧重建，下面的列表不动
            AnimatedBuilder(
              animation: _searchCurve,
              builder: (context, _) => SliverPersistentHeader(
                pinned: true,
                delegate: _Hero(
                  d: d,
                  title: _title,
                  meta: _meta(l, d),
                  top: top,
                  maxHeight: top + _heroHeight,
                  minHeight: top + _barHeight,
                  search: _searchCurve.value,
                  searchBar: _searchAnim.isDismissed
                      ? null
                      : IgnorePointer(
                          ignoring: !_searching,
                          child: _SearchBar(
                            _query,
                            focusNode: _focus,
                            onChanged: () => setState(() {}),
                            onCancel: () => _search(false),
                          ),
                        ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizeTransition(
                sizeFactor: ReverseAnimation(_searchCurve),
                alignment: Alignment.topCenter,
                child: FadeTransition(
                  opacity: ReverseAnimation(_searchCurve),
                  child: _Actions(
                    songs: _songs,
                    description: d.description
                        .replaceAll(RegExp(r'<[^>]+>'), '')
                        .trim(),
                    onSearch: widget.searchable ? () => _search(true) : null,
                    onEdit: onEdit,
                  ),
                ),
              ),
            ),
            if (filtered && shown.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.filterFound(shown.length),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: () =>
                            context.read<PlayerController>().playList(shown, 0),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(l.playFiltered(shown.length)),
                      ),
                    ],
                  ),
                ),
              ),
            if (shown.isEmpty && filtered)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text(l.searchNoResults)),
                ),
              )
            // 每行一样高，定位按钮才能直接算出某一首的位置；样板行拿第一首排，空歌单不放
            else if (shown.isNotEmpty)
              SliverPrototypeExtentList.builder(
                key: _listKey,
                prototypeItem: SongTile(
                  songs: shown,
                  index: 0,
                  rank: widget.ranked ? 1 : null,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final song = shown[i];
                  return LocateHighlight(
                    index: i,
                    child: SongTile(
                      songs: shown,
                      index: i,
                      // 筛选后仍显示原来的名次
                      rank: widget.ranked ? _songs.indexOf(song) + 1 : null,
                      // “我喜欢”里不给删，取消喜欢就行
                      onRemove: onEdit != null ? () => _remove(song) : null,
                    ),
                  );
                },
              ),
            const SliverToBoxAdapter(child: BottomSpacer()),
          ],
        ),
      ),
    );
  }

  String _meta(AppLocalizations l, ListData d) {
    final secs = _songs.fold<int>(0, (sum, s) => sum + s.durationSecs);
    final hours = secs ~/ 3600;
    final minutes = secs % 3600 ~/ 60;
    return [
      d.creator,
      l.songCount(_songs.length),
      if (secs > 0)
        hours > 0
            ? l.durationHoursMinutes(hours, minutes)
            : l.durationMinutes(minutes),
      if (d.period.isNotEmpty) l.updatedAt(d.period),
    ].where((s) => s.isNotEmpty).join(' · ');
  }
}

/// 封面铺满顶部，标题压在左下角；往上滚收成一条只有标题的顶栏。
/// 搜索时（[search] 从 0 到 1）整个头部也收成顶栏，标题换成 [searchBar]。
class _Hero extends SliverPersistentHeaderDelegate {
  _Hero({
    required this.d,
    required this.title,
    required this.meta,
    required this.top,
    required this.maxHeight,
    required this.minHeight,
    required this.search,
    required this.searchBar,
  });

  final ListData d;
  final String title;
  final String meta;
  final double top;
  final double maxHeight;
  final double minHeight;
  final double search;
  final Widget? searchBar;

  @override
  double get maxExtent => maxHeight + (minHeight - maxHeight) * search;

  @override
  double get minExtent => minHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // 按实际剩下的高度算收起了多少，滚动和搜索两种收法表现一致
    final height = max(minHeight, maxExtent - shrinkOffset);
    final t = ((maxHeight - height) / (maxHeight - minHeight)).clamp(0.0, 1.0);
    final bar = searchBar;
    return Stack(
      fit: StackFit.expand,
      children: [
        Cover(d.cover, radius: 0),
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
          bottom: 4,
          child: Opacity(
            opacity: (1 - t * 2).clamp(0.0, 1.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
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
            // 只有往上滚收起时显示；搜索时让给搜索框
            opacity: (((t - 0.6) / 0.4).clamp(0.0, 1.0) * (1 - search * 2))
                .clamp(0.0, 1.0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                title,
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
        if (bar != null)
          Positioned(
            left: 72,
            right: 8,
            top: top,
            height: minHeight - top,
            child: Opacity(
              opacity: ((search - 0.3) / 0.7).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(24 * (1 - search), 0),
                child: bar,
              ),
            ),
          ),
      ],
    );
  }

  @override
  bool shouldRebuild(_Hero old) =>
      old.d != d ||
      old.title != title ||
      old.meta != meta ||
      old.top != top ||
      old.maxHeight != maxHeight ||
      old.minHeight != minHeight ||
      old.search != search ||
      old.searchBar != searchBar;
}

/// 简介一行（点开看全文），下面左边是搜索、更多，右边是随机和柠檬绿的大播放钮。
class _Actions extends StatefulWidget {
  const _Actions({
    required this.songs,
    required this.description,
    this.onSearch,
    this.onEdit,
  });

  final List<Song> songs;
  final String description;
  final VoidCallback? onSearch;

  /// 自己的歌单（“我喜欢”除外）才有：改名、删除。
  final VoidCallback? onEdit;

  @override
  State<_Actions> createState() => _ActionsState();
}

class _ActionsState extends State<_Actions> {
  bool _expanded = false;

  void _shuffle() {
    final songs = widget.songs;
    final p = context.read<PlayerController>();
    p.setMode(PlayMode.shuffle);
    p.playList(songs, Random().nextInt(songs.length));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final songs = widget.songs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.description.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: Text(
                    widget.description,
                    maxLines: _expanded ? null : 1,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (widget.onSearch != null)
                IconButton(
                  tooltip: l.filterSongsHint,
                  onPressed: widget.onSearch,
                  icon: const Icon(Icons.search_rounded),
                ),
              if (widget.onEdit != null)
                IconButton(
                  tooltip: l.more,
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              const Spacer(),
              IconButton(
                tooltip: l.shufflePlay,
                onPressed: songs.isEmpty ? null : _shuffle,
                icon: const Icon(Icons.shuffle_rounded),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l.playAll(songs.length),
                style: IconButton.styleFrom(
                  fixedSize: const Size(56, 56),
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  disabledBackgroundColor: scheme.surfaceContainerHigh,
                ),
                onPressed: songs.isEmpty
                    ? null
                    : () => context.read<PlayerController>().playList(songs, 0),
                icon: const Icon(Icons.play_arrow_rounded, size: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 搜索时顶栏里的搜索框和“取消”，左边让出玻璃返回钮的位置（由 [_Hero] 摆放）。
class _SearchBar extends StatelessWidget {
  const _SearchBar(
    this.controller, {
    required this.focusNode,
    required this.onChanged,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                onChanged: (_) => onChanged(),
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
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            controller.clear();
                            onChanged();
                          },
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
            style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
            onPressed: onCancel,
            child: Text(l.cancel),
          ),
        ],
      ),
    );
  }
}
