part of 'player_controller.dart';

class _RemotePlayerController extends PlayerController {
  _RemotePlayerController(
    super.auth,
    this._library,
    this._locale,
    String directory, {
    AndroidPlaybackConnection Function(String, void Function(PlaybackMessage))?
    connectionFactory,
  }) : super._() {
    _connection = (connectionFactory ?? AndroidPlaybackConnection.new)(
      directory,
      _applyUpdate,
    );
    _lifecycle = AppLifecycleListener(
      onResume: _connect,
      onPause: () => _connection.setWatching(false),
    );
    _auth.addListener(_syncAuth);
    _library.addListener(_syncLiked);
    _locale.addListener(_syncLocale);
    _connect();
  }

  final LibraryController _library;
  final LocaleController _locale;
  late final AndroidPlaybackConnection _connection;
  late final AppLifecycleListener _lifecycle;
  (String, bool)? _lastLike;
  bool _disposed = false;

  void _connect() {
    _connection.setWatching(true);
    _ignore(_connection.connect());
  }

  void _ignore(Future<Object?> future) {
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object failure) {
          if (_disposed) return;
          error = StreamFailed(failure.toString());
          notifyListeners();
        },
      ),
    );
  }

  void _syncAuth() {
    _lastLike = null;
    _ignore(_connection.call('auth'));
  }

  void _syncLocale() => _ignore(_connection.call('locale'));

  void _syncLiked() {
    final song = current;
    if (song == null || !_library.canLike) return;
    final liked = _library.isLiked(song);
    final key = (song.mid, liked);
    if (_lastLike == key) return;
    _lastLike = key;
    _ignore(_connection.call('like', [songToJson(song), liked]));
  }

  void _applyUpdate(PlaybackMessage message) {
    if (_disposed) return;
    if (message['position'] case final int milliseconds) {
      position.value = Duration(milliseconds: milliseconds);
      return;
    }
    final before = current?.mid;
    if (message['queue'] case final List<Object?> items) {
      queue = items.cast<Map<String, dynamic>>().map(songFromJson).toList();
    }
    index = message['index'] as int;
    playing = message['playing'] as bool;
    loading = message['loading'] as bool;
    buffering = message['buffering'] as bool;
    duration = Duration(milliseconds: message['duration'] as int);
    defaultQuality = Quality.values.byName(message['defaultQuality'] as String);
    quality = Quality.values.byName(message['quality'] as String);
    actualQuality = Quality.values.asNameMap()[message['actualQuality']];
    mode = PlayMode.values.byName(message['mode'] as String);
    volume = (message['volume'] as num).toDouble();
    fade = Duration(seconds: message['fade'] as int);
    sleepAt = switch (message['sleepAt']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    };
    sleepAfterSong = message['sleepAfterSong'] as bool;
    error = decodePlayerError(message['error']);
    if (before != current?.mid) _refreshDisplayMetadata();
    if (current case final song?) {
      if (message['liked'] case final bool liked) {
        _lastLike = (song.mid, liked);
        _library.updateLiked(song, liked);
      }
    }
    notifyListeners();
  }

  Future<void> _send(String method, [Object? arguments]) async {
    await _connection.call(method, arguments);
  }

  static List<Map<String, Object?>> _songs(List<Song> songs) =>
      songs.map(songToJson).toList();

  @override
  Future<void> playList(List<Song> songs, int start) =>
      _send('playList', [_songs(songs), start]);

  @override
  Future<void> playRadio(RadioSource source, {List<Song>? first}) => _send(
    'playRadio',
    [source.kind, source.seed, source.id, first == null ? null : _songs(first)],
  );

  @override
  PlayNextResult playNext(Song song) {
    if (current?.mid == song.mid) return PlayNextResult.current;
    _ignore(_send('playNext', songToJson(song)));
    return current == null ? PlayNextResult.started : PlayNextResult.queued;
  }

  @override
  Future<void> playAt(int i) => _send('playAt', i);

  // 删除和挪动先改界面这边的队列，拖完松手列表不会先弹回原位再等播放服务的快照
  @override
  Future<void> removeAt(int i) {
    if (i < 0 || i >= queue.length) return Future.value();
    final before = current?.mid;
    final (q, n) = removeFromQueue(queue, index, i);
    queue = q;
    index = n;
    if (before != current?.mid) _refreshDisplayMetadata();
    notifyListeners();
    return _send('removeAt', i);
  }

  @override
  void moveQueue(int from, int to) {
    if (from == to ||
        from < 0 ||
        from >= queue.length ||
        to < 0 ||
        to >= queue.length) {
      return;
    }
    final (q, n) = moveInQueue(queue, index, from, to);
    queue = q;
    index = n;
    notifyListeners();
    _ignore(_send('moveQueue', [from, to]));
  }

  @override
  Future<void> next() => _send('next');

  @override
  Future<void> previous() => _send('previous');

  @override
  Future<void> play() => _send('play');

  @override
  Future<void> pause() => _send('pause');

  @override
  Future<void> toggle() => _send('toggle');

  @override
  Future<void> seek(Duration d) => _send('seek', d.inMilliseconds);

  @override
  void setMode(PlayMode m) {
    mode = m;
    notifyListeners();
    _ignore(_send('mode', m.name));
  }

  @override
  void setDefaultQuality(Quality q) {
    defaultQuality = quality = q;
    notifyListeners();
    _ignore(_send('defaultQuality', q.name));
  }

  @override
  void setFade(Duration d) {
    fade = d;
    notifyListeners();
    _ignore(_send('fade', d.inSeconds));
  }

  // 定时在播放服务里走，界面退到后台或被回收也照样到点停
  @override
  void setSleepTimer(Duration? d) {
    sleepAt = d == null ? null : DateTime.now().add(d);
    notifyListeners();
    _ignore(_send('sleep', d?.inSeconds));
  }

  @override
  void setSleepAfterSong(bool v) {
    sleepAfterSong = v;
    notifyListeners();
    _ignore(_send('sleepAfterSong', v));
  }

  @override
  Future<void> setVolume(double v) {
    volume = v.clamp(0, 100);
    notifyListeners();
    return _send('volume', volume);
  }

  @override
  Future<void> setQuality(Quality q) => _send('quality', q.name);

  @override
  Future<({int limitMb, int bytes})> audioCacheInfo() async {
    final value = await _connection.call('cacheInfo') as List<Object?>;
    return (limitMb: value[0] as int, bytes: value[1] as int);
  }

  @override
  Future<void> setAudioCacheLimit(int mb) => _send('cacheLimit', mb);

  @override
  Future<void> clearAudioCache() => _send('clearAudioCache');

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_syncAuth);
    _library.removeListener(_syncLiked);
    _locale.removeListener(_syncLocale);
    _lifecycle.dispose();
    _connection.dispose();
    super.dispose();
  }
}
