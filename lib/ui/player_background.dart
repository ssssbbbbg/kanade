import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/data_ext.dart';
import '../src/rust/api/types.dart';

const fallbackPalette = [
  Color(0xFF3A2A4A),
  Color(0xFF5B3FA8),
  Color(0xFFB0476A),
  Color(0xFF2A3F6B),
];

/// 背景用的封面素材：4 个主色、一张预先模糊好的小图。
/// 模糊只在取图时做一次，之后每帧由 shader 把这张小图放大、旋转、扭曲着画出来。
/// 不能每帧新建渐变或模糊：Impeller 会给每个新渐变分配纹理，
/// 实测打开播放页时内存从 200MB 冲到 5GB 以上。
class CoverArt {
  CoverArt(this.palette, this.blurred);

  final List<Color> palette;
  final ui.Image blurred;

  /// 按主色生成的深色主题（弹出菜单、底部面板用）。fromSeed 要算色调，生成一次就留着。
  late final ThemeData theme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette[1],
      brightness: Brightness.dark,
    ),
  );
}

/// 解码封面用的尺寸（取色也用它）和预模糊图的尺寸。
/// 预模糊图要够大，放大到全屏时才不会出现颗粒和色块。
const _srcSize = 128;
const _artSize = 256;

/// 最近用过的封面素材，每张约 256 KB。
final _artCache = <String, CoverArt>{};

/// 正在生成的素材，同一张封面同时被预取和播放页请求时只算一次。
final _artLoading = <String, Future<CoverArt>>{};
Future<void>? _coverWarmUp;

/// 还没取到封面时用的默认图：默认主色画几团光斑，第一次用到时才生成。
final _fallbackImage = () {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)..drawColor(fallbackPalette.first, BlendMode.src);
  const s = _artSize + 0.0;
  for (final (i, c) in fallbackPalette.indexed) {
    final center = Offset(
      s * (0.25 + 0.5 * (i % 2)),
      s * (0.25 + 0.5 * (i ~/ 2)),
    );
    canvas.drawCircle(
      center,
      s * 0.5,
      Paint()
        ..shader = ui.Gradient.radial(center, s * 0.5, [
          c,
          c.withValues(alpha: 0),
        ]),
    );
  }
  return rec.endRecording().toImageSync(_artSize, _artSize);
}();

ui.FragmentProgram? _program;
Future<void>? _programLoading;

/// 加载背景 shader。迷你播放器预取封面时就会调用，打开播放页时一般已经好了。
Future<void> _loadProgram() => _programLoading ??= ui.FragmentProgram.fromAsset(
  'shaders/player_background.frag',
).then((p) => _program = p);

/// 预加载并实际绘制一次，提前完成 Windows / Skia 的首次 GPU 编译。
/// 只加载 FragmentProgram 不会执行绘制，编译开销仍会落在首次转场里。
Future<void> warmUpPlayerBackground({CoverArt? art}) async {
  await _loadProgram();
  final shader = _program!.fragmentShader();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final pixelRatio =
      ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
  canvas.scale(pixelRatio);
  const size = Size(64, 64);
  _BackgroundPainter.paintShader(canvas, size, shader, Paint(), art, art, 0, 1);
  final picture = recorder.endRecording();
  try {
    final extent = (64 * pixelRatio).ceil();
    // toImage 的 Skia 输出格式不同；与实际绘制用同一路径，并等待 GPU 完成。
    final image = picture.toImageSync(extent, extent);
    try {
      await image.toByteData();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
    shader.dispose();
  }
}

/// 已经生成好的素材，播放页第一帧就能直接用，不用等异步。
CoverArt? cachedCoverArt(String url) => _artCache[httpsUrl(url)];

Future<CoverArt> loadCoverArt(String url) {
  unawaited(_loadProgram());
  url = httpsUrl(url);
  final cached = _artCache.remove(url);
  if (cached != null) return SynchronousFuture(_artCache[url] = cached);
  // 回调不能写成 `=> _artLoading.remove(url)`：remove 返回的就是这个 Future 本身，
  // whenComplete 会等它完成，自己等自己，永远不结束（播放页里切歌背景不变就是这个原因）
  return _artLoading[url] ??= _build(url).whenComplete(() {
    _artLoading.remove(url);
  });
}

String? _prefetched;

/// 切歌时就把播放页要用的大封面和背景素材准备好，
/// 打开播放页时不用在转场动画期间临时下载、取色、模糊。
void prefetchPlayerArt(BuildContext context, Song song) {
  final url = bigCoverUrl(song);
  if (url.isEmpty || url == _prefetched) return;
  _prefetched = url;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    unawaited(precacheImage(NetworkImage(url), context));
    unawaited(loadCoverArt(url).then<void>((_) {}, onError: (_) {}));
  });
}

Future<CoverArt> _build(String url) async {
  final src = await _loadSmall(NetworkImage(url));
  try {
    final data = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
    final palette = data == null ? fallbackPalette : _pick(data);
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      const Rect.fromLTWH(0, 0, _artSize + 0.0, _artSize + 0.0),
      Paint()
        ..filterQuality = FilterQuality.high
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 6,
          sigmaY: 6,
          tileMode: TileMode.mirror,
        ),
    );
    final blurred = await rec.endRecording().toImage(_artSize, _artSize);
    final art = CoverArt(palette, blurred);
    if (Platform.isWindows) {
      await (_coverWarmUp ??= warmUpPlayerBackground(art: art));
    }
    _artCache[url] = art;
    // 只留最近 12 张；被挤掉的图可能还在画，交给 GC 回收，不手动 dispose
    while (_artCache.length > 12) {
      _artCache.remove(_artCache.keys.first);
    }
    return art;
  } finally {
    src.dispose();
  }
}

Future<ui.Image> _loadSmall(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = ResizeImage(
    provider,
    width: _srcSize,
    height: _srcSize,
  ).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info.image.clone());
      info.dispose();
    },
    onError: (e, s) {
      stream.removeListener(listener);
      completer.completeError(e, s);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// 按色相分 12 个桶，饱和度高、像素多的桶优先，取前 4 个。
/// 亮度压到中低区间，保证上面的白字看得清。
List<Color> _pick(ByteData data) {
  final sums = List.generate(
    13,
    (_) => [0.0, 0.0, 0.0, 0.0, 0.0],
  ); // r g b count score
  // 隔一个像素采样就够了
  for (var i = 0; i + 3 < data.lengthInBytes; i += 8) {
    if (data.getUint8(i + 3) < 128) continue;
    final c = Color.fromARGB(
      255,
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
    final hsv = HSVColor.fromColor(c);
    // 灰色单独放最后一个桶
    final bucket = hsv.saturation < 0.15 || hsv.value < 0.12
        ? 12
        : (hsv.hue / 30).floor() % 12;
    final s = sums[bucket];
    s[0] += c.r;
    s[1] += c.g;
    s[2] += c.b;
    s[3] += 1;
    s[4] += 0.25 + hsv.saturation * hsv.value;
  }
  final ranked = [
    for (var b = 0; b < 13; b++)
      if (sums[b][3] > 0) b,
  ]..sort((a, b) => sums[b][4].compareTo(sums[a][4]));
  final colors = [
    for (final b in ranked.take(4))
      Color.from(
        alpha: 1,
        red: sums[b][0] / sums[b][3],
        green: sums[b][1] / sums[b][3],
        blue: sums[b][2] / sums[b][3],
      ),
  ];
  if (colors.isEmpty) return fallbackPalette;
  // 颜色不够时用主色的深浅变体补齐
  while (colors.length < 4) {
    final hsl = HSLColor.fromColor(colors.first);
    colors.add(
      hsl.withLightness((hsl.lightness + 0.18 * colors.length) % 0.7).toColor(),
    );
  }
  return [
    for (final c in colors)
      () {
        final hsl = HSLColor.fromColor(c);
        return hsl
            .withLightness(hsl.lightness.clamp(0.22, 0.55))
            .withSaturation(min(1, hsl.saturation * 1.25))
            .toColor();
      }(),
  ];
}

/// Apple Music 式的流动背景：模糊封面三层不同速度旋转、整体轻微扭曲流动，再叠几团漂移的主色光斑，
/// 由 shaders/player_background.frag 一次画完整屏，30fps 刷新；暂停播放时停止流动。
class PlayerBackground extends StatefulWidget {
  const PlayerBackground({super.key, required this.art, required this.animate});

  final CoverArt? art;
  final bool animate;

  @override
  State<PlayerBackground> createState() => _PlayerBackgroundState();
}

/// 流动相位全局共用：拖动预览交给真正的播放页、重新打开播放页时都接着转，不从头开始。
double _sharedPhase = 0;

class _PlayerBackgroundState extends State<PlayerBackground>
    with TickerProviderStateMixin {
  /// 流动相位 0–1，一圈 60 秒。
  final _phase = ValueNotifier<double>(_sharedPhase);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..value = 1;
  late CoverArt? _from = widget.art;
  late CoverArt? _to = widget.art;

  /// 每个背景一个 shader 对象，只建一次，每帧只改参数。
  ui.FragmentShader? _shader;

  final _shaderReady = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ticker.start();
    if (_program == null) {
      _loadProgram().then((_) {
        if (mounted) {
          _shaderReady.value++;
        }
      }, onError: (_) {});
    }
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _last;
    if (dt < const Duration(milliseconds: 33)) return;
    _last = elapsed;
    _phase.value = _sharedPhase = (_sharedPhase + dt.inMicroseconds / 60e6) % 1;
  }

  @override
  void didUpdateWidget(PlayerBackground old) {
    super.didUpdateWidget(old);
    if (!identical(old.art, widget.art)) {
      _from = _fade.value < 0.5 ? _from : _to;
      _to = widget.art;
      _fade.forward(from: 0);
    }
    if (widget.animate && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.animate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _fade.dispose();
    _phase.dispose();
    _shaderReady.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BackgroundPainter(
          this,
          MediaQuery.maybeDevicePixelRatioOf(context) ??
              View.of(context).devicePixelRatio,
        ),
        // 每帧都变，告诉引擎别尝试光栅缓存
        willChange: true,
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.s, this.pixelRatio)
    : super(repaint: Listenable.merge([s._phase, s._fade, s._shaderReady]));

  final _PlayerBackgroundState s;
  final double pixelRatio;

  static final _paint = Paint();
  static final _imagePaint = Paint()..filterQuality = FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = Curves.easeInOut.transform(s._fade.value);
    final full = Offset.zero & size;
    final program = _program;
    if (program == null) {
      // shader 还没加载好（通常只有冷启动后第一次打开播放页的头几帧），先铺主色
      final c = HSLColor.fromColor(
        Color.lerp(s._from?.palette.first, s._to?.palette.first, t) ??
            fallbackPalette.first,
      );
      canvas.drawRect(
        full,
        _paint..color = c.withLightness(c.lightness * 0.6).toColor(),
      );
      return;
    }
    final shader = s._shader ??= program.fragmentShader();
    if (!Platform.isWindows) {
      paintShader(
        canvas,
        size,
        shader,
        _paint,
        s._from,
        s._to,
        s._phase.value,
        t,
      );
      return;
    }
    // Windows / Skia 会为转场中的裁剪和透明度组合另编译背景 shader。
    // 按窗口像素比先绘成纹理，转场只合成图片，复用已经预热的背景程序。
    final recorder = ui.PictureRecorder();
    final imageCanvas = Canvas(recorder)..scale(pixelRatio);
    paintShader(
      imageCanvas,
      size,
      shader,
      _paint,
      s._from,
      s._to,
      s._phase.value,
      t,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (size.width * pixelRatio).ceil(),
      (size.height * pixelRatio).ceil(),
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      full,
      _imagePaint,
    );
    image.dispose();
    picture.dispose();
  }

  static void paintShader(
    Canvas canvas,
    Size size,
    ui.FragmentShader shader,
    Paint paint,
    CoverArt? fromArt,
    CoverArt? toArt,
    double phase,
    double t,
  ) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, _artSize + 0.0)
      ..setFloat(3, phase * 2 * pi)
      ..setFloat(4, t);
    final from = fromArt?.palette ?? fallbackPalette;
    final to = toArt?.palette ?? fallbackPalette;
    for (var i = 0; i < 4; i++) {
      final c = Color.lerp(from[i], to[i], t)!;
      shader
        ..setFloat(5 + i * 3, c.r)
        ..setFloat(6 + i * 3, c.g)
        ..setFloat(7 + i * 3, c.b);
    }
    shader
      // 硬件只做双线性，shader 里再拼成双三次
      ..setImageSampler(
        0,
        fromArt?.blurred ?? _fallbackImage,
        filterQuality: FilterQuality.low,
      )
      ..setImageSampler(
        1,
        toArt?.blurred ?? _fallbackImage,
        filterQuality: FilterQuality.low,
      );
    canvas.drawRect(Offset.zero & size, paint..shader = shader);
    paint.shader = null;
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) =>
      old.s != s || old.pixelRatio != pixelRatio;
}
