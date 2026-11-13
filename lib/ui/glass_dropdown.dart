import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'glass.dart';

/// 点一下就地长成液态玻璃菜单的选择器，动画和播放页的音质菜单是同一套。
/// [child] 是平时显示的当前值；展开时它藏起来，玻璃从它的位置长出来，
/// 选完白色选中块先滑到新的一项，再缩回成新的值。
///
/// 页面要用 [GlassDropdown.backdrop] 包住内容，Windows 上玻璃才有东西可折射。
class GlassDropdown<T> extends StatefulWidget {
  const GlassDropdown({
    super.key,
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    required this.child,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final Widget child;

  /// 菜单后面的模糊。只有菜单在时才截图，平时没有开销。
  static const _blur = 10.0;

  /// 包住菜单后面的页面内容。
  static Widget backdrop({required Widget child}) => KanadeGlass.backdropScope(
    blur: _blur,
    child: KanadeGlass.backdropSource(
      child: Builder(
        builder: (context) => Material(
          color: Theme.of(context).colorScheme.surface,
          child: child,
        ),
      ),
    ),
  );

  @override
  State<GlassDropdown<T>> createState() => GlassDropdownState<T>();
}

class GlassDropdownState<T> extends State<GlassDropdown<T>>
    with TickerProviderStateMixin {
  static const _headerHeight = 34.0;
  static const _rowHeight = 44.0;
  static const _pad = 6.0;
  static const _menuWidth = 220.0;

  /// 圆角从按钮到菜单都不变：Windows 上玻璃的圆角一变就要现编一次 shader，会卡一下。
  static const _radius = 18.0;

  /// 按钮四周留出的边，玻璃一开始就比文字大一圈。上下各 8 让按钮正好 36 高（2 × [_radius]）：
  /// 矮于两倍圆角时 Windows 上第一次缩回按钮会现编 shader，实测卡一帧 100ms 以上。
  static const _chipPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 8);

  /// 菜单离屏幕边缘至少留这么多。
  static const _margin = 12.0;

  // 展开和收起都带一点回弹；收起时冲过按钮一点，像果冻一样收紧再弹回来
  static final _openSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 380,
    ratio: 0.68,
  );
  static final _closeSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.72,
  );

  /// 缩回按钮以后玻璃淡出、原来的字淡入。
  static const _fadeDuration = Duration(milliseconds: 200);

  /// 收起开始后多久开始淡出，和回弹的尾巴叠在一起。
  static const _fadeDelay = Duration(milliseconds: 230);

  final _chipKey = GlobalKey();
  final _portal = OverlayPortalController();

  // 0 是按钮，1 是菜单；弹簧会冲过两头一点，所以不设上下界
  late final _c = AnimationController.unbounded(vsync: this);

  /// 0 是玻璃还在，1 是玻璃淡没、按钮的字完全出来。
  late final _fade = AnimationController(vsync: this, duration: _fadeDuration);

  /// 按钮在 root overlay 里的位置，已经加上了 [_chipPadding]。
  Rect _chip = Rect.zero;

  /// 菜单在 root overlay 里的位置。
  Rect _menu = Rect.zero;

  /// 菜单往上长（下面放不下）。
  bool _up = false;
  bool _expanded = false;

  /// 刚点中、还没收起的那一项，选中块先滑过去再收。
  T? _picked;
  bool _hasPicked = false;

  /// 玻璃淡出：把着色、厚度、光照、折射、亮边暗边和阴影一起压到 0，只剩背后的页面。
  /// 不用 visibility：它在 Windows 上靠外面套一层 Opacity，第一次用要现编 shader，实测卡 100ms。
  /// 这些都只是 shader 的参数，不会多出新的变体。blur 不动，它一变绘制方式就变；
  /// 按钮背后是纯色的卡片，模糊了也看不出来。
  static LiquidGlassSettings dissolve(LiquidGlassSettings s, double t) {
    if (t == 0) return s;
    final k = 1 - t;
    return s.copyWith(
      glassColor: s.glassColor.withValues(alpha: s.glassColor.a * k),
      thickness: s.thickness * k,
      lightIntensity: s.lightIntensity * k,
      refractionAmount: s.refractionAmount * k,
      fresnelStrength: s.fresnelStrength * k,
      edgeAbsorption: s.edgeAbsorption * k,
      rimLight: s.rimLight * k,
      rimShade: s.rimShade * k,
      saturation: lerpDouble(s.saturation, 1, t),
      shadowElevation: s.shadowElevation * k,
    );
  }

  /// 收起途中盯着的页面滚动；玻璃钉在 overlay 里不会跟着走。
  ScrollPosition? _scroll;

  void _watchScroll() {
    _scroll = Scrollable.maybeOf(context)?.position?..addListener(_hide);
  }

  void _unwatchScroll() {
    _scroll?.removeListener(_hide);
    _scroll = null;
  }

  /// 收起收尾：玻璃拿掉，真按钮露出来。收起途中页面一滚就直接走到这一步，
  /// 不然玻璃和里面那份字留在原处，真按钮跟着页面跑了，看起来像按钮被挪开。
  void _hide() {
    _unwatchScroll();
    _c.stop();
    _fade.stop();
    _c.value = 0;
    _fade.value = 0;
    if (_portal.isShowing) _portal.hide();
    if (mounted) setState(() => _hasPicked = false);
  }

  @override
  void dispose() {
    _unwatchScroll();
    _c.dispose();
    _fade.dispose();
    super.dispose();
  }

  Rect? _measureChip() {
    final box = _chipKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    if (box == null || !box.hasSize || overlay == null) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return _chipPadding.inflateRect(topLeft & box.size);
  }

  /// 打开菜单。整行都能点时，从行的 onTap 调这里。
  void open() {
    if (_expanded) return;
    final chip = _measureChip();
    if (chip == null) return;
    final screen = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);
    final size = Size(
      max(_menuWidth, chip.width),
      _headerHeight + widget.values.length * _rowHeight + _pad * 2,
    );
    // 右边和按钮对齐；下面放不下就往上长
    final left = (chip.right - size.width).clamp(
      _margin,
      screen.width - _margin - size.width,
    );
    final up =
        chip.top + size.height > screen.height - insets.bottom - _margin &&
        chip.bottom - size.height >= insets.top + _margin;
    final top = up ? chip.bottom - size.height : chip.top;
    setState(() {
      _chip = chip;
      _menu = Offset(left, top) & size;
      _up = up;
      _expanded = true;
      _hasPicked = false;
    });
    // 淡出途中又点开：玻璃直接回到不透明
    _unwatchScroll();
    _fade.value = 0;
    _portal.show();
    unawaited(
      _c.animateWith(SpringSimulation(_openSpring, _c.value, 1, _c.velocity)),
    );
  }

  Future<void> _close() async {
    if (!_expanded) return;
    _expanded = false;
    // 选完以后按钮上的字变了，收回到新的宽度
    final chip = _measureChip();
    if (chip != null) setState(() => _chip = chip);
    // 遮罩一撤页面就能滚了
    _watchScroll();
    final shrink = _c.animateBackWith(
      SpringSimulation(_closeSpring, _c.value, 0, _c.velocity, snapToEnd: true),
    );
    await Future<void>.delayed(_fadeDelay);
    // 又点开了，或者滚动时已经收尾了
    if (!mounted || _expanded || !_portal.isShowing) return;
    await Future.wait([
      shrink.orCancel.catchError((_) {}),
      _fade.forward(from: 0).orCancel.catchError((_) {}),
    ]);
    if (!mounted || _expanded || !_portal.isShowing) return;
    _hide();
  }

  Future<void> _pick(T v) async {
    setState(() {
      _picked = v;
      _hasPicked = true;
    });
    if (v != widget.selected) widget.onSelected(v);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    // 等这一帧按钮换上新的字再量
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await _close();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      overlayLocation: OverlayChildLocation.rootOverlay,
      controller: _portal,
      overlayChildBuilder: _buildMenu,
      // 展开期间按钮本体让给菜单，原位置留空。玻璃淡出时也不露出来：
      // 它在玻璃背后会被截进模糊里；玻璃里那份字和它在同一个位置，淡完直接换回来
      child: Opacity(
        opacity: _portal.isShowing ? 0 : 1,
        child: KeyedSubtree(key: _chipKey, child: widget.child),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dpr = View.of(context).devicePixelRatio;
    double snap(double x) => (x * dpr).roundToDouble() / dpr;
    final count = widget.values.length;
    final T selected = _hasPicked ? _picked as T : widget.selected;
    final selectedIndex = widget.values.indexOf(selected);
    final settings =
        KanadeGlass.surfaceSettings(
          context,
          quality: KanadeGlass.navigationQuality,
        ).copyWith(
          blur: GlassDropdown._blur,
          glassColor: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        );

    return Stack(
      children: [
        // 收起以后不再挡着页面，淡出那一下也能直接点别处
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_close()),
            ),
          ),
        AnimatedBuilder(
          animation: Listenable.merge([_c, _fade]),
          builder: (context, _) {
            final v = _c.value;
            double fade(double from, double to) =>
                ((v - from) / (to - from)).clamp(0.0, 1.0);
            // 选项一行接一行浮上来，行多的时候间隔压缩，保证在弹簧到位前都出来
            final step = min(0.06, 0.3 / count);
            final chipFade = 1 - fade(0, 0.3);

            Widget appear(int i, Widget child) {
              final a = Curves.easeOut.transform(
                fade(0.3 + i * step, 0.7 + i * step),
              );
              return Opacity(
                opacity: a,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - a)),
                  child: child,
                ),
              );
            }

            final menu = Padding(
              padding: const EdgeInsets.all(_pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Opacity(
                    opacity: fade(0.25, 0.65),
                    child: SizedBox(
                      height: _headerHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Stack(
                    children: [
                      // 选中块：换一项时滑到新的一行
                      if (selectedIndex >= 0)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          left: 0,
                          right: 0,
                          top: selectedIndex * _rowHeight,
                          height: _rowHeight,
                          child: Opacity(
                            opacity: fade(0.35, 0.75),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.secondaryContainer,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(_radius - _pad),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < count; i++)
                            appear(
                              i,
                              _row(
                                scheme,
                                widget.label(widget.values[i]),
                                i == selectedIndex,
                                widget.values[i],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );

            // 右边对齐，往下长时顶边对齐，往上长时底边对齐；尺寸和位置对齐到物理像素
            final double left, top, w, h;
            if (v >= 0) {
              w = lerpDouble(_chip.width, _menu.width, v)!;
              h = lerpDouble(_chip.height, _menu.height, v)!;
              left = lerpDouble(_chip.right, _menu.right, v)! - w;
              top = _up
                  ? lerpDouble(_chip.bottom, _menu.bottom, v)! - h
                  : lerpDouble(_chip.top, _menu.top, v)!;
            } else {
              // 收起冲过头：以按钮中心收窄、面积不变所以稍微变高，再弹回按钮大小。
              // 高度不会低于按钮（2 × 圆角），见 [_chipPadding]。
              w = lerpDouble(_chip.width, _menu.width, v)!;
              h = _chip.height * _chip.width / w;
              left = _chip.center.dx - w / 2;
              top = _chip.center.dy - h / 2;
            }
            final align = _up ? Alignment.bottomRight : Alignment.topRight;
            final l = snap(left), r = snap(left + w);
            final t = snap(top), b = snap(top + h);
            return Positioned(
              left: l,
              top: t,
              width: r - l,
              height: b - t,
              child: GlassContainer(
                useOwnLayer: true,
                settings: dissolve(settings, _fade.value),
                quality: KanadeGlass.navigationQuality,
                shape: const LiquidRoundedRectangle(borderRadius: _radius),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // 按钮上原来的字钉在它原本的位置：不跟着玻璃挤压、回弹，
                    // 玻璃对齐像素后差的那一点也补回来，淡完换回真按钮时不会挪动
                    if (chipFade > 0)
                      Positioned(
                        right: r - (_chip.right - _chipPadding.right),
                        top: _up ? null : _chip.top + _chipPadding.top - t,
                        bottom: _up
                            ? b - (_chip.bottom - _chipPadding.bottom)
                            : null,
                        child: Opacity(opacity: chipFade, child: widget.child),
                      ),
                    if (v > 0.25)
                      Positioned.fill(
                        child: OverflowBox(
                          alignment: align,
                          minWidth: _menu.width,
                          maxWidth: _menu.width,
                          minHeight: _menu.height,
                          maxHeight: _menu.height,
                          child: menu,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _row(ColorScheme scheme, String text, bool selected, T value) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_pick(value)),
      child: SizedBox(
        height: _rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurface,
                  ),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: selected ? 1 : 0,
                child: Icon(
                  Icons.check,
                  size: 18,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
