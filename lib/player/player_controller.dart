import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Int64List;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/auth_controller.dart';
import '../data/song_json.dart';
import '../library/library_controller.dart';
import '../settings/locale_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'android_playback_connection.dart';
import 'audio_source.dart';
import 'player_error.dart';
import 'playback_messages.dart';
import 'player_session_store.dart';

part 'local_player_controller.dart';
part 'remote_player_controller.dart';

enum PlayMode { sequence, repeatOne, shuffle }

class RadioSource {
  const RadioSource.guess() : kind = 'guess', seed = const [], id = null;
  const RadioSource.radar(this.seed) : kind = 'radar', id = null;
  const RadioSource.station(this.id) : kind = 'station', seed = const [];
  const RadioSource.fromMessage(this.kind, this.seed, this.id);

  final String kind;
  final List<int> seed;
  final int? id;

  Future<List<Song>> Function() _fetcher() {
    var page = 0;
    return switch (kind) {
      'guess' => api.getGuessYouLike,
      'radar' => () => api.getRadarSongs(
        seed: Int64List.fromList(seed),
        page: ++page,
      ),
      _ => () => api.getRadioSongs(id: id!),
    };
  }
}

/// “下一首播放”的结果：插进了队列、队列是空的所以直接开放、或者就是正在放的这首。
enum PlayNextResult { queued, started, current }

/// 把 [song] 插到第 [index] 首后面，已经在队列里的先挪出来。返回新队列和当前歌曲的新下标。
(List<Song>, int) insertNext(List<Song> queue, int index, Song song) {
  final q = List.of(queue);
  var i = index;
  final old = q.indexWhere((s) => s.mid == song.mid);
  if (old >= 0) {
    q.removeAt(old);
    if (old < i) i--;
  }
  q.insert(i + 1, song);
  return (q, i);
}

/// 从队列里删掉第 [i] 首，返回新队列和当前歌曲的新下标。
/// 删的就是当前这首时，新下标指向原来的下一首（删的是最后一首就回到开头），队列删空了是 -1。
(List<Song>, int) removeFromQueue(List<Song> queue, int index, int i) {
  final q = List.of(queue)..removeAt(i);
  if (q.isEmpty) return (q, -1);
  if (i < index) return (q, index - 1);
  if (i == index) return (q, i % q.length);
  return (q, index);
}

/// 把第 [from] 首挪到第 [to] 个位置（挪完后的下标），返回新队列和当前歌曲的新下标。
(List<Song>, int) moveInQueue(List<Song> queue, int index, int from, int to) {
  final q = List.of(queue);
  q.insert(to, q.removeAt(from));
  if (from == index) return (q, to);
  if (from < index && to >= index) return (q, index - 1);
  if (from > index && to <= index) return (q, index + 1);
  return (q, index);
}

/// 两种播放实现共用的状态与展示元数据，不持有本地播放器。
abstract class PlayerController extends ChangeNotifier {
  factory PlayerController(
    AuthController auth, {
    bool loadDisplayMetadata,
    Player? player,
  }) = _LocalPlayerController;

  factory PlayerController.android(
    AuthController auth,
    LibraryController library,
    LocaleController locale,
    String directory, {
    AndroidPlaybackConnection Function(String, void Function(PlaybackMessage))?
    connectionFactory,
  }) = _RemotePlayerController;

  PlayerController._(this._auth, {this.loadDisplayMetadata = true}) {
    _auth.addListener(_onAuthChanged);
    _restoreSession();
  }

  final AuthController _auth;
  final bool loadDisplayMetadata;
  final _sessionStore = PlayerSessionStore();
  static const _defaultQualityKey = 'default_quality';
  static const _modeKey = 'play_mode';
  static const _volumeKey = 'volume';
  static const _fadeKey = 'song_fade_seconds';
  static const _sleepAfterSongKey = 'sleep_after_song';

  List<Song> queue = [];
  int index = -1;
  Song? get current => index >= 0 && index < queue.length ? queue[index] : null;

  /// 播放过渡时长；暂停和继续时的渐变最多 1 秒。
  Duration fade = Duration(
    seconds: int.tryParse(api.getPref(key: _fadeKey) ?? '') ?? 0,
  );

  /// 默认音质用于启动和后续切歌，当前音源的档位见 actualQuality。
  Quality defaultQuality =
      Quality.values.asNameMap()[api.getPref(key: _defaultQualityKey)] ??
      Quality.high;

  /// 用户选中的音质，切歌后继续沿用；不可用时实际播放会降级。
  late Quality quality = defaultQuality;
  PlayMode mode =
      PlayMode.values.asNameMap()[api.getPref(key: _modeKey)] ??
      PlayMode.sequence;
  bool playing = false;
  bool buffering = false;
  bool loading = false;
  Duration duration = Duration.zero;

  /// 高频进度更新独立通知，避免整个播放状态随每一帧刷新。
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  /// 实际播放的音质，可能低于请求的档位。
  Quality? actualQuality;
  List<QualityOption> qualityOptions = [];
  bool qualitiesLoading = false;
  Object? qualitiesError;
  Lyric? lyric;

  /// 当前歌曲的高潮片段，用于进度条标记。
  ChorusRange? chorus;
  PlayerError? error;

  /// 音量 0–100，重启后恢复上次的值。
  double volume = (double.tryParse(api.getPref(key: _volumeKey) ?? '') ?? 100)
      .clamp(0, 100);

  /// 定时关闭时间；仅存于内存，等待当前歌曲结束时可以早于现在。
  DateTime? sleepAt;

  /// 定时到了先把当前这首放完再停。
  bool sleepAfterSong = api.getPref(key: _sleepAfterSongKey) == 'true';
  int _metadataToken = 0;
  int _qualitiesToken = 0;

  Future<void> playList(List<Song> songs, int start);
  Future<void> playRadio(RadioSource source, {List<Song>? first});
  PlayNextResult playNext(Song song);
  Future<void> playAt(int i);

  /// 从队列里删掉第 [i] 首；删的是正在放的就接着放下一首，删空了就停下。
  Future<void> removeAt(int i);

  /// 把第 [from] 首挪到第 [to] 个位置（挪完后的下标）。
  void moveQueue(int from, int to);
  Future<void> next();
  Future<void> previous();
  Future<void> play();
  Future<void> pause();
  Future<void> toggle() => playing ? pause() : play();
  Future<void> seek(Duration d);
  void setMode(PlayMode m);
  void cycleMode() =>
      setMode(PlayMode.values[(mode.index + 1) % PlayMode.values.length]);
  void setDefaultQuality(Quality q);
  Future<void> setQuality(Quality q);
  void setFade(Duration d);
  Future<void> setVolume(double v);
  void setSleepTimer(Duration? d);
  void setSleepAfterSong(bool v);
  Future<({int limitMb, int bytes})> audioCacheInfo();
  Future<void> setAudioCacheLimit(int mb);
  Future<void> clearAudioCache();

  /// 恢复、切歌和远程快照共用；清空队列时也要使旧请求失效。
  void _refreshDisplayMetadata() {
    final token = ++_metadataToken;
    ++_qualitiesToken;
    lyric = null;
    chorus = null;
    qualityOptions = [];
    qualitiesError = null;
    qualitiesLoading = false;
    if (!loadDisplayMetadata) return;
    unawaited(refreshQualities());
    final song = current;
    if (song == null) return;
    unawaited(_loadLyric(song, token));
    unawaited(_loadChorus(song, token));
  }

  Future<void> _loadLyric(Song song, int token) async {
    try {
      final l = await api.getLyric(mid: song.mid, id: song.id);
      if (token != _metadataToken) return;
      lyric = l;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadChorus(Song song, int token) async {
    try {
      final c = await api.getSongChorus(id: song.id);
      if (token != _metadataToken) return;
      chorus = c;
      notifyListeners();
    } catch (_) {}
  }

  void _onAuthChanged() {
    if (loadDisplayMetadata) unawaited(refreshQualities());
  }

  Future<void> refreshQualities() async {
    final song = current;
    final token = ++_qualitiesToken;
    qualityOptions = [];
    qualitiesError = null;
    qualitiesLoading = song != null;
    notifyListeners();
    if (song == null) return;
    try {
      final options = await api.getSongQualities(mid: song.mid);
      if (token != _qualitiesToken) return;
      qualityOptions = options;
    } catch (e) {
      if (token != _qualitiesToken) return;
      qualitiesError = e;
    }
    if (token != _qualitiesToken) return;
    qualitiesLoading = false;
    notifyListeners();
  }

  /// 记下队列、当前歌曲和播放模式，下次启动时播放栏还显示这首。
  void _saveSession() {
    if (current == null) return;
    _sessionStore.write(queue, index, mode.name);
  }

  /// 恢复上次的队列，只显示不播放。电台模式恢复成普通列表。
  void _restoreSession() {
    final session = _sessionStore.read();
    if (session == null) return;
    queue = session.queue;
    index = session.index;
    // 旧版本只把模式存在会话里
    if (api.getPref(key: _modeKey) == null) {
      mode = PlayMode.values.asNameMap()[session.mode] ?? mode;
    }
    duration = Duration(seconds: queue[index].durationSecs);
    _refreshDisplayMetadata();
  }

  /// 当前应高亮的歌词行。
  int lyricIndexAt(Duration pos) {
    final lines = lyric?.lines ?? const [];
    final ms = pos.inMilliseconds;
    var lo = 0, hi = lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].timeMs <= ms) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  @override
  void dispose() {
    ++_metadataToken;
    ++_qualitiesToken;
    _auth.removeListener(_onAuthChanged);
    position.dispose();
    super.dispose();
  }
}
