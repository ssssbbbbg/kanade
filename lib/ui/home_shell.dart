import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../l10n/app_localizations.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'desktop_shell.dart';
import 'discover_page.dart';
import 'glass.dart';
import 'mine_page.dart';
import 'mini_player.dart';
import 'overlay_layout_state.dart';
import 'player_route.dart';
import 'search_page.dart';
import 'session_ended_dialog.dart';
import 'song_list_page.dart';
import 'update_dialog.dart';
import 'widgets.dart';

/// 底部（窄屏）或侧边（宽屏）导航。每个标签页有自己的 Navigator，
/// 这样进入歌单详情时迷你播放条仍然保留。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  int _tab = 0;
  final _keys = List.generate(3, (_) => GlobalKey<NavigatorState>());
  late final _depths = List.generate(3, (_) => _DepthObserver(_onDepthChanged));

  /// 当前标签页进了二级页面（歌单、设置……）时收起底部导航。
  bool get _nested => _depths[_tab].depth > 1;

  // 观察者的回调可能发生在构建期间，推到这一帧结束后再刷新
  void _onDepthChanged() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) setState(() {});
  });

  static List<(IconData, IconData, String)> _destinations(AppLocalizations l) =>
      [
        (Icons.explore_outlined, Icons.explore, l.tabDiscover),
        (Icons.search, Icons.search, l.tabSearch),
        (Icons.person_outline, Icons.person, l.tabMine),
      ];

  // 键盘每动一帧都会改 viewInsets：没显示的标签页、被二级页面盖住的首页不跟着逐帧重建，
  // 只留给正在看的页面（比如歌单页的搜索框）
  Widget _tabNavigator(int i, Widget root) {
    // Navigator 放在 Builder 外面建好：它一重建就让里面每个页面整页重建
    final navigator = Navigator(
      key: _keys[i],
      observers: [_depths[i]],
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => Builder(
          builder: (context) => MediaQuery.removeViewInsets(
            context: context,
            removeBottom: !(ModalRoute.of(context)?.isCurrent ?? true),
            child: root,
          ),
        ),
      ),
    );
    return Builder(
      builder: (context) => MediaQuery.removeViewInsets(
        context: context,
        removeBottom: i != _tab,
        child: navigator,
      ),
    );
  }

  void _select(int i) {
    if (i == _tab) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = i);
    }
  }

  /// 侧栏点开的歌单，用来判断是不是又点了正在看的那个。
  (String, Route<void>)? _sidebarPlaylist;

  /// 侧栏点歌单：替换掉当前标签里已经打开的页面，不往上叠，返回时直接回到发现/搜索/我的。
  void _openSidebarPlaylist(PlaylistBrief p) {
    final nav = _keys[_tab].currentState;
    if (nav == null) return;
    final open = _sidebarPlaylist;
    if (open != null && open.$1 == p.id && open.$2.isCurrent) return;
    final route = SongListPage.playlist(p.id, p.title);
    _sidebarPlaylist = (p.id, route);
    nav.pushAndRemoveUntil(route, (r) => r.isFirst);
  }

  /// 手机上滚动页面时播放条收成导航栏右边的圆球，只有点圆球才恢复。
  bool _collapsed = false;
  bool _hadSong = false;
  double _scrolled = 0;

  /// 播放条的形状：0 胶囊，1 圆球。用弹簧驱动，会稍微冲过头再回来。
  late final _shape = AnimationController.unbounded(vsync: this);

  /// 进二级页面的第一段：播放条融进导航栏（每条边 0 原位，1 到导航栏胶囊的位置）。
  /// 四条边各挂一根弹簧：往哪边走哪条边先到，另一条慢半拍跟上，像橡皮筋。
  late final _fuse = _Edges(this);

  /// 第二段：融合后的那一块落成底部的胶囊（每条边 0 导航栏胶囊，1 底部胶囊）。
  late final _drop = _Edges(this);

  /// 导航栏被吸进播放条的程度（0 原样，1 缩小贴着播放条）。返回时用弹簧，冒出来会冲过头弹一下。
  late final _absorb = AnimationController.unbounded(vsync: this);

  /// 导航栏上图标和文字的显示程度。
  late final _navFace = AnimationController(vsync: this, value: 1);

  /// 播放条第一次出现：从导航栏右端分裂出来。
  late final _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
    value: 1,
  );
  double _shapeTarget = 0;
  bool _nestedShown = false;
  int _nestedRun = 0;

  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.72,
  );

  /// 收成圆球慢一点，展开回胶囊还是用快的。
  static final _springCollapse = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 190,
    ratio: 0.8,
  );

  // 进二级页面的边弹簧：前导边硬一点先到，后跟边软一点、晚一点出发
  static final _lead = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 520,
    ratio: 0.72,
  );
  static final _trail = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 260,
    ratio: 0.66,
  );
  static final _dropLead = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 560,
    ratio: 0.68,
  );
  static final _dropTrail = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 240,
    ratio: 0.6,
  );
  static final _side = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 480,
    ratio: 0.75,
  );
  static final _navBounce = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.58,
  );

  /// 有 Impeller 的高画质玻璃时，导航栏和播放条放进同一个玻璃层，融合时真的粘成一块；
  /// 其他平台照旧各画各的，融合时导航栏整个淡掉。
  static bool get _blendGlass =>
      KanadeGlass.navigationQuality == GlassQuality.premium;

  @override
  void initState() {
    super.initState();
    MiniPlayer.anchor.hidden.addListener(_reportPlayerVisibility);
    DesktopPlayerBar.anchor.hidden.addListener(_reportPlayerVisibility);
    _auth.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reportPlayerVisibility();
      _onAuthChanged();
      // 开发时版本号不准，只在发布版里启动时检查
      if (kReleaseMode) unawaited(checkForUpdate(context));
    });
  }

  late final _auth = context.read<AuthController>();

  /// 登录凭证失效被自动退出时，说明原因并提供重新登录的入口。
  void _onAuthChanged() {
    final reason = _auth.sessionEnd;
    if (reason == null) return;
    _auth.dismissSessionEnd();
    unawaited(_showSessionEnded(reason));
  }

  Future<void> _showSessionEnded(SessionEndReason reason) async {
    if (!await showSessionEndedDialog(context, reason) || !mounted) return;
    // 「我的」页未登录时就是登录方式列表
    _keys[2].currentState?.popUntil((r) => r.isFirst);
    if (_tab != 2) setState(() => _tab = 2);
  }

  void _reportPlayerVisibility() {
    OverlayLayoutState.instance.playerVisible.value =
        MiniPlayer.anchor.hidden.value || DesktopPlayerBar.anchor.hidden.value;
  }

  @override
  void dispose() {
    MiniPlayer.anchor.hidden.removeListener(_reportPlayerVisibility);
    DesktopPlayerBar.anchor.hidden.removeListener(_reportPlayerVisibility);
    _auth.removeListener(_onAuthChanged);
    _shape.dispose();
    _fuse.dispose();
    _drop.dispose();
    _absorb.dispose();
    _navFace.dispose();
    _appear.dispose();
    super.dispose();
  }

  TickerFuture _springTo(
    AnimationController c,
    double target,
    SpringDescription spring,
  ) => c.animateWith(SpringSimulation(spring, c.value, target, c.velocity));

  void _syncChrome(bool hasSong) {
    if (hasSong && !_hadSong) {
      _collapsed = touchPlatform;
      _shapeTarget = _collapsed ? 1 : 0;
      _shape.value = _shapeTarget;
      _nestedShown = _nested;
      _fuse.value = _drop.value = _absorb.value = _nested ? 1 : 0;
      _navFace.value = _nested ? 0 : 1;
      _appear.forward(from: 0);
    }
    _hadSong = hasSong;
    final shape = _collapsed ? 1.0 : 0.0;
    if (shape != _shapeTarget) {
      _shapeTarget = shape;
      _springTo(_shape, shape, shape == 1 ? _springCollapse : _spring);
    }
    if (_nested != _nestedShown) {
      _nestedShown = _nested;
      _runNested(_nested);
    }
  }

  /// 进二级页面：播放条融进导航栏（导航栏缩小着被吸进去，两块玻璃粘成一块），
  /// 融到一半就往底部落。往下走时下边先到，上边慢半拍；圆球展开时左边先冲出去。
  /// 退出来倒着走：上边先往上，分出来以后导航栏带着回弹冒出来。
  /// 半路又切回去时，新的一轮从每条边当前的位置和速度接着走。
  Future<void> _runNested(bool nested) async {
    final run = ++_nestedRun;
    bool live() => mounted && run == _nestedRun;
    Future<bool> wait(int ms) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      return live();
    }

    final round = _shapeTarget == 1;
    if (nested) {
      _springTo(_fuse.bottom, 1, _lead);
      _springTo(_fuse.left, 1, round ? _lead : _side);
      _springTo(_fuse.right, 1, round ? _trail : _side);
      unawaited(_absorbNav(run));
      if (!await wait(20)) return;
      final top = _fuse.top.value;
      _springTo(_fuse.top, 1, _trail);
      if (!await _reached(_fuse.top, top, 1, 0.55, run)) return;
      _springTo(_drop.bottom, 1, _dropLead);
      _springTo(_drop.left, 1, _side);
      _springTo(_drop.right, 1, _side);
      if (!await _reached(_fuse.top, top, 1, 0.6, run)) return;
      _springTo(_drop.top, 1, _dropTrail);
    } else {
      _absorb.stop();
      _navFace.stop();
      _springTo(_drop.top, 0, _dropLead);
      _springTo(_drop.left, 0, _side);
      _springTo(_drop.right, 0, _side);
      if (!await wait(30)) return;
      final bottom = _drop.bottom.value;
      _springTo(_drop.bottom, 0, _dropTrail);
      if (!await _reached(_drop.bottom, bottom, 0, 0.5, run)) return;
      final top = _fuse.top.value;
      _springTo(_fuse.top, 0, _lead);
      _springTo(_fuse.left, 0, round ? _trail : _side);
      _springTo(_fuse.right, 0, round ? _lead : _side);
      if (!await _reached(_drop.bottom, bottom, 0, 0.55, run)) return;
      _springTo(_fuse.bottom, 0, _trail);
      if (!await _reached(_fuse.top, top, 0, 0.5, run)) return;
      _springTo(_absorb, 0, _navBounce);
      _navFace.animateTo(
        1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// 进二级页面时导航栏缩小着被吸进去，图标稍晚一点淡掉。
  Future<void> _absorbNav(int run) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted || run != _nestedRun) return;
    _absorb.animateTo(
      1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInCubic,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (!mounted || run != _nestedRun) return;
    _navFace.animateTo(0, duration: const Duration(milliseconds: 220));
  }

  /// 等 [c] 从 [from] 往 [to] 走到 [at] 成。它停下了、或者又开始了新的一轮，也不再等。
  /// 返回这一轮是否还有效。
  Future<bool> _reached(
    AnimationController c,
    double from,
    double to,
    double at,
    int run,
  ) async {
    bool hit() =>
        (to - from).abs() < 1e-6 || (c.value - from) / (to - from) >= at;
    if (!hit() && c.isAnimating) {
      final done = Completer<void>();
      void check() {
        if (run != _nestedRun || hit() || !c.isAnimating) {
          if (!done.isCompleted) done.complete();
        }
      }

      c.addListener(check);
      await done.future;
      c.removeListener(check);
    }
    return mounted && run == _nestedRun;
  }

  /// 上下滑页面（手指拖动的）超过一点距离就收起播放条。
  bool _onScroll(ScrollNotification n) {
    if (!touchPlatform ||
        _collapsed ||
        _nested ||
        !_hadSong ||
        n.metrics.axis != Axis.vertical) {
      return false;
    }
    if (n is ScrollStartNotification) _scrolled = 0;
    final delta = switch (n) {
      ScrollUpdateNotification(dragDetails: != null, :final scrollDelta) =>
        scrollDelta ?? 0,
      OverscrollNotification(dragDetails: != null, :final overscroll) =>
        overscroll,
      _ => 0.0,
    };
    _scrolled += delta.abs();
    if (_scrolled > 24) setState(() => _collapsed = true);
    return false;
  }

  /// 告诉提示浮在哪：在导航栏和播放条之外。构建期间不能通知监听者，推到这一帧之后。
  void _reportChrome(EdgeInsets insets) {
    if (OverlayLayoutState.instance.chrome.value == insets) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) OverlayLayoutState.instance.chrome.value = insets;
    });
  }

  /// 玻璃条浮在内容上方，内容本身铺满全屏；把被遮住的高度加进 padding，
  /// 列表滚到底时最后一项才不会藏在玻璃条下面。
  /// 放在 Builder 里读 MediaQuery，键盘动的时候只有这一层重建，外壳不跟着重建。
  Widget _insetBottom(double inset, Widget child) => Builder(
    builder: (context) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(
          padding: mq.padding.copyWith(bottom: mq.padding.bottom + inset),
        ),
        child: child,
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    // 桌面播放栏两侧是固定宽度，太窄放不下，窄于 960 用手机布局
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final hasSong = context.select<PlayerController, bool>(
      (p) => p.current != null,
    );
    _syncChrome(hasSong);
    final scheme = Theme.of(context).colorScheme;
    final destinations = _destinations(AppLocalizations.of(context));
    final body = _TabSwitcher(
      index: _tab,
      children: [
        _tabNavigator(0, const DiscoverPage()),
        _tabNavigator(1, const SearchPage()),
        _tabNavigator(2, const MinePage()),
      ],
    );

    final Widget content;
    if (wide) {
      // 左侧实心侧栏 + 底部整宽玻璃播放栏，侧栏底部让出播放栏的位置
      const gap = 12.0;
      final padding = MediaQuery.paddingOf(context);
      // 桌面播放栏常驻，还没放过歌时显示空状态
      const barSpace = DesktopPlayerBar.height + gap * 2;
      // 播放栏和窗口一样宽，提示在整个窗口居中，正好对着中间的播放键
      _reportChrome(EdgeInsets.only(bottom: padding.bottom + barSpace));
      content = Material(
        color: scheme.surface,
        child: KanadeGlass.backdropScope(
          child: Stack(
            children: [
              Positioned.fill(
                // 播放栏的玻璃长成播放页时会变高，这段时间截到它最高长到的地方
                child: ValueListenableBuilder(
                  valueListenable: DesktopPlayerBar.anchor.growing,
                  builder: (_, growing, child) => KanadeGlass.backdropSource(
                    captureBounds: (size) => Rect.fromLTRB(
                      0,
                      (size.height - barSpace) *
                              (growing == null
                                  ? 1
                                  : 1 - PlayerMorph.glassUntil) -
                          32,
                      size.width,
                      size.height,
                    ),
                    child: child!,
                  ),
                  child: ColoredBox(
                    color: scheme.surface,
                    child: Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            gap,
                            padding.top + 8,
                            0,
                            padding.bottom + barSpace,
                          ),
                          child: SizedBox(
                            width: DesktopSidebar.width,
                            child: DesktopSidebar(
                              destinations: destinations,
                              selected: _tab,
                              onSelect: _select,
                              onOpenPlaylist: _openSidebarPlaylist,
                            ),
                          ),
                        ),
                        Expanded(child: _insetBottom(barSpace, body)),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: gap,
                right: gap,
                bottom: gap + padding.bottom,
                child: const DesktopPlayerBar(),
              ),
            ],
          ),
        ),
      );
    } else {
      const navPad = 6.0;
      const navHeight = KanadeGlass.navigationControlHeight + navPad * 2;
      const miniGap = 2.0;
      // 导航栏的玻璃胶囊在组件里左右各缩进 12
      const pillInset = 12.0;
      const circleSize = KanadeGlass.navigationControlHeight;
      const circleGap = 8.0;
      final safeBottom = MediaQuery.paddingOf(context).bottom;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final screenHeight = MediaQuery.sizeOf(context).height;
      // 三个标签的胶囊不需要铺满整行，收窄后居中；手机上还要给右边的圆球留位置
      final navWidth =
          (screenWidth - 32 - (touchPlatform ? circleSize + circleGap : 0))
              .clamp(0.0, 300.0);
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final foreground = isDark ? Colors.white : Colors.black87;
      final shadows = [
        Shadow(
          color: isDark ? Colors.black54 : Colors.white54,
          blurRadius: 1.5,
        ),
      ];
      final labelStyle = TextStyle(
        decoration: TextDecoration.none,
        shadows: shadows,
      );
      final tabs = GlassTabBar.bottom(
        selectedIndex: _tab,
        onTabSelected: _select,
        tabs: [
          for (final d in destinations)
            GlassTab(
              icon: Icon(d.$1, shadows: shadows),
              activeIcon: Icon(d.$2, shadows: shadows),
              label: d.$3,
              semanticLabel: d.$3,
            ),
        ],
        quality: KanadeGlass.navigationQuality,
        settings: KanadeGlass.navigationSettings(context),
        sharedLayer: _blendGlass,
        indicatorSettings: KanadeGlass.indicatorSettings,
        // 指示器是一颗透明透镜，选中态靠抗色图标区分
        indicatorColor: foreground.withValues(alpha: 0.1),
        selectedIconColor: scheme.primary,
        selectedLabelColor: scheme.primary,
        unselectedIconColor: foreground,
        unselectedLabelColor: foreground,
        selectedLabelStyle: labelStyle,
        unselectedLabelStyle: labelStyle,
        adaptiveBrightness: false,
        magnification: 1.2,
        horizontalPadding: 12,
        verticalPadding: navPad,
        barHeight: KanadeGlass.navigationControlHeight,
        tabWidth: (navWidth - 24) / destinations.length,
        barBorderRadius: GlassDefaults.capsuleRadius,
        indicatorBorderRadius: GlassDefaults.capsuleRadius,
      );
      final brightness = Theme.of(context).brightness;
      // 同 _insetBottom：在 Builder 里读 MediaQuery，外壳不跟着键盘重建
      final tabBar = Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
          child: tabs,
        ),
      );
      // 二级页面里导航栏和播放条融成一块，落到底部变成胶囊
      final navSpace = _nested ? 8.0 : navHeight;
      final inset = navSpace + (hasSong ? MiniPlayer.height + miniGap : 0) + 8;
      // 播放条收成导航栏旁边的圆球时，提示只要躲开导航栏
      _reportChrome(
        EdgeInsets.only(
          bottom:
              safeBottom +
              (hasSong && _collapsed && !_nested ? navHeight + 6 : inset + 4),
        ),
      );
      final chrome = AnimatedBuilder(
        animation: Listenable.merge([
          _shape,
          ..._fuse.all,
          ..._drop.all,
          _absorb,
          _navFace,
          _appear,
        ]),
        builder: (context, _) {
          final s = _shape.value;
          // 整体进度看上下两条边的平均
          final f = ((_fuse.top.value + _fuse.bottom.value) / 2).clamp(
            0.0,
            1.0,
          );
          final d = ((_drop.top.value + _drop.bottom.value) / 2).clamp(
            0.0,
            1.0,
          );
          final a = _appear.value;
          final round = s.clamp(0.0, 1.0);
          // 收成圆球时导航栏往左让，和圆球一起居中；圆球和导航栏的玻璃胶囊一样高、对齐
          final shift = s * Curves.easeOutCubic.transform(a);
          final navCentered = (screenWidth - navWidth) / 2;
          final navGrouped =
              (screenWidth -
                      (navWidth - pillInset * 2 + circleGap + circleSize)) /
                  2 -
              pillInset;
          final navLeft = lerpDouble(navCentered, navGrouped, shift)!;
          final navTop = screenHeight - safeBottom - navHeight;
          // 导航栏里那块玻璃胶囊本身的位置
          final pill = Rect.fromLTWH(
            navLeft + pillInset,
            navTop + navPad,
            navWidth - pillInset * 2,
            circleSize,
          );
          final circle = Rect.fromLTWH(
            pill.right + circleGap,
            pill.top,
            circleSize,
            circleSize,
          );
          final capsule = Rect.fromLTWH(
            16,
            navTop - miniGap - MiniPlayer.height,
            screenWidth - 32,
            MiniPlayer.height,
          );
          final bottom = Rect.fromLTWH(
            16,
            screenHeight - safeBottom - 8 - MiniPlayer.height,
            screenWidth - 32,
            MiniPlayer.height,
          );
          // 一级页面里的样子（胶囊 / 圆球）→ 融成导航栏那块 → 落成底部胶囊，每条边各走各的
          final start = Rect.lerp(capsule, circle, s)!;
          double edge(
            double a,
            double b,
            double c,
            AnimationController fuse,
            AnimationController drop,
          ) => lerpDouble(lerpDouble(a, b, fuse.value)!, c, drop.value)!;
          final left = edge(
            start.left,
            pill.left,
            bottom.left,
            _fuse.left,
            _drop.left,
          );
          final top = edge(
            start.top,
            pill.top,
            bottom.top,
            _fuse.top,
            _drop.top,
          );
          final right = edge(
            start.right,
            pill.right,
            bottom.right,
            _fuse.right,
            _drop.right,
          );
          final bottomEdge = edge(
            start.bottom,
            pill.bottom,
            bottom.bottom,
            _fuse.bottom,
            _drop.bottom,
          );
          var bar = Rect.fromLTRB(
            left,
            top,
            math.max(left, right),
            math.max(top, bottomEdge),
          );
          // 歌名和按钮：收成圆、融合时淡掉，落到底部时再错开出来；返回时等它和导航栏快分开了才出来
          final face = math.max(
            (1 - round / 0.4).clamp(0.0, 1.0) *
                (1 - const Interval(0, 0.25).transform(f)),
            const Interval(0.35, 0.85).transform(d),
          );
          // 从圆球融进去时封面先待在右端，融到一半快速挪到左端
          final coverShift =
              round *
              (1 -
                  const Interval(
                    0.4,
                    0.8,
                    curve: Curves.easeInOut,
                  ).transform(f));
          // 有播放条时导航栏缩小着被吸进去，落到底部时藏进胶囊里；没有播放条就像原来一样整条往下滑走
          final Rect navRect;
          if (hasSong) {
            final k = _absorb.value;
            final sx = lerpDouble(1, 0.78, k)!, sy = lerpDouble(1, 0.8, k)!;
            final ox = bar.center.dx, oy = pill.center.dy + 4 * k;
            final absorbed = Rect.fromLTRB(
              ox + (pill.left - ox) * sx,
              oy + (pill.top - pill.center.dy) * sy,
              ox + (pill.right - ox) * sx,
              oy + (pill.bottom - pill.center.dy) * sy,
            );
            navRect = Rect.lerp(absorbed, bar.deflate(4), d)!;
          } else {
            navRect = pill.translate(0, f * navHeight * 1.6);
          }
          // 把导航栏里那块胶囊（组件内的位置）映射到 navRect
          final navScaleX = navRect.width / pill.width,
              navScaleY = navRect.height / pill.height;
          final navTransform = Matrix4.translationValues(
            navRect.left - navLeft - pillInset * navScaleX,
            navRect.top - navTop - navPad * navScaleY,
            0,
          )..multiply(Matrix4.diagonal3Values(navScaleX, navScaleY, 1));
          // 导航栏的图标在播放条压上来之前就淡完，不和歌名叠在一起
          final navFace = hasSong
              ? math.min(
                  _navFace.value,
                  1 - const Interval(0.2, 0.6).transform(f),
                )
              : 1.0;
          // 同一个玻璃层里两块玻璃靠近时才开始粘连，一级页面里分开的时候不粘。
          // 落成底部胶囊的最后一段粘连退掉：缩在里面 4 像素的导航栏会把轮廓撑大近 3 像素，
          // 播放页从播放条本身的大小变形出来，拖动时下半段会露出一圈多出来的玻璃
          final blend =
              18 *
              (f / 0.15).clamp(0.0, 1.0) *
              (1 - const Interval(0.85, 1).transform(d));
          var opacity = 1.0;
          if (a < 1) {
            // 第一次出现：一颗小圆从导航栏胶囊的右端分裂出来，长大挪到位（二级页面里从胶囊右端长出来）
            final seed = Rect.fromCircle(
              center: d > 0.5
                  ? bottom.centerRight - const Offset(MiniPlayer.height / 2, 0)
                  : s > 0.5
                  ? Offset(pill.right - circleSize / 2, pill.center.dy)
                  : capsule.centerRight -
                        const Offset(MiniPlayer.height / 2, 0),
              radius: 12,
            );
            bar = Rect.lerp(seed, bar, Curves.easeOutBack.transform(a))!;
            opacity = (a / 0.2).clamp(0.0, 1.0);
          }
          final stack = Stack(
            children: [
              if (hasSong)
                Positioned.fromRect(
                  rect: bar,
                  child: Opacity(
                    opacity: opacity,
                    child: MiniPlayer(
                      round: s > 0.5 && f < 0.5,
                      faceOpacity: face,
                      coverShift: coverShift,
                      capsuleWidth: capsule.width,
                      grouped: _blendGlass,
                      faceStagger: f > 0.001 || d > 0.001,
                      onExpand: () => setState(() => _collapsed = false),
                    ),
                  ),
                ),
              // 融合时导航栏缩小着贴到播放条上。同一个玻璃层里 Opacity 只淡掉图标，玻璃留着和播放条粘在一起；
              // 各画各的时候整个导航栏淡掉
              Positioned(
                left: navLeft,
                top: navTop,
                width: navWidth,
                height: navHeight,
                child: IgnorePointer(
                  ignoring: _nested,
                  child: Transform(
                    transform: navTransform,
                    child: Opacity(
                      opacity: navFace.clamp(0.0, 1.0),
                      child: tabBar,
                    ),
                  ),
                ),
              ),
            ],
          );
          if (!_blendGlass) return stack;
          return AdaptiveLiquidGlassLayer(
            settings: KanadeGlass.navigationSettings(context),
            quality: KanadeGlass.navigationQuality,
            blendAmount: blend,
            child: stack,
          );
        },
      );
      content = Material(
        color: scheme.surface,
        child: KanadeGlass.backdropScope(
          child: Stack(
            children: [
              Positioned.fill(
                child: KanadeGlass.backdropSource(
                  child: ColoredBox(
                    color: scheme.surface,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: _insetBottom(inset, body),
                    ),
                  ),
                ),
              ),
              // 空白处点不中，手势会落到下面的页面
              Positioned.fill(child: chrome),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = _keys[_tab].currentState;
        if (nav != null && nav.canPop()) {
          // maybePop 让二级页面自己的 PopScope 先处理（比如歌单页先退出搜索）
          nav.maybePop();
        } else if (_tab != 0) {
          setState(() => _tab = 0);
        }
      },
      child: content,
    );
  }
}

/// 切换标签时页面横着滑过去：往右边的标签切，新页面从右边推进来，反过来从左边。
/// 三个页面一直留着（滚动位置、二级页面都在），不在显示的不绘制、停掉动画。
class _TabSwitcher extends StatefulWidget {
  const _TabSwitcher({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<_TabSwitcher>
    with SingleTickerProviderStateMixin {
  late final _slide =
      AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
          value: 1,
        )
        // 滑完把旧页面藏起来
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) setState(() {});
        });
  late int _from = widget.index;

  @override
  void didUpdateWidget(_TabSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      _from = old.index;
      _slide.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final to = widget.index;
    return ClipRect(
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          final moving = _slide.isAnimating;
          final t = Curves.easeOutCubic.transform(_slide.value);
          final dir = to > _from ? 1.0 : -1.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              for (final (i, child) in widget.children.indexed)
                // 每一层的结构保持不变，页面的状态才不会丢
                Offstage(
                  offstage: i != to && !(moving && i == _from),
                  child: TickerMode(
                    enabled: i == to || (moving && i == _from),
                    child: FractionalTranslation(
                      translation: Offset(
                        i == to ? dir * (1 - t) : -dir * t,
                        0,
                      ),
                      child: IgnorePointer(
                        ignoring: i != to,
                        // 滑动时只挪图层，不重绘页面内容
                        child: RepaintBoundary(child: child),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 记录一个标签页 Navigator 里有几层页面。
class _DepthObserver extends NavigatorObserver {
  _DepthObserver(this.onChanged);

  final VoidCallback onChanged;
  int depth = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth++;
    onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth--;
    onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth--;
    onChanged();
  }
}

/// 播放条矩形的四条边，各自一个弹簧驱动的进度（0 起点，1 终点）。
class _Edges {
  _Edges(TickerProvider vsync)
    : top = AnimationController.unbounded(vsync: vsync),
      bottom = AnimationController.unbounded(vsync: vsync),
      left = AnimationController.unbounded(vsync: vsync),
      right = AnimationController.unbounded(vsync: vsync);

  final AnimationController top, bottom, left, right;

  List<AnimationController> get all => [top, bottom, left, right];

  set value(double v) {
    for (final c in all) {
      c.value = v;
    }
  }

  void dispose() {
    for (final c in all) {
      c.dispose();
    }
  }
}
