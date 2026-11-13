import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 全应用唯一的配色：黑白灰 + 柠檬绿抗色，不随封面变，也不给用户改。
/// 抗色只用在播放按钮、进度条、正在播放、红心、VIP、分类下划线上；选中态用白底黑字。
abstract final class KanadeColors {
  static const lime = Color(0xFFD4FF3A);

  /// 亮色模式下柠檬绿当文字看不清，换深一号的橄榄绿。
  static const olive = Color(0xFF4D6400);
}

ColorScheme _scheme(Brightness b) {
  if (b == Brightness.dark) {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: KanadeColors.lime,
      onPrimary: Colors.black,
      primaryContainer: KanadeColors.lime,
      onPrimaryContainer: Colors.black,
      // 选中态（导航指示器、tonal 按钮）：白底黑字
      secondary: Colors.white,
      onSecondary: Colors.black,
      secondaryContainer: Colors.white,
      onSecondaryContainer: Colors.black,
      tertiary: KanadeColors.lime,
      onTertiary: Colors.black,
      error: Color(0xFFFF5A4E),
      onError: Colors.black,
      surface: Colors.black,
      onSurface: Colors.white,
      onSurfaceVariant: Color(0xFF9A9A9A),
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Color(0xFF0A0A0A),
      surfaceContainer: Color(0xFF111111),
      surfaceContainerHigh: Color(0xFF1C1C1C),
      surfaceContainerHighest: Color(0xFF262626),
      outline: Color(0xFF3A3A3A),
      outlineVariant: Color(0xFF242424),
      inverseSurface: Colors.white,
      onInverseSurface: Colors.black,
      inversePrimary: KanadeColors.olive,
      surfaceTint: Colors.transparent,
    );
  }
  return const ColorScheme(
    brightness: Brightness.light,
    primary: KanadeColors.olive,
    onPrimary: Colors.white,
    primaryContainer: KanadeColors.lime,
    onPrimaryContainer: Colors.black,
    secondary: Colors.black,
    onSecondary: Colors.white,
    secondaryContainer: Colors.black,
    onSecondaryContainer: Colors.white,
    tertiary: KanadeColors.olive,
    onTertiary: Colors.white,
    error: Color(0xFFC62828),
    onError: Colors.white,
    surface: Colors.white,
    onSurface: Colors.black,
    onSurfaceVariant: Color(0xFF6B6B6B),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF7F7F7),
    surfaceContainer: Color(0xFFF2F2F2),
    surfaceContainerHigh: Color(0xFFEAEAEA),
    surfaceContainerHighest: Color(0xFFE0E0E0),
    outline: Color(0xFFC4C4C4),
    outlineVariant: Color(0xFFE2E2E2),
    inverseSurface: Colors.black,
    onInverseSurface: Colors.white,
    inversePrimary: KanadeColors.lime,
    surfaceTint: Colors.transparent,
  );
}

ThemeData buildTheme(Brightness b) {
  final scheme = _scheme(b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
      selectedColor: scheme.secondaryContainer,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: scheme.onSecondaryContainer,
      ),
      showCheckmark: false,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      subtitleTextStyle: TextStyle(
        fontSize: 13,
        color: scheme.onSurfaceVariant,
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      thumbColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    // 二级页面从右边推进来，旧页面往左让一点；手机上从左边缘右滑能返回
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values)
          p: const CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
