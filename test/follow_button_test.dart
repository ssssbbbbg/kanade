import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/auth/auth_controller.dart';
import 'package:kanade/l10n/l10n_ext.dart';
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/ui/follow_button.dart';
import 'package:provider/provider.dart';

class _Auth extends ChangeNotifier implements AuthController {
  @override
  UserInfo? user = const UserInfo(uin: 'test', nickname: 'test', avatarUrl: '');

  @override
  SessionEndReason? sessionEnd;

  @override
  void dismissSessionEnd() => sessionEnd = null;

  @override
  bool get loggedIn => user != null;

  @override
  void reloadSession() => notifyListeners();

  @override
  void onLoggedIn(UserInfo u) {
    user = u;
    notifyListeners();
  }

  @override
  Future<UserInfo> loginWithCookie(String cookie) => throw UnimplementedError();

  @override
  Future<void> logout() async {
    user = null;
    notifyListeners();
  }
}

Future<void> _show(WidgetTester tester, _Auth auth, Future<void> Function(bool) submit) async {
  bool followed = false;
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthController>.value(
      value: auth,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FollowButton(
              followed: followed,
              onChanged: (value) async {
                await submit(value);
                setState(() => followed = value);
              },
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('follow waits for success and prevents duplicate submissions', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await _show(tester, _Auth(), (value) {
      expect(value, isTrue);
      calls++;
      return pending.future;
    });
    await tester.tap(find.text('关注'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(find.text('已关注'), findsNothing);
    await tester.tap(find.text('关注'));
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('已关注'), findsOneWidget);
  });

  testWidgets('failed follow retains the previous state and offers retry', (tester) async {
    await _show(tester, _Auth(), (_) async => throw StateError('rejected'));
    await tester.tap(find.text('关注'));
    await tester.pump();
    expect(find.text('已关注'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('anonymous follow never sends a write', (tester) async {
    var calls = 0;
    await _show(tester, _Auth()..user = null, (_) async {
      calls++;
    });
    await tester.tap(find.text('关注'));
    await tester.pump();
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
