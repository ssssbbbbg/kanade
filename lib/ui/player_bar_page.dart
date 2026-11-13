import 'package:flutter/material.dart';

import 'desktop_shell.dart';
import 'glass.dart';
import 'keyed_route.dart';
import 'mini_player.dart';
import 'player_route.dart';

/// 从播放页进的二级页面（歌手、专辑……）：盖在播放页上面，返回就回到播放页。
/// 页面底部自带一条播放条，进来时从下往上弹出，返回时跟着页面一起走。
/// 里面有自己的 Navigator，在这里接着点进的页面也带着这条播放条。
/// 同一时间只有一层：点这条播放条打开的播放页里再进歌手页，不会再叠一层，见 [pushFromPlayer]。
class PlayerBarPage extends StatefulWidget {
  const PlayerBarPage({super.key, required this.first});

  /// 里面的第一个页面。
  final Route<void> first;

  static Route<void> route(Route<void> first) =>
      MaterialPageRoute(builder: (_) => PlayerBarPage(first: first));

  @override
  State<PlayerBarPage> createState() => _PlayerBarPageState();
}

class _PlayerBarPageState extends State<PlayerBarPage>
    with SingleTickerProviderStateMixin {
  static _PlayerBarPageState? _open;

  final _nav = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _open = this;
  }

  /// 从这条播放条打开的播放页里又要进 [route]：收起播放页，在这一层里接着推；
  /// 这一页这一层里已经开着就退回到它。
  void openFrom(PlayerRoute player, Route<void> route) {
    // 更多面板这时可能还在关，先退到播放页再收起它
    player.navigator!
      ..popUntil((r) => r == player)
      ..pop();
    final inner = _nav.currentState;
    if (inner != null) openPageIn(inner, route);
  }

  // 每一层都有自己的播放条，播放页要变形回打开它的那一条
  final _miniAnchor = MiniPlayer.newAnchor();
  final _desktopAnchor = DesktopPlayerBar.newAnchor();

  late final _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();
  late final _offset = CurvedAnimation(
    parent: _rise,
    curve: Curves.easeOutBack,
  );

  @override
  void dispose() {
    if (_open == this) _open = null;
    _offset.dispose();
    _rise.dispose();
    super.dispose();
  }

  /// 系统返回和左上角的返回钮都走这里：里面还有页面就退里面的，退到第一页再关掉自己。
  /// 里面的页面自己拦着返回（比如歌单页先退出搜索）时也先交给它。
  Future<void> _onPop() async {
    final handled = await _nav.currentState?.maybePop() ?? false;
    if (!handled && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final wide = mq.size.width >= 960;
    const gap = 12.0;
    final barHeight = wide ? DesktopPlayerBar.height : MiniPlayer.height;
    final barBottom = mq.padding.bottom + (wide ? gap : 8);
    final barSpace = barHeight + (wide ? gap * 2 : 16);
    final bar = wide
        ? DesktopPlayerBar(barAnchor: _desktopAnchor)
        : SizedBox(
            height: MiniPlayer.height,
            child: MiniPlayer(barAnchor: _miniAnchor),
          );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPop();
      },
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: KanadeGlass.backdropScope(
          child: Stack(
            children: [
              Positioned.fill(
                // 播放条的玻璃长成播放页时会变高，这段时间截到它最高长到的地方
                child: ValueListenableBuilder(
                  valueListenable:
                      (wide ? _desktopAnchor : _miniAnchor).growing,
                  builder: (_, growing, child) => KanadeGlass.backdropSource(
                    captureBounds: (size) => Rect.fromLTRB(
                      0,
                      (size.height - barBottom - barHeight) *
                              (growing == null
                                  ? 1
                                  : 1 - PlayerMorph.glassUntil) -
                          32,
                      size.width,
                      size.height,
                    ),
                    child: child!,
                  ),
                  child: MediaQuery(
                    // 播放条浮在内容上面，列表滚到底时最后一项不被它挡住
                    data: mq.copyWith(
                      padding: mq.padding.copyWith(
                        bottom: mq.padding.bottom + barSpace,
                      ),
                    ),
                    child: Navigator(
                      key: _nav,
                      onGenerateInitialRoutes: (_, _) => [widget.first],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: wide ? gap : 16,
                right: wide ? gap : 16,
                bottom: barBottom,
                child: AnimatedBuilder(
                  animation: _offset,
                  child: bar,
                  builder: (_, bar) => Transform.translate(
                    offset: Offset(
                      0,
                      (1 - _offset.value) * (barHeight + barBottom + 16),
                    ),
                    child: bar,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 从 [context] 所在的地方打开 [route]，同一个页面已经开着就退回到它（见 [openPage]）。
/// 在播放页里就套一层 [PlayerBarPage] 盖在播放页上面；已经有这一层了（播放页是从它的播放条打开的）就放进那一层里。
void pushFromPlayer(BuildContext context, Route<void> route) {
  final player = ModalRoute.of(context);
  if (player is! PlayerRoute) {
    openPage(context, route);
    return;
  }
  final open = _PlayerBarPageState._open;
  if (open != null && open.mounted) {
    open.openFrom(player, route);
  } else {
    Navigator.of(context).push(PlayerBarPage.route(route));
  }
}
