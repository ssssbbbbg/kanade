import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// 液态玻璃的统一参数，照搬 Hazuki 调好的那套（圆弧透镜 + 亮边 + 暗边）。
abstract final class KanadeGlass {
  static const double navigationControlHeight = 58;

  static final bool _isFlutterTest = Platform.environment.containsKey(
    'FLUTTER_TEST',
  );

  /// Windows 没有 shader image filter，用共享内容纹理做折射；
  /// 玻璃控件要放在 [backdropSource] 外面，否则会采样到自己。
  /// 纹理截下来先做一次真正的高斯模糊，和安卓 premium 的背景模糊一致；
  /// 玻璃 shader 自带的五点近似模糊会让背后的文字出重影。
  static Widget backdropScope({required Widget child, double blur = _blur}) =>
      Platform.isWindows
      ? GlassBackdropScope(blurSigma: blur, child: child)
      : child;

  static const double _blur = 2;

  static Widget backdropSource({
    required Widget child,
    Rect Function(Size size)? captureBounds,
  }) => Platform.isWindows
      ? GlassBackdropSource(captureBounds: captureBounds, child: child)
      : child;

  static GlassQuality get navigationQuality =>
      !_isFlutterTest &&
          !Platform.isWindows &&
          !Platform.isLinux &&
          ui.ImageFilter.isShaderFilterSupported
      ? GlassQuality.premium
      : GlassQuality.standard;

  static bool _usesPremiumRenderer(BuildContext context, GlassQuality quality) {
    final ceiling = GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality;
    return quality == GlassQuality.premium &&
        navigationQuality == GlassQuality.premium &&
        (ceiling == null || ceiling == GlassQuality.premium);
  }

  /// 宽圆弧透镜。premium 引擎的 bevel 以 3 倍基准像素计，72 ≈ 24 逻辑像素过渡。
  static LiquidGlassSettings surfaceSettings(
    BuildContext context, {
    GlassQuality quality = GlassQuality.standard,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final circularLens =
        _usesPremiumRenderer(context, quality) || Platform.isWindows;
    return LiquidGlassSettings(
      thickness: circularLens ? 72 : 10,
      blur: _blur,
      refractiveIndex: 1.18,
      lensModel: circularLens
          ? GlassLensModel.circularArc
          : GlassLensModel.spherical,
      refractionAmount: circularLens ? 24 : 0,
      chromaticAberration: 0,
      lightAngle: 2.356194490192345,
      lightIntensity: circularLens ? 0.65 : 0.9,
      fresnelStrength: 1.2,
      edgeAbsorption: isDark ? 0.14 : 0.12,
      rimShade: circularLens ? (isDark ? 0.45 : 0.65) : 0,
      rimShadeEnds: isDark ? 0 : 0.2,
      rimLight: circularLens ? (isDark ? 1.05 : 0.85) : 0,
      ambientStrength: 0,
      saturation: 1.15,
      glassColor: isDark ? const Color(0x20141820) : const Color(0x14FFFFFF),
      bodyMode: GlassBodyMode.clear,
      glowIntensity: 0,
      shadowElevation: 0.35,
    );
  }

  /// 导航栏里滑动的那颗透镜。栏本身已经是玻璃，里面别再放玻璃控件。
  static const indicatorSettings = LiquidGlassSettings(
    thickness: 30,
    blur: 0,
    refractiveIndex: 1.15,
    lensModel: GlassLensModel.circularArcWithDepth,
    refractionAmount: 14,
    chromaticAberration: 0.3,
    lightIntensity: 0.75,
    fresnelStrength: 1,
    edgeAbsorption: 0.05,
    rimShade: 0.35,
    rimLight: 0.75,
    ambientStrength: 0,
    saturation: 1,
    bodyMode: GlassBodyMode.clear,
    glowIntensity: 0,
    shadowElevation: 0,
  );

  /// 着色压得很淡，让后面的封面透得出来。
  static LiquidGlassSettings navigationSettings(BuildContext context) =>
      surfaceSettings(context, quality: navigationQuality).copyWith(
        glassColor: Theme.of(context).colorScheme.surfaceContainer
            .withValues(alpha: 0.16),
      );

  static Future<void> initialize() async {
    await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
    if (Platform.isWindows) {
      // 窗口首帧完成后再预热实际 GPU 绘制，不只把 shader 文件加载进内存。
      unawaited(
        WidgetsBinding.instance.waitUntilFirstFrameRasterized.then(
          (_) => LightweightLiquidGlass.warmUpRendering(),
        ),
      );
    }
  }

  static Widget wrap({required Widget child}) => LiquidGlassWidgets.wrap(
    brightnessResolver: Theme.maybeBrightnessOf,
    respectSystemAccessibility: true,
    // 自适应画质的测速会把滚动、解码图片的帧也算进去，容易把透镜降级成普通毛玻璃
    adaptiveQuality: false,
    theme: GlassThemeData.simple(quality: GlassQuality.standard),
    child: child,
  );
}

/// 详情页（歌单、专辑）：不要顶栏，左上角浮一颗玻璃返回钮，内容从它下面滚过。
/// 内容的第一项要自己在顶部留出按钮的高度（[topInset]）。
class GlassBackScaffold extends StatelessWidget {
  const GlassBackScaffold({super.key, required this.body});

  static const topInset = 60.0;

  final Widget body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: KanadeGlass.backdropScope(
        child: Stack(
          children: [
            Positioned.fill(
              child: KanadeGlass.backdropSource(
                // Only the floating back button samples this source. Keep its
                // lens/blur margin without copying the whole fullscreen list.
                captureBounds: (_) => Rect.fromLTWH(
                  0,
                  0,
                  112,
                  MediaQuery.paddingOf(context).top + 112,
                ),
                // Material rather than ColoredBox so list tiles in the body keep their ink.
                child: Material(color: scheme.surface, child: body),
              ),
            ),
            Positioned(
              left: 16,
              top: MediaQuery.paddingOf(context).top + 8,
              child: GlassIconButton(
                useOwnLayer: true,
                settings: KanadeGlass.navigationSettings(context),
                quality: KanadeGlass.navigationQuality,
                semanticLabel: MaterialLocalizations.of(context)
                    .backButtonTooltip,
                onPressed: () async {
                  final nav = Navigator.of(context);
                  // 套在 PlayerBarPage 里的第一页：里面那层退不了，交给外面那层
                  final outer = nav.context
                      .findAncestorStateOfType<NavigatorState>();
                  if (!await nav.maybePop()) outer?.maybePop();
                },
                icon: Icon(Icons.arrow_back_rounded, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
