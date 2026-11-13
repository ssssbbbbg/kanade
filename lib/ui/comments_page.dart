import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'sheet.dart';
import 'smooth_scroll.dart';
import 'widgets.dart';

/// 取一页评论；`cursor` 第一页是空字符串，之后是上一页返回的游标。
typedef CommentLoader = Future<CommentFeed> Function(String cursor);

/// 评论页：推荐 / 最热 / 最新三个分类，左右滑动或点顶上的滑块切换，各自滚到底继续加载。
class CommentsPage extends StatefulWidget {
  const CommentsPage({
    super.key,
    required this.title,
    required this.load,
    this.subtitle = '',
    this.coverUrl,
  });

  final String title;

  /// 标题下面的小字（歌手），后面会接上评论总数。
  final String subtitle;
  final String? coverUrl;
  final Future<CommentFeed> Function(CommentSort sort, String cursor) load;

  static Route<void> song(Song s) => MaterialPageRoute(
    builder: (_) => CommentsPage(
      title: s.name,
      subtitle: singerNames(s),
      coverUrl: s.coverUrl,
      load: (sort, cursor) => api.getCommentFeed(
        target: CommentTarget.song,
        id: s.id,
        sort: sort,
        cursor: cursor,
      ),
    ),
  );

  static Route<void> album(AlbumDetail a) => MaterialPageRoute(
    builder: (_) => CommentsPage(
      title: a.name,
      subtitle: a.singers.map((e) => e.name).join(' / '),
      coverUrl: a.coverUrl,
      load: (sort, cursor) => api.getCommentFeed(
        target: CommentTarget.album,
        id: a.id,
        sort: sort,
        cursor: cursor,
      ),
    ),
  );

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  // 未登录时推荐只有第一页，所以默认看最热
  late final _pages = PageController(
    initialPage:
        (context.read<AuthController>().loggedIn
                ? CommentSort.recommend
                : CommentSort.hot)
            .index,
  );
  int _total = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      if (widget.subtitle.isNotEmpty) widget.subtitle,
      _total > 0 ? l.commentCount(formatCount(l, _total)) : l.comments,
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            if (widget.coverUrl != null) ...[
              Cover(widget.coverUrl!, size: 40, radius: 10, cacheWidth: 120),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _SortSlider(
              controller: _pages,
              labels: [l.commentsRecommended, l.hottest, l.newest],
            ),
          ),
          Expanded(
            // 滑到哪一页才建哪一页的列表；建过的留着，切回去内容和滚动位置都在
            child: PageView.builder(
              controller: _pages,
              itemCount: CommentSort.values.length,
              itemBuilder: (_, i) => _CommentList(
                load: (cursor) => widget.load(CommentSort.values[i], cursor),
                onTotal: (total) {
                  if (total != _total) setState(() => _total = total);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类滑块：深灰轨道上一块白色滑块，跟着页面的滑动进度走，点一项就滑到那一页。
class _SortSlider extends StatelessWidget {
  const _SortSlider({required this.controller, required this.labels});

  final PageController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = labels.length - 1;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
      ),
      // 每一格一样宽，按最长的那个标签定
      child: IntrinsicWidth(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final page =
                controller.hasClients &&
                    controller.position.hasContentDimensions
                ? controller.page!
                : controller.initialPage.toDouble();
            return Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment(page / last * 2 - 1, 0),
                    child: FractionallySizedBox(
                      widthFactor: 1 / labels.length,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: scheme.secondaryContainer,
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, label) in labels.indexed)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => controller.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                              ),
                              child: Text(
                                label,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color.lerp(
                                    scheme.onSurfaceVariant,
                                    scheme.onSecondaryContainer,
                                    (1 - (page - i).abs()).clamp(0, 1),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CommentList extends StatefulWidget {
  const _CommentList({
    required this.load,
    this.onTotal,
    this.controller,
    this.reply = false,
  });

  final CommentLoader load;
  final ValueChanged<int>? onTotal;
  final ScrollController? controller;

  /// 回复面板里的列表：头像小一号、缩进，评论之间不画分隔线。
  final bool reply;

  @override
  State<_CommentList> createState() => _CommentListState();
}

class _CommentListState extends State<_CommentList>
    with AutomaticKeepAliveClientMixin {
  final List<Comment> _items = [];
  String _cursor = '';
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  /// 回复面板会传进它自己的 controller（拖动面板用），否则用自己的。
  final _scroll = SmoothScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _more();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await widget.load(_cursor);
      if (!mounted) return;
      setState(() {
        // 防止翻页游标不准时出现重复
        final seen = _items.map((c) => c.id).toSet();
        final fresh = p.comments.where((c) => seen.add(c.id)).toList();
        _items.addAll(fresh);
        _cursor = p.cursor;
        _hasMore = p.hasMore && fresh.isNotEmpty;
      });
      widget.onTotal?.call(p.total);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget footer;
    if (_error != null) {
      footer = Center(
        child: TextButton(
          onPressed: _more,
          child: Text(
            l.loadFailed(errorText(l, _error!)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (_loading) {
      footer = const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_items.isEmpty) {
      footer = Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(l.noComments, style: text.bodyMedium)),
      );
    } else {
      footer = const SizedBox(height: 24);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400 && _error == null) _more();
        return false;
      },
      child: ListView.builder(
        controller: widget.controller ?? _scroll,
        itemCount: _items.length + 1,
        itemBuilder: (_, i) {
          if (i == _items.length) return footer;
          final tile = CommentTile(_items[i], reply: widget.reply);
          if (widget.reply || i == 0) return tile;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [const Divider(height: 1, indent: 64), tile],
          );
        },
      ),
    );
  }
}

/// 一周内显示“3 天前”这样的相对时间，更早的只显示日期。
String _commentTime(AppLocalizations l, int secs) {
  final time = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  final ago = DateTime.now().difference(time);
  if (ago.inMinutes < 1) return l.timeJustNow;
  if (ago.inHours < 1) return l.timeMinutesAgo(ago.inMinutes);
  if (ago.inDays < 1) return l.timeHoursAgo(ago.inHours);
  if (ago.inDays < 7) return l.timeDaysAgo(ago.inDays);
  return DateFormat.yMd(l.localeName).format(time);
}

class CommentTile extends StatelessWidget {
  const CommentTile(
    this.c, {
    super.key,
    this.reply = false,
    this.showReplies = true,
  });

  final Comment c;

  /// 回复面板里的回复：头像小一号并缩进。
  final bool reply;

  /// 回复面板顶部的原评论不再显示“N 条回复”。
  final bool showReplies;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final faint = scheme.onSurfaceVariant;
    final radius = reply ? 14.0 : 18.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(reply ? 24 : 16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: scheme.surfaceContainerHighest,
            backgroundImage: c.avatarUrl.isEmpty
                ? null
                : NetworkImage(httpsUrl(c.avatarUrl)),
            child: c.avatarUrl.isEmpty
                ? Icon(Icons.person, size: radius, color: faint)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.nick,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: faint, fontSize: 13),
                      ),
                    ),
                    if (c.praiseCount > 0) ...[
                      Icon(Icons.thumb_up_alt_outlined, size: 14, color: faint),
                      const SizedBox(width: 4),
                      Text(
                        formatCount(l, c.praiseCount),
                        style: TextStyle(fontSize: 12, color: faint),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                _CommentText(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 15,
                      height: 23 / 15,
                      color: scheme.onSurface,
                    ),
                    children: [
                      if (c.replyTo.isNotEmpty)
                        TextSpan(
                          text: l.replyTo(c.replyTo),
                          style: TextStyle(color: faint),
                        ),
                      TextSpan(text: c.content),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                if (c.picUrl.isNotEmpty) ...[
                  _CommentPicture(c),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    Text(
                      _commentTime(l, c.timeSecs.toInt()),
                      style: TextStyle(fontSize: 12, color: faint),
                    ),
                    if (showReplies && c.replyCount > 0) ...[
                      const SizedBox(width: 10),
                      Material(
                        color: scheme.surfaceContainerHigh,
                        shape: const StadiumBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _showReplies(context, c),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l.replyCount(c.replyCount),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: 14,
                                  color: scheme.onSurface,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 评论正文：超过 6 行先收起，右下角给一个“展开 / 收起”。
class _CommentText extends StatefulWidget {
  const _CommentText(this.span);

  final TextSpan span;

  @override
  State<_CommentText> createState() => _CommentTextState();
}

class _CommentTextState extends State<_CommentText> {
  static const _lines = 6;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final base = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(style: base, children: [widget.span]),
          maxLines: _lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 展开、收起时高度慢慢变，不一下跳过去
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Text.rich(
                widget.span,
                maxLines: _expanded ? null : _lines,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
            ),
            if (long)
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2, left: 16),
                    child: Text(
                      _expanded ? l.showLess : l.showMore,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

void _showReplies(BuildContext context, Comment root) {
  showExpandableSheet<void>(
    context: context,
    heightFactor: 0.75,
    builder: (context, controller) {
      final l = AppLocalizations.of(context);
      final scheme = Theme.of(context).colorScheme;
      final (_, band) = sheetColors(scheme);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Text(
              l.replyCount(root.replyCount),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          CommentTile(root, showReplies: false),
          Divider(height: 8, thickness: 8, color: band),
          Expanded(
            child: _CommentList(
              controller: controller,
              reply: true,
              load: (cursor) =>
                  api.getReplyFeed(rootId: root.id, cursor: cursor),
            ),
          ),
        ],
      );
    },
  );
}

/// 评论里的图片：按原图比例显示缩略图，点开后缩略图放大飞到全屏。
class _CommentPicture extends StatefulWidget {
  const _CommentPicture(this.c);

  final Comment c;

  @override
  State<_CommentPicture> createState() => _CommentPictureState();
}

class _CommentPictureState extends State<_CommentPicture> {
  /// 同一条评论会同时出现在几个分类里，Hero 的标记不能重复，所以每个缩略图各用各的。
  final _tag = Object();

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final url = httpsUrl(c.picUrl);
    final real = c.picWidth > 0 && c.picHeight > 0
        ? c.picWidth / c.picHeight
        : null;
    // 没给尺寸时按方图处理；过长过宽的图只裁出中间一块
    final ratio = (real ?? 1.0).clamp(0.5, 2.0);
    const side = 160.0;
    final thumb = ResizeImage(NetworkImage(url), width: 480);
    return GestureDetector(
      // 走根导航器，盖住底栏；路由不是不透明的，后面的评论页还在
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black.withValues(alpha: 0.9),
          pageBuilder: (_, _, _) => _PictureViewer(
            url: url,
            thumb: thumb,
            tag: _tag,
            aspectRatio: real,
          ),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
      child: Hero(
        tag: _tag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: ratio < 1 ? side * ratio : side,
            height: ratio > 1 ? side / ratio : side,
            child: Image(
              image: thumb,
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) => ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 全屏看图，可以缩放，点一下关闭。
class _PictureViewer extends StatelessWidget {
  const _PictureViewer({
    required this.url,
    required this.thumb,
    required this.tag,
    required this.aspectRatio,
  });

  final String url;

  /// 列表里已经加载好的缩略图，原图下载完之前先顶着，飞过来时不会是空的。
  final ImageProvider thumb;
  final Object tag;

  /// 原图宽高比，接口没给时是 null。
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      url,
      fit: BoxFit.contain,
      frameBuilder: (_, child, frame, _) =>
          frame == null ? Image(image: thumb, fit: BoxFit.contain) : child,
    );
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: InteractiveViewer(
        maxScale: 4,
        child: Center(
          child: Hero(
            tag: tag,
            child: aspectRatio == null
                ? image
                : AspectRatio(aspectRatio: aspectRatio!, child: image),
          ),
        ),
      ),
    );
  }
}
