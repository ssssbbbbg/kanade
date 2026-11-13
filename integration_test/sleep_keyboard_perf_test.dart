import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/home_shell.dart';
import 'package:kanade/ui/player_page.dart';
import 'package:kanade/ui/sleep_timer_sheet.dart';

import 'harness.dart';

/// 定时关闭弹窗里键盘弹起 / 收起时逐帧记录构建和渲染耗时：
/// 键盘每一帧都改 viewInsets，看底下哪些页面跟着重建、重排。
/// flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/sleep_keyboard_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('定时关闭键盘动画性能', (tester) async {
    final view = tester.view;
    // 手机布局：竖屏、窄于 800
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 2.75;
    final (_, nav) = await launchWithSong(tester);
    final report = StringBuffer();

    Future<void> run(String name) async {
      final idle = await tester.runAsync(() => _keyboard(view, move: false));
      report.writeln('$name-idle  $idle');
      for (var round = 0; round < 2; round++) {
        final r = await tester.runAsync(() => _keyboard(view));
        report.writeln('$name#$round  $r');
      }
    }

    // 只有弹窗，底下是首页
    unawaited(showSleepTimer(nav.context));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await run('home');
    nav.pop();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));

    // 播放页上的弹窗
    unawaited(nav.push(PlayerPage.route()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1500)));
    unawaited(showSleepTimer(nav.context));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await run('player');

    // ignore: avoid_print
    print('\n===== PERF =====\n$report================');
    binding.reportData = {'perf': report.toString()};
  });
}

/// 模拟键盘弹起再收起：每帧改一次底部 inset，和系统键盘动画一样。
Future<String> _keyboard(TestFlutterView view, {bool move = true}) async {
  final timings = <FrameTiming>[];
  final start = Timeline.now;
  void onTimings(List<FrameTiming> t) =>
      timings.addAll(t.where((f) => f.timestampInMicroseconds(FramePhase.buildStart) >= start));
  SchedulerBinding.instance.addTimingsCallback(onTimings);
  // debug 下按所在页面分组数重建的组件，和平台快慢无关
  final where = <String, int>{};
  final types = <String, int>{};
  // 父组件这一帧没重建、自己却重建了的：是它们把整棵子树带着重建
  final roots = <String, int>{};
  var frame = Duration.zero;
  final built = <Element>{};
  if (kDebugMode) {
    debugOnRebuildDirtyWidget = (e, _) {
      final now = SchedulerBinding.instance.currentFrameTimeStamp;
      if (now != frame) {
        frame = now;
        built.clear();
      }
      Element? parent;
      e.visitAncestorElements((p) {
        parent = p;
        return false;
      });
      if (!built.contains(parent)) {
        final chain = <String>[];
        e.visitAncestorElements((p) {
          chain.add('${p.widget.runtimeType}');
          return chain.length < 4;
        });
        final k = '${e.widget.runtimeType} < ${chain.join(' < ')}';
        roots[k] = (roots[k] ?? 0) + 1;
      }
      built.add(e);
      final page = e.findAncestorWidgetOfExactType<PlayerPage>() != null
          ? 'player'
          : e.findAncestorWidgetOfExactType<HomeShell>() != null
          ? 'home'
          : e.findAncestorWidgetOfExactType<BottomSheet>() != null
          ? 'sheet'
          : 'other';
      where[page] = (where[page] ?? 0) + 1;
      final k = '$page:${e.widget.runtimeType}';
      types[k] = (types[k] ?? 0) + 1;
    };
  }
  const steps = 20;
  const height = 900.0;
  for (final up in [true, false]) {
    for (var i = 1; i <= steps; i++) {
      final t = Curves.easeOutCubic.transform(i / steps);
      if (move) view.viewInsets = FakeViewPadding(bottom: height * (up ? t : 1 - t));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  SchedulerBinding.instance.removeTimingsCallback(onTimings);
  debugOnRebuildDirtyWidget = null;
  final top = (types.entries.toList()..sort((a, b) => b.value - a.value)).take(25).map((e) => '${e.key}=${e.value}');
  final rootTop = (roots.entries.toList()..sort((a, b) => b.value - a.value)).take(30).map((e) => '      ${e.value}  ${e.key}');
  final counts = kDebugMode ? '\n    rebuilds $where\n    ${top.join(', ')}\n    roots:\n${rootTop.join('\n')}\n' : '';

  int us(Duration d) => d.inMicroseconds;
  final builds = timings.map((t) => us(t.buildDuration)).toList()..sort();
  final rasters = timings.map((t) => us(t.rasterDuration)).toList()..sort();
  String p(List<int> v, double q) => v.isEmpty ? '-' : (v[((v.length - 1) * q).round()] / 1000).toStringAsFixed(1);
  final slow = timings.where((t) => t.totalSpan > const Duration(milliseconds: 17)).length;
  return 'frames ${timings.length}, slow $slow | build p50 ${p(builds, .5)} p90 ${p(builds, .9)} max ${p(builds, 1)}ms'
      ' | raster p50 ${p(rasters, .5)} p90 ${p(rasters, .9)} max ${p(rasters, 1)}ms$counts';
}
