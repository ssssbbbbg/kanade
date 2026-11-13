import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'keyed_route.dart';
import 'recognize_sheet.dart';
import 'video_tile.dart';
import 'singer_page.dart';
import 'smooth_scroll.dart';
import 'song_list_page.dart';
import 'user_page.dart';
import 'song_tile.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

/// 一个分类已经加载的结果；只有和分类对应的列表有内容。
class _Results {
  List<Song> songs = [];
  List<String> lyricSnippets = [];
  List<SingerBrief> singers = [];
  List<AlbumBrief> albums = [];
  List<PlaylistBrief> playlists = [];
  List<VideoBrief> videos = [];
  List<UserBrief> users = [];
  int page = 0;
  int total = 0;
  bool hasMore = true;
  bool loading = false;
  Object? error;

  int get length =>
      songs.length +
      singers.length +
      albums.length +
      playlists.length +
      videos.length +
      users.length;

  /// 每次换成新列表：歌曲列表会交给播放队列，不能在原列表上追加。
  void add(SearchResult r) {
    page++;
    total = r.total;
    hasMore = r.hasMore;
    songs = [...songs, ...r.songs];
    lyricSnippets = [...lyricSnippets, ...r.lyricSnippets];
    singers = [...singers, ...r.singers];
    albums = [...albums, ...r.albums];
    playlists = [...playlists, ...r.playlists];
    videos = [...videos, ...r.videos];
    users = [...users, ...r.users];
  }
}

class _SearchPageState extends State<SearchPage> {
  static const _pageSize = 30;

  final _controller = TextEditingController();
  final _hotScroll = SmoothScrollController();
  final _suggestScroll = SmoothScrollController();
  final _scrolls = {
    for (final k in SearchKind.values) k: SmoothScrollController(),
  };
  String _keyword = '';
  SearchKind _kind = SearchKind.song;
  final _results = <SearchKind, _Results>{};

  HotSearch? _hot;
  Object? _hotError;

  /// 正在输入（还没回车）时显示联想，而不是上一次的搜索结果。
  bool _typing = false;
  List<SearchSuggestion> _suggestions = [];
  Timer? _debounce;

  _Results get _current => _results.putIfAbsent(_kind, _Results.new);

  @override
  void initState() {
    super.initState();
    _loadHot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _hotScroll.dispose();
    _suggestScroll.dispose();
    for (final c in _scrolls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadHot() async {
    try {
      final hot = await api.getHotSearch();
      if (mounted) setState(() => _hot = hot);
    } catch (e) {
      if (mounted) setState(() => _hotError = e);
    }
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    setState(() {
      _typing = true;
      if (text.trim().isEmpty) _suggestions = [];
    });
    final query = text.trim();
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final list = await api.getSearchSuggestions(query: query);
        // 只保留和输入框当前内容对应的结果，丢弃过期的请求
        if (mounted && _typing && _controller.text.trim() == query) {
          setState(() => _suggestions = list);
        }
      } catch (_) {
        // 联想失败不影响直接回车搜索
      }
    });
  }

  void _clear() {
    _debounce?.cancel();
    setState(() {
      _controller.clear();
      _typing = false;
      _suggestions = [];
      _keyword = '';
      _results.clear();
    });
  }

  /// 点联想或热搜词：填进输入框并直接搜索。
  void _searchFor(String keyword) {
    _controller.text = keyword;
    _search(keyword);
  }

  /// 换关键词时保留当前分类，和官方客户端一样。
  Future<void> _search(String keyword) async {
    keyword = keyword.trim();
    if (keyword.isEmpty) return;
    _debounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _typing = false;
      _keyword = keyword;
      _results.clear();
    });
    await _loadMore();
  }

  void _selectKind(SearchKind kind) {
    if (kind == _kind) return;
    setState(() => _kind = kind);
    if (_current.page == 0) _loadMore();
  }

  Future<void> _loadMore() async {
    final kind = _kind;
    final r = _current;
    if (r.loading || _keyword.isEmpty || !r.hasMore || r.error != null) return;
    final keyword = _keyword;
    setState(() => r.loading = true);
    try {
      final page = await api.search(
        keyword: keyword,
        kind: kind,
        page: r.page + 1,
        pageSize: _pageSize,
      );
      // 等待期间换了关键词，这份结果已经被清掉了
      if (!mounted || keyword != _keyword || _results[kind] != r) return;
      setState(() => r.add(page));
    } catch (e) {
      if (mounted) setState(() => r.error = e);
    } finally {
      if (mounted) setState(() => r.loading = false);
    }
  }

  void _retry() {
    setState(() => _current.error = null);
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: SearchBar(
          controller: _controller,
          hintText: l.searchHint,
          leading: const Icon(Icons.search),
          elevation: const WidgetStatePropertyAll(0),
          onSubmitted: _search,
          trailing: [
            if (_controller.text.isNotEmpty)
              IconButton(icon: const Icon(Icons.clear), onPressed: _clear)
            else
              IconButton(
                icon: const Icon(Icons.mic_none_rounded),
                tooltip: l.recognizeSong,
                onPressed: () => showRecognizeSheet(context),
              ),
          ],
          onChanged: _onChanged,
        ),
      ),
      body: _body(l),
    );
  }

  Widget _body(AppLocalizations l) {
    if (_typing && _controller.text.trim().isNotEmpty) {
      return _suggestionList();
    }
    if (_keyword.isEmpty) {
      return _hotView(l);
    }
    return Column(
      children: [
        _kindBar(l),
        Expanded(child: _resultView(l)),
      ],
    );
  }

  String _kindLabel(AppLocalizations l, SearchKind kind) => switch (kind) {
    SearchKind.song => l.searchKindSong,
    SearchKind.singer => l.searchKindSinger,
    SearchKind.album => l.searchKindAlbum,
    SearchKind.playlist => l.searchKindPlaylist,
    SearchKind.video => l.searchKindVideo,
    SearchKind.lyric => l.searchKindLyric,
    SearchKind.user => l.searchKindUser,
  };

  Widget _kindBar(AppLocalizations l) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (final kind in SearchKind.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Pill(
                label: _kindLabel(l, kind),
                selected: kind == _kind,
                onTap: () => _selectKind(kind),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultView(AppLocalizations l) {
    final r = _current;
    if (r.length == 0) {
      if (r.error != null) {
        return Center(
          child: TextButton(
            onPressed: _retry,
            child: Text(
              l.searchFailed(errorText(l, r.error!)),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return Center(
        child: r.loading || r.page == 0
            ? const PageLoading()
            : Text(l.searchNoResults),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: ListView.builder(
        key: ValueKey(_kind),
        controller: _scrolls[_kind],
        itemCount: r.length + 1,
        itemBuilder: (context, i) =>
            i == r.length ? _footer(l, r) : _item(l, r, i),
      ),
    );
  }

  Widget _footer(AppLocalizations l, _Results r) {
    if (r.error != null) {
      return ListTile(
        title: Text(
          l.loadFailed(errorText(l, r.error!)),
          textAlign: TextAlign.center,
        ),
        onTap: _retry,
      );
    }
    final songs = _kind == SearchKind.song || _kind == SearchKind.lyric;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: r.loading
            ? const CircularProgressIndicator()
            : Text(
                songs ? l.searchTotal(r.total) : l.searchTotalItems(r.total),
              ),
      ),
    );
  }

  Widget _item(AppLocalizations l, _Results r, int i) {
    switch (_kind) {
      case SearchKind.song:
        return SongTile(songs: r.songs, index: i);
      case SearchKind.lyric:
        return _LyricTile(
          songs: r.songs,
          index: i,
          snippet: r.lyricSnippets[i],
        );
      case SearchKind.singer:
        final s = r.singers[i];
        return ListTile(
          leading: Cover(s.avatarUrl, size: 52, radius: 26),
          title: Text(
            s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(l.singerStats(s.songCount, s.albumCount)),
          onTap: () => openPage(context, SingerPage.route(s.mid, s.name)),
        );
      case SearchKind.album:
        return AlbumTile(r.albums[i]);
      case SearchKind.playlist:
        final p = r.playlists[i];
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
              if (p.playCount > BigInt.zero)
                '▶ ${formatCount(l, p.playCount.toInt())}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => openPage(context, SongListPage.playlist(p.id, p.title)),
        );
      case SearchKind.video:
        return VideoTile(r.videos[i]);
      case SearchKind.user:
        final u = r.users[i];
        return ListTile(
          leading: Cover(u.avatarUrl, size: 52, radius: 26),
          title: Text(
            u.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            u.description.isNotEmpty
                ? u.description
                // 歌手账号没有歌单标签，不显示“歌单 0”
                : u.playlistCount > 0
                ? l.userBriefStats(
                    formatCount(l, u.fansCount.toInt()),
                    u.playlistCount,
                  )
                : l.userFans(formatCount(l, u.fansCount.toInt())),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => openPage(context, UserPage.route(u.euin, u.name)),
        );
    }
  }

  Widget _suggestionList() {
    return ListView(
      controller: _suggestScroll,
      children: [
        for (final s in _suggestions)
          ListTile(
            leading: Icon(switch (s.kind) {
              SuggestionKind.song => Icons.music_note_outlined,
              SuggestionKind.singer => Icons.person_outline,
              SuggestionKind.album => Icons.album_outlined,
            }),
            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: s.subtitle.isEmpty
                ? null
                : Text(
                    s.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            // 歌曲/专辑带上歌手名一起搜，结果更准
            onTap: () => _searchFor(
              s.subtitle.isEmpty ? s.title : '${s.title} ${s.subtitle}',
            ),
          ),
      ],
    );
  }

  Widget _hotView(AppLocalizations l) {
    final hot = _hot;
    if (hot == null) {
      // 热搜加载失败时退回原来的提示，不影响搜索
      return Center(
        child: _hotError != null ? Text(l.searchPrompt) : const PageLoading(),
      );
    }
    final theme = Theme.of(context);
    return ListView(
      controller: _hotScroll,
      // 自己指定 padding 会盖掉 ListView 自动加的底部留白，要把玻璃条的高度算进去
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: [
        if (hot.recommended.isNotEmpty) ...[
          _sectionTitle(l.searchRecommended),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in hot.recommended.take(12))
                  ActionChip(
                    label: Text(k.title),
                    onPressed: () => _searchFor(k.query),
                  ),
              ],
            ),
          ),
        ],
        if (hot.hot.isNotEmpty) _sectionTitle(l.searchHot),
        for (final (i, k) in hot.hot.indexed)
          ListTile(
            dense: true,
            leading: SizedBox(
              width: 28,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: i < 3
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // 说明放在标题行里而不是 trailing：trailing 不限宽，窗口缩放时后台的这页会被排得很窄，
            // 说明占满整行就触发 ListTile 的断言。标题最多占 3/4、说明最多 1/4 并靠右，再窄也只是省略
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  flex: 3,
                  child: Text(
                    k.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (k.description.isNotEmpty)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        k.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onTap: () => _searchFor(k.query),
          ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// 歌曲行下面带一行命中的歌词。
class _LyricTile extends StatelessWidget {
  const _LyricTile({
    required this.songs,
    required this.index,
    required this.snippet,
  });

  final List<Song> songs;
  final int index;
  final String snippet;

  @override
  Widget build(BuildContext context) {
    final tile = SongTile(songs: songs, index: index);
    if (snippet.isEmpty) return tile;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        Padding(
          // 和歌名对齐：左边距 16 + 封面 48 + 间距 16
          padding: const EdgeInsetsDirectional.fromSTEB(80, 0, 16, 8),
          child: Text(
            snippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 16:9 封面，右下角是时长。官方 MV 标 MV，用户上传的不标。
