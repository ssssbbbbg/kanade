import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/player/audio_source.dart';
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/src/rust/frb_generated.dart';

/// 假的 Rust 层：本地缓存是一张表，在线取链接按 [served] 降级或抛出 [urlError]。
class _FakeApi implements RustLibApi {
  final cache = <(String, Quality), String>{};
  final served = <Quality, Quality>{};
  Object? urlError;
  String? sourceKey;
  String? streamKey;
  final removed = <(String, Quality)>[];
  final urlRequests = <Quality>[];
  final readinessRequests = <String>[];
  Completer<void>? decoded;

  void reset() {
    cache.clear();
    served.clear();
    urlError = null;
    sourceKey = streamKey = null;
    removed.clear();
    urlRequests.clear();
    readinessRequests.clear();
    decoded = null;
  }

  @override
  String? crateApiMusicGetCachedAudio({required String mid, required Quality quality}) => cache[(mid, quality)];

  @override
  CachedAudio? crateApiMusicGetAnyCachedAudio({required String mid}) {
    final hit = cache.entries.where((e) => e.key.$1 == mid).firstOrNull;
    return hit == null ? null : CachedAudio(path: hit.value, quality: hit.key.$2);
  }

  @override
  Future<SongUrl> crateApiMusicGetSongUrl({required String mid, required String mediaMid, required Quality quality}) async {
    urlRequests.add(quality);
    final error = urlError;
    if (error != null) throw error;
    return SongUrl(
      url: 'https://qq.example/$mediaMid',
      quality: served[quality] ?? quality,
      ekey: sourceKey,
    );
  }

  @override
  String crateApiMusicStreamAudio({
    required String mid,
    required Quality quality,
    required String url,
    String? ekey,
  }) {
    streamKey = ekey;
    return 'http://127.0.0.1:1/$mid/${quality.name}';
  }

  @override
  Future<void> crateApiMusicWaitForDecodedAudio({required String url}) {
    readinessRequests.add(url);
    return decoded!.future;
  }

  @override
  void crateApiMusicRemoveCachedAudio({required String mid, required Quality quality}) {
    removed.add((mid, quality));
    cache.remove((mid, quality));
  }

  @override
  Quality? crateApiMusicLowerQuality({required Quality quality}) => switch (quality) {
        Quality.lossless => Quality.high,
        Quality.high => Quality.standard,
        _ => null,
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _song = Song(
  id: 1,
  mid: 'm1',
  name: 'song',
  singers: [],
  albumMid: '',
  albumName: '',
  durationSecs: 200,
  mediaMid: 'media1',
  coverUrl: '',
  vip: false,
  hasHq: true,
  hasFlac: true,
  mvVid: '',
);

bool _fresh() => false;

void main() {
  final fake = _FakeApi();
  // 每个测试文件只能初始化一次
  setUpAll(() => RustLib.initMock(api: fake));
  setUp(fake.reset);

  test('选中的音质有缓存：直接用，不在线取', () async {
    fake.cache[('m1', Quality.lossless)] = 'C:/cache/a.flac';
    final src = (await AudioSource.resolve(_song, Quality.lossless, stale: _fresh))!;
    expect((src.url, src.quality, src.cached), ('C:/cache/a.flac', Quality.lossless, true));
    expect(fake.urlRequests, isEmpty);
  });

  test('没缓存：在线取，经本机中转', () async {
    final src = (await AudioSource.resolve(_song, Quality.high, stale: _fresh))!;
    expect((src.url, src.quality, src.cached), ('http://127.0.0.1:1/m1/high', Quality.high, false));
    expect(fake.urlRequests, [Quality.high]);
  });

  test('加密音源的密钥交给本机中转，播放器只拿到回环地址', () async {
    fake.sourceKey = 'test-ekey';
    final src = (await AudioSource.resolve(
      _song,
      Quality.high,
      stale: _fresh,
    ))!;
    expect(
      (src.url, src.quality),
      ('http://127.0.0.1:1/m1/high', Quality.high),
    );
    expect(fake.streamKey, 'test-ekey');
  });

  test('在线降级拿到的那档之前缓存过：用缓存', () async {
    fake.served[Quality.lossless] = Quality.high;
    fake.cache[('m1', Quality.high)] = 'C:/cache/a.m4a';
    final src = (await AudioSource.resolve(_song, Quality.lossless, stale: _fresh))!;
    expect((src.url, src.quality, src.cached), ('C:/cache/a.m4a', Quality.high, true));
  });

  test('整曲解码档位等待 Rust 准备好，普通音源直接打开', () async {
    final regular = (await AudioSource.resolve(
      _song,
      Quality.high,
      stale: _fresh,
    ))!;
    expect(regular.waitUntilReady(), isNull);
    for (final quality in [Quality.aicodec, Quality.dts]) {
      final decoded = fake.decoded = Completer<void>();
      final source = (await AudioSource.resolve(
        _song,
        quality,
        stale: _fresh,
      ))!;
      final ready = source.waitUntilReady()!;
      expect(fake.readinessRequests.last, source.url);
      final completion = expectLater(ready, completes);
      decoded.complete();
      await completion;
    }
  });

  test('取链接失败：用这首歌任一音质的缓存，都没有就抛出原来的错误', () async {
    final error = Exception('offline');
    fake.urlError = error;
    fake.cache[('m1', Quality.standard)] = 'C:/cache/a.mp3';
    final src = (await AudioSource.resolve(_song, Quality.lossless, stale: _fresh))!;
    expect((src.url, src.quality, src.cached), ('C:/cache/a.mp3', Quality.standard, true));

    fake.cache.clear();
    await expectLater(AudioSource.resolve(_song, Quality.lossless, stale: _fresh), throwsA(same(error)));
  });

  test('取链接期间切了歌：返回 null', () async {
    expect(await AudioSource.resolve(_song, Quality.high, stale: () => true), isNull);
    fake.urlError = Exception('offline');
    fake.cache[('m1', Quality.standard)] = 'C:/cache/a.mp3';
    expect(await AudioSource.resolve(_song, Quality.high, stale: () => true), isNull);
  });

  test('缓存播不了：删掉缓存，同一档重新在线取', () async {
    fake.cache[('m1', Quality.high)] = 'C:/cache/a.m4a';
    final src = (await AudioSource.resolve(_song, Quality.high, stale: _fresh))!;
    expect(src.fallback(), Quality.high);
    expect(fake.removed, [('m1', Quality.high)]);
  });

  test('在线的播不了：降一档，降到底返回 null，不删缓存', () async {
    final high = (await AudioSource.resolve(_song, Quality.high, stale: _fresh))!;
    expect(high.fallback(), Quality.standard);
    final standard = (await AudioSource.resolve(_song, Quality.standard, stale: _fresh))!;
    expect(standard.fallback(), isNull);
    expect(fake.removed, isEmpty);
  });

  test('在线地址带 Referer，缓存文件不带', () async {
    final online = (await AudioSource.resolve(_song, Quality.high, stale: _fresh))!;
    expect(online.media().httpHeaders, {'Referer': 'https://y.qq.com/'});
    fake.cache[('m1', Quality.high)] = 'C:/cache/a.m4a';
    final local = (await AudioSource.resolve(_song, Quality.high, stale: _fresh))!;
    expect(local.media(start: const Duration(seconds: 5)).httpHeaders, isNull);
    expect(local.media(start: const Duration(seconds: 5)).start, const Duration(seconds: 5));
  });
}
