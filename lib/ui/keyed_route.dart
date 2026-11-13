import 'package:flutter/material.dart';

/// 按 id 打开的页面（歌手、专辑、歌单、用户）。
/// 同一个页面已经在当前这一叠里时 [openPage] 退回到它，不会在上面再叠一份。
final _keyed = <Route<void>>[];

Route<void> keyedPage(String key, WidgetBuilder builder) {
  final route = MaterialPageRoute<void>(
    settings: RouteSettings(name: key),
    builder: builder,
  );
  _keyed.add(route);
  route.popped.whenComplete(() => _keyed.remove(route));
  return route;
}

/// [nav] 里还开着的 [key] 页面。
Route<void>? findPage(NavigatorState nav, String? key) {
  if (key == null) return null;
  // 被整叠清掉的页面不一定走 popped，顺手清理
  _keyed.removeWhere((r) => r.navigator != null && !r.isActive);
  for (final r in _keyed.reversed) {
    if (r.isActive && r.navigator == nav && r.settings.name == key) return r;
  }
  return null;
}

/// 在 [nav] 里打开 [route]；同一个页面已经开着就退回到它。
void openPageIn(NavigatorState nav, Route<void> route) {
  final existing = findPage(nav, route.settings.name);
  if (existing == null) {
    nav.push(route);
    return;
  }
  // 这一份没用上
  _keyed.remove(route);
  nav.popUntil((r) => r == existing);
}

void openPage(BuildContext context, Route<void> route) =>
    openPageIn(Navigator.of(context), route);
