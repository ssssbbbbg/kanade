import 'package:media_kit/media_kit.dart';

import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

/// 交给播放器的音源：本地缓存文件，或（经过边播边存中转的）在线地址。
/// 只管从哪儿取、坏了换哪档；什么时候取、结果过期没有，由 PlayerController 判断。
class AudioSource {
  const AudioSource._(this.mid, this.url, this.quality, {required this.cached});

  final String mid;
  final String url;
  final Quality quality;
  final bool cached;

  /// 先找本地缓存，没有再在线取链接（经 Rust 中转边播边存）；没网时用这首歌任一音质的缓存。
  /// 在线取链接期间 [stale] 变成 true 时返回 null；一个能用的都没有时抛出取链接的异常。
  static Future<AudioSource?> resolve(
    Song song,
    Quality q, {
    required bool Function() stale,
  }) async {
    final hit = api.getCachedAudio(mid: song.mid, quality: q);
    if (hit != null) return AudioSource._(song.mid, hit, q, cached: true);
    try {
      final u = await api.getSongUrl(
        mid: song.mid,
        mediaMid: song.mediaMid,
        quality: q,
      );
      if (stale()) return null;
      // 选的音质没有、降级拿到的那档之前缓存过
      final local = api.getCachedAudio(mid: song.mid, quality: u.quality);
      if (local != null) {
        return AudioSource._(song.mid, local, u.quality, cached: true);
      }
      final url = api.streamAudio(
        mid: song.mid,
        quality: u.quality,
        url: u.url,
        ekey: u.ekey,
      );
      return AudioSource._(song.mid, url, u.quality, cached: false);
    } catch (_) {
      if (stale()) return null;
      final any = api.getAnyCachedAudio(mid: song.mid);
      if (any != null) {
        return AudioSource._(song.mid, any.path, any.quality, cached: true);
      }
      rethrow;
    }
  }

  /// 普通音频在缓存关闭时直接使用 QQ 链接，在线地址要带 Referer。
  Media media({Duration? start}) => cached
      ? Media(url, start: start)
      : Media(
          url,
          httpHeaders: const {'Referer': 'https://y.qq.com/'},
          start: start,
        );

  Future<void>? waitUntilReady() =>
      !cached &&
          (quality == Quality.aicodec ||
              quality == Quality.dts ||
              quality == Quality.ra360)
      ? api.waitForDecodedAudio(url: url)
      : null;

  /// 这个音源播不了时下一次用哪档：缓存文件坏了就删掉，同一档重新在线取；
  /// 在线的降一档；已经是最低档时返回 null。
  Quality? fallback() {
    if (!cached) return api.lowerQuality(quality: quality);
    api.removeCachedAudio(mid: mid, quality: quality);
    return quality;
  }
}
