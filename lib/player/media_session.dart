import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../data/data_ext.dart';
import '../library/library_controller.dart';
import '../settings/locale_controller.dart';
import '../src/rust/api/types.dart';
import 'player_controller.dart';
import 'taskbar_thumbnail.dart';

/// 卡片上的红心按钮：是否已收藏，以及读屏用的说明。没登录或没在放歌时为 null，不显示按钮。
typedef _Like = ({bool liked, String label});

/// 卡片上的播放模式按钮：当前模式，以及读屏用的说明。
typedef _Mode = ({PlayMode mode, String label});

/// 系统媒体控件的一种实现。
abstract class _Sink {
  void song(Song? s, Duration duration);
  void state({
    required bool playing,
    required bool loading,
    required Duration position,
    required Duration duration,
    _Like? like,
    required _Mode mode,
  });
}

/// 把播放状态同步给系统的媒体卡片：Android 是通知栏和锁屏（audio_service），
/// Windows 是音量浮窗里的媒体控件（SMTC）和任务栏图标的悬停预览。卡片上点的按钮再转回 [PlayerController]。
/// Android 卡片上另有红心和播放模式按钮；Windows 的卡片按钮是系统固定的，加不了。
///
/// 进度不逐帧推：系统拿到「某时刻在某位置、是否在播」后会自己往前走，
/// 只在播放状态变化或进度跳变（拖动、切歌）时重新告诉它。
class MediaSession {
  MediaSession._(this._p, this._library, this._locale, this._sink) {
    _p.addListener(_sync);
    _library.addListener(_sync);
    _locale.addListener(_sync);
    _p.position.addListener(_onPosition);
    _sync();
    if (Platform.isWindows) {
      _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    }
  }

  final PlayerController _p;
  final LibraryController _library;
  final LocaleController _locale;
  final _Sink _sink;
  AppLifecycleListener? _lifecycle;
  Future<AppExitResponse>? _exitRequest;

  Future<AppExitResponse> _onExitRequested() =>
      _exitRequest ??= _closeWindowsSession();

  Future<AppExitResponse> _closeWindowsSession() async {
    _p.removeListener(_sync);
    _library.removeListener(_sync);
    _locale.removeListener(_sync);
    _p.position.removeListener(_onPosition);
    await (_sink as _WindowsSink).dispose();
    _lifecycle?.dispose();
    return AppExitResponse.exit;
  }

  String? _songKey;
  bool? _playing;
  bool? _loading;
  _Like? _like;
  _Mode? _mode;
  Duration _anchor = Duration.zero;
  final _clock = Stopwatch();

  /// 在支持的平台上接入系统媒体控件，其他平台什么都不做。失败只影响系统卡片，不影响播放。
  static Future<void> attach(
    PlayerController p,
    LibraryController library,
    LocaleController locale,
  ) async {
    try {
      final _Sink? sink;
      if (Platform.isAndroid) {
        sink = await _AndroidSink.create(p, () => _toggleLike(p, library));
      } else if (Platform.isWindows) {
        sink = await _WindowsSink.create(p, locale);
      } else {
        sink = null;
      }
      if (sink != null) MediaSession._(p, library, locale, sink);
    } catch (e) {
      debugPrint('media session unavailable: $e');
    }
  }

  static Future<void> _toggleLike(
    PlayerController p,
    LibraryController library,
  ) async {
    final song = p.current;
    if (song == null || !library.canLike) return;
    try {
      await library.toggleLike(song);
    } catch (e) {
      // 失败时红心状态不变，卡片上的图标也就不变
      debugPrint('like from media card failed: $e');
    }
  }

  _Like? _currentLike() {
    final song = _p.current;
    if (song == null || !_library.canLike) return null;
    final liked = _library.isLiked(song);
    final l = _locale.strings;
    return (liked: liked, label: liked ? l.unlike : l.like);
  }

  _Mode _currentMode() {
    final l = _locale.strings;
    final mode = _p.mode;
    return (
      mode: mode,
      label: switch (mode) {
        PlayMode.sequence => l.modeSequence,
        PlayMode.repeatOne => l.modeRepeatOne,
        PlayMode.shuffle => l.modeShuffle,
      },
    );
  }

  void _sync() {
    final song = _p.current;
    final key = song == null
        ? null
        : '${song.mid}/${_p.duration.inMilliseconds}';
    if (key != _songKey) {
      _songKey = key;
      _sink.song(song, _p.duration);
      _pushState();
      return;
    }
    final loading = _p.loading || _p.buffering;
    if (_p.playing != _playing ||
        loading != _loading ||
        _currentLike() != _like ||
        _currentMode() != _mode) {
      _pushState();
    }
  }

  void _onPosition() {
    final expected =
        _anchor +
        (_playing == true && _loading == false
            ? _clock.elapsed
            : Duration.zero);
    if ((_p.position.value - expected).abs() >
        const Duration(milliseconds: 1500)) {
      _pushState();
    }
  }

  void _pushState() {
    _playing = _p.playing;
    _loading = _p.loading || _p.buffering;
    _like = _currentLike();
    _mode = _currentMode();
    _anchor = _p.position.value;
    _clock
      ..reset()
      ..start();
    _sink.state(
      playing: _playing!,
      loading: _loading!,
      position: _anchor,
      duration: _p.duration,
      like: _like,
      mode: _mode!,
    );
  }
}

class _AndroidSink extends BaseAudioHandler with SeekHandler implements _Sink {
  _AndroidSink(this._p, this._onLike);

  final PlayerController _p;
  final Future<void> Function() _onLike;

  static const _likeAction = 'like';
  static const _modeAction = 'mode';

  static Future<_AndroidSink> create(
    PlayerController p,
    Future<void> Function() onLike,
  ) => AudioService.init(
    builder: () => _AndroidSink(p, onLike),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.lxi.kanade.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_notification',
    ),
  );

  @override
  void song(Song? s, Duration duration) => mediaItem.add(
    s == null
        ? null
        : MediaItem(
            id: s.mid,
            title: s.name,
            artist: singerNames(s),
            album: s.albumName,
            duration: duration,
            artUri: Uri.parse(bigCoverUrl(s)),
          ),
  );

  @override
  void state({
    required bool playing,
    required bool loading,
    required Duration position,
    required Duration duration,
    _Like? like,
    required _Mode mode,
  }) {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          // 图标在 android/app/src/main/res/drawable，收起的卡片只放前三个，红心和播放模式在展开后和锁屏上显示
          if (like != null)
            MediaControl.custom(
              androidIcon: like.liked
                  ? 'drawable/ic_liked'
                  : 'drawable/ic_like',
              label: like.label,
              name: _likeAction,
            ),
          MediaControl.custom(
            androidIcon: switch (mode.mode) {
              PlayMode.sequence => 'drawable/ic_mode_sequence',
              PlayMode.repeatOne => 'drawable/ic_mode_repeat_one',
              PlayMode.shuffle => 'drawable/ic_mode_shuffle',
            },
            label: mode.label,
            name: _modeAction,
          ),
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _p.current == null
            ? AudioProcessingState.idle
            : loading
            ? AudioProcessingState.loading
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
      ),
    );
  }

  @override
  Future<void> play() => _p.play();

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> stop() => _p.pause();

  @override
  Future<void> skipToNext() => _p.next();

  @override
  Future<void> skipToPrevious() => _p.previous();

  @override
  Future<void> seek(Duration position) => _p.seek(position);

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == _likeAction) await _onLike();
    if (name == _modeAction) _p.cycleMode();
  }
}

class _WindowsSink implements _Sink {
  _WindowsSink(this._p, LocaleController locale)
    : _taskbar = TaskbarThumbnail(_p, locale) {
    _buttons = _smtc.buttonPressStream.listen((b) {
      switch (b) {
        case PressedButton.play:
          _p.play();
        case PressedButton.pause:
          _p.pause();
        case PressedButton.next:
          _p.next();
        case PressedButton.previous:
          _p.previous();
        default:
      }
    });
  }

  static Future<_WindowsSink> create(
    PlayerController p,
    LocaleController locale,
  ) async {
    await SMTCWindows.initialize();
    return _WindowsSink(p, locale);
  }

  final PlayerController _p;
  final TaskbarThumbnail _taskbar;
  late final StreamSubscription<PressedButton> _buttons;

  Future<void> dispose() async {
    _taskbar.dispose();
    await _buttons.cancel();
    await _smtc.dispose();
  }

  /// 没在放歌时不显示卡片，第一次有歌时再打开。
  final _smtc = SMTCWindows(
    enabled: false,
    config: const SMTCConfig(
      playEnabled: true,
      pauseEnabled: true,
      nextEnabled: true,
      prevEnabled: true,
      stopEnabled: false,
      fastForwardEnabled: false,
      rewindEnabled: false,
    ),
  );

  @override
  void song(Song? s, Duration duration) {
    _taskbar.song(s);
    if (s == null) {
      if (_smtc.enabled) _smtc.disableSmtc();
      return;
    }
    if (!_smtc.enabled) _smtc.enableSmtc();
    _smtc.updateMetadata(
      MusicMetadata(
        title: s.name,
        artist: singerNames(s),
        album: s.albumName,
        thumbnail: bigCoverUrl(s),
      ),
    );
  }

  @override
  void state({
    required bool playing,
    required bool loading,
    required Duration position,
    required Duration duration,
    _Like? like,
    required _Mode mode,
  }) {
    _taskbar.state(playing: playing);
    if (!_smtc.enabled) return;
    _smtc.setPlaybackStatus(
      playing ? PlaybackStatus.playing : PlaybackStatus.paused,
    );
    _smtc.updateTimeline(
      PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: duration.inMilliseconds,
        positionMs: position.inMilliseconds,
        minSeekTimeMs: 0,
        maxSeekTimeMs: duration.inMilliseconds,
      ),
    );
  }
}
