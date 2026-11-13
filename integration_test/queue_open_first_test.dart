import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/ui/player_page.dart';
import 'package:kanade/ui/player_route.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 窄屏播放页上滑翻到队列再按返回翻回来，连做几轮，看第一次是否比后面卡。第一轮抓时间线，列出最长的事件。
/// flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/queue_open_first_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('队列首次翻开', (tester) async {
    Future<void> wait(int ms) =>
        tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    final (_, nav) = await launchWithSong(
      tester,
      setup: () => windowManager.setSize(const Size(430, 900)),
    );
    unawaited(nav.push(PlayerRoute()));
    await wait(2500);
    final page = tester.getRect(find.byType(PlayerPage));
    final report = StringBuffer();
    double ms(Duration d) => d.inMicroseconds / 1000;

    Future<void> measure(String name, Future<void> Function() run) async {
      final frames = <FrameTiming>[];
      void onTimings(List<FrameTiming> t) => frames.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(onTimings);
      await run();
      await wait(300);
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
      final worst = [...frames]
        ..sort((a, b) => b.totalSpan.compareTo(a.totalSpan));
      report.writeln(
        '$name: frames ${frames.length}, >16.7ms ${frames.where((f) => ms(f.totalSpan) > 16.7).length}, '
        'slowBuild ${[for (final (i, f) in frames.indexed)
          if (ms(f.buildDuration) > 3) '#$i ${ms(f.buildDuration).toStringAsFixed(1)}'].join(' ')}, worst '
        '${worst.take(4).map((f) => 'total ${ms(f.totalSpan).toStringAsFixed(1)}/build ${ms(f.buildDuration).toStringAsFixed(1)}/raster ${ms(f.rasterDuration).toStringAsFixed(1)}').join(', ')}',
      );
    }

    Future<void> swipeUp() async {
      final g = await tester.startGesture(page.center);
      var time = Duration.zero;
      for (var i = 0; i < 12; i++) {
        time += const Duration(milliseconds: 16);
        await g.moveBy(const Offset(0, -30), timeStamp: time);
        await wait(16);
      }
      await g.up(timeStamp: time + const Duration(milliseconds: 16));
      await wait(800);
    }

    for (var i = 0; i < 3; i++) {
      if (i == 0) {
        await binding.traceAction(
          () => measure('open$i', swipeUp),
          reportKey: 'open',
        );
        final data = binding.reportData!.remove('open') as Map;
        final events = ((data['traceEvents'] ?? const []) as List).cast<Map>();
        final open = <String, List<Map>>{};
        final spans = <(double, String)>[];
        for (final e in events) {
          final tid = '${e['tid']}';
          final ts = (e['ts'] as num? ?? 0).toDouble();
          if (e['ph'] == 'X') {
            spans.add((
              (e['dur'] as num? ?? 0).toDouble() / 1000,
              '${e['name']} tid=$tid',
            ));
          } else if (e['ph'] == 'B') {
            (open[tid] ??= []).add(e);
          } else if (e['ph'] == 'E' && (open[tid]?.isNotEmpty ?? false)) {
            final b = open[tid]!.removeLast();
            spans.add((
              (ts - (b['ts'] as num).toDouble()) / 1000,
              '${b['name']} tid=$tid depth=${open[tid]!.length}',
            ));
          }
        }
        spans.sort((a, b) => b.$1.compareTo(a.$1));
        report.writeln('  top spans:');
        for (final s in spans.where((s) => s.$1 > 3).take(40)) {
          report.writeln('    ${s.$1.toStringAsFixed(1)}ms ${s.$2}');
        }
      } else {
        await measure('open$i', swipeUp);
      }
      await measure('back$i', () async {
        await nav.maybePop();
        await wait(800);
      });
    }
    // ignore: avoid_print
    print('QUEUE OPEN FIRST\n$report');
    expect(find.byType(PlayerPage), findsOneWidget);
  });
}
