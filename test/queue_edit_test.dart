import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/src/rust/api/types.dart';

Song _song(String mid) => Song(
  id: 0,
  mid: mid,
  name: mid,
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

List<String> _mids(List<Song> q) => [for (final s in q) s.mid];

void main() {
  final queue = [_song('a'), _song('b'), _song('c'), _song('d')];

  group('removeFromQueue', () {
    test('删当前歌前面的，当前下标前移', () {
      final (q, i) = removeFromQueue(queue, 2, 0);
      expect(_mids(q), ['b', 'c', 'd']);
      expect(q[i].mid, 'c');
    });

    test('删当前歌后面的，当前下标不变', () {
      final (q, i) = removeFromQueue(queue, 1, 3);
      expect(_mids(q), ['a', 'b', 'c']);
      expect(q[i].mid, 'b');
    });

    test('删当前这首，指向原来的下一首', () {
      final (q, i) = removeFromQueue(queue, 1, 1);
      expect(q[i].mid, 'c');
    });

    test('删最后一首且正在放它，回到开头', () {
      final (q, i) = removeFromQueue(queue, 3, 3);
      expect(q[i].mid, 'a');
    });

    test('删空了下标是 -1', () {
      final (q, i) = removeFromQueue([_song('a')], 0, 0);
      expect(q, isEmpty);
      expect(i, -1);
    });
  });

  group('moveInQueue', () {
    test('挪当前这首，下标跟着走', () {
      final (q, i) = moveInQueue(queue, 1, 1, 3);
      expect(_mids(q), ['a', 'c', 'd', 'b']);
      expect(q[i].mid, 'b');
    });

    test('从前面挪到当前歌后面，当前下标前移', () {
      final (q, i) = moveInQueue(queue, 2, 0, 3);
      expect(_mids(q), ['b', 'c', 'd', 'a']);
      expect(q[i].mid, 'c');
    });

    test('从后面挪到当前歌前面，当前下标后移', () {
      final (q, i) = moveInQueue(queue, 1, 3, 0);
      expect(_mids(q), ['d', 'a', 'b', 'c']);
      expect(q[i].mid, 'b');
    });

    test('挪到当前歌的位置上，当前歌被挤到后面', () {
      final (q, i) = moveInQueue(queue, 2, 3, 2);
      expect(_mids(q), ['a', 'b', 'd', 'c']);
      expect(q[i].mid, 'c');
    });

    test('不跨过当前歌，当前下标不变', () {
      final (q, i) = moveInQueue(queue, 0, 1, 3);
      expect(_mids(q), ['a', 'c', 'd', 'b']);
      expect(i, 0);
    });
  });
}
