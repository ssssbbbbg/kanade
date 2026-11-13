import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../player/player_controller.dart';
import 'player_page.dart';
import 'title_bar.dart';
import 'widgets.dart';

/// 播放条在屏幕上的锚点：播放页从它变形出来，关闭时再变回它。
/// 播放条把 [barKey] / [coverKey] 挂在自己和封面上，并提供一份不带封面的 [face]，
/// 变形开头由转场层画这份副本，播放条本身藏起来（[hidden]）。
class PlayerBarAnchor {
  PlayerBarAnchor({required this.face, required this.coverRadius});

  final barKey = GlobalKey(debugLabel: 'player bar');
  final coverKey = GlobalKey(debugLabel: 'player bar cover');

  /// 播放条上除封面以外的内容（歌名、按钮），按播放条的尺寸排版。
  final WidgetBuilder face;

  /// 播放条上封面的圆角，飞行封面从它过渡到大封面的圆角。
  final double coverRadius;

  /// 播放页盖在上面（包括转场途中）时为 true。
  final hidden = ValueNotifier(false);

  /// 变形开头（进度不到 [PlayerMorph.glassUntil]）时是正在驱动它的那个变形：
  /// 这段的玻璃就是播放条自己那块跟着长大（见 [PlayerBarGrowth]），其余时候为 null。
  final growing = ValueNotifier<PlayerMorph?>(null);

  Rect? get rect => _globalRect(barKey);
  Rect? get coverRect => _globalRect(coverKey);

  /// 挂着 [key] 的组件在屏幕上的位置。还没布局时返回 null。
  static Rect? _globalRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// 驱动"播放条 ⇄ 播放页"变形的一方：播放页的路由，或者手指从播放条往上拖、还没松手时的预览。
/// 播放页通过 [PlayerMorph.maybeOf] 拿到它，把大封面挂到 [artKey] 上。
mixin PlayerMorph {
  PlayerBarAnchor? get anchor;

  /// 播放页里大封面的 key，飞行封面的终点。
  final artKey = GlobalKey(debugLabel: 'player art');

  /// 封面还在飞的时候，播放页自己的封面先藏起来。
  late final artInFlight = ValueNotifier(anchor != null);

  /// 上一次量到的大封面位置（相对播放页）。预览交接给路由时带过去，路由第一帧还没排版也能用。
  Rect? lastArt;

  /// 形状顶边从播放条走到屏幕顶的距离，把手指位移换算成进度。
  double travel = 600;

  /// 变形进度变化时通知重建。
  Listenable get motion;

  /// 当前看到的变形进度，0 是播放条，1 是全屏播放页。
  double get progress;

  static PlayerMorph? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MorphScope>()?.morph;

  /// 播放页在这之前还没完全显出来，底下要有玻璃。
  static const glassUntil = 0.3;

  /// 形状在进度 [t] 时的圆角（不算快到全屏时收成直角的那段），从播放条的半圆走向大圆角。
  static double radiusAt(double barShortestSide, double t) =>
      lerpDouble(barShortestSide / 2, 38, t)!;

  /// 进度变化时调用：开头这段让播放条的玻璃跟着长。
  void syncGrowing() {
    final a = anchor;
    if (a == null) return;
    if (progress < glassUntil) {
      a.growing.value = this;
    } else {
      stopGrowing();
    }
  }

  void stopGrowing() {
    if (anchor?.growing.value == this) anchor!.growing.value = null;
  }
}

class _MorphScope extends InheritedWidget {
  const _MorphScope({required this.morph, required super.child});

  final PlayerMorph morph;

  @override
  bool updateShouldNotify(_MorphScope old) => morph != old.morph;
}

/// 变形进度从 [from] 走到 [to] 的运动，[velocity] 是当前每秒走多少进度。
/// 打开和收起都是 easeOutQuart：起步特别快，快到终点时明显放慢、轻轻停住，不回弹。
/// 中途掉头或手指松开时接着已有的速度走，不会突然变快变慢；甩得快就相应缩短时长。
Simulation _spring(double from, double to, double velocity) {
  final dist = (to - from).abs();
  final dir = to > from ? 1.0 : -1.0;
  // 路短的时候时间也短一些
  var duration = 0.5 * (0.4 + 0.6 * dist);
  final toward = velocity * dir;
  // 起步切线（进度 / 全程）默认 4，超过 5 会冲过终点，甩得快就缩短时长
  if (toward * duration > 5 * dist) duration = 5 * dist / toward;
  final tangent = toward >= 0
      ? math.max(toward * duration, 4 * dist)
      : toward * duration;
  return _Ease(from, to, tangent * dir, math.max(duration, 0.001));
}

/// x = 起点 + 路程·(1 − (1 − s)⁴) + (起步切线 − 4·路程)·s(1 − s)⁴。
/// 后一项两端为 0、终点斜率为 0、起点斜率为 1，只用来调起步速度，不影响落点。
class _Ease extends Simulation {
  _Ease(this.from, this.to, double tangent, this.duration)
    : _m = tangent - (to - from) * 4;

  final double from, to, duration;
  final double _m;

  double _s(double time) => (time / duration).clamp(0.0, 1.0);

  @override
  double x(double time) {
    final s = _s(time), r = 1 - s, r4 = r * r * r * r;
    return from + (to - from) * (1 - r4) + _m * s * r4;
  }

  @override
  double dx(double time) {
    final s = _s(time), r = 1 - s, r3 = r * r * r;
    return ((to - from) * 4 * r3 + _m * r3 * (1 - 5 * s)) / duration;
  }

  @override
  bool isDone(double time) => time >= duration;
}

/// 播放条上"按住往上拖打开播放页"的手势。
///
/// 拖动途中不能推路由：Navigator 推页面时会取消屏幕上正在进行的触摸，手势就断了。
/// 所以拖的时候先在最上层画一份一模一样的变形预览跟手，松手要打开时再推真正的路由，
/// 从同一个进度接着展开，同一帧撤掉预览。
class PlayerBarDrag {
  PlayerBarDrag(this.anchor, this.vsync);

  final PlayerBarAnchor anchor;
  final TickerProvider vsync;
  _DragPreview? _preview;

  void update(BuildContext context, DragUpdateDetails d) {
    if (_preview == null) {
      if (d.delta.dy >= 0) return;
      _preview = _DragPreview(anchor, vsync)..show(context);
    }
    _preview!.dragUpdate(d.delta.dy);
  }

  void end(BuildContext context, double velocityY) {
    _preview?.release(context, velocityY);
    _preview = null;
  }
}

class _DragPreview with PlayerMorph {
  _DragPreview(this.anchor, TickerProvider vsync)
    : _controller = AnimationController(vsync: vsync) {
    // 拖到顶时飞行封面撤掉，换播放页自己的封面露出来，和路由里一样
    _controller.addListener(() {
      artInFlight.value = _controller.value < 1;
      syncGrowing();
    });
  }

  @override
  final PlayerBarAnchor anchor;
  final AnimationController _controller;
  OverlayEntry? _entry;

  @override
  Listenable get motion => _controller;

  @override
  double get progress => _controller.value;

  void show(BuildContext context) {
    anchor.hidden.value = true;
    syncGrowing();
    // 手指一直按在播放条上，预览不接收点击
    _entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: _BarMorph(morph: this, child: const PlayerPage()),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void dragUpdate(double dy) => _controller.value -= dy / travel;

  void release(BuildContext context, double velocityY) {
    final v = -velocityY / travel;
    final open = v.abs() > 1 ? v > 0 : _controller.value > 0.5;
    if (open) {
      Navigator.of(context, rootNavigator: true).push(
        PlayerRoute(
          anchor: anchor,
          startAt: _controller.value,
          startVelocity: v,
          artHint: lastArt,
        ),
      );
      _dispose();
    } else {
      _controller
          .animateBackWith(_spring(_controller.value, 0, v))
          .whenComplete(() {
            anchor.hidden.value = false;
            _dispose();
          });
    }
  }

  void _dispose() {
    // 交给路由时它已经接手了播放条的玻璃，这里只撤自己的
    stopGrowing();
    _entry
      ?..remove()
      ..dispose();
    _entry = null;
    // 预览下一帧才真正卸载，卸载时还要从这两个上面摘监听
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.dispose();
      artInFlight.dispose();
    });
  }
}

/// 播放页的路由。打开时播放条本身变形成播放页：形状从胶囊长到全屏，全程保持大圆角；
/// 页面内容按全屏排好，只跟着形状的顶边平移，所以底部的控制区是从下面滑上来的；
/// 封面单独从播放条飞到大封面的位置。播放页里上下拖可以直接拖动这个过程（[dragStart] 那一组）。
///
/// 用 ModalRoute 而不是 PageRoute：PageRoute 推上来的第一帧会被 Hero 机制挂成 offstage、
/// 动画临时接到"已完成"；下面的页面也不会跟着做页面切换的动画。
class PlayerRoute extends ModalRoute<void> with PlayerMorph {
  PlayerRoute({
    this.anchor,
    this.showQueue = false,
    this.startAt,
    double? startVelocity,
    Rect? artHint,
  }) : _release = startVelocity {
    lastArt = artHint;
  }

  @override
  final PlayerBarAnchor? anchor;

  final bool showQueue;

  /// 从拖动预览接手时的起始进度。
  final double? startAt;

  /// 手指松开时的速度，下一段运动从它起步；用一次就清掉。
  double? _release;
  bool _dragging = false;

  @override
  Listenable get motion => controller!;

  /// 控制器全程由 [_spring] 或手指驱动，它的值就是看到的进度，不再套曲线。
  @override
  double get progress => controller!.value;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 560);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 460);

  @override
  void install() {
    super.install();
    controller!
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
  }

  @override
  TickerFuture didPush() {
    anchor?.hidden.value = true;
    // 接着拖动预览的进度往下展开
    if (startAt case final start?) controller!.value = start;
    syncGrowing();
    return super.didPush();
  }

  /// 推入和返回都用 [_spring]。打开途中按返回时控制器还在往前走，接着这个速度掉头，
  /// 不会按剩下的时间比例硬缩成一小段。
  @override
  Simulation createSimulation({required bool forward}) {
    final c = controller!;
    final v = _release ?? c.velocity;
    _release = null;
    return _spring(c.value, forward ? 1 : 0, v);
  }

  void _onTick() {
    artInFlight.value = anchor != null && controller!.value < 1;
    syncGrowing();
  }

  void _onStatus(AnimationStatus status) {
    if (status.isDismissed && !isActive) {
      stopGrowing();
      anchor?.hidden.value = false;
    }
  }

  @override
  void dispose() {
    stopGrowing();
    anchor?.hidden.value = false;
    artInFlight.dispose();
    super.dispose();
  }

  /// 从播放条点开。
  static void open(
    BuildContext context, {
    PlayerBarAnchor? anchor,
    bool showQueue = false,
  }) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(PlayerRoute(anchor: anchor, showQueue: showQueue));

  /// 手指按下：停在当前看到的位置接管。
  void dragStart() {
    _dragging = true;
    controller!.stop();
  }

  /// 竖直方向的手指位移，往下为正。
  void dragUpdate(double dy) => controller!.value -= dy / travel;

  /// 松手：按速度或位置决定展开还是收回，从手指的速度起步。
  void dragEnd(double velocityY) {
    // 点按钮时下拉手势没真正开始也会收到取消，这时不能打断正在进行的动画
    if (!_dragging) return;
    final c = controller!;
    final v = -velocityY / travel;
    final open = v.abs() > 1 ? v > 0 : c.value > 0.5;
    _dragging = false;
    if (open) {
      c.animateWith(_spring(c.value, 1, v));
    } else if (isCurrent) {
      // 返回的运动在 createSimulation 里建，带上手指的速度
      _release = v;
      navigator!.pop();
    } else {
      c.animateBackWith(_spring(c.value, 0, v));
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // 全屏沉浸：窗口按钮平时隐藏，鼠标移到顶部才出现
    final page = ImmersiveTitleBar(child: PlayerPage(showQueue: showQueue));
    if (!Platform.isWindows) return page;
    // Windows 上按 Esc 收起播放页
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            navigator?.maybePop(),
      },
      child: Focus(autofocus: true, child: page),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _BarMorph(morph: this, child: child);
}

class _BarMorph extends StatefulWidget {
  const _BarMorph({required this.morph, required this.child});

  final PlayerMorph morph;
  final Widget child;

  @override
  State<_BarMorph> createState() => _BarMorphState();
}

class _BarMorphState extends State<_BarMorph> {
  /// 包住整个播放页，大封面的位置相对它来量，不受变形时的平移影响。
  final _pageKey = GlobalKey();
  Rect? _start;

  /// 大封面在播放页里的位置。播放页第一帧还没排版，就用上一次量到的。
  Rect? _artRect() {
    final morph = widget.morph;
    final art = morph.artKey.currentContext?.findRenderObject();
    final page = _pageKey.currentContext?.findRenderObject();
    if (art is RenderBox && page is RenderBox && art.hasSize && art.attached) {
      morph.lastArt = MatrixUtils.transformRect(
        art.getTransformTo(page),
        Offset.zero & art.size,
      );
    }
    return morph.lastArt;
  }

  /// 封面落到播放页位置时的进度，之后钉在播放页上跟着走。
  static const _coverSettle = 0.84;

  /// 飞行封面在进度 [t] 时相对形状左上角的位置：从它在播放条里的位置过渡到它在播放页里的位置。
  /// 封面贴着形状底边长大，一开始就慢慢往上挪，越往后挪得越多，到 [_coverSettle] 正好落到 [art]；
  /// 大小先快后慢，横向居中比大小再快一点。[from] 是封面在屏幕上的位置，[start] 是播放条。
  static Rect _coverRect(Rect from, Rect start, Rect full, Rect art, double t) {
    if (t >= _coverSettle) return art;
    final u = t / _coverSettle;
    final height = lerpDouble(start.height, full.height, t)!;
    final settledHeight = lerpDouble(start.height, full.height, _coverSettle)!;
    final grow = 1 - math.pow(1 - u, 1.7).toDouble();
    final size = Size.lerp(from.size, art.size, grow)!;
    final centerX = lerpDouble(
      from.center.dx - start.left,
      art.center.dx,
      1 - math.pow(1 - u, 2.2).toDouble(),
    )!;
    final gap = lerpDouble(
      start.bottom - from.bottom,
      settledHeight - art.bottom,
      math.pow(u, 2.5).toDouble(),
    )!;
    return Rect.fromLTWH(
      centerX - size.width / 2,
      height - gap - size.height,
      size.width,
      size.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final morph = widget.morph;
    final anchor = morph.anchor;
    return AnimatedBuilder(
      animation: morph.motion,
      child: _MorphScope(
        morph: morph,
        child: KeyedSubtree(key: _pageKey, child: widget.child),
      ),
      builder: (context, page) {
        final size = MediaQuery.sizeOf(context);
        final full = Offset.zero & size;
        // 没有播放条（测试、其他入口）时从屏幕底边升上来
        final start = _start =
            anchor?.rect ??
            _start ??
            Rect.fromLTWH(16, size.height, size.width - 32, 64);
        morph.travel = math.max(160, start.top);
        final t = morph.progress;
        final rect = Rect.lerp(start, full, t)!;
        // 全程大圆角，到全屏前的最后一小段才收成直角
        final radius =
            PlayerMorph.radiusAt(start.shortestSide, t) *
            ((1 - t) / 0.06).clamp(0.0, 1.0);
        // 播放页在前 30% 里显出来，之后它不透明，底下的玻璃就不用画了
        final pageOpacity = anchor == null
            ? 1.0
            : (t / PlayerMorph.glassUntil).clamp(0.0, 1.0);
        final from = anchor != null && t < 1 ? anchor.coverRect : null;
        final art = from == null ? null : _artRect();
        return Stack(
          fit: StackFit.expand,
          children: [
            // 底下的玻璃是播放条自己那块在长大（[PlayerBarGrowth]），这里不另画
            // 页面按全屏排好，只跟着形状的顶边平移、被形状裁剪；不缩放，每帧不用重新排版
            Transform.translate(
              // 后面的副本会增删，靠 key 对上，页面不被重建
              key: const ValueKey('page'),
              offset: Offset(0, rect.top),
              child: ClipRRect(
                clipper: _RRectClipper(
                  RRect.fromRectAndRadius(
                    rect.translate(0, -rect.top),
                    Radius.circular(radius),
                  ),
                ),
                clipBehavior: t >= 1 ? Clip.none : Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(opacity: pageOpacity, child: page),
                    // 这一层已经跟着形状的顶边平移，横向再补上形状的左边；封面始终在形状里面，也被形状裁住
                    if (from != null)
                      Positioned.fromRect(
                        rect: _coverRect(
                          from,
                          start,
                          full,
                          art ?? from.shift(-start.topLeft),
                          t,
                        ).translate(rect.left, 0),
                        child: IgnorePointer(
                          child: _FlyingCover(
                            radius: lerpDouble(anchor!.coverRadius, 14, t)!,
                            t: t,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 播放条上的歌名和按钮跟着顶边走，很快淡掉
            if (anchor != null && t < 0.18)
              Positioned(
                left: rect.left,
                top: rect.top,
                width: start.width,
                height: start.height,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 1 - t / 0.18,
                    child: anchor.face(context),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 飞行中的封面：大图加载时继续显示播放条的小图。
/// 投影随进度 [t] 从无长到大封面那样，落地换成真封面时不会突然冒出阴影。
class _FlyingCover extends StatelessWidget {
  const _FlyingCover({required this.radius, required this.t});

  final double radius;
  final double t;

  @override
  Widget build(BuildContext context) {
    final song = context.read<PlayerController>().current;
    if (song == null) return const SizedBox.shrink();
    final shadow = albumArtShadow(
      lifted: context.select<PlayerController, bool>((p) => p.playing),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: shadow.color.withValues(alpha: shadow.color.a * t),
            offset: shadow.offset * t,
            blurRadius: shadow.blurRadius * t,
            spreadRadius: shadow.spreadRadius * t,
          ),
        ],
      ),
      child: Cover(
        bigCoverUrl(song),
        placeholderUrl: song.coverUrl,
        radius: radius,
      ),
    );
  }
}

class _RRectClipper extends CustomClipper<RRect> {
  const _RRectClipper(this.rrect);

  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(_RRectClipper old) => old.rrect != rrect;
}

/// 播放条的玻璃，变形开头（[PlayerBarAnchor.growing]）由它自己长成播放页的形状，
/// 不另画一块：同一个图层、同一份背景，看起来不会突然换掉（手机上和导航栏粘在一起的那块也一样）。
/// 外面的布局不变，只把玻璃排大、画到形状的位置。`growing` 时歌名、封面由转场层画，
/// 玻璃里的内容要藏起来，并用 [pin] 包住，让它留在原位。
///
/// [builder] 拿到的 `shapeT` 用来按 [PlayerMorph.radiusAt] 给圆角，和播放页的形状对齐。
/// Windows 上它一直是 0，圆角保持播放条自己的：Skia 上圆角一变就要现场编译另一份玻璃着色器，
/// 第一次打开会卡一两百毫秒；这段圆角只差 1～2 像素，播放页还盖在上面淡入，看不出来。
class PlayerBarGrowth extends StatelessWidget {
  const PlayerBarGrowth({
    super.key,
    required this.anchor,
    required this.builder,
  });

  final PlayerBarAnchor anchor;
  final Widget Function(bool growing, double shapeT) builder;

  /// 进度里玻璃用的那份：Windows 上不跟着变圆角，见上。
  static double shapeT(double t) => Platform.isWindows ? 0 : t;

  /// 玻璃里的内容按播放条原来的尺寸排、画回原来的位置，不跟着玻璃重新排版；
  /// 封面量出来一直是它停着时的位置，飞行封面不会跟着跳。
  static Widget pin(Widget child) => _Pin(child: child);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: anchor.growing,
    builder: (context, morph, _) => AnimatedBuilder(
      // 换动画不换结构，玻璃一直是同一个
      animation: morph?.motion ?? const AlwaysStoppedAnimation(0.0),
      builder: (context, _) {
        final t = morph?.progress ?? 0.0;
        return _Grow(
          t: t,
          screen: MediaQuery.sizeOf(context),
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
          child: builder(morph != null, shapeT(t)),
        );
      },
    ),
  );
}

class _Grow extends SingleChildRenderObjectWidget {
  const _Grow({
    required this.t,
    required this.screen,
    required this.pixelRatio,
    super.child,
  });

  final double t;
  final Size screen;
  final double pixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGrow(t, screen, pixelRatio);

  @override
  void updateRenderObject(BuildContext context, _RenderGrow object) => object
    ..t = t
    ..screen = screen
    ..pixelRatio = pixelRatio;
}

/// 自己占播放条的大小；里面按 [_BarMorph] 的形状排：尺寸从播放条走向全屏，位置走向屏幕左上角。
/// 尺寸只看进度，排版时就能定；位置要等外面排完，在绘制时才算。
class _RenderGrow extends RenderProxyBox {
  _RenderGrow(this._t, this._screen, this._pixelRatio);

  double _t;
  set t(double value) {
    if (value == _t) return;
    _t = value;
    markNeedsLayout();
  }

  Size _screen;
  set screen(Size value) {
    if (value == _screen) return;
    _screen = value;
    markNeedsLayout();
  }

  double _pixelRatio;
  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    markNeedsLayout();
  }

  // 长大途中对齐到整像素，和播放条停着时一样；带小数的边缘在 Windows 的 Skia 上走另一份抗锯齿着色器，第一次要现场编译
  double _snap(double v) => (v * _pixelRatio).roundToDouble() / _pixelRatio;

  Offset get _shift {
    if (_t == 0) return Offset.zero;
    final shift = -localToGlobal(Offset.zero) * _t;
    return Offset(_snap(shift.dx), _snap(shift.dy));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  /// 播放条自己的尺寸，[_RenderPin] 按它排里面的内容。
  Size _restSize = Size.zero;

  @override
  void performLayout() {
    size = _restSize = constraints.biggest;
    final grown = Size.lerp(size, _screen, _t)!;
    child?.layout(
      BoxConstraints.tight(
        _t == 0 ? size : Size(_snap(grown.width), _snap(grown.height)),
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset + _shift);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _shift;
    transform.multiply(Matrix4.translationValues(shift.dx, shift.dy, 0));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child != null &&
      result.addWithPaintOffset(
        offset: _shift,
        position: position,
        hitTest: (result, position) =>
            child!.hitTest(result, position: position),
      );
}

class _Pin extends SingleChildRenderObjectWidget {
  const _Pin({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPin();
}

/// 在长大的玻璃里抵消 [_RenderGrow] 的放大和平移：内容按播放条的尺寸排，画回播放条原来的位置。
class _RenderPin extends RenderProxyBox {
  _RenderGrow? get _grow {
    var node = parent;
    while (node != null && node is! _RenderGrow) {
      node = node.parent;
    }
    return node as _RenderGrow?;
  }

  bool get _pinned => (_grow?._t ?? 0) != 0;

  Offset get _back => _pinned ? -_grow!._shift : Offset.zero;

  @override
  void performLayout() {
    if (!_pinned || child == null) return super.performLayout();
    size = constraints.biggest;
    child!.layout(BoxConstraints.tight(_grow!._restSize));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset + _back);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final back = _back;
    transform.multiply(Matrix4.translationValues(back.dx, back.dy, 0));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child != null &&
      result.addWithPaintOffset(
        offset: _back,
        position: position,
        hitTest: (result, position) =>
            child!.hitTest(result, position: position),
      );
}
