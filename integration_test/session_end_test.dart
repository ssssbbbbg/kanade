import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kanade/app.dart';
import 'package:kanade/l10n/app_localizations.dart';
import 'package:kanade/src/rust/api/music.dart' as api;
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/ui/glass.dart';
import 'package:kanade/ui/home_shell.dart';
import 'package:kanade/ui/mine_page.dart';
import 'package:kanade/ui/session_ended_dialog.dart';
import 'package:window_manager/window_manager.dart';

/// 服务器拒绝登录凭证时自动退出并提示原因。用空白数据目录和假凭证，不碰真实登录态。
/// 各种原因在宽窗口和手机宽度下的截图存到系统临时目录的 kanade_session_end 里。
/// flutter drive -d windows --driver=test_driver/integration_test.dart --target=integration_test/session_end_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('登录凭证被拒绝时自动退出并提示', (tester) async {
    final data = Directory(
      '${Directory.systemTemp.path}/kanade_session_end_data',
    );
    if (data.existsSync()) data.deleteSync(recursive: true);
    data.createSync();
    final out = Directory('${Directory.systemTemp.path}/kanade_session_end');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync();
    await initApp(dataDir: data.path);
    await windowManager.setSize(const Size(1280, 800));
    await api.loginWithCookie(cookie: 'uin=1234567890; qm_keyst=Q_H_L_invalid');

    final view = tester.binding.renderViews.first;
    Future<void> shoot(String name) => tester.runAsync(() async {
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final image = await layer.toImage(
        Offset.zero & view.flutterView.physicalSize,
        pixelRatio: 1,
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      ExcludeSemantics(
        excluding: Platform.isWindows,
        child: KanadeGlass.wrap(
          child: const AppProviders(mediaSession: false, child: KanadeApp()),
        ),
      ),
    );
    final dialog = find.byIcon(Icons.link_off_rounded);
    for (var i = 0; i < 100 && dialog.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await settle();
    final l = AppLocalizations.of(tester.element(find.byType(HomeShell)));
    expect(find.text(l.sessionEndedTitle), findsOneWidget);
    expect(find.text(l.sessionRejected), findsOneWidget);
    expect(api.currentUser(), isNull);
    await shoot('desktop_unknown');

    await tester.tap(find.text(l.loginAgain));
    await settle();
    expect(find.text(l.sessionEndedTitle), findsNothing);
    expect(find.byType(MinePage), findsOneWidget);
    expect(find.text(l.loginMethods), findsOneWidget);

    Future<void> showReason(String name, SessionEndReason reason) async {
      unawaited(
        showSessionEndedDialog(tester.element(find.byType(HomeShell)), reason),
      );
      await settle();
      await shoot(name);
      await tester.tap(find.text(l.later));
      await settle();
      expect(find.text(l.sessionEndedTitle), findsNothing);
    }

    await showReason('desktop_revoked', SessionEndReason.revoked);
    await showReason('desktop_expired', SessionEndReason.expired);
    await tester.runAsync(() => windowManager.setSize(const Size(430, 900)));
    await settle();
    await showReason('phone_revoked', SessionEndReason.revoked);
    await showReason('phone_unknown', SessionEndReason.unknown);
    await tester.runAsync(() => windowManager.setSize(const Size(1280, 800)));
    await settle();

    // 其他改成同一样式的弹窗：Cookie 登录（含错误提示）和扫码登录
    await tester.tap(find.text(l.loginCookie));
    await settle();
    expect(find.text(l.cookieLoginTitle), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'not a cookie');
    await tester.tap(find.text(l.login));
    await settle();
    await shoot('desktop_cookie');
    await tester.tap(find.text(l.cancel));
    await settle();
    expect(find.text(l.cookieLoginTitle), findsNothing);

    await tester.tap(find.text(l.loginQq));
    final qr = find.descendant(
      of: find.byType(QrLoginDialog),
      matching: find.byType(Image),
    );
    for (var i = 0; i < 100 && qr.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await settle();
    await shoot('desktop_qr');
    await tester.tap(find.text(l.cancel));
    await settle();
  });
}
