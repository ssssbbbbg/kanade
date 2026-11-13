import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import 'glass.dart';
import 'glass_dropdown.dart';
import 'queue_list.dart';
import 'smooth_scroll.dart';

/// 桌面播放栏上的队列按钮：点一下按钮本身长成往上展开的玻璃弹窗，里面是播放队列。
/// 再点一次（点在弹窗外面）或按 Esc 缩回按钮。动画和 [GlassDropdown] 是同一套。
class DesktopQueueButton extends StatefulWidget {
  const DesktopQueueButton({super.key, required this.color});

  final Color color;

  @override
  State<DesktopQueueButton> createState() => _DesktopQueueButtonState();
}

class _DesktopQueueButtonState extends State<DesktopQueueButton>
    with TickerProviderStateMixin {
  /// 按钮的大小（IconButton 去掉点击留白后的样子）。圆角从按钮到弹窗都不变，
  /// 而且正好是按钮高度的一半：Windows 上玻璃的圆角一变、或矮于两倍圆角就要现编 shader。
  static const _chipSize = 40.0;
  static const _radius = 20.0;
  static const _width = 380.0;
  static const _maxHeight = 560.0;
  static const _headerHeight = 52.0;

  /// 弹窗离窗口边缘至少留这么多。
  static const _margin = 12.0;

  static final _openSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 380,
    ratio: 0.74,
  );
  static final _closeSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.72,
  );
  static const _fadeDuration = Duration(milliseconds: 200);
  static const _fadeDelay = Duration(milliseconds: 230);

  final _chipKey = GlobalKey();
  final _portal = OverlayPortalController();
  final _scroll = SmoothScrollController();
  final _focus = FocusNode(debugLabel: 'queue popup');

  // 0 是按钮，1 是弹窗；弹簧会冲过两头一点，所以不设上下界
  late final _c = AnimationController.unbounded(vsync: this);

  /// 0 是玻璃还在，1 是玻璃淡没、按钮完全露出来。
  late final _fade = AnimationController(vsync: this, duration: _fadeDuration);

  /// 按钮和弹窗在 root overlay 里的位置。
  Rect _chip = Rect.zero;
  Rect _popup = Rect.zero;
  bool _expanded = false;

  @override
  void dispose() {
    _c.dispose();
    _fade.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Rect? _measureChip() {
    final box = _chipKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    if (box == null || !box.hasSize || overlay == null) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return Rect.fromCenter(
      center: (topLeft & box.size).center,
      width: _chipSize,
      height: _chipSize,
    );
  }

  void _open() {
    if (_expanded) return;
    final chip = _measureChip();
    if (chip == null) return;
    final screen = MediaQuery.sizeOf(context);
    // 往上长，底边和按钮对齐，右边和按钮对齐
    final height = min(
      min(_maxHeight, screen.height * 0.6),
      chip.bottom - _margin,
    );
    final left = (chip.right - _width).clamp(
      _margin,
      screen.width - _margin - _width,
    );
    setState(() {
      _chip = chip;
      _popup = Rect.fromLTWH(left, chip.bottom - height, _width, height);
      _expanded = true;
    });
    _fade.value = 0;
    final reopening = _portal.isShowing;
    _portal.show();
    // 页面里别的控件已经拿着焦点时 autofocus 不生效，要主动要过来 Esc 才收得到
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_expanded) _focus.requestFocus();
    });
    // 让当前这首露在第二行；列表这一帧才建出来
    if (!reopening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final p = context.read<PlayerController>();
        _scroll.jumpTo(
          min(
            QueueList.initialOffset(p.index),
            _scroll.position.maxScrollExtent,
          ),
        );
      });
    }
    unawaited(
      _c.animateWith(SpringSimulation(_openSpring, _c.value, 1, _c.velocity)),
    );
  }

  Future<void> _close() async {
    if (!_expanded) return;
    setState(() => _expanded = false);
    final shrink = _c.animateBackWith(
      SpringSimulation(_closeSpring, _c.value, 0, _c.velocity, snapToEnd: true),
    );
    await Future<void>.delayed(_fadeDelay);
    if (!mounted || _expanded || !_portal.isShowing) return;
    await Future.wait([
      shrink.orCancel.catchError((_) {}),
      _fade.forward(from: 0).orCancel.catchError((_) {}),
    ]);
    if (!mounted || _expanded || !_portal.isShowing) return;
    _c.value = 0;
    _fade.value = 0;
    _portal.hide();
    setState(() {});
  }

  Widget _icon() =>
      Icon(Icons.queue_music_rounded, size: 20, color: widget.color);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return OverlayPortal(
      overlayLocation: OverlayChildLocation.rootOverlay,
      controller: _portal,
      overlayChildBuilder: _buildPopup,
      // 展开期间按钮让给弹窗，玻璃里同一个位置画着一样的图标
      child: Opacity(
        opacity: _portal.isShowing ? 0 : 1,
        child: KeyedSubtree(
          key: _chipKey,
          child: IconButton(tooltip: l.queue, onPressed: _open, icon: _icon()),
        ),
      ),
    );
  }

  Widget _buildPopup(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final dpr = View.of(context).devicePixelRatio;
    double snap(double x) => (x * dpr).roundToDouble() / dpr;
    final settings = KanadeGlass.surfaceSettings(
      context,
      quality: KanadeGlass.navigationQuality,
    ).copyWith(glassColor: scheme.surfaceContainerHigh.withValues(alpha: 0.82));

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _headerHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.upNext,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l.queue,
                  onPressed: () => unawaited(_close()),
                  icon: _icon(),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: QueueList(
            controller: _scroll,
            color: scheme.onSurface,
            dragColor: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          ),
        ),
      ],
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            unawaited(_close()),
      },
      child: Focus(
        focusNode: _focus,
        child: Stack(
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
              builder: (context, child) {
                final v = _c.value;
                double fade(double from, double to) =>
                    ((v - from) / (to - from)).clamp(0.0, 1.0);
                final chipFade = 1 - fade(0, 0.3);
                // 右下角对齐按钮；收起冲过头时以按钮中心收窄、面积不变所以稍微变高
                final double left, top, w, h;
                if (v >= 0) {
                  w = lerpDouble(_chip.width, _popup.width, v)!;
                  h = lerpDouble(_chip.height, _popup.height, v)!;
                  left = lerpDouble(_chip.right, _popup.right, v)! - w;
                  top = _chip.bottom - h;
                } else {
                  w = lerpDouble(_chip.width, _popup.width, v)!;
                  h = _chip.height * _chip.width / w;
                  left = _chip.center.dx - w / 2;
                  top = _chip.center.dy - h / 2;
                }
                final l = snap(left), r = snap(left + w);
                final t = snap(top), b = snap(top + h);
                return Positioned(
                  left: l,
                  top: t,
                  width: r - l,
                  height: b - t,
                  child: GlassContainer(
                    useOwnLayer: true,
                    settings: GlassDropdownState.dissolve(
                      settings,
                      _fade.value,
                    ),
                    quality: KanadeGlass.navigationQuality,
                    shape: const LiquidRoundedRectangle(borderRadius: _radius),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        // 按钮上的图标钉在原位，淡完换回真按钮时不会挪动
                        if (chipFade > 0)
                          Positioned(
                            left: _chip.left - l,
                            top: _chip.top - t,
                            width: _chip.width,
                            height: _chip.height,
                            child: Opacity(
                              opacity: chipFade,
                              child: Center(child: _icon()),
                            ),
                          ),
                        // 带 key：上面的图标层拿掉时，列表不会被当成新的重建、滚动位置丢掉
                        Positioned.fill(
                          key: const ValueKey('content'),
                          child: IgnorePointer(
                            ignoring: !_expanded,
                            child: Opacity(
                              opacity: fade(0.3, 0.7),
                              child: OverflowBox(
                                alignment: Alignment.bottomRight,
                                minWidth: _popup.width,
                                maxWidth: _popup.width,
                                minHeight: _popup.height,
                                maxHeight: _popup.height,
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: Material(type: MaterialType.transparency, child: content),
            ),
          ],
        ),
      ),
    );
  }
}
