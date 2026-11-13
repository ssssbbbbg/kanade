import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../src/rust/api/types.dart';
import 'theme.dart';
import 'widgets.dart';

/// 倍速菜单，从快到慢。
const _rates = [2.0, 1.5, 1.25, 1.0, 0.75, 0.5];

String _rateLabel(double r) =>
    '${r == r.roundToDouble() ? r.toStringAsFixed(1) : r}x';

/// 画面上的控件不跟主题走，始终是深色。
const _menuColor = Color(0xFF1C1C1C);
const _chipColor = Color(0x8C000000);

/// MV 播放器的控制层：点画面显示/隐藏，播放中 3 秒没操作就隐藏。
/// 右下角是倍速、清晰度和全屏；倍速和清晰度点开后按钮原地向上长成菜单。
/// 全屏时 media_kit 会用同一个 builder 再建一份，所以清晰度走 [stream] 通知，不靠重建。
class MvControls extends StatefulWidget {
  const MvControls({
    super.key,
    required this.player,
    required this.title,
    required this.streams,
    required this.stream,
    required this.onStream,
  });

  final Player player;
  final String title;

  /// 从高到低。
  final List<MvStream> streams;
  final ValueListenable<MvStream?> stream;
  final ValueChanged<MvStream> onStream;

  @override
  State<MvControls> createState() => _MvControlsState();
}

enum _Menu { rate, quality }

class _MvControlsState extends State<MvControls> {
  final _subs = <StreamSubscription<Object>>[];
  late bool _playing = widget.player.state.playing;
  late bool _buffering = widget.player.state.buffering;
  bool _visible = true;
  _Menu? _menu;
  Timer? _hide;

  Player get _player => widget.player;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _player.stream.playing.listen((v) {
        setState(() => _playing = v);
        _scheduleHide();
      }),
    );
    _subs.add(
      _player.stream.buffering.listen((v) => setState(() => _buffering = v)),
    );
    _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (!_playing || _menu != null) return;
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _onTap() {
    if (_menu != null) return _toggleMenu(_menu!);
    setState(() => _visible = !_visible);
    if (_visible) _scheduleHide();
  }

  void _toggleMenu(_Menu menu) {
    setState(() => _menu = _menu == menu ? null : menu);
    _scheduleHide();
  }

  void _seekBy(Duration d) {
    final total = _player.state.duration;
    final target = _player.state.position + d;
    _player.seek(
      target < Duration.zero
          ? Duration.zero
          : (target > total ? total : target),
    );
    _show();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.space:
        _player.playOrPause();
        _show();
      case LogicalKeyboardKey.arrowLeft:
        _seekBy(const Duration(seconds: -10));
      case LogicalKeyboardKey.arrowRight:
        _seekBy(const Duration(seconds: 10));
      case LogicalKeyboardKey.escape when isFullscreen(context):
        exitFullscreen(context);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final fullscreen = isFullscreen(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        onHover: (_) => _show(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(behavior: HitTestBehavior.opaque, onTap: _onTap),
            if (_buffering)
              const Center(
                child: SizedBox.square(
                  dimension: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
              ),
            IgnorePointer(
              ignoring: !_visible,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.3),
                      ),
                    ),
                    SafeArea(
                      top: fullscreen,
                      bottom: fullscreen,
                      child: Padding(
                        padding: EdgeInsets.all(fullscreen ? 12 : 8),
                        child: Column(
                          children: [
                            _TopBar(title: fullscreen ? widget.title : null),
                            Expanded(
                              child: _buffering
                                  ? const SizedBox()
                                  : _center(fullscreen),
                            ),
                            _SeekBar(_player, onSeek: _show),
                            _bottomRow(fullscreen),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _center(bool fullscreen) {
    final size = fullscreen ? 56.0 : 46.0;
    final play = GestureDetector(
      onTap: () {
        _player.playOrPause();
        _show();
      },
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: _chipColor,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: size * 0.6,
        ),
      ),
    );
    return Center(child: play);
  }

  Widget _bottomRow(bool fullscreen) {
    final timeStyle = const TextStyle(
      fontSize: 12,
      color: Colors.white,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          const SizedBox(width: 4),
          StreamBuilder<Duration>(
            stream: _player.stream.position,
            initialData: _player.state.position,
            builder: (_, snap) => Text(
              '${formatDuration(snap.data!)} / ${formatDuration(_player.state.duration)}',
              style: timeStyle,
            ),
          ),
          const Spacer(),
          StreamBuilder<double>(
            stream: _player.stream.rate,
            initialData: _player.state.rate,
            builder: (_, snap) => _MorphMenu<double>(
              items: _rates,
              selected: snap.data!,
              label: _rateLabel,
              open: _menu == _Menu.rate,
              onToggle: () => _toggleMenu(_Menu.rate),
              onSelected: _player.setRate,
            ),
          ),
          if (widget.streams.length > 1) ...[
            const SizedBox(width: 6),
            ValueListenableBuilder(
              valueListenable: widget.stream,
              builder: (_, current, _) => _MorphMenu<MvStream>(
                items: widget.streams,
                selected: current ?? widget.streams.first,
                label: (s) => '${s.height}P',
                open: _menu == _Menu.quality,
                onToggle: () => _toggleMenu(_Menu.quality),
                onSelected: widget.onStream,
              ),
            ),
          ],
          IconButton(
            visualDensity: VisualDensity.compact,
            color: Colors.white,
            icon: Icon(
              fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
            ),
            onPressed: () => toggleFullscreen(context),
          ),
        ],
      ),
    );
  }
}

/// 左上角返回；全屏时返回是退出全屏，旁边带标题。
class _TopBar extends StatelessWidget {
  const _TopBar({this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => title != null
              ? exitFullscreen(context)
              : Navigator.of(context).maybePop(),
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: _chipColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          ),
        ),
        if (title != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 细进度条：已播放和拖动点用抗色，缓冲用半透明白。拖动时只改显示，松手才 seek。
class _SeekBar extends StatefulWidget {
  const _SeekBar(this.player, {required this.onSeek});

  final Player player;
  final VoidCallback onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  final _subs = <StreamSubscription<Object>>[];
  late Duration _position = widget.player.state.position;
  late Duration _duration = widget.player.state.duration;
  late Duration _buffer = widget.player.state.buffer;
  double? _drag;

  @override
  void initState() {
    super.initState();
    final s = widget.player.stream;
    _subs.add(s.position.listen((v) => setState(() => _position = v)));
    _subs.add(s.duration.listen((v) => setState(() => _duration = v)));
    _subs.add(s.buffer.listen((v) => setState(() => _buffer = v)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  double _fraction(Duration d) => _duration.inMilliseconds == 0
      ? 0
      : (d.inMilliseconds / _duration.inMilliseconds).clamp(0, 1);

  void _seekTo(double f) {
    widget.player.seek(_duration * f);
    widget.onSeek();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const inset = 6.0;
        final width = constraints.maxWidth - inset * 2;
        double at(Offset p) => ((p.dx - inset) / width).clamp(0, 1);
        final played = _drag ?? _fraction(_position);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _seekTo(at(d.localPosition)),
          onHorizontalDragStart: (d) =>
              setState(() => _drag = at(d.localPosition)),
          onHorizontalDragUpdate: (d) =>
              setState(() => _drag = at(d.localPosition)),
          onHorizontalDragEnd: (_) {
            _seekTo(_drag!);
            setState(() => _drag = null);
          },
          child: SizedBox(
            width: double.infinity,
            height: 24,
            child: CustomPaint(
              painter: _SeekPainter(
                played: played,
                buffered: max(played, _fraction(_buffer)),
                dragging: _drag != null,
                inset: inset,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({
    required this.played,
    required this.buffered,
    required this.dragging,
    required this.inset,
  });

  final double played;
  final double buffered;
  final bool dragging;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final width = size.width - inset * 2;
    final track = dragging ? 4.0 : 3.0;
    RRect bar(double f) => RRect.fromLTRBR(
      inset,
      y - track / 2,
      inset + width * f,
      y + track / 2,
      Radius.circular(track),
    );
    canvas.drawRRect(
      bar(1),
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );
    canvas.drawRRect(
      bar(buffered),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    canvas.drawRRect(bar(played), Paint()..color = KanadeColors.lime);
    canvas.drawCircle(
      Offset(inset + width * played, y),
      dragging ? 7 : 5,
      Paint()..color = KanadeColors.lime,
    );
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.dragging != dragging;
}

/// 小胶囊按钮，[open] 时底边不动、原地向上长成一列选项；关上时再缩回去。
/// 动效和播放页的音质菜单一致：弹簧展开、选项逐行浮上来、白色选中块滑到新的一行再收。
/// 画面上是视频，不用毛玻璃，底色实心。菜单画在 Overlay 里，盖过进度条也能点到。
class _MorphMenu<T> extends StatefulWidget {
  const _MorphMenu({
    required this.items,
    required this.selected,
    required this.label,
    required this.open,
    required this.onToggle,
    required this.onSelected,
  });

  final List<T> items;
  final T selected;
  final String Function(T) label;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<T> onSelected;

  @override
  State<_MorphMenu<T>> createState() => _MorphMenuState<T>();
}

class _MorphMenuState<T> extends State<_MorphMenu<T>>
    with SingleTickerProviderStateMixin {
  static const _chipHeight = 26.0;
  static const _rowHeight = 32.0;
  static const _pad = 4.0;
  static const _minWidth = 72.0;
  static const _menuRadius = 16.0;
  static const _textStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  // 展开带一点回弹，收起不回弹、干脆利落
  static final _openSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 380,
    ratio: 0.68,
  );
  static final _closeSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 560,
    ratio: 1,
  );

  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _chipKey = GlobalKey();

  // 0 是按钮，1 是菜单；弹簧会冲过 1 一点，所以不设上下界
  late final _c = AnimationController.unbounded(vsync: this);
  Size _chipSize = Size.zero;

  /// 刚点中、还没收起的那一项，选中块先滑过去再收。
  T? _picked;
  bool _hasPicked = false;

  /// 展开在点按时直接做（build 期间不能 show Overlay），收起跟着 [open] 变化走，
  /// 这样另一个菜单打开或点了外面，这个都会缩回去。
  void _open() {
    final box = _chipKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    setState(() {
      _chipSize = box.size;
      _hasPicked = false;
    });
    _portal.show();
    unawaited(
      _c.animateWith(SpringSimulation(_openSpring, _c.value, 1, _c.velocity)),
    );
    widget.onToggle();
  }

  @override
  void didUpdateWidget(_MorphMenu<T> old) {
    super.didUpdateWidget(old);
    if (old.open && !widget.open) unawaited(_close());
  }

  Future<void> _close() async {
    await _c.animateBackWith(
      SpringSimulation(_closeSpring, _c.value, 0, _c.velocity, snapToEnd: true),
    );
    if (!mounted || widget.open) return;
    _portal.hide();
    setState(() => _hasPicked = false);
  }

  Future<void> _pick(T item) async {
    setState(() {
      _picked = item;
      _hasPicked = true;
    });
    widget.onSelected(item);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted && widget.open) widget.onToggle();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _chipLabel() => Text(
    widget.label(widget.selected),
    style: _textStyle.copyWith(color: Colors.white),
    maxLines: 1,
  );

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildMenu,
      child: CompositedTransformTarget(
        link: _link,
        // 展开期间按钮本体让给菜单，原位置留空
        child: Opacity(
          opacity: _portal.isShowing ? 0 : 1,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _open,
            child: Container(
              key: _chipKey,
              height: _chipHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const ShapeDecoration(
                color: _chipColor,
                shape: StadiumBorder(),
              ),
              child: _chipLabel(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final count = widget.items.length;
    final selected = _hasPicked ? _picked as T : widget.selected;
    final selectedIndex = widget.items.indexOf(selected);
    final menuSize = Size(
      max(_minWidth, _chipSize.width),
      count * _rowHeight + _pad * 2,
    );

    return Stack(
      children: [
        // 点菜单外面就收起
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onToggle,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          // 以按钮底边中点为锚，菜单从按钮所在位置往上长出来
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.bottomCenter,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final v = _c.value;
              final t = v.clamp(0.0, 1.0);
              double fade(double from, double to) =>
                  ((v - from) / (to - from)).clamp(0.0, 1.0);
              // 选项从下往上一行接一行浮上来，挨着按钮的先出来
              final step = min(0.06, 0.3 / count);
              final chipFade = 1 - fade(0, 0.3);

              Widget appear(int i, Widget child) {
                final order = count - 1 - i;
                final a = Curves.easeOut.transform(
                  fade(0.3 + order * step, 0.7 + order * step),
                );
                return Opacity(
                  opacity: a,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - a)),
                    child: child,
                  ),
                );
              }

              final menu = Padding(
                padding: const EdgeInsets.all(_pad),
                child: Stack(
                  children: [
                    // 白底选中块：换一项时滑到新的一行
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
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.all(
                                Radius.circular(_menuRadius - _pad),
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
                            _row(widget.items[i], selected: i == selectedIndex),
                          ),
                      ],
                    ),
                  ],
                ),
              );

              return SizedBox(
                width: lerpDouble(_chipSize.width, menuSize.width, v),
                height: lerpDouble(_chipSize.height, menuSize.height, v),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    lerpDouble(_chipSize.height / 2, _menuRadius, t)!,
                  ),
                  child: ColoredBox(
                    color: Color.lerp(_chipColor, _menuColor, t)!,
                    child: Stack(
                      children: [
                        if (chipFade > 0)
                          Positioned.fill(
                            child: Opacity(
                              opacity: chipFade,
                              child: Center(child: _chipLabel()),
                            ),
                          ),
                        if (v > 0.25)
                          Positioned.fill(
                            child: OverflowBox(
                              alignment: Alignment.bottomCenter,
                              minWidth: menuSize.width,
                              maxWidth: menuSize.width,
                              minHeight: menuSize.height,
                              maxHeight: menuSize.height,
                              child: menu,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _row(T item, {required bool selected}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_pick(item)),
      child: SizedBox(
        height: _rowHeight,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: _textStyle.copyWith(
              color: selected ? Colors.black : Colors.white,
            ),
            child: Text(widget.label(item)),
          ),
        ),
      ),
    );
  }
}
