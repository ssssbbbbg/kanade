import 'dart:convert';

import '../data/song_json.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

/// 播放会话的存储格式；播放模式由控制器解释。
class PlayerSessionStore {
  static const _key = 'last_session';

  ({List<Song> queue, int index, String? mode})? read() {
    final raw = api.getPref(key: _key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final songs = [
        for (final s in m['queue'] as List)
          songFromJson(s as Map<String, dynamic>),
      ];
      final index = m['index'] as int;
      if (index < 0 || index >= songs.length) return null;
      return (
        queue: songs,
        index: index,
        mode: m['mode'] is String ? m['mode'] as String : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// 队列删空了：下次启动不再恢复。读的时候解析失败就当没有会话。
  void clear() => api.setPref(key: _key, value: '');

  void write(List<Song> queue, int index, String mode) {
    api.setPref(
      key: _key,
      value: jsonEncode({
        'queue': [for (final song in queue) songToJson(song)],
        'index': index,
        'mode': mode,
      }),
    );
  }
}
