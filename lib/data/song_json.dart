import '../src/rust/api/types.dart';

/// 会话存储和播放进程通信共用的歌曲 JSON 格式。
Map<String, Object?> songToJson(Song s) => {
  'id': s.id,
  'mid': s.mid,
  'name': s.name,
  'singers': [
    for (final g in s.singers) {'mid': g.mid, 'name': g.name},
  ],
  'albumMid': s.albumMid,
  'albumName': s.albumName,
  'durationSecs': s.durationSecs,
  'mediaMid': s.mediaMid,
  'coverUrl': s.coverUrl,
  'vip': s.vip,
  'hasHq': s.hasHq,
  'hasFlac': s.hasFlac,
  'mvVid': s.mvVid,
};

Song songFromJson(Map<String, dynamic> m) => Song(
  id: m['id'] as int,
  mid: m['mid'] as String,
  name: m['name'] as String,
  singers: [
    for (final g in m['singers'] as List)
      Singer(mid: (g as Map)['mid'] as String, name: g['name'] as String),
  ],
  albumMid: m['albumMid'] as String,
  albumName: m['albumName'] as String,
  durationSecs: m['durationSecs'] as int,
  mediaMid: m['mediaMid'] as String,
  coverUrl: m['coverUrl'] as String,
  vip: m['vip'] as bool,
  hasHq: m['hasHq'] as bool,
  hasFlac: m['hasFlac'] as bool,
  mvVid: m['mvVid'] as String? ?? '',
);
