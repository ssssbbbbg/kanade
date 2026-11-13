import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/l10n/app_localizations.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/ui/desktop_queue_popup.dart';
import 'package:kanade/ui/queue_list.dart';
import 'package:provider/provider.dart';

Song _song(String mid) => Song(
  id: 0,
  mid: mid,
  name: 'song-$mid',
  singers: const [],
  albumMid: '',
  albumName: '',
  durationSecs: 200,
  mediaMid: mid,
  coverUrl: '',
  vip: false,
  hasHq: false,
  hasFlac: false,
  mvVid: '',
);

class _Player extends ChangeNotifier implements PlayerController {
  @override
  List<Song> queue = [for (final m in 'abcde'.split('')) _song(m)];

  @override
  int index = 1;

  @override
  // 正在播放时音柱一直在跳，pumpAndSettle 等不到停
  bool playing = false;

  @override
  Song? get current => index >= 0 ? queue[index] : null;

  @override
  Future<void> playAt(int i) async {
    index = i;
    notifyListeners();
  }

  @override
  Future<void> removeAt(int i) async {
    final (q, n) = removeFromQueue(queue, index, i);
    queue = q;
    index = n;
    notifyListeners();
  }

  @override
  void moveQueue(int from, int to) {
    final (q, n) = moveInQueue(queue, index, from, to);
    queue = q;
    index = n;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<String> _mids(List<Song> q) => [for (final s in q) s.mid];

void main() {
  testWidgets('队列按钮展开成弹窗，可以删除、拖动，Esc 收起', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final player = _Player();
    addTearDown(player.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerController>.value(
        value: player,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Stack(
              children: [
                // 页面里已经有控件拿着焦点，弹窗也要收得到 Esc
                TextField(autofocus: true),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: DesktopQueueButton(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('接下来播放'), findsNothing);
    await tester.tap(find.byType(DesktopQueueButton));
    await tester.pumpAndSettle();
    expect(find.text('接下来播放'), findsOneWidget);
    expect(find.text('song-a'), findsOneWidget);

    // 弹窗在按钮上方，右边对齐，没有出窗口
    final popup = tester.getRect(find.text('接下来播放'));
    final button = tester.getRect(find.byType(DesktopQueueButton));
    expect(popup.bottom, lessThan(button.top));
    expect(popup.top, greaterThan(0));

    // 鼠标移到一行上才出现移除和拖动手柄
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('song-c')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(_mids(player.queue), ['a', 'b', 'd', 'e']);
    expect(player.current!.mid, 'b');

    // 把 a 拖到最后
    await mouse.moveTo(tester.getCenter(find.text('song-a')));
    await tester.pumpAndSettle();
    final handle = find.byIcon(Icons.drag_indicator_rounded);
    expect(handle, findsOneWidget);
    final drag = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 20; i++) {
      await drag.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(_mids(player.queue), ['b', 'd', 'e', 'a']);
    expect(player.current!.mid, 'b');

    // 点一首播放
    await tester.tap(find.text('song-e'));
    await tester.pumpAndSettle();
    expect(player.current!.mid, 'e');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('接下来播放'), findsNothing);

    // 点弹窗外面也收起
    await tester.tap(find.byType(DesktopQueueButton));
    await tester.pumpAndSettle();
    expect(find.text('接下来播放'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('接下来播放'), findsNothing);
  });

  testWidgets('打开时当前这首在第二行', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final player = _Player()
      ..queue = [for (var i = 0; i < 30; i++) _song('$i')]
      ..index = 15;
    addTearDown(player.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerController>.value(
        value: player,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: DesktopQueueButton(color: Colors.grey),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DesktopQueueButton));
    await tester.pumpAndSettle();
    final first = tester.getRect(find.byType(QueueTile).first);
    final current = tester.getRect(
      find.ancestor(of: find.text('song-15'), matching: find.byType(QueueTile)),
    );
    expect(current.top - first.top, QueueList.extent);
    expect(
      tester.widget<QueueTile>(find.byType(QueueTile).first).song.mid,
      '14',
    );
  });
}
