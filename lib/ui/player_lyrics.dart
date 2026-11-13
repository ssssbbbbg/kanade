import 'dart:math' show max, min;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:provider/provider.dart';

import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';

/// Apple Music 式歌词：大号粗体左对齐，当前行从左到右逐渐点亮，
/// 离当前行越远越暗越模糊。用户手动滚动时调亮歌词并取消模糊，3 秒后恢复自动跟随。
class LyricView extends StatefulWidget {
  const LyricView({super.key, this.fontSize = 28});

  final double fontSize;

  @override
  State<LyricView> createState() => _LyricViewState();
}

/// 换句时每一行滑到新位置、放大缩小用的时长。
const _glide = Duration(milliseconds: 700);

/// 往下每一行比上一行晚这么久出发，一句接一句像波浪传下去；最多错开 [_staggerSteps] 步。
const _stagger = Duration(milliseconds: 45);
const _staggerSteps = 8;

class _LyricViewState extends State<LyricView> with TickerProviderStateMixin {
  late final PlayerController _player = context.read<PlayerController>();
  final _scroll = ScrollController();
  List<GlobalKey> _keys = [];
  Lyric? _lyric;
  int _current = -1;

  /// 用户正在手动滚动（停手 3 秒内）：歌词都调亮方便看。只有各行的明暗听它，切换时不用整页重建。
  final _free = ValueNotifier(false);
  DateTime _userScrolledAt = DateTime(0);

  /// 模糊的强弱：手动滚动时渐渐变清楚，回到自动跟随时再糊回去。
  late final _blur = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  /// 刚打开或换了歌词：直接停到当前行，不从第一行滚下来。
  bool _jump = true;

  /// 换句时整页先一下跳到位，每行再从原来的位置滑过去。
  /// 每行各自记着离新位置还差多远（[_off]）、滑得多快（[_vel]）、什么时候出发（[_startAt]）。
  /// 连着换句（比如开头 0.2 秒一句的制作人员名单）时在各行眼下的位置上接着算：
  /// 正在滑的行接着滑，停着的行按波浪顺序出发，哪一行都不会往回跳。
  List<double> _off = [];
  List<double> _vel = [];
  List<Duration> _startAt = [];
  final _clock = Stopwatch()..start();
  Duration _lastTick = Duration.zero;
  late final Ticker _waveTicker = createTicker(_onWaveTick);

  /// 每帧滑动后通知各行挪位置。
  final _waveTick = ValueNotifier(0);

  /// 这一波从哪一句开始、往哪边滑（内容往上滑为 1）。
  int _waveFrom = 0;
  int _waveDir = 1;

  /// 各行拉回原位的弹簧：临界阻尼不回弹，大约半秒滑到位。
  static const _omega = 11.0;

  @override
  void initState() {
    super.initState();
    _player.position.addListener(_onPosition);
    _free.addListener(() => _free.value ? _blur.reverse() : _blur.forward());
  }

  @override
  void dispose() {
    _player.position.removeListener(_onPosition);
    _free.dispose();
    _blur.dispose();
    _waveTicker.dispose();
    _waveTick.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onPosition() {
    final free =
        DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 3);
    final i = _player.lyricIndexAt(_player.position.value);
    if (_free.value != free) {
      _free.value = free;
      // 手动滚动结束，回到当前行
      if (!free) _follow(i);
    }
    if (i == _current) return;
    setState(() {
      _current = i;
      _waveFrom = i;
    });
    if (free) return;
    _follow(i);
  }

  /// 第 [i] 行在这一波里第几个出发：顺着滑动方向在前面的先走，往后一行晚一步，
  /// 这样各行只会拉开、不会叠到一起。往下翻（内容往上滑）时上面的先走，往回跳时下面的先走。
  int _step(int i) => (_waveDir > 0 ? i - _waveFrom + 1 : _waveFrom - i + 1)
      .clamp(0, _staggerSteps);

  /// 第 [i] 行这一刻离它的新位置还差多少。
  double _offset(int i) => i < _off.length ? _off[i] : 0;

  void _resetWave(int lines) {
    _waveTicker.stop();
    _off = List.filled(lines, 0);
    _vel = List.filled(lines, 0);
    _startAt = List.filled(lines, Duration.zero);
  }

  void _follow(int i) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = i >= 0 && i < _keys.length ? _keys[i].currentContext : null;
      if (ctx == null || !_scroll.hasClients) return;
      final jump = _jump;
      _jump = false;
      final before = _scroll.position.pixels;
      Scrollable.ensureVisible(ctx, alignment: 0.3);
      final moved = _scroll.position.pixels - before;
      if (jump || moved == 0) return;
      // 内容一下挪了 moved，每行先原地补回这段，再自己滑过去
      final now = _clock.elapsed;
      _waveDir = moved > 0 ? 1 : -1;
      for (var j = 0; j < _off.length; j++) {
        if (_off[j] == 0 && _vel[j] == 0) {
          _startAt[j] = now + _stagger * _step(j);
        }
        _off[j] += moved;
      }
      if (!_waveTicker.isActive) {
        _lastTick = now;
        _waveTicker.start();
      }
    });
  }

  void _onWaveTick(Duration _) {
    final now = _clock.elapsed;
    // 掉帧时步长也别太大，弹簧算式才稳
    final dt = min((now - _lastTick).inMicroseconds / 1e6, 1 / 30);
    _lastTick = now;
    var moving = false;
    for (var j = 0; j < _off.length; j++) {
      if (_off[j] == 0 && _vel[j] == 0) continue;
      moving = true;
      if (now < _startAt[j]) continue;
      _vel[j] += (-_omega * _omega * _off[j] - 2 * _omega * _vel[j]) * dt;
      _off[j] += _vel[j] * dt;
      if (_off[j].abs() < 0.3 && _vel[j].abs() < 6) {
        _off[j] = 0;
        _vel[j] = 0;
      }
    }
    _waveTick.value++;
    if (!moving) _waveTicker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final lyric = context.select<PlayerController, Lyric?>((p) => p.lyric);
    if (!identical(lyric, _lyric)) {
      _lyric = lyric;
      _keys = List.generate(lyric?.lines.length ?? 0, (_) => GlobalKey());
      _resetWave(_keys.length);
      _current = _player.lyricIndexAt(_player.position.value);
      _jump = true;
      _follow(_current);
    }
    final l = AppLocalizations.of(context);
    final big = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );
    if (lyric == null || (lyric.lines.isEmpty && lyric.plain.isEmpty)) {
      return Center(
        child: Text(
          l.noLyrics,
          style: big.copyWith(color: Colors.white54, fontSize: 20),
        ),
      );
    }
    // 桌面端默认会给可滚动区域加滚动条，歌词不需要
    final noScrollbar = ScrollConfiguration.of(context)
        .copyWith(scrollbars: false);
    if (lyric.lines.isEmpty) {
      return ScrollConfiguration(
        behavior: noScrollbar,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
          child: Text(
            lyric.plain,
            style: big.copyWith(
              fontSize: widget.fontSize * 0.7,
              color: Colors.white70,
            ),
          ),
        ),
      );
    }

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        _free.value = true;
        return false;
      },
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, 0.1, 0.85, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: LayoutBuilder(
          builder: (context, c) => ScrollConfiguration(
            behavior: noScrollbar,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                12,
                c.maxHeight * 0.3,
                12,
                c.maxHeight * 0.6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, line) in lyric.lines.indexed)
                    // key 挂在平移外面：找当前行位置时不算还没滑完的那段
                    KeyedSubtree(
                      key: _keys[i],
                      child: AnimatedBuilder(
                        animation: _waveTick,
                        builder: (_, child) => Transform.translate(
                          offset: Offset(0, _offset(i)),
                          child: child,
                        ),
                        child: _Line(
                          line: line,
                          nextMs: i + 1 < lyric.lines.length
                              ? lyric.lines[i + 1].timeMs
                              : null,
                          distance: _current < 0 ? i + 1 : (i - _current).abs(),
                          active: i == _current,
                          free: _free,
                          blur: _blur,
                          // 上一波还没滑完又换句：大小明暗也直接接着变，不再停下来等
                          delay: _free.value || _waveTicker.isActive
                              ? Duration.zero
                              : _stagger * _step(i),
                          style: big,
                          onTap: () {
                            _userScrolledAt = DateTime(0);
                            _player.seek(Duration(milliseconds: line.timeMs));
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 离当前行越远越模糊：按这一行在屏幕上的位置算，当前行附近是清楚的，往上往下逐渐变糊。
/// 滤镜加在行的重绘边界外面，行本身不用重画；只有屏幕里看得见、而且需要糊的行才有滤镜。
///
/// 这一行的缩放也在这里做：大小在变的时候和模糊合成同一个滤镜。分开成两层套着的话
/// （模糊滤镜里面再套一层按图片缩放的滤镜），Windows 上这一行滑动时会整行消失几帧，看着就是闪。
/// 模糊都是按缩放之前的大小算的，所以小一号的行实际糊得也略轻一点。
class _LyricBlur extends SingleChildRenderObjectWidget {
  const _LyricBlur({
    required this.active,
    required this.strength,
    required this.scale,
    required this.scaling,
    super.child,
  });

  final bool active;

  /// 1 是正常模糊，0 是完全不糊（手动滚动时）。
  final Animation<double> strength;

  /// 这一行眼下的大小，以左边中点为准。
  final double scale;

  /// 大小还在变：按图片缩放；停稳了直接按这个大小画字。
  final bool scaling;

  @override
  _RenderLyricBlur createRenderObject(BuildContext context) => _RenderLyricBlur(
    active,
    strength,
    scale,
    scaling,
    MediaQuery.devicePixelRatioOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, _RenderLyricBlur renderObject) {
    renderObject
      ..active = active
      ..strength = strength
      ..scale = scale
      ..scaling = scaling
      ..pixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class _RenderLyricBlur extends RenderProxyBox {
  _RenderLyricBlur(
    this._active,
    this._strength,
    this._scale,
    this._scaling,
    this._pixelRatio,
  );

  double _scale;
  set scale(double value) {
    if (_scale == value) return;
    _scale = value;
    markNeedsPaint();
  }

  bool _scaling;
  set scaling(bool value) {
    if (_scaling == value) return;
    _scaling = value;
    markNeedsPaint();
  }

  Matrix4 get _matrix => Matrix4.translationValues(0, size.height / 2, 0)
    ..scaleByDouble(_scale, _scale, 1, 1)
    ..translateByDouble(0, -size.height / 2, 0, 1);

  final _transformLayer = LayerHandle<TransformLayer>();

  double _pixelRatio;
  set pixelRatio(double value) {
    if (_pixelRatio == value) return;
    _pixelRatio = value;
    markNeedsPaint();
  }

  bool _active;
  set active(bool value) {
    if (_active == value) return;
    _active = value;
    markNeedsPaint();
  }

  Animation<double> _strength;
  set strength(Animation<double> value) {
    if (_strength == value) return;
    if (attached) _strength.removeListener(markNeedsPaint);
    _strength = value;
    if (attached) _strength.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  final _filterLayer = LayerHandle<ImageFilterLayer>();

  /// 滤镜按模糊程度存着复用，不会每帧新建。每 0.05 个像素一档，最糊 4.8 个逻辑像素：
  /// 档位要细，粗了（比如 0.6 一档）歌词滑过档位时清晰度会突然跳一下，看着就是在闪。
  static const _step = 0.05;
  static const _maxSteps = 96;
  static final _filters = <int, ui.ImageFilter>{};

  static ui.ImageFilter _filter(int steps) =>
      _filters[steps] ??= ui.ImageFilter.blur(
        sigmaX: steps * _step,
        sigmaY: steps * _step,
        tileMode: TileMode.decal,
      );

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _strength.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _strength.removeListener(markNeedsPaint);
    super.detach();
  }

  int _blurSteps() {
    if (_active || _strength.value == 0) return 0;
    final viewport = RenderAbstractViewport.of(this) as RenderBox;
    final height = viewport.size.height;
    if (height == 0) return 0;
    final y = localToGlobal(size.center(Offset.zero), ancestor: viewport).dy;
    if (y + size.height / 2 <= 0 || y - size.height / 2 >= height) return 0;
    // 当前行停在离顶 30% 的地方，从它往外逐渐变糊。
    // 往上：8% 高度以内不糊，到顶边最糊。往下留得宽一些：16% 以内不糊，到底边才最糊。
    final away = y - height * 0.3;
    final t = away < 0
        ? (-away - height * 0.08) / (height * 0.22)
        : (away - height * 0.16) / (height * 0.54);
    return (t.clamp(0.0, 1.0) * _strength.value * _maxSteps).round();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final steps = _blurSteps();
    if (_scaling) {
      // 大小还在变：缩放和模糊合成一个滤镜，先糊再缩，和停稳以后的画法是同一个顺序。
      // 写成先缩再糊的话，手机上实际出来的还是先糊再缩，比停稳时弱一截：
      // 动画一开始模糊突然变弱，结束时又跳回来。
      _transformLayer.layer = null;
      final resize = ui.ImageFilter.matrix(
        _matrix.storage,
        filterQuality: FilterQuality.medium,
      );
      final layer = _filterLayer.layer ??= ImageFilterLayer();
      layer
        ..offset = offset
        ..imageFilter = steps == 0
            ? resize
            : ui.ImageFilter.compose(outer: resize, inner: _filter(steps));
      context.pushLayer(
        layer,
        super.paint,
        Offset.zero,
        childPaintBounds: paintBounds,
      );
      return;
    }
    // 停稳了：外面按这个大小缩放，里面直接画字，要糊的再套一层模糊
    _transformLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _matrix,
      (context, offset) {
        if (steps == 0) {
          _filterLayer.layer = null;
          super.paint(context, offset);
          return;
        }
        // 对齐到整数物理像素：模糊比较强时，位置差不到一个像素糊出来的结果也会不一样，滑动时会跟着抖
        final origin =
            (localToGlobal(Offset.zero) +
                Offset(0, size.height / 2 * (1 - _scale))) *
            _pixelRatio;
        final snap =
            Offset(
              origin.dx.roundToDouble() - origin.dx,
              origin.dy.roundToDouble() - origin.dy,
            ) /
            (_pixelRatio * _scale);
        final layer = _filterLayer.layer ??= ImageFilterLayer();
        layer
          ..offset = offset + snap
          ..imageFilter = _filter(steps);
        context.pushLayer(
          layer,
          super.paint,
          Offset.zero,
          childPaintBounds: paintBounds,
        );
      },
      oldLayer: _transformLayer.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_matrix);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintTransform(
      transform: _matrix,
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }

  @override
  void dispose() {
    _filterLayer.layer = null;
    _transformLayer.layer = null;
    super.dispose();
  }
}

/// 一句歌词：当前句最大最亮，往外一级比一级小、一级比一级暗。
/// 大小变化时整行当成图片缩放，不在每个中间尺寸重新画字（那样中日文字多时显存会暴涨）；
/// 停稳以后按最终大小直接画，字是清楚的。最终大小只有几档，字形缓存不会越积越多。
/// 明暗用透明度图层调，字本身一直是白色：改文字颜色会让这一行重新排版，
/// 开始手动滚动时全部歌词一起变亮，每帧重排上百行就会卡。
class _Line extends StatelessWidget {
  const _Line({
    required this.line,
    required this.nextMs,
    required this.distance,
    required this.active,
    required this.free,
    required this.blur,
    required this.delay,
    required this.style,
    required this.onTap,
  });

  final LyricLine line;
  final int? nextMs;
  final int distance;
  final bool active;
  final ValueListenable<bool> free;

  /// 模糊的强弱，见 [_LyricBlur.strength]。
  final Animation<double> blur;

  /// 换句时这一行晚多久开始变，跟着整页的波浪一起。
  final Duration delay;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    double opacity(bool free) => active
        ? 1.0
        : free
        ? 0.55
        : (0.4 - distance * 0.05).clamp(0.12, 0.4);
    // 当前句 1，旁边一句 0.88，再往外每句小 0.03，最小 0.8。
    // 手动滚动时不改大小：那一下全部歌词一起缩放，每行都要当图片缩，会卡
    final scale = active ? 1.0 : (0.91 - distance * 0.03).clamp(0.8, 0.88);
    final empty = line.text.trim().isEmpty;
    final transStyle = style.copyWith(
      fontSize: style.fontSize! * 0.6,
      fontWeight: FontWeight.w600,
    );
    final duration = _glide + delay;
    final curve = Interval(
      delay.inMilliseconds / duration.inMilliseconds,
      1,
      curve: Curves.easeOutCubic,
    );

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: Colors.white10,
        splashColor: Colors.white12,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: scale),
          duration: duration,
          curve: curve,
          builder: (_, s, child) => _LyricBlur(
            active: active,
            strength: blur,
            scale: s,
            // 还在变的时候按图片缩放，停稳了直接按这个大小画字
            scaling: (s - scale).abs() > 0.001,
            // 每行的内容单独一层：滑动、缩放、模糊都只动图层，当前行逐帧点亮也只重画它自己
            child: RepaintBoundary(child: child),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: empty
                ? (active
                      ? _InterludeDots(size: style.fontSize! * 0.35)
                      : SizedBox(height: style.fontSize! * 0.4))
                : ValueListenableBuilder(
                    valueListenable: free,
                    builder: (_, free, child) => TweenAnimationBuilder<double>(
                      tween: Tween(end: opacity(free)),
                      duration: duration,
                      curve: curve,
                      builder: (_, o, child) =>
                          Opacity(opacity: o, child: child),
                      child: child,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        active
                            ? _Sweep(line: line, nextMs: nextMs, style: style)
                            : Text(
                                line.text,
                                style: style.copyWith(color: Colors.white),
                              ),
                        if (line.trans.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              line.trans,
                              style: transStyle.copyWith(color: Colors.white70),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 当前行从左往右点亮：按本行到下一行的时间比例推进。
/// 一句歌词折成好几行时一行一行亮，每行分到的时间按这一行的字数算。
class _Sweep extends StatefulWidget {
  const _Sweep({required this.line, required this.nextMs, required this.style});

  final LyricLine line;
  final int? nextMs;
  final TextStyle style;

  @override
  State<_Sweep> createState() => _SweepState();
}

class _SweepState extends State<_Sweep> {
  _SweepText? _text;

  /// 文字、字体和宽度不变就沿用上次的排版，播放进度变化时只重画。
  _SweepText _layout(
    TextStyle style,
    TextScaler scaler,
    Locale? locale,
    TextHeightBehavior? heights,
    double width,
  ) {
    final t = _text;
    if (t != null &&
        t.width == width &&
        t.text == widget.line.text &&
        t.style == style &&
        t.scaler == scaler &&
        t.locale == locale &&
        t.heights == heights) {
      return t;
    }
    t?.dispose();
    return _text = _SweepText(
      widget.line.text,
      style,
      scaler,
      locale,
      heights,
      width,
    );
  }

  @override
  void dispose() {
    _text?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final line = widget.line;
    // 行间隔太长（间奏）时只按 6 秒算，避免长时间半亮
    final span = ((widget.nextMs ?? line.timeMs + 5000) - line.timeMs).clamp(
      800,
      6000,
    );
    // 自己排版不会自动带上主题字体、字号缩放和语言（中文标点选哪套字体），要和旁边用 Text 的行一致
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final heights = DefaultTextStyle.of(context).textHeightBehavior;
    return LayoutBuilder(
      builder: (context, c) {
        final text = _layout(style, scaler, locale, heights, c.maxWidth);
        return Semantics(
          label: line.text,
          child: ValueListenableBuilder(
            valueListenable: player.position,
            builder: (_, pos, _) => TweenAnimationBuilder<double>(
              tween: Tween(
                end: ((pos.inMilliseconds - line.timeMs) / span).clamp(
                  0.0,
                  1.0,
                ),
              ),
              duration: const Duration(milliseconds: 250),
              builder: (_, v, _) => CustomPaint(
                size: Size(text.lit.width, text.lit.height),
                painter: _SweepPainter(text, v),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 一句歌词排好版的亮、暗两份，以及每一行的位置和它在整句进度里占的区间。
class _SweepText {
  _SweepText(
    this.text,
    this.style,
    this.scaler,
    this.locale,
    this.heights,
    this.width,
  ) {
    TextPainter painter(Color color) => TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      locale: locale,
      textHeightBehavior: heights,
    )..layout(maxWidth: width);
    lit = painter(Colors.white);
    dim = painter(const Color(0x88FFFFFF));

    final metrics = lit.computeLineMetrics();
    final chars = <int>[];
    final rows = <Rect>[];
    var top = 0.0;
    for (final m in metrics) {
      final start = lit.getPositionForOffset(
        Offset(m.left + 1, top + m.height / 2),
      );
      final range = lit.getLineBoundary(start);
      chars.add(max(1, range.end - range.start));
      rows.add(Rect.fromLTWH(m.left, top, m.width, m.height));
      top += m.height;
    }
    final total = chars.fold(0, (a, b) => a + b);
    var done = 0;
    for (final (i, row) in rows.indexed) {
      lines.add((row: row, from: done / total, to: (done + chars[i]) / total));
      done += chars[i];
    }
  }

  final String text;
  final TextStyle style;
  final TextScaler scaler;
  final Locale? locale;
  final TextHeightBehavior? heights;
  final double width;
  late final TextPainter lit;
  late final TextPainter dim;
  final lines = <({Rect row, double from, double to})>[];

  void dispose() {
    lit.dispose();
    dim.dispose();
  }
}

/// 先画暗的整句，再把亮的一份按行盖上去：亮完的行整行露出，正在亮的行露到进度位置并带一段渐变，后面的行不露。
class _SweepPainter extends CustomPainter {
  _SweepPainter(this.text, this.progress);

  final _SweepText text;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    text.dim.paint(canvas, Offset.zero);
    // 字形会伸出行框一点，四周多留些
    final bounds = (Offset.zero & size).inflate(12);
    canvas.saveLayer(bounds, Paint());
    text.lit.paint(canvas, Offset.zero);
    final lines = text.lines;
    for (final (i, l) in lines.indexed) {
      final p = ((progress - l.from) / (l.to - l.from)).clamp(0.0, 1.0);
      if (p >= 1) continue;
      // 每行的遮罩上下接起来铺满，第一行往上、最后一行往下延伸到边
      final rect = Rect.fromLTRB(
        bounds.left,
        i == 0 ? bounds.top : l.row.top,
        bounds.right,
        i == lines.length - 1 ? bounds.bottom : l.row.bottom,
      );
      final mask = Paint()..blendMode = BlendMode.dstIn;
      if (p > 0) {
        mask.shader = ui.Gradient.linear(
          Offset(l.row.left, 0),
          Offset(l.row.right, 0),
          const [
            Colors.black,
            Colors.black,
            Colors.transparent,
            Colors.transparent,
          ],
          [0, p, min(p + 0.15, 1), 1],
        );
      } else {
        mask.color = Colors.transparent;
      }
      canvas.drawRect(rect, mask);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.progress != progress || old.text != text;
}

/// 间奏时的三个呼吸圆点。
class _InterludeDots extends StatefulWidget {
  const _InterludeDots({required this.size});

  final double size;

  @override
  State<_InterludeDots> createState() => _InterludeDotsState();
}

class _InterludeDotsState extends State<_InterludeDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.size * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(right: widget.size * 0.6),
                child: Transform.scale(
                  scale:
                      0.7 +
                      0.5 *
                          Curves.easeInOut.transform(
                            ((_c.value * 3 - i) % 3 / 3 - 0.5).abs() * 2,
                          ),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
