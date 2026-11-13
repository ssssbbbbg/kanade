import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';

/// 桌面端去掉了系统标题栏（见 main.dart），由这里自己画。
bool get hasCustomTitleBar => Platform.isWindows || Platform.isLinux;

const titleBarHeight = 32.0;

/// 隐藏系统标题栏后再显示窗口（runner 里不再自动 Show，避免启动时闪一下）。
/// main 和集成测试都要调用，否则窗口一直不出来。
Future<void> setupWindow() async {
  if (!hasCustomTitleBar) return;
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      minimumSize: Size(400, 560),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

/// 大于 0 时标题栏进入沉浸模式：按钮平时隐藏，鼠标移到窗口顶部才浮现。
final _immersive = ValueNotifier<int>(0);

/// 包住需要沉浸式标题栏的页面（播放页），页面存在期间生效。
class ImmersiveTitleBar extends StatefulWidget {
  const ImmersiveTitleBar({super.key, required this.child});

  final Widget child;

  @override
  State<ImmersiveTitleBar> createState() => _ImmersiveTitleBarState();
}

class _ImmersiveTitleBarState extends State<ImmersiveTitleBar> {
  // initState / dispose 发生在构建和树锁定期间，这时改 notifier 会让标题栏
  // setState 报错（标题栏不更新），所以推到这一帧结束后再改。
  static void _bump(int delta) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _immersive.value += delta)
      ..ensureVisualUpdate();
  }

  @override
  void initState() {
    super.initState();
    _bump(1);
  }

  @override
  void dispose() {
    _bump(-1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 把自绘标题栏叠在整个 App 上面，并通过 MediaQuery.padding.top 让出位置。
/// 这样 AppBar 会把自己的背景延伸到标题栏底下（跟 Android 状态栏一样），
/// 播放页的流动背景也能铺满到窗口顶端。
class WindowFrame extends StatelessWidget {
  const WindowFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!hasCustomTitleBar) return child;
    final mq = MediaQuery.of(context);
    return Stack(
      children: [
        MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(top: mq.padding.top + titleBarHeight),
          ),
          child: child,
        ),
        // MaterialApp.builder 在 Navigator 外面，没有 Overlay，按钮的 Tooltip 需要自己给一个。
        // 只有顶部 32px 能命中，其余区域的点击会落到下面的页面。
        Positioned.fill(
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => const Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: titleBarHeight,
                    child: Material(
                      type: MaterialType.transparency,
                      child: _TitleBar(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TitleBar extends StatefulWidget {
  const _TitleBar();

  @override
  State<_TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<_TitleBar> with WindowListener {
  bool _maximized = false;
  bool _focused = true;
  bool _hover = false;

  /// 标题栏底下内容的明暗，从页面的 `AnnotatedRegion<SystemUiOverlayStyle>` 读
  /// （AppBar 会按自身背景色自动设置，播放页设成 light）。null = 跟随主题。
  Brightness? _iconBrightness;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
    SchedulerBinding.instance.addPersistentFrameCallback(_probe);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// 每帧画完后在标题栏中间位置查一下图层上的状态栏样式，只是一次图层树查找，很便宜。
  void _probe(Duration _) {
    if (!mounted) return;
    final views = WidgetsBinding.instance.renderViews;
    if (views.isEmpty) return;
    final view = views.first;
    // ignore: invalid_use_of_protected_member
    final layer = view.layer;
    if (layer == null) return;
    final style = layer.find<SystemUiOverlayStyle>(
      Offset(view.size.width / 2, titleBarHeight / 2),
    );
    final b =
        style?.statusBarIconBrightness ??
        switch (style?.statusBarBrightness) {
          Brightness.dark => Brightness.light,
          Brightness.light => Brightness.dark,
          null => null,
        };
    if (b != _iconBrightness) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _iconBrightness = b);
      });
      _iconBrightness = b;
    }
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);
  @override
  void onWindowFocus() => setState(() => _focused = true);
  @override
  void onWindowBlur() => setState(() => _focused = false);

  void _toggleMaximize() =>
      _maximized ? windowManager.unmaximize() : windowManager.maximize();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final fg = switch (_iconBrightness) {
      Brightness.light => Colors.white,
      Brightness.dark => Colors.black,
      null => theme.colorScheme.onSurface,
    }.withValues(alpha: _focused ? 0.9 : 0.4);

    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          tooltip: l.windowMinimize,
          glyph: _Glyph.minimize,
          color: fg,
          onPressed: windowManager.minimize,
        ),
        _CaptionButton(
          tooltip: _maximized ? l.windowRestore : l.windowMaximize,
          glyph: _maximized ? _Glyph.restore : _Glyph.maximize,
          color: fg,
          onPressed: _toggleMaximize,
        ),
        _CaptionButton(
          tooltip: l.windowClose,
          glyph: _Glyph.close,
          color: fg,
          danger: true,
          onPressed: windowManager.close,
        ),
      ],
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleMaximize,
            ),
          ),
          ValueListenableBuilder(
            valueListenable: _immersive,
            child: buttons,
            builder: (_, immersive, buttons) => AnimatedOpacity(
              opacity: immersive == 0 || _hover ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: buttons,
            ),
          ),
        ],
      ),
    );
  }
}

enum _Glyph { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.glyph,
    required this.color,
    required this.onPressed,
    this.danger = false,
  });

  final String tooltip;
  final _Glyph glyph;
  final Color color;
  final VoidCallback onPressed;
  final bool danger;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;
  bool _down = false;

  static const _closeRed = Color(0xFFC42B1C);

  @override
  Widget build(BuildContext context) {
    final Color bg;
    var fg = widget.color;
    if (widget.danger && (_hover || _down)) {
      bg = _down ? _closeRed.withValues(alpha: 0.85) : _closeRed;
      fg = Colors.white;
    } else {
      bg = widget.color.withValues(alpha: _down ? 0.16 : (_hover ? 0.09 : 0));
    }
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = _down = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 46,
            height: titleBarHeight,
            color: bg,
            child: CustomPaint(painter: _GlyphPainter(widget.glyph, fg)),
          ),
        ),
      ),
    );
  }
}

/// 仿 Windows 11 的细线图标，10 逻辑像素见方。
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final c = size.center(Offset.zero);
    const s = 5.0;
    switch (glyph) {
      case _Glyph.minimize:
        canvas.drawLine(
          c + const Offset(-s, 0.5),
          c + const Offset(s, 0.5),
          paint,
        );
      case _Glyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: s * 2, height: s * 2),
            const Radius.circular(1.5),
          ),
          paint,
        );
      case _Glyph.restore:
        final front = Rect.fromLTWH(
          c.dx - s,
          c.dy - s + 2,
          s * 2 - 2,
          s * 2 - 2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(front, const Radius.circular(1.5)),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - s + 2, c.dy - s)
            ..lineTo(c.dx + s - 1.5, c.dy - s)
            ..arcToPoint(
              Offset(c.dx + s, c.dy - s + 1.5),
              radius: const Radius.circular(1.5),
            )
            ..lineTo(c.dx + s, c.dy + s - 2),
          paint,
        );
      case _Glyph.close:
        canvas.drawLine(
          c + const Offset(-s, -s),
          c + const Offset(s, s),
          paint,
        );
        canvas.drawLine(
          c + const Offset(s, -s),
          c + const Offset(-s, s),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
