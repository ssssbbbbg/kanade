import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/data_ext.dart';
import 'recognition_controller.dart';

/// 识曲的 Android 悬浮按钮和前台服务，不持有页面或导航器。
class AndroidRecognitionPlatform {
  AndroidRecognitionPlatform(
    this.controller, {
    required this.title,
    required this.message,
    required this.onChanged,
    required this.onClose,
    this.channel = const MethodChannel('kanade/recognize'),
  }) {
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
    channel.setMethodCallHandler(_onAction);
    controller.addListener(_sync);
    unawaited(_checkOverlay());
  }

  final RecognitionController controller;
  String title;
  final String Function() message;
  final VoidCallback onChanged;
  final VoidCallback onClose;
  final MethodChannel channel;
  late final AppLifecycleListener _lifecycle;
  bool? canOverlay;
  bool _away = false;
  bool _service = false;
  bool _micGranted = false;
  bool _finished = false;
  Future<void>? _startingService;
  Future<void>? _finishing;

  Future<void> _checkOverlay() async {
    final can = await channel.invokeMethod<bool>('canOverlay') ?? false;
    if (_finished) return;
    canOverlay = can;
    onChanged();
    unawaited(_ensureService());
    _syncBubble();
  }

  Future<void> _ensureService() async {
    if (_finished ||
        _away ||
        _service ||
        _startingService != null ||
        canOverlay != true ||
        !controller.micGranted) {
      return;
    }
    final request = channel.invokeMethod<bool>('startService', {
      'title': title,
    });
    final work = request.then((started) {
      _service = started ?? false;
    });
    _startingService = work;
    try {
      await work;
    } finally {
      _startingService = null;
    }
  }

  void _sync() {
    if (controller.finished) {
      unawaited(finish());
      return;
    }
    if (_finished) return;
    if (!_micGranted && controller.micGranted) {
      _micGranted = true;
      unawaited(_ensureService());
    }
    _syncBubble();
  }

  void _syncBubble() {
    if (_finished || !_away || canOverlay != true) return;
    final song = controller.song;
    unawaited(
      channel.invokeMethod('update', {
        'mode': switch (controller.phase) {
          RecognitionPhase.listening => 'listening',
          RecognitionPhase.found => 'found',
          _ => 'message',
        },
        'seconds': controller.seconds,
        'title': song?.name,
        'artist': song == null ? null : singerNames(song),
        'cover': song == null ? null : httpsUrl(song.coverUrl),
        'message': message(),
      }),
    );
  }

  void _onHide() {
    _away = true;
    if (_finished || canOverlay != true) return;
    _syncBubble();
    unawaited(channel.invokeMethod('show'));
  }

  void _onShow() {
    if (_finished) return;
    _away = false;
    unawaited(channel.invokeMethod('hide'));
    unawaited(_checkOverlay());
  }

  Future<void> openSettings() => channel.invokeMethod('openOverlaySettings');

  Future<void> _onAction(MethodCall call) async {
    if (_finished) return;
    switch (call.arguments) {
      case 'play':
        unawaited(controller.playResult());
      case 'retry':
        unawaited(controller.start());
      case 'close':
        unawaited(controller.finish());
        onClose();
    }
  }

  Future<void> finish() {
    if (_finishing case final work?) return work;
    _finished = true;
    return _finishing = () async {
      await channel.invokeMethod('hide');
      await _startingService;
      if (_service) {
        _service = false;
        await channel.invokeMethod('stopService');
      }
    }();
  }

  void dispose() {
    controller.removeListener(_sync);
    _lifecycle.dispose();
    channel.setMethodCallHandler(null);
    unawaited(finish());
  }
}
