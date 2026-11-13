import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Windows 上鼠标滚轮一格不再瞬间跳一段，而是减速滑过去；连着滚几格时目标往前累加。
/// 触控板（走拖动手势）、拖滚动条、其他平台都照旧。
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.blockWheel,
  });

  /// 返回 true 时这一下滚轮不滚列表，比如弹窗还在往上升。
  final bool Function()? blockWheel;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return super.createScrollPosition(physics, context, oldPosition);
    }
    return _SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      blockWheel: blockWheel,
    );
  }
}

/// 给没有自己 State 的列表用：建一个 [SmoothScrollController] 交给 [builder]，跟着这个组件一起销毁。
class SmoothScroll extends StatefulWidget {
  const SmoothScroll({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<SmoothScroll> createState() => _SmoothScrollState();
}

class _SmoothScrollState extends State<SmoothScroll> {
  final _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
    this.blockWheel,
  });

  final bool Function()? blockWheel;

  static const _duration = Duration(milliseconds: 220);

  /// 正在滑向的位置；滚轮动画被打断（拖动、点滚动条、动画播完）后就作废。
  double _target = 0;
  _WheelActivity? _wheel;

  @override
  void pointerScroll(double delta) {
    if (blockWheel?.call() ?? false) return;
    if (delta == 0.0) return super.pointerScroll(delta);
    final from = activity == _wheel ? _target : pixels;
    final to = (from + delta).clamp(minScrollExtent, maxScrollExtent);
    if (to == from) return;
    _target = to;
    beginActivity(
      _wheel = _WheelActivity(
        this,
        from: pixels,
        to: to,
        duration: _duration,
        curve: Curves.easeOutCubic,
        vsync: context.vsync,
      ),
    );
    updateUserScrollDirection(
      delta > 0.0 ? ScrollDirection.reverse : ScrollDirection.forward,
    );
  }
}

/// 滚轮滑动时不挡住鼠标，悬停效果和点击照常。
class _WheelActivity extends DrivenScrollActivity {
  _WheelActivity(
    super.delegate, {
    required super.from,
    required super.to,
    required super.duration,
    required super.curve,
    required super.vsync,
  });

  @override
  bool get shouldIgnorePointer => false;
}
