import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/l10n/l10n_ext.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/ui/discover_page.dart';
import 'package:kanade/ui/song_list_page.dart';

import 'harness.dart';

/// 歌单页点搜索：头部收起、按钮行收起，同时键盘弹起。逐帧记录耗时，
/// debug 下再按“谁把子树带着重建”统计，看是哪些页面跟着键盘逐帧重建。
/// flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/playlist_search_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('歌单页搜索转场性能', (tester) async {
    final view = tester.view;
    // 手机布局：竖屏、窄于 960
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 2.75;
    Future<void> wait(int ms) =>
        tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await launchWithSong(tester);
    // 不用登录：拿榜单的歌搭一个可搜索的歌单页，和真正的歌单页是同一套页面
    final songs = (await tester.runAsync(() async {
      final top = (await api.getToplists()).first.lists.first;
      return (await api.getToplistDetail(
        topId: top.topId,
        period: top.period,
      )).songs;
    }))!;
    final ListData data = (
      title: '测试歌单',
      cover: songs.first.coverUrl,
      creator: 'kanade',
      period: '',
      description: '用来测搜索转场的歌单',
      songs: songs,
      owned: null,
    );
    unawaited(
      Navigator.of(tester.element(find.byType(DiscoverPage))).push(
        MaterialPageRoute<void>(
          builder: (_) => SongListPage(
            title: data.title,
            searchable: true,
            load: () async => data,
          ),
        ),
      ),
    );
    await wait(4000);
    final l = AppLocalizations.of(tester.element(find.byType(SongListPage)));

    final report = StringBuffer();
    for (final keyboard in [false, true, true]) {
      final r = await tester.runAsync(
        () => _measure(view, l.filterSongsHint, keyboard: keyboard),
      );
      report.writeln('${keyboard ? 'keyboard' : 'no-kb   '}  $r');
      // 退出搜索，等键盘和动画都收完
      final cancel = find.text(l.cancel);
      if (cancel.evaluate().isNotEmpty) {
        await tester.runAsync(() async {
          (tester.widget<TextButton>(
            find.ancestor(of: cancel, matching: find.byType(TextButton)),
          )).onPressed!();
          await Future<void>.delayed(const Duration(milliseconds: 1000));
        });
      }
    }

    // ignore: avoid_print
    print('\n===== PERF =====\n$report================');
    binding.reportData = {'perf': report.toString()};
  });
}

/// 点搜索按钮；[keyboard] 时同时模拟系统键盘弹起（每帧改一次底部 inset）。
Future<String> _measure(
  TestFlutterView view,
  String tooltip, {
  required bool keyboard,
}) async {
  final timings = <FrameTiming>[];
  final start = Timeline.now;
  void onTimings(List<FrameTiming> t) => timings.addAll(
    t.where((f) => f.timestampInMicroseconds(FramePhase.buildStart) >= start),
  );
  SchedulerBinding.instance.addTimingsCallback(onTimings);
  // 自己 setState 或依赖变了的组件（dirty）是源头；被它顺带重建的子树
  // （dirty 为 false，按深度优先紧跟在后面）算在它头上
  // 沿父链找这一帧的源头；找不到的是排版时才建的（列表、LayoutBuilder、持久头部），
  // 记成离它最近的那种组件
  final roots = <String, int>{};
  final dirtyRoots = <Element, String>{};
  var total = 0;
  var frame = Duration.zero;
  String chainOf(Element e, int n) {
    final chain = <String>['${e.widget.runtimeType}'];
    e.visitAncestorElements((p) {
      chain.add('${p.widget.runtimeType}');
      return chain.length < n;
    });
    return chain.join(' < ');
  }

  if (kDebugMode) {
    debugOnRebuildDirtyWidget = (e, builtOnce) {
      total++;
      final now = SchedulerBinding.instance.currentFrameTimeStamp;
      if (now != frame) {
        frame = now;
        dirtyRoots.clear();
      }
      String? key;
      if (e.dirty && builtOnce) {
        key = dirtyRoots[e] = chainOf(e, 6);
      } else {
        e.visitAncestorElements((p) {
          key = dirtyRoots[p];
          if (key != null) return false;
          final t = '${p.widget.runtimeType}';
          if (t.startsWith('Sliver') ||
              t.contains('LayoutBuilder') ||
              t == '_Theater') {
            key = 'layout: ${chainOf(p, 6)}';
            return false;
          }
          return true;
        });
      }
      key ??= 'unknown';
      roots[key!] = (roots[key] ?? 0) + 1;
    };
  }

  final button = find
      .byWidgetPredicate((w) => w is IconButton && w.tooltip == tooltip)
      .evaluate()
      .single;
  (button.widget as IconButton).onPressed!();
  const height = 900.0;
  for (var i = 1; i <= 20; i++) {
    final t = Curves.easeOutCubic.transform(i / 20);
    if (keyboard) view.viewInsets = FakeViewPadding(bottom: height * t);
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
  SchedulerBinding.instance.removeTimingsCallback(onTimings);
  debugOnRebuildDirtyWidget = null;
  if (keyboard) view.resetViewInsets();

  final rootTop = (roots.entries.toList()..sort((a, b) => b.value - a.value))
      .take(15)
      .map((e) => '      ${e.value}  ${e.key}');
  final counts = kDebugMode
      ? '\n    rebuilds $total\n    roots:\n${rootTop.join('\n')}\n'
      : '';
  int us(Duration d) => d.inMicroseconds;
  final builds = timings.map((t) => us(t.buildDuration)).toList()..sort();
  final rasters = timings.map((t) => us(t.rasterDuration)).toList()..sort();
  String p(List<int> v, double q) => v.isEmpty
      ? '-'
      : (v[((v.length - 1) * q).round()] / 1000).toStringAsFixed(1);
  final slow = timings
      .where((t) => t.totalSpan > const Duration(milliseconds: 17))
      .length;
  return 'frames ${timings.length}, slow $slow | build p50 ${p(builds, .5)} p90 ${p(builds, .9)} max ${p(builds, 1)}ms'
      ' | raster p50 ${p(rasters, .5)} p90 ${p(rasters, .9)} max ${p(rasters, 1)}ms$counts';
}
