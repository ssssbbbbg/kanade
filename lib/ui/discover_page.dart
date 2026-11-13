import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'feed_column.dart';
import 'foryou_settings_page.dart';
import 'keyed_route.dart';
import 'ring_refresh.dart';
import 'smooth_scroll.dart';
import 'song_list_page.dart';
import 'toast.dart';
import 'song_tile.dart';
import 'widgets.dart';

/// 发现页：顶上固定两颗胶囊切换“推荐”和“排行榜”，也可以左右滑。
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _pages = PageController();

  /// 推荐页内容，顶部刷新键通过它整页刷新。
  final _recommend = GlobalKey<_RecommendBodyState>();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // 不要大标题：底部导航已经说明了在哪一页
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 8,
              16,
              4,
            ),
            child: ListenableBuilder(
              listenable: _pages,
              builder: (context, _) {
                final at = _pages.hasClients ? (_pages.page ?? 0).round() : 0;
                void go(int i) => _pages.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                );
                return Row(
                  children: [
                    Pill(
                      label: l.discoverRecommend,
                      selected: at == 0,
                      large: true,
                      onTap: () => go(0),
                    ),
                    const SizedBox(width: 8),
                    Pill(
                      label: l.discoverToplists,
                      selected: at == 1,
                      large: true,
                      onTap: () => go(1),
                    ),
                    // Windows 上鼠标拉不动下拉刷新，改在这里放刷新键；只在推荐页显示，占位不变免得这排跳动
                    if (Platform.isWindows) ...[
                      const Spacer(),
                      Visibility.maintain(
                        visible: at == 0,
                        child: RefreshIconButton(
                          () =>
                              _recommend.currentState?.refresh() ??
                              Future.value(),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          Expanded(
            // 胶囊那排已经让开了状态栏
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: PageView(
                controller: _pages,
                children: [
                  _KeepAlive(_RecommendTab(bodyKey: _recommend)),
                  const _KeepAlive(_ToplistTab()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 滑到另一页时不销毁，回来还在原来的滚动位置，也不用重新加载。
class _KeepAlive extends StatefulWidget {
  const _KeepAlive(this.child);

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _RecommendTab extends StatelessWidget {
  const _RecommendTab({required this.bodyKey});

  final GlobalKey<_RecommendBodyState> bodyKey;

  @override
  Widget build(BuildContext context) => AsyncView<RecommendFeed>(
    load: api.getRecommendFeed,
    builder: (context, data) => _RecommendBody(key: bodyKey, data: data),
  );
}

/// 推荐页已经加载出来的内容。整页刷新（Android 下拉、Windows 顶部刷新键）和单栏刷新期间旧内容留在原处，
/// 取到新的再换；失败时弹提示，内容不变。
class _RecommendBody extends StatefulWidget {
  const _RecommendBody({super.key, required this.data});

  final RecommendFeed data;

  @override
  State<_RecommendBody> createState() => _RecommendBodyState();
}

class _RecommendBodyState extends State<_RecommendBody> {
  /// 每个歌曲区块在首页只露出几首，其余点“查看全部”。
  static const _previewSongs = 6;

  late var _feed = widget.data;
  late var _sections = widget.data.sections;

  /// 整页刷新一次加一，专属乐流跟着从头加载。
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    // 改了自定义推荐页后，最上面那排卡片要重新取
    foryouSaved.addListener(_onForyouSaved);
  }

  @override
  void dispose() {
    foryouSaved.removeListener(_onForyouSaved);
    super.dispose();
  }

  void _onForyouSaved() => refresh();

  /// 失败时弹提示并返回 false。
  Future<bool> refresh() async {
    final failed = _failedToast();
    try {
      final feed = await api.getRecommendFeed();
      if (!mounted) return false;
      setState(() {
        _feed = feed;
        _sections = feed.sections;
        _generation++;
      });
      return true;
    } catch (e) {
      failed(e);
      return false;
    }
  }

  Future<void> _refreshSection(RecommendSection old) async {
    final failed = _failedToast();
    try {
      final fresh = await api.refreshRecommendSection(refresh: old.refresh);
      // 等待期间整页刷新过的话，旧栏目已经不在了
      final i = _sections.indexOf(old);
      if (mounted && i >= 0) {
        setState(() => _sections = [..._sections]..[i] = fresh);
      }
    } catch (e) {
      failed(e);
    }
  }

  void Function(Object) _failedToast() {
    final l = AppLocalizations.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    return (e) => Toast.show(
      overlay,
      l.loadFailed(errorText(l, e)),
      kind: ToastKind.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // 电台卡排在第一排歌单（每日30首那排）的最前面；没有歌单时单独一排
    final radioAt = _sections.indexWhere((s) => s.playlists.isNotEmpty);
    final radio = _RadioCards(_feed);
    return SmoothScroll(
      builder: (context, scroll) {
        final list = CustomScrollView(
          controller: scroll,
          slivers: [
            if (radioAt < 0) _PlaylistRow(const [], leading: radio),
            for (final (i, section) in _sections.indexed) ...[
              if (section.playlists.isNotEmpty) ...[
                _Header(
                  section.title.isEmpty
                      ? l.recommendedPlaylists
                      : section.title,
                  onRefresh: _onRefresh(section),
                ),
                _PlaylistRow(
                  section.playlists,
                  leading: i == radioAt ? radio : null,
                ),
              ],
              if (section.songs.isNotEmpty)
                ..._songSection(
                  context,
                  section.title.isEmpty ? l.recommendedSongs : section.title,
                  section.songs,
                  // 同一栏的刷新键只放在第一个标题上
                  onRefresh: section.playlists.isEmpty
                      ? _onRefresh(section)
                      : null,
                ),
            ],
            FeedColumn(key: ValueKey(_generation)),
            const SliverToBoxAdapter(child: BottomSpacer()),
          ],
        );
        return Platform.isWindows
            ? list
            : RingRefresh(onRefresh: refresh, child: list);
      },
    );
  }

  Future<void> Function()? _onRefresh(RecommendSection section) =>
      section.refresh.isEmpty ? null : () => _refreshSection(section);

  List<Widget> _songSection(
    BuildContext context,
    String title,
    List<Song> songs, {
    Future<void> Function()? onRefresh,
  }) {
    final shown = songs.length > _previewSongs ? _previewSongs : songs.length;
    void viewAll() =>
        Navigator.of(context).push(SongListPage.songs(title, songs));
    return [
      _Header(
        title,
        onMore: songs.length > shown ? viewAll : null,
        onRefresh: onRefresh,
      ),
      // 点某一首时把整个区块作为播放列表
      SliverList.builder(
        itemCount: shown,
        itemBuilder: (_, i) => SongTile(songs: songs, index: i),
      ),
    ];
  }
}

/// 歌单卡宽度，电台卡跟它对齐。
const _cardWidth = 124.0;

/// 横向滚动的一排歌单卡片（含“每日30首”等入口），[leading] 排在最前面。
class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow(this.playlists, {this.leading});

  final List<PlaylistBrief> playlists;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(
      height: 186,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: playlists.length + (leading == null ? 0 : 1),
        itemBuilder: (context, i) {
          if (leading != null) {
            if (i == 0) return leading!;
            i--;
          }
          final p = playlists[i];
          return Container(
            width: _cardWidth,
            // leading 自己带右边距
            margin: EdgeInsets.only(left: i == 0 ? 0 : 12),
            child: PlaylistCard(
              title: p.title,
              coverUrl: p.coverUrl,
              badge: p.playCount > BigInt.zero
                  ? '▶ ${formatCount(AppLocalizations.of(context), p.playCount.toInt())}'
                  : null,
              onTap: () =>
                  openPage(context, SongListPage.playlist(p.id, p.title)),
            ),
          );
        },
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.onMore, this.onRefresh});

  final String text;
  final VoidCallback? onMore;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SectionHeader(text, onMore: onMore, onRefresh: onRefresh),
  );
}

/// 排行榜页：第一组（巅峰榜）做成横滑的大卡，露出前三名；其余各组排成封面网格。
class _ToplistTab extends StatelessWidget {
  const _ToplistTab();

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<TopListGroup>>(
      load: api.getToplists,
      builder: (context, groups) => SmoothScroll(
        builder: (context, scroll) => CustomScrollView(
          controller: scroll,
          slivers: [
            for (final (i, g) in groups.indexed)
              if (g.lists.isNotEmpty) ...[
                _Header(g.name),
                if (i == 0)
                  _FeaturedToplists(g.lists)
                else
                  _ToplistGrid(g.lists),
              ],
            const SliverToBoxAdapter(child: BottomSpacer()),
          ],
        ),
      ),
    );
  }
}

void _openToplist(BuildContext context, TopList t) =>
    Navigator.of(context)
        .push(SongListPage.toplist(t.topId, t.period, t.title));

class _FeaturedToplists extends StatelessWidget {
  const _FeaturedToplists(this.lists);

  final List<TopList> lists;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(
      height: 178,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: lists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _FeaturedToplistCard(lists[i]),
      ),
    ),
  );
}

/// 上面封面 + 榜名，下面前三名。
class _FeaturedToplistCard extends StatelessWidget {
  const _FeaturedToplistCard(this.t);

  final TopList t;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 272,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openToplist(context, t),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Cover(t.coverUrl, size: 64, radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final (i, s) in t.preview.take(3).indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: i == 0
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            s,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行三个（宽屏多几个）方形封面，下面写榜名。
class _ToplistGrid extends StatelessWidget {
  const _ToplistGrid(this.lists);

  final List<TopList> lists;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    sliver: SliverLayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final cols = ((c.crossAxisExtent + gap) / (140 + gap)).ceil().clamp(
          3,
          8,
        );
        final w = (c.crossAxisExtent - gap * (cols - 1)) / cols;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: gap,
            mainAxisSpacing: 14,
            // 封面 + 间距 + 两行标题
            mainAxisExtent: w + 8 + 36,
          ),
          itemCount: lists.length,
          itemBuilder: (context, i) {
            final t = lists[i];
            return PlaylistCard(
              title: t.title,
              coverUrl: t.coverUrl,
              onTap: () => _openToplist(context, t),
            );
          },
        );
      },
    ),
  );
}

/// 猜你喜欢（需要登录）和刷歌模式（需要推荐页给出起始歌曲）两个电台入口，放在歌单那排最前面。
/// 猜你喜欢先预取一批，长条卡上显示第一首的封面、歌名和歌手，点开就从这批放起；刷歌用入口卡给的封面。
class _RadioCards extends StatefulWidget {
  const _RadioCards(this.feed);

  final RecommendFeed feed;

  @override
  State<_RadioCards> createState() => _RadioCardsState();
}

class _RadioCardsState extends State<_RadioCards> {
  /// 预取的猜你喜欢下一批；没登录或已经用掉时为 null。
  Future<List<Song>>? _guess;
  List<Song> _guessShown = const [];

  void _prefetchGuess() {
    final f = api.getGuessYouLike();
    _guess = f;
    f.then(
      (songs) {
        if (mounted && _guess == f) setState(() => _guessShown = songs);
      },
      onError: (_) {
        // 预取失败只是没有封面，点击时会再取
      },
    );
  }

  Future<void> _start(RadioSource source, {Future<List<Song>>? first}) async {
    final l = AppLocalizations.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    final player = context.read<PlayerController>();
    try {
      final batch = await first?.then<List<Song>?>(
        (s) => s.isEmpty ? null : s,
        onError: (_) => null,
      );
      await player.playRadio(source, first: batch);
    } catch (e) {
      Toast.show(
        overlay,
        l.radioFailed(errorText(l, e)),
        kind: ToastKind.error,
      );
    }
  }

  void _startGuess() {
    final first = _guess;
    // 这批交给播放器了，封面换成下一批
    _guessShown = const [];
    _prefetchGuess();
    _start(const RadioSource.guess(), first: first);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final feed = widget.feed;
    final loggedIn = context.watch<AuthController>().loggedIn;
    if (loggedIn && _guess == null) _prefetchGuess();
    if (!loggedIn && _guess != null) {
      _guess = null;
      _guessShown = const [];
    }
    if (!loggedIn && feed.radarSeed.isEmpty) return const SizedBox.shrink();
    final next = _guessShown.firstOrNull;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loggedIn) ...[
          _GuessCard(
            title: l.radioGuessYouLike,
            song: next,
            onTap: _startGuess,
          ),
          const SizedBox(width: 12),
        ],
        if (feed.radarSeed.isNotEmpty) ...[
          SizedBox(
            width: _cardWidth,
            child: PlaylistCard(
              title: l.radioRadar,
              coverUrl: feed.radarCover,
              // 每次点击从第 1 批开始，之后续取依次往后翻
              onTap: () => _start(
                RadioSource.radar([
                  for (final id in feed.radarSeed) id.toInt(),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ],
    );
  }
}

/// 猜你喜欢：比歌单卡宽一倍的长条，左边封面、右边歌名和歌手，下面跟歌单卡一样写入口名。
class _GuessCard extends StatelessWidget {
  const _GuessCard({
    required this.title,
    required this.song,
    required this.onTap,
  });

  final String title;

  /// 点开会先放的那首；还没取到时为 null。
  final Song? song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = song;
    return SizedBox(
      width: _cardWidth * 2 + 12,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: _cardWidth,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Cover(s?.coverUrl ?? '', size: _cardWidth, radius: 0),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s?.name ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        if (s != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            singerNames(s),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.play_circle_fill,
                      size: 32,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
