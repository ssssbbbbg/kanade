import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'smooth_scroll.dart';

/// 底部弹窗：一张浮起来的圆角卡片，左右和底部留空，背景压暗。
/// 电脑上窗口很宽，卡片最宽 480 居中。底色是实心的，不用毛玻璃，长列表也不掉帧。
/// 走根导航器：每个标签页有自己的 Navigator，不然只会盖住内容区、在页面中间弹出来。
Future<T?> showKanadeSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? heightFactor,
  EdgeInsets padding = const EdgeInsets.fromLTRB(10, 0, 10, 10),
}) => _showSheet<T>(
  context,
  (sheet) => _SheetFrame(
    heightFactor: heightFactor,
    padding: padding,
    child: builder(sheet),
  ),
);

/// [showExpandableSheet] 的内容，[controller] 要交给里面那个能滚的列表。
typedef ScrollSheetBuilder = Widget Function(
  BuildContext context,
  ScrollController controller,
);

/// 能拉高的弹窗，先按 [heightFactor] 弹出来。
/// 手机上往上拖先把弹窗拉到铺满屏幕，铺满后才滚列表；列表在顶上时往下拖先缩回原高度，再往下就关掉。
/// Windows 上滚轮往下先把弹窗升到窗口顶部再滚列表，列表在顶上时往上滚再降回来。
Future<T?> showExpandableSheet<T>({
  required BuildContext context,
  required double heightFactor,
  required ScrollSheetBuilder builder,
}) => _showSheet<T>(
  context,
  (_) => defaultTargetPlatform == TargetPlatform.windows
      ? _WheelExpandSheet(heightFactor: heightFactor, builder: builder)
      : _DragExpandSheet(heightFactor: heightFactor, builder: builder),
  // 拖动、松手都由弹窗自己管，不让外层再拖一份
  enableDrag: false,
);

Future<T?> _showSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool enableDrag = true,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  elevation: 0,
  barrierColor: Colors.black.withValues(alpha: 0.6),
  constraints: const BoxConstraints(maxWidth: 480),
  enableDrag: enableDrag,
  builder: builder,
);

/// Windows：卡片样式不变，高度在原高度和窗口顶部之间升降。
class _WheelExpandSheet extends StatefulWidget {
  const _WheelExpandSheet({required this.heightFactor, required this.builder});

  final double heightFactor;
  final ScrollSheetBuilder builder;

  @override
  State<_WheelExpandSheet> createState() => _WheelExpandSheetState();
}

class _WheelExpandSheetState extends State<_WheelExpandSheet>
    with SingleTickerProviderStateMixin {
  late final _expand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final _curve = CurvedAnimation(
    parent: _expand,
    curve: Curves.easeOutCubic,
  );

  // 没完全升到顶时滚轮只管升弹窗，不滚列表
  late final _scroll = SmoothScrollController(
    blockWheel: () => _expand.value < 1,
  );

  @override
  void dispose() {
    _scroll.dispose();
    _curve.dispose();
    _expand.dispose();
    super.dispose();
  }

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final dy = e.scrollDelta.dy;
    if (dy > 0) {
      if (!_expand.status.isForwardOrCompleted) _expand.forward();
    } else if (dy < 0 &&
        _expand.status.isForwardOrCompleted &&
        _scroll.hasClients &&
        _scroll.position.pixels <= _scroll.position.minScrollExtent) {
      _expand.reverse();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _wheel,
    child: AnimatedBuilder(
      animation: _curve,
      builder: (_, child) => _SheetFrame(
        heightFactor: lerpDouble(widget.heightFactor, 1, _curve.value),
        padding: EdgeInsets.zero,
        child: child!,
      ),
      child: Builder(builder: (context) => widget.builder(context, _scroll)),
    ),
  );
}

/// 手机：跟着手指拉高，铺满屏幕时卡片的留白、圆角都收掉，内容让开状态栏和底部手势条。
/// 松手后用弹簧接着手指的速度走到停靠点（关闭、原高度、铺满），不是按固定时长匀速挪过去。
class _DragExpandSheet extends StatefulWidget {
  const _DragExpandSheet({required this.heightFactor, required this.builder});

  final double heightFactor;
  final ScrollSheetBuilder builder;

  @override
  State<_DragExpandSheet> createState() => _DragExpandSheetState();
}

class _DragExpandSheetState extends State<_DragExpandSheet>
    with TickerProviderStateMixin {
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 400,
    ratio: 1,
  );

  /// 弹窗露出来的高度（像素），从屏幕底边往上算。
  late final _extent = AnimationController.unbounded(vsync: this);

  /// 1 是圆角，0 是直角：拉的过程中一直是圆角，真铺满了才很快收成直角，离开顶部再变回圆角。
  late final _corner = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 180),
  );
  bool _square = false;
  late final _scroll = _SheetScrollController(this);

  double? _full;
  double _initial = 0;

  /// 这次按下时弹窗是不是铺满的：从铺满往下甩只回到原高度，不直接关掉。
  bool _fromFull = false;

  bool get _isFull => _extent.value >= _full! - 0.5;

  @override
  void initState() {
    super.initState();
    _extent.addListener(_syncCorner);
  }

  void _syncCorner() {
    if (_isFull == _square) return;
    _square = _isFull;
    _corner.animateTo(_square ? 0 : 1, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _extent.dispose();
    _corner.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 手指按下：停住正在走的动画，从当前位置接着拖。
  void _hold() {
    _extent.stop();
    _fromFull = _isFull;
  }

  /// [delta] 往下为正。
  void _dragBy(double delta) =>
      _extent.value = (_extent.value - delta).clamp(0.0, _full!);

  /// [velocity] 往上为正，单位像素每秒。
  void _settle(double velocity) {
    final x = _extent.value;
    final stops = [0.0, _initial, _full!];
    var target = velocity.abs() > 700
        ? velocity > 0
              ? stops.firstWhere((s) => s > x + 1, orElse: () => stops.last)
              : stops.lastWhere((s) => s < x - 1, orElse: () => 0)
        : stops.reduce((a, b) => (a - x).abs() <= (b - x).abs() ? a : b);
    // 从铺满往下甩只回到原高度；拖过原高度的一半再松手才关
    if (_fromFull && target == 0 && x > _initial / 2) target = _initial;
    final full = _full!;
    // 往铺满走时瞄准顶部再往上一点、碰到顶就停：不会在最后一截慢慢蹭，圆角也就贴到顶才变直角
    final spring = SpringSimulation(
      _spring,
      x,
      target == full ? full + 24 : target,
      velocity,
      tolerance: const Tolerance(distance: 0.5, velocity: 20),
    );
    _extent
        .animateWith(target == full ? _StopAtTop(spring, full) : spring)
        .then((_) {
          if (target == 0 && mounted) Navigator.of(context).pop();
        });
  }

  @override
  Widget build(BuildContext context) {
    // 弹窗里 MediaQuery 的顶部留白被去掉了，状态栏高度要从窗口本身拿
    final view = View.of(context);
    final inset = MediaQuery.paddingOf(context)
        .copyWith(top: view.padding.top / view.devicePixelRatio);
    final scheme = Theme.of(context).colorScheme;
    final (bg, _) = sheetColors(scheme);
    final full = MediaQuery.sizeOf(context).height;
    // 和普通弹窗一样：卡片高度按可用高度算，再加上底下的留白
    final available = full - inset.top - inset.bottom - 16;
    _initial = math.min(
      full,
      available * widget.heightFactor + 8 + inset.bottom,
    );
    if (full != _full) {
      // 第一次从原高度开始；屏幕尺寸变了的话铺满的还铺满，其余回到原高度
      final wasFull = _full != null && _isFull;
      _full = full;
      _extent.stop();
      _extent.value = wasFull ? full : _initial;
    }
    final content = GestureDetector(
      // 拖顶部、原评论这些不滚的地方也能拉动弹窗
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) => _hold(),
      onVerticalDragUpdate: (d) => _dragBy(d.primaryDelta!),
      onVerticalDragEnd: (d) => _settle(-(d.primaryVelocity ?? 0)),
      child: Column(
        children: [
          const _Handle(),
          Expanded(
            child: Builder(
              builder: (context) => widget.builder(context, _scroll),
            ),
          ),
        ],
      ),
    );
    // 拖动时每帧只重建外框，内容只建一次
    return AnimatedBuilder(
      animation: Listenable.merge([_extent, _corner]),
      child: content,
      builder: (context, child) {
        final h = _extent.value.clamp(0.0, full);
        // 卡片顶边离屏幕顶部还有多远；从原高度往上拉的整段里左右和底下的留白慢慢收掉
        final gap = full - h;
        final margin = (gap / math.max(full - _initial, 1)).clamp(0.0, 1.0);
        // 往下拖着关闭时卡片保持原高度往下滑出去，不压扁
        final height = math.max(h, _initial);
        return SizedBox(
          height: h,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: height,
            maxHeight: height,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                8 * margin,
                0,
                8 * margin,
                (8 + inset.bottom) * margin,
              ),
              child: Material(
                color: bg,
                clipBehavior: Clip.antiAlias,
                // 形状每帧都在变，Material 自带的形状过渡会让圆角慢半拍
                animationDuration: Duration.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24 * _corner.value),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(
                      alpha: _corner.value,
                    ),
                    width: 0.5,
                  ),
                ),
                child: Padding(
                  // 卡片顶到状态栏里的那一截让出来；底部留白收掉多少，里面就补多少
                  padding: EdgeInsets.only(
                    top: math.max(0.0, inset.top - gap),
                    bottom: inset.bottom * (1 - margin),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 回复列表的滚动：弹窗没铺满时手指拖列表是在拉弹窗，铺满后才滚列表；
/// 列表在顶上时往下拖、往下甩到顶剩下的速度，都交给弹窗。
class _SheetScrollController extends ScrollController {
  _SheetScrollController(this.sheet);

  final _DragExpandSheetState sheet;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SheetScrollPosition(
    sheet,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition(
    this.sheet, {
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _DragExpandSheetState sheet;

  /// 手指按着列表，松手时弹窗要停到停靠点上。
  bool _touched = false;

  /// 这一下拖动里拉过弹窗。
  bool _dragsSheet = false;

  @override
  ScrollHoldController hold(VoidCallback holdCancelCallback) {
    sheet._hold();
    _touched = true;
    return super.hold(holdCancelCallback);
  }

  @override
  void applyUserOffset(double delta) {
    if (!sheet._isFull || (delta > 0 && pixels <= minScrollExtent)) {
      _dragsSheet = true;
      sheet._dragBy(delta);
    } else {
      super.applyUserOffset(delta);
    }
  }

  @override
  void goBallistic(double velocity) {
    if (_touched) {
      _touched = false;
      // 往上甩到铺满后剩下的速度给列表，其余都交给弹窗
      if (_dragsSheet && !(sheet._isFull && velocity > 0)) {
        sheet._settle(velocity);
        velocity = 0;
      } else {
        sheet._settle(0);
      }
      _dragsSheet = false;
    }
    super.goBallistic(velocity);
  }

  @override
  double setPixels(double newPixels) {
    final overscroll = super.setPixels(newPixels);
    // 铺满时列表往下甩到顶，剩下的速度把弹窗带回原高度
    final a = activity;
    if (overscroll < 0 && a is BallisticScrollActivity && sheet._isFull) {
      sheet._fromFull = true;
      sheet._settle(a.velocity);
    }
    return overscroll;
  }
}

/// 卡片底色和里面分组的底色，亮色模式下是白卡片 + 浅灰分组。
(Color, Color) sheetColors(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
    ? (scheme.surfaceContainer, scheme.surfaceContainerHigh)
    : (scheme.surface, scheme.surfaceContainer);

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.child,
    required this.padding,
    this.heightFactor,
  });

  final Widget child;
  final EdgeInsets padding;

  /// 给定时卡片固定这么高（占可用高度的比例），否则跟着内容走，最高 85%。
  final double? heightFactor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (bg, _) = sheetColors(scheme);
    // 有输入框时键盘弹起，卡片要贴着键盘上沿
    final bottom = media.padding.bottom + media.viewInsets.bottom;
    final available = media.size.height - media.padding.top - bottom - 16;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Handle(),
        if (heightFactor != null)
          Expanded(child: child)
        else
          Flexible(child: child),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + bottom),
      child: Material(
        color: bg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
        child: Padding(
          padding: padding,
          child: heightFactor != null
              ? SizedBox(height: available * heightFactor!, child: content)
              : ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: available * 0.85),
                  child: content,
                ),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Container(
      width: 32,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// 弹窗顶部：封面 + 标题 + 副标题，没有封面时只有一行标题。
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一排大方块，放最常用的几个操作。
class SheetQuickActions extends StatelessWidget {
  const SheetQuickActions({super.key, required this.children});

  final List<SheetQuickAction> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    ),
  );
}

class SheetQuickAction extends StatelessWidget {
  const SheetQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (_, group) = sheetColors(scheme);
    return Material(
      color: group,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, size: 24, color: iconColor ?? scheme.onSurface),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    );
  }
}

/// 圆角分组，行与行之间一条细线。给了 [controller] 就能在里面滚动（外面要包 Flexible）。
class SheetGroup extends StatelessWidget {
  const SheetGroup({super.key, required this.children, this.controller});

  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (_, group) = sheetColors(scheme);
    return Material(
      color: group,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        controller: controller,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: controller == null
            ? const NeverScrollableScrollPhysics()
            : null,
        itemCount: children.length,
        itemBuilder: (_, i) => children[i],
        separatorBuilder: (_, _) => Divider(
          height: 0.5,
          thickness: 0.5,
          indent: 14,
          color: scheme.outlineVariant,
        ),
      ),
    );
  }
}

/// 分组里的一行。[chevron] 表示点了会跳到别的页面；[destructive] 整行标红。
class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onTap,
    this.trailing,
    this.chevron = false,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onTap;

  /// 行尾的控件，比如开关。
  final Widget? trailing;
  final bool chevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme.merge(
                data: IconThemeData(
                  size: 22,
                  color: destructive ? scheme.error : scheme.onSurfaceVariant,
                ),
                child: leading!,
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
            if (chevron)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.outline,
              ),
          ],
        ),
      ),
    );
  }
}

/// 往上弹到 [top] 就停。
class _StopAtTop extends Simulation {
  _StopAtTop(this.inner, this.top);

  final Simulation inner;
  final double top;

  @override
  double x(double time) => math.min(inner.x(time), top);

  @override
  double dx(double time) => inner.dx(time);

  @override
  bool isDone(double time) => inner.x(time) >= top || inner.isDone(time);
}
