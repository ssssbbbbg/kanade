import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/app.dart';
import 'package:kanade/l10n/l10n_ext.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/ui/comments_page.dart';
import 'package:kanade/ui/theme.dart';
import 'package:window_manager/window_manager.dart';

import 'harness.dart';

/// 只浏览：打开一首歌的评论页，切换推荐 / 最热 / 最新，往下翻页，再展开一条评论的回复。
/// 不点赞、不发评论。截图在 build/comments_frames。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('comment tabs page independently and replies load', (
    tester,
  ) async {
    final out = Directory('build/comments_frames')..createSync(recursive: true);
    Future<void> wait([int ms = 1800]) =>
        tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    Future<void> screenshot(String name) => tester.runAsync(() async {
      // ignore: invalid_use_of_protected_member
      final layer = tester.binding.renderViews.first.layer! as OffsetLayer;
      final image = await layer.toImage(
        Offset.zero & tester.view.physicalSize,
        pixelRatio: 1,
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
    Future<void> settle() async {
      await wait();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    int tiles() =>
        tester.widgetList(find.byType(CommentTile, skipOffstage: false)).length;

    await initTestApp();
    await windowManager.setSize(const Size(430, 900));
    await tester.pumpWidget(
      AppProviders(
        mediaSession: false,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(Brightness.dark),
          // 抓包笔记里的样本歌曲，评论两千多条，最新第一页有一条带图评论
          home: CommentsPage(
            title: 'River Flows in You',
            load: (sort, cursor) => api.getCommentFeed(
              target: CommentTarget.song,
              id: 121345659,
              sort: sort,
              cursor: cursor,
            ),
          ),
        ),
      ),
    );
    await settle();
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('最热'), findsOneWidget);
    expect(find.text('最新'), findsOneWidget);
    expect(find.byType(CommentTile), findsWidgets);
    await screenshot('1_default');

    await tester.tap(find.text('推荐'));
    await settle();
    expect(find.byType(CommentTile), findsWidgets);
    await screenshot('1b_recommended');

    // 左右滑动页面也能切换分类
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await settle();
    expect(find.byType(CommentTile), findsWidgets);
    await screenshot('1c_swiped_to_hot');
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await settle();

    // 最热：滚到底触发下一页，列表会变长
    await tester.tap(find.text('最热'));
    await settle();
    expect(find.byType(CommentTile), findsWidgets);
    await tester.fling(
      find.byType(ListView).last,
      const Offset(0, -6000),
      8000,
    );
    await settle();
    await tester.fling(
      find.byType(ListView).last,
      const Offset(0, -6000),
      8000,
    );
    await settle();
    await screenshot('2_hot_scrolled');

    // 最新：第一页里有带图评论
    await tester.tap(find.text('最新'));
    await settle();
    final picture = find.descendant(
      of: find.byType(CommentTile),
      matching: find.byType(ClipRRect),
    );
    await tester.scrollUntilVisible(
      picture,
      300,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 60,
    );
    await settle();
    await screenshot('3_latest_picture');
    await tester.tap(picture.first);
    await settle();
    await screenshot('4_picture_viewer');
    await tester.tapAt(const Offset(20, 20));
    await settle();

    // 切回最热：之前翻到的位置还在，再展开一条回复
    await tester.tap(find.text('最热'));
    await settle();
    await screenshot('5_hot_kept');
    final replies = find.textContaining('条回复');
    await tester.ensureVisible(replies.first);
    await settle();
    final before = tiles();
    await tester.tap(replies.first);
    await settle();
    expect(tiles(), greaterThan(before), reason: '回复面板应当列出回复');
    await screenshot('6_replies');
  });
}
