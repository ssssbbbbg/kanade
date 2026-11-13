import 'dart:async';

import 'package:flutter/foundation.dart';

import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

/// 登录状态。登录态本身由 Rust 层持久化在 SQLite 里。
class AuthController extends ChangeNotifier {
  /// [watchSession] 为 true 时（界面进程）登录凭证被服务器拒绝会自动退出登录，
  /// 启动时也复核一次。Android 播放进程传 false，由界面进程同步过来。
  AuthController({bool watchSession = true}) : user = api.currentUser() {
    if (!watchSession) return;
    _sessionEnds = api.watchSessionEnd().listen(_onSessionEnded);
    unawaited(api.checkSession());
  }

  UserInfo? user;

  /// 被自动退出登录的原因，界面提示过后用 [dismissSessionEnd] 清掉。
  SessionEndReason? sessionEnd;

  StreamSubscription<SessionEndReason>? _sessionEnds;

  bool get loggedIn => user != null;

  void reloadSession() {
    user = api.currentUser();
    notifyListeners();
  }

  void onLoggedIn(UserInfo u) {
    user = u;
    sessionEnd = null;
    api.clearCache();
    notifyListeners();
  }

  Future<UserInfo> loginWithCookie(String cookie) async {
    final u = await api.loginWithCookie(cookie: cookie);
    onLoggedIn(u);
    return u;
  }

  Future<void> logout() async {
    await api.logout();
    await api.clearCache();
    user = null;
    notifyListeners();
  }

  /// Rust 层已经清掉了登录态和接口缓存。
  void _onSessionEnded(SessionEndReason reason) {
    user = null;
    sessionEnd = reason;
    notifyListeners();
  }

  void dismissSessionEnd() => sessionEnd = null;

  @override
  void dispose() {
    _sessionEnds?.cancel();
    super.dispose();
  }
}
