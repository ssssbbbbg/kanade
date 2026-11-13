part of 'player_controller.dart';

/// 刚打开、还没加载成功的音源。这时出错就降一档重试。
class _Attempt {
  _Attempt(
    this.song,
    this.source,
    this.start,
    this.play,
    this.token,
    this.urlToken,
  );

  final Song song;
  final AudioSource source;
  final Duration? start;
  final bool play;
  final int token;
  final int urlToken;
}

class _LocalPlayerController extends PlayerController {
  _LocalPlayerController(
    super.auth, {
    super.loadDisplayMetadata,
    Player? player,
  }) : _player =
           player ??
           Player(configuration: const PlayerConfiguration(title: 'Kanade')),
       super._() {
    _subs.addAll([
      _player.stream.playing.listen((v) {
        // 一首放完时 mpv 会先报「暂停」，紧接着就自动切下一首。不能把它当成暂停告诉系统，
        // 否则 Android 会撤掉后台播放服务和唤醒锁，切歌时在后台重新起不来，
        // 结果是被杀后台，或者进度在走却没声音。
        if (!v && _atEnd()) return;
        // 换音源时 media_kit 会先 stop 报一次「暂停」再接着播，封面会因此缩一下又弹回
        if (!v && _opening) return;
        playing = v;
        _reportPlay();
        notifyListeners();
      }),
      _player.stream.buffering.listen((v) {
        buffering = v;
        notifyListeners();
      }),
      _player.stream.position.listen((v) {
        // 手动切歌淡出的那一小段，进度条已经换成了新歌，旧歌的进度不再显示
        if (_holdGain) return;
        position.value = v;
        _fadePos = v;
        _fadeClock.reset();
        _setGain(_gainAt(v));
        _startFadeTick();
      }),
      _player.stream.duration.listen((v) {
        duration = v;
        // 拿到时长说明音源已经加载成功
        if (v > Duration.zero) _attempt = null;
        _reportPlay();
        notifyListeners();
      }),
      _player.stream.completed.listen((done) {
        // 淡出时旧歌刚好放完不算：已经在切去别的歌了
        if (done && !_holdGain) _onCompleted();
      }),
      _player.stream.error.listen((e) {
        // 个别音频帧解不出来（多见于文件开头结尾），mpv 会跳过继续放，不算出错
        if (e.startsWith('Error decoding')) return;
        if (_attempt != null) {
          _downgrade(e);
          return;
        }
        error = StreamFailed(e);
        notifyListeners();
      }),
    ]);
    _restored = current != null;
    if (volume != 100) unawaited(_player.setVolume(volume));
  }

  final Player _player;
  late final Future<void> _androidDiskCache = _configureAndroidDiskCache();
  final List<StreamSubscription> _subs = [];
  final _random = Random();

  /// 手动切歌时旧歌淡出最多这么久，免得点了下一首要等太久。
  static const _manualFadeOut = Duration(seconds: 1);

  /// 淡入淡出乘在 [volume] 上的系数（0–1），不改用户设的音量。
  double _gain = 1;

  /// 手动切歌正在淡出，或淡出完还没换上新歌：这时音量不再跟着进度走。
  bool _holdGain = false;
  Future<void>? _fadingOut;

  /// 按进度算淡入淡出系数：开头渐强，结尾渐弱。
  double _gainAt(Duration pos) {
    final f = fade.inMilliseconds;
    if (f == 0) return 1;
    final total = _player.state.duration.inMilliseconds;
    final ms = pos.inMilliseconds;
    final left = total > 0 ? total - ms : f;
    return (min(ms, left) / f).clamp(0.0, 1.0);
  }

  void _setGain(double g) {
    if (g == _gain) return;
    _gain = g;
    _applyVolume();
  }

  /// mpv 报进度的间隔比较稀，只在报进度时调音量会一级一级地跳。
  /// 淡入淡出区间里按上次报的进度加上经过的时间，每 16ms 算一次。
  Duration _fadePos = Duration.zero;
  final _fadeClock = Stopwatch()..start();
  Timer? _fadeTick;

  void _startFadeTick() {
    if (_fadeTick != null || _gain >= 1 || !_player.state.playing) return;
    _fadeTick = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_holdGain || !_player.state.playing || _player.state.buffering) {
        _stopFadeTick();
        return;
      }
      // 卡住不报进度时最多往前推 0.5 秒，免得音量自己走完
      final ahead = _fadeClock.elapsed < const Duration(milliseconds: 500)
          ? _fadeClock.elapsed
          : const Duration(milliseconds: 500);
      final g = _gainAt(_fadePos + ahead);
      _setGain(g);
      if (g >= 1) _stopFadeTick();
    });
  }

  void _stopFadeTick() {
    _fadeTick?.cancel();
    _fadeTick = null;
  }

  /// 暂停、继续时的渐变系数（0–1），和按进度算的 [_gain] 分开乘，互不打乱。
  double _pauseGain = 1;

  /// 每次开始新的暂停/继续渐变就加一，旧的渐变看到不一样就停下。
  int _pauseRamp = 0;

  void _applyVolume() =>
      unawaited(_player.setVolume(volume * _gain * _pauseGain));

  /// 把 [_pauseGain] 渐变到 [to]，时长跟着播放过渡设置、最多 1 秒，关闭时立刻到位。
  /// 中途被新的渐变打断时返回 false。
  Future<bool> _rampPause(double to) async {
    final ramp = ++_pauseRamp;
    final from = _pauseGain;
    final total =
        (fade < _manualFadeOut ? fade : _manualFadeOut) * (to - from).abs();
    final clock = Stopwatch()..start();
    while (clock.elapsed < total) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (ramp != _pauseRamp) return false;
      final t = (clock.elapsedMicroseconds / total.inMicroseconds).clamp(
        0.0,
        1.0,
      );
      _pauseGain = from + (to - from) * t;
      _applyVolume();
    }
    _pauseGain = to;
    _applyVolume();
    return true;
  }

  /// 手动切歌前把正在放的歌淡出。连着点几首时共用同一次淡出。
  Future<void> _fadeOutCurrent() {
    if (!playing || fade == Duration.zero || _gain == 0) return Future.value();
    _holdGain = true;
    return _fadingOut ??= () async {
      final from = _gain;
      final total = (fade < _manualFadeOut ? fade : _manualFadeOut) * from;
      final clock = Stopwatch()..start();
      do {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        _setGain(
          from *
              (1 - clock.elapsedMicroseconds / total.inMicroseconds).clamp(
                0.0,
                1.0,
              ),
        );
      } while (clock.elapsed < total);
      _fadingOut = null;
    }();
  }

  /// 设置里改播放过渡时长，从当前进度起生效。
  @override
  void setFade(Duration d) {
    fade = d;
    api.setPref(key: PlayerController._fadeKey, value: '${d.inSeconds}');
    if (!_holdGain) _setGain(_gainAt(_player.state.position));
    notifyListeners();
  }

  /// 上次的队列是启动时恢复出来的，还没取过音源：按播放键时才真正打开。
  bool _restored = false;

  /// 正在把新音源交给播放器并接着播放，期间忽略它报的暂停。
  bool _opening = false;

  /// 每次切歌递增，用来丢弃过期的异步结果。
  int _token = 0;

  /// 每次重新取播放链接（切歌、切音质或降级重试）递增。
  int _urlToken = 0;

  _Attempt? _attempt;

  /// 当前这首歌之前已经连续跳过了几首播不了的歌。
  int _skipped = 0;

  /// 已经上报过最近播放的那次切歌（`_token`），切音质、拖进度不再重复上报。
  int _reportedToken = -1;

  /// 歌曲加载成功并真正开始播放后，记一次云端最近播放。只在登录时，失败不影响播放。
  void _reportPlay() {
    final song = current;
    if (song == null ||
        !playing ||
        _attempt != null ||
        _player.state.duration <= Duration.zero) {
      return;
    }
    if (_reportedToken == _token || !_auth.loggedIn) return;
    _reportedToken = _token;
    api.reportPlay(songId: song.id).ignore();
  }

  /// 当前这首已经放到结尾（马上会自动切歌）。
  bool _atEnd() {
    final s = _player.state;
    return s.completed ||
        (s.duration > Duration.zero &&
            s.position >= s.duration - const Duration(seconds: 1));
  }

  /// 切歌失败停下来时，按播放器的真实状态更新（放完时报的暂停之前被忽略了）。
  void _syncPlaying() => playing = _player.state.playing;

  /// 电台模式（猜你喜欢、刷歌）下用来取下一批歌；普通播放列表为 null。
  Future<List<Song>> Function()? _radio;
  bool _radioLoading = false;

  @override
  Future<void> playList(List<Song> songs, int start) async {
    _radio = null;
    queue = List.of(songs);
    if (queue.isEmpty) {
      _refreshDisplayMetadata();
      notifyListeners();
      return;
    }
    await playAt(start);
  }

  /// 开始电台播放。`first` 是已经预取到的第一批（比如首页卡片封面用的那批），
  /// 没有就现取；第一批取不到时抛出异常，由调用方提示。
  @override
  Future<void> playRadio(RadioSource source, {List<Song>? first}) async {
    final fetch = source._fetcher();
    first ??= await fetch();
    if (first.isEmpty) throw StateError('radio returned no songs');
    _radio = fetch;
    queue = List.of(first);
    await playAt(0);
  }

  /// 往电台队列末尾补一批，跳过已经在队列里的歌。返回是否补到了新歌。
  Future<bool> _extendRadio() async {
    final fetch = _radio;
    if (fetch == null || _radioLoading) return false;
    _radioLoading = true;
    try {
      final known = {for (final s in queue) s.mid};
      final more = (await fetch()).where((s) => known.add(s.mid)).toList();
      if (_radio != fetch || more.isEmpty) return false;
      queue = [...queue, ...more];
      _saveSession();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    } finally {
      _radioLoading = false;
    }
  }

  /// 随机模式下，“下一首播放”插在当前歌后面、还没放到的有几首；[next] 先按顺序放完它们。
  int _pinnedNext = 0;

  /// 把歌插到当前这首后面。连着点几首时，后点的先放。
  @override
  PlayNextResult playNext(Song song) {
    if (current == null) {
      unawaited(playList([song], 0));
      return PlayNextResult.started;
    }
    if (current!.mid == song.mid) return PlayNextResult.current;
    final (q, i) = insertNext(queue, index, song);
    queue = q;
    index = i;
    _pinnedNext = min(_pinnedNext + 1, queue.length - 1 - index);
    _saveSession();
    notifyListeners();
    return PlayNextResult.queued;
  }

  @override
  Future<void> playAt(int i) => _playAt(i);

  @override
  Future<void> removeAt(int i) async {
    if (i < 0 || i >= queue.length) return;
    final removingCurrent = i == index;
    if (i > index && i <= index + _pinnedNext) _pinnedNext--;
    final (q, n) = removeFromQueue(queue, index, i);
    queue = q;
    if (q.isEmpty) {
      ++_token;
      ++_urlToken;
      _attempt = null;
      _radio = null;
      _pinnedNext = 0;
      _restored = false;
      index = -1;
      playing = false;
      loading = false;
      error = null;
      actualQuality = null;
      duration = Duration.zero;
      position.value = Duration.zero;
      _sessionStore.clear();
      _refreshDisplayMetadata();
      notifyListeners();
      await _player.stop();
      return;
    }
    if (removingCurrent) {
      // 原来的下一首已经挪到这个位置；插过“下一首播放”的话它就是第一首插的
      await _playAt(n, pinnedNext: max(0, _pinnedNext - 1));
      return;
    }
    index = n;
    _saveSession();
    notifyListeners();
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
    _pinnedNext = min(_pinnedNext, queue.length - 1 - index);
    _saveSession();
    notifyListeners();
  }

  Future<void> _playAt(int i, {int skipped = 0, int pinnedNext = 0}) async {
    if (i < 0 || i >= queue.length) return;
    // 手动点了别的歌，之前插的“下一首”就不再算数
    _pinnedNext = pinnedNext;
    final token = ++_token;
    final urlToken = ++_urlToken;
    _attempt = null;
    _skipped = skipped;
    _restored = false;
    index = i;
    _saveSession();
    loading = true;
    error = null;
    actualQuality = null;
    position.value = Duration.zero;
    duration = Duration(seconds: queue[i].durationSecs);
    _refreshDisplayMetadata();
    notifyListeners();

    final song = queue[i];
    // 电台快放完时提前取下一批，切歌时不用等
    if (_radio != null && i >= queue.length - 2) unawaited(_extendRadio());
    try {
      // 自动跳过播不了的歌时，它本来就没声音，不用淡出
      await _open(
        song,
        quality,
        token: token,
        urlToken: urlToken,
        fadeOut: skipped == 0,
      );
    } catch (e) {
      if (token != _token || urlToken != _urlToken) return;
      error = PlaybackFailed(song, e);
      if (await _skipFailed()) return;
      _syncPlaying();
    }
    // 降级重试已经接手时由它收尾
    if (token != _token || urlToken != _urlToken) return;
    loading = false;
    notifyListeners();
  }

  /// 自动跳过无法播放的歌，整个队列都失败时停下。返回是否跳了。
  Future<bool> _skipFailed() async {
    if (queue.length <= 1 || _skipped >= queue.length - 1) return false;
    loading = false;
    notifyListeners();
    await _playAt((index + 1) % queue.length, skipped: _skipped + 1);
    return true;
  }

  Future<void> _configureAndroidDiskCache() async {
    final native = _player.platform;
    if (native is! NativePlayer) return;
    // OpenSL ES 默认一次交给系统 250ms 的音频，整块共用一个音量，
    // 淡入淡出听起来就是每 0.25 秒跳一级。缩到 50ms 让音量变化连贯。
    await native.setProperty('opensles-buffer-size-in-ms', '50');
    try {
      // Android 的默认目录可能不可写，mpv 会退回内存缓存。
      final directory = await getTemporaryDirectory();
      await native.setProperty('demuxer-cache-dir', directory.path);
    } catch (error) {
      debugPrint('mpv disk cache unavailable: $error');
    }
  }

  /// 边解边播的音源从上次位置恢复或往后拖时，要等本机解码追上，可能超过
  /// media_kit 默认的 5 秒网络超时；本机中转在解码失败或切歌时会断开，
  /// 所以这类音源不限时，其他音源保持 5 秒。
  Future<void> _setNetworkTimeout({required bool decoded}) async {
    final native = _player.platform;
    if (native is! NativePlayer) return;
    await native.setProperty('network-timeout', decoded ? '0' : '5');
  }

  /// 取音源并交给播放器。取不到任何音质的链接时抛出异常；
  /// 拿到了却播不了的情况由 [_downgrade] 处理。
  Future<void> _open(
    Song song,
    Quality q, {
    required int token,
    required int urlToken,
    Duration? start,
    bool play = true,
    bool fadeOut = false,
  }) async {
    bool stale() => token != _token || urlToken != _urlToken;
    final src = await AudioSource.resolve(song, q, stale: stale);
    if (src == null || stale()) return;
    if (Platform.isAndroid) {
      await _androidDiskCache;
      if (stale()) return;
    }
    final attempt = _Attempt(song, src, start, play, token, urlToken);
    final ready = src.waitUntilReady();
    if (ready != null) {
      try {
        await ready;
      } catch (e) {
        if (!stale()) {
          _attempt = attempt;
          _downgrade(e);
        }
        return;
      }
      if (stale()) return;
    }
    actualQuality = src.quality;
    // 链接取到了再淡出，取链接的这段时间旧歌照常放
    if (fadeOut) {
      await _fadeOutCurrent();
      if (stale()) return;
    }
    _attempt = attempt;
    // 暂停淡到一半就换歌：不再接着淡，新歌照常按进度渐强
    _pauseRamp++;
    _pauseGain = 1;
    // 新歌从静音开始，等进度走起来再渐强
    _stopFadeTick();
    _fadePos = start ?? Duration.zero;
    _fadeClock.reset();
    _gain = _gainAt(_fadePos);
    _applyVolume();
    try {
      await _setNetworkTimeout(decoded: ready != null);
      _opening = play;
      await _player.open(src.media(start: start), play: play);
    } catch (e) {
      _downgrade(e);
    } finally {
      _opening = false;
      _holdGain = false;
    }
  }

  /// 音源加载失败：缓存文件坏了就删掉重新在线取，在线的就降一档，降到底算这首歌播不了。
  void _downgrade(Object cause) {
    final a = _attempt;
    _attempt = null;
    if (a == null || a.token != _token || a.urlToken != _urlToken) return;
    final next = a.source.fallback();
    unawaited(() async {
      try {
        if (next == null) throw cause;
        final urlToken = ++_urlToken;
        loading = true;
        notifyListeners();
        await _open(
          a.song,
          next,
          token: a.token,
          urlToken: urlToken,
          start: a.start,
          play: a.play,
        );
        if (a.token != _token || urlToken != _urlToken) return;
      } catch (e) {
        if (a.token != _token) return;
        error = PlaybackFailed(a.song, e);
        if (await _skipFailed()) return;
        _syncPlaying();
      }
      loading = false;
      notifyListeners();
    }());
  }

  void _onCompleted() {
    if (queue.isEmpty) return;
    if (_sleepPending) {
      // 定时已到，等的就是这首放完：停在这首开头
      _clearSleep();
      unawaited(_player.seek(Duration.zero));
      unawaited(pause());
      return;
    }
    if (mode == PlayMode.repeatOne) {
      _player.seek(Duration.zero);
      _player.play();
    } else {
      next();
    }
  }

  @override
  Future<void> next() async {
    if (queue.isEmpty) return;
    // 电台按顺序往下播，到头时现取一批，取不到才回到开头
    if (_radio != null) {
      if (index + 1 >= queue.length) await _extendRadio();
      await playAt((index + 1) % queue.length);
      return;
    }
    if (mode == PlayMode.shuffle &&
        _pinnedNext > 0 &&
        index + 1 < queue.length) {
      await _playAt(index + 1, pinnedNext: _pinnedNext - 1);
    } else if (mode == PlayMode.shuffle && queue.length > 1) {
      var n = index;
      while (n == index) {
        n = _random.nextInt(queue.length);
      }
      await playAt(n);
    } else {
      await playAt((index + 1) % queue.length);
    }
  }

  @override
  Future<void> previous() async {
    if (queue.isEmpty) return;
    if (position.value > const Duration(seconds: 5)) {
      await _player.seek(Duration.zero);
      return;
    }
    await playAt((index - 1 + queue.length) % queue.length);
  }

  @override
  Future<void> play() async {
    if (_restored) return playAt(index);
    if (!_player.state.playing) {
      // 从静音开始放，再慢慢升回原来的音量
      _pauseRamp++;
      _pauseGain = 0;
      _applyVolume();
      await _player.play();
    } else if (!playing) {
      // 暂停还在淡出时又按了播放：从现在的音量直接升回去
      playing = true;
      notifyListeners();
    }
    await _rampPause(1);
  }

  @override
  Future<void> pause() async {
    if (playing) {
      // 按钮先变成暂停，声音淡下去再真正停；中途又按了播放就不停了
      playing = false;
      notifyListeners();
      if (!await _rampPause(0)) return;
    } else {
      _pauseRamp++;
    }
    await _player.pause();
    // 快放完时按暂停，播放器报的暂停会被当成放完而忽略，这里补上
    _syncPlaying();
    notifyListeners();
  }

  @override
  Future<void> seek(Duration d) => _player.seek(d);

  @override
  Future<({int limitMb, int bytes})> audioCacheInfo() async => (
    limitMb: api.getAudioCacheLimitMb(),
    bytes: await api.getAudioCacheSize(),
  );

  @override
  Future<void> setAudioCacheLimit(int mb) async =>
      api.setAudioCacheLimitMb(mb: mb);

  @override
  Future<void> clearAudioCache() => api.clearAudioCache();

  /// 设置里改默认音质：保存下来，并从下一首开始使用。
  @override
  void setDefaultQuality(Quality q) {
    defaultQuality = q;
    quality = q;
    api.setPref(key: PlayerController._defaultQualityKey, value: q.name);
    notifyListeners();
  }

  @override
  void setMode(PlayMode m) {
    mode = m;
    api.setPref(key: PlayerController._modeKey, value: m.name);
    _saveSession();
    notifyListeners();
  }

  Timer? _volumeSave;

  @override
  Future<void> setVolume(double v) {
    volume = v.clamp(0, 100);
    // 拖动音量时每帧都会调到这里，停下来再写库
    _volumeSave?.cancel();
    _volumeSave = Timer(const Duration(milliseconds: 400), _saveVolume);
    notifyListeners();
    return _player.setVolume(volume * _gain * _pauseGain);
  }

  void _saveVolume() {
    _volumeSave = null;
    api.setPref(
      key: PlayerController._volumeKey,
      value: volume.toStringAsFixed(1),
    );
  }

  Timer? _sleepTimer;

  /// 已经到点，在等当前这首放完。
  bool _sleepPending = false;

  /// [d] 之后停止播放，null 关闭定时。
  @override
  void setSleepTimer(Duration? d) {
    _clearSleep();
    if (d != null) {
      sleepAt = DateTime.now().add(d);
      _sleepTimer = Timer(d, _onSleep);
    }
    notifyListeners();
  }

  @override
  void setSleepAfterSong(bool v) {
    sleepAfterSong = v;
    api.setPref(key: PlayerController._sleepAfterSongKey, value: '$v');
    // 正在等这首放完时关掉开关，就不再等了
    if (!v && _sleepPending) {
      _clearSleep();
      unawaited(pause());
      return;
    }
    notifyListeners();
  }

  void _clearSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepPending = false;
    sleepAt = null;
  }

  void _onSleep() {
    _sleepTimer = null;
    if (sleepAfterSong && playing) {
      _sleepPending = true;
      return;
    }
    _clearSleep();
    unawaited(pause());
  }

  /// 切换当前歌曲的音质：从当前进度继续播放，暂停状态保持暂停。
  /// 取链接失败时继续播放原来的音质。
  @override
  Future<void> setQuality(Quality q) async {
    final song = current;
    final previous = quality;
    quality = q;
    if (song == null || (q == actualQuality && !loading)) {
      notifyListeners();
      return;
    }
    final token = _token;
    final urlToken = ++_urlToken;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _open(
        song,
        q,
        token: token,
        urlToken: urlToken,
        start: position.value,
        play: playing,
      );
      if (token != _token || urlToken != _urlToken) return;
    } catch (e) {
      if (token != _token || urlToken != _urlToken) return;
      quality = previous;
      error = PlaybackFailed(song, e);
    }
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    ++_token;
    _stopFadeTick();
    _sleepTimer?.cancel();
    if (_volumeSave != null) {
      _volumeSave!.cancel();
      _saveVolume();
    }
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
