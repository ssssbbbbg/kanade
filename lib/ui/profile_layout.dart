import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../l10n/l10n_ext.dart';
import 'widgets.dart';

/// 返回这一页的条目和“后面还有没有”；`page` 是已经取过几次，`offset` 是已有条数。
typedef PageFetch<T> = Future<(List<T>, bool)> Function(int page, int offset);

/// 一个分类的翻页数据，放在页面 State 里，切走再切回来不用重新加载。
class Pager<T> extends ChangeNotifier {
  Pager(this._fetch, {List<T> initial = const [], this.hasMore = true})
    : items = [...initial],
      _page = initial.isEmpty ? 0 : 1;

  final PageFetch<T> _fetch;
  final List<T> items;
  int _page;

  /// 只由 [more] 更新。
  bool hasMore;
  bool _loading = false;
  bool _disposed = false;
  Object? _error;

  bool get loading => _loading;
  Object? get error => _error;

  Future<void> more() async {
    if (_disposed || _loading || !hasMore || _error != null) return;
    _loading = true;
    notifyListeners();
    try {
      final (next, more) = await _fetch(_page, items.length);
      if (_disposed) return;
      items.addAll(next);
      _page++;
      hasMore = more && next.isNotEmpty;
    } catch (e) {
      if (_disposed) return;
      _error = e;
    }
    _loading = false;
    notifyListeners();
  }

  void retry() {
    _error = null;
    more();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// [Pager] 的列表；滚到末尾那一格被建出来时自动取下一页。
class PagedSliver<T> extends StatelessWidget {
  const PagedSliver({
    super.key,
    required this.pager,
    required this.itemBuilder,
    this.emptyText,
  });

  final Pager<T> pager;
  final Widget Function(BuildContext, List<T>, int) itemBuilder;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pager,
      builder: (context, _) => SliverList.builder(
        itemCount: pager.items.length + 1,
        itemBuilder: (context, i) => i < pager.items.length
            ? itemBuilder(context, pager.items, i)
            : _footer(context),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final l = AppLocalizations.of(context);
    final error = pager.error;
    if (error != null) {
      return ListTile(
        title: Text(
          l.loadFailed(errorText(l, error)),
          textAlign: TextAlign.center,
        ),
        onTap: pager.retry,
      );
    }
    if (pager.hasMore && !pager.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => pager.more());
    }
    if (pager.hasMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (pager.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(emptyText ?? l.noItems)),
      );
    }
    return const BottomSpacer();
  }
}

/// 固定高度、滚到顶就钉住的一条（分类胶囊、顶栏）。
class PinnedBox extends SliverPersistentHeaderDelegate {
  PinnedBox({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: SizedBox.expand(child: child),
  );

  @override
  bool shouldRebuild(PinnedBox old) => true;
}

/// 一排横向滑动的切换胶囊。
class PillRow extends StatelessWidget {
  const PillRow({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.spacing = 6,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double spacing;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: padding,
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          children[i],
        ],
      ],
    ),
  );
}

/// 切换分类时，如果分类栏已经钉在顶上，就让它继续钉着、新内容从头开始显示；
/// [marker] 是紧挨在分类栏前面的空 sliver，[pinnedAbove] 是钉在它上面的高度。
void keepPinned(ScrollController scroll, GlobalKey marker, double pinnedAbove) {
  final sliver = marker.currentContext?.findRenderObject() as RenderSliver?;
  if (sliver == null || !scroll.hasClients) return;
  final pinAt = sliver.constraints.precedingScrollExtent - pinnedAbove;
  if (scroll.offset > pinAt) scroll.jumpTo(pinAt);
}

/// 放在最后：内容不够一屏时补空白，让分类栏仍能滚到顶上钉住，
/// 不然切到还在加载的分类会被弹回页面顶部。参数同 [keepPinned]。
class PinFiller extends LeafRenderObjectWidget {
  const PinFiller({super.key, required this.marker, required this.pinnedAbove});

  final GlobalKey marker;
  final double pinnedAbove;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPinFiller(marker, pinnedAbove);

  @override
  void updateRenderObject(BuildContext context, RenderPinFiller renderObject) {
    renderObject
      ..marker = marker
      ..pinnedAbove = pinnedAbove
      ..markNeedsLayout();
  }
}

class RenderPinFiller extends RenderSliver {
  RenderPinFiller(this.marker, this.pinnedAbove);

  GlobalKey marker;
  double pinnedAbove;

  @override
  void performLayout() {
    // 标记在前面，这一轮已经排好了
    final start = (marker.currentContext?.findRenderObject() as RenderSliver?)
        ?.constraints
        .precedingScrollExtent;
    final content =
        constraints.precedingScrollExtent -
        (start ?? constraints.precedingScrollExtent);
    final extent = math.max(
      0.0,
      constraints.viewportMainAxisExtent - pinnedAbove - content,
    );
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintExtent: calculatePaintOffset(constraints, from: 0, to: extent),
      maxPaintExtent: extent,
    );
  }
}
