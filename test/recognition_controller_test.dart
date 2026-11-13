import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/player/player_controller.dart';
import 'package:kanade/recognition/android_recognition_platform.dart';
import 'package:kanade/recognition/recognition_controller.dart';
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/src/rust/frb_generated.dart';
import 'package:record/record.dart';

Song _song(int id) => Song(
  id: id,
  mid: 'm$id',
  name: 'song$id',
  singers: [],
  albumMid: '',
  albumName: '',
  durationSecs: 200,
  mediaMid: 'media$id',
  coverUrl: '',
  vip: false,
  hasHq: true,
  hasFlac: true,
  mvVid: '',
);

class _Player extends ChangeNotifier implements PlayerController {
  @override
  bool playing = true;
  @override
  Song? current = _song(1);
  int plays = 0;
  Completer<void>? pausing;
  @override
  Future<void> pause() async {
    await pausing?.future;
    playing = false;
  }

  @override
  Future<void> play() async {
    plays++;
    playing = true;
  }

  @override
  Future<void> playList(List<Song> songs, int start) async {
    current = songs[start];
    playing = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recorder implements AudioRecorder {
  final audio = StreamController<Uint8List>.broadcast();
  Completer<bool>? permission;
  Completer<Stream<Uint8List>>? starting;
  bool granted = true;
  int starts = 0;
  int stops = 0;
  bool disposed = false;
  final events = <String>[];
  @override
  Future<bool> hasPermission({bool request = true}) async =>
      permission == null ? granted : await permission!.future;
  @override
  Future<void> setOnConfigChanged(
    void Function(RecordConfig)? callback,
  ) async {}
  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    expectSync(config.audioInterruption, AudioInterruptionMode.none);
    starts++;
    events.add('start');
    return starting == null ? audio.stream : await starting!.future;
  }

  @override
  Future<String?> stop() async {
    stops++;
    events.add('stop');
    return null;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await audio.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements RustLibApi {
  final requests = <int>[];
  Future<Song?> Function() respond = () async => null;
  @override
  Future<Song?> crateApiMusicRecognizeSong({
    required int sessionId,
    required List<int> pcm,
  }) {
    requests.add(sessionId);
    return respond();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Channel extends MethodChannel {
  _Channel() : super('test/recognize');
  final calls = <String>[];
  final updates = <Map<Object?, Object?>>[];
  Future<dynamic> Function(MethodCall)? handler;
  Completer<bool>? startingService;
  bool overlay = true;
  bool serviceStarted = true;
  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? value) {
    handler = value;
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    calls.add(method);
    if (method == 'update') updates.add(arguments as Map<Object?, Object?>);
    final Object? result = switch (method) {
      'canOverlay' => overlay,
      'startService' =>
        startingService == null
            ? serviceStarted
            : await startingService!.future,
      _ => null,
    };
    return result as T?;
  }
}

void main() {
  final api = _Api();
  late _Player player;
  late _Recorder recorder;
  late RecognitionController controller;
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.requests.clear();
    api.respond = () async => null;
  });
  void recognitionTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      player = _Player();
      recorder = _Recorder();
      controller = RecognitionController(player, recorder: recorder);
      try {
        await body(tester);
      } finally {
        controller.dispose();
        await tester.pump();
        player.dispose();
      }
    });
  }

  recognitionTest('uploads at existing intervals and stops after no match', (
    tester,
  ) async {
    await controller.start();
    recorder.audio.add(Uint8List(16000));
    for (var second = 1; second <= 15; second++) {
      await tester.pump(const Duration(seconds: 1));
      expect(
        api.requests.length,
        [1, 2, 3, 6, 9, 12, 15].where((v) => v <= second).length,
      );
    }
    expect(api.requests.toSet(), hasLength(1));
    expect(controller.phase, RecognitionPhase.notFound);
    final count = api.requests.length;
    await tester.pump(const Duration(seconds: 5));
    expect(api.requests, hasLength(count));
    await controller.finish();
    await controller.finish();
    expect(player.plays, 1);
  });

  recognitionTest(
    'success stops capture and playing result does not resume old song',
    (tester) async {
      api.respond = () async => _song(2);
      await controller.start();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.phase, RecognitionPhase.found);
      expect(controller.song?.id, 2);
      await tester.pump(const Duration(seconds: 4));
      expect(api.requests, hasLength(1));
      await controller.playResult();
      await controller.finish();
      expect(player.current?.id, 2);
      expect(player.plays, 0);
    },
  );

  recognitionTest(
    'permission denial and upload error retain their distinct causes',
    (tester) async {
      recorder.granted = false;
      await controller.start();
      expect(controller.phase, RecognitionPhase.failed);
      expect(controller.error, RecognitionFailure.noMicrophone);
      expect(recorder.starts, 0);
      recorder.granted = true;
      final error = StateError('network');
      api.respond = () async => throw error;
      await controller.start();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.phase, RecognitionPhase.failed);
      expect(controller.error, same(error));
      await tester.pump(const Duration(seconds: 5));
      expect(api.requests, hasLength(1));
    },
  );

  recognitionTest(
    'retry ignores old upload and its completion cannot unlock new upload',
    (tester) async {
      final old = Completer<Song?>();
      api.respond = () => old.future;
      await controller.start();
      await tester.pump(const Duration(seconds: 1));
      final current = Completer<Song?>();
      api.respond = () => current.future;
      await controller.start();
      await tester.pump(const Duration(seconds: 1));
      expect(api.requests.toSet(), hasLength(2));
      old.complete(_song(9));
      await tester.pump(const Duration(seconds: 1));
      expect(
        controller.phase,
        RecognitionPhase.listening,
        reason: controller.error.toString(),
      );
      expect(api.requests, hasLength(2));
      current.complete(_song(2));
      await tester.pump();
      expect(controller.song?.id, 2);
    },
  );

  recognitionTest('closing during permission does not start recording', (
    tester,
  ) async {
    final permission = recorder.permission = Completer<bool>();
    final start = controller.start();
    await tester.pump();
    final finish = controller.finish();
    permission.complete(true);
    await start;
    await finish;
    expect(recorder.starts, 0);
    expect(player.plays, 1);
    await controller.start();
    expect(recorder.starts, 0);
  });

  recognitionTest(
    'closing while pause is pending restores playback after pause',
    (tester) async {
      final pause = player.pausing = Completer<void>();
      final start = controller.start();
      await tester.pump();
      final finish = controller.finish();
      pause.complete();
      await start;
      await finish;
      expect(player.playing, isTrue);
      expect(player.plays, 1);
      expect(recorder.starts, 0);
    },
  );

  recognitionTest(
    'retry serializes recorder startup and closing stops a late startup',
    (tester) async {
      final pending = recorder.starting = Completer<Stream<Uint8List>>();
      final first = controller.start();
      await tester.pump();
      expect(controller.error, isNull);
      expect(recorder.starts, 1);
      final second = controller.start();
      recorder.starting = null;
      pending.complete(recorder.audio.stream);
      await first;
      await second;
      expect(recorder.events, ['stop', 'start', 'stop', 'start']);
      await controller.finish();
      expect(recorder.events.last, 'stop');
    },
  );

  recognitionTest(
    'dispose while recorder starts cleans resources without notifications',
    (tester) async {
      final pending = recorder.starting = Completer<Stream<Uint8List>>();
      final start = controller.start();
      await tester.pump();
      expect(recorder.starts, 1);
      controller.dispose();
      pending.complete(recorder.audio.stream);
      await start;
      await tester.pump();
      expect(recorder.disposed, isTrue);
      expect(recorder.events.last, 'stop');
      expect(tester.takeException(), isNull);
    },
  );

  recognitionTest(
    'close invalidates in-flight upload and leaves a newly selected song alone',
    (tester) async {
      final pending = Completer<Song?>();
      api.respond = () => pending.future;
      await controller.start();
      await tester.pump(const Duration(seconds: 1));
      player.current = _song(3);
      await controller.finish();
      pending.complete(_song(2));
      await tester.pump();
      expect(controller.song, isNull);
      expect(player.plays, 0);
    },
  );

  recognitionTest(
    'Android service rejection does not retry on every progress update',
    (tester) async {
      final channel = _Channel()..serviceStarted = false;
      final platform = AndroidRecognitionPlatform(
        controller,
        title: 'Recognize',
        message: () => 'No match',
        onChanged: () {},
        onClose: () {},
        channel: channel,
      );
      await controller.start();
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        channel.calls.where((call) => call == 'startService'),
        hasLength(1),
      );
      await controller.finish();
      await platform.finish();
      expect(channel.calls, isNot(contains('stopService')));
      platform.dispose();
    },
  );

  recognitionTest(
    'Android adapter waits for pending service start before cleanup',
    (tester) async {
      final channel = _Channel();
      final pending = channel.startingService = Completer<bool>();
      var closed = 0;
      final platform = AndroidRecognitionPlatform(
        controller,
        title: 'Recognize',
        message: () => 'No match',
        onChanged: () {},
        onClose: () {
          closed++;
        },
        channel: channel,
      );
      await controller.start();
      await tester.pump();
      expect(channel.calls.where((c) => c == 'startService'), hasLength(1));
      await channel.handler!(const MethodCall('action', 'close'));
      pending.complete(true);
      await platform.finish();
      await controller.finish();
      expect(closed, 1);
      expect(channel.calls.where((c) => c == 'stopService'), hasLength(1));
      platform.dispose();
      expect(channel.handler, isNull);
    },
  );

  recognitionTest(
    'Android adapter updates result while backgrounded and routes actions',
    (tester) async {
      final channel = _Channel();
      final pending = Completer<Song?>();
      api.respond = () => pending.future;
      final platform = AndroidRecognitionPlatform(
        controller,
        title: 'Recognize',
        message: () => 'No match',
        onChanged: () {},
        onClose: () {},
        channel: channel,
      );
      await controller.start();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 1));
      expect(channel.calls, contains('show'));
      pending.complete(_song(2));
      await tester.pump();
      expect(channel.updates.last['mode'], 'found');
      await channel.handler!(const MethodCall('action', 'play'));
      await tester.pump();
      expect(player.current?.id, 2);
      await channel.handler!(const MethodCall('action', 'retry'));
      await tester.pump();
      expect(
        controller.phase,
        RecognitionPhase.listening,
        reason: controller.error.toString(),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(channel.calls, contains('hide'));
      await controller.finish();
      await platform.finish();
      platform.dispose();
    },
  );
}
