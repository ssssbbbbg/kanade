import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'glass.dart';

/// 歌曲列表里正在播放的那首滚出屏幕后，右下角浮出一颗玻璃定位钮；点一下平滑滚过去，
/// 停在可见区域中间偏上，再让那一行背景闪两下。
///
/// 歌曲那一段要用 [SliverPrototypeExtentList]（每行一样高，位置才算得准）并挂上 [listKey]，
/// 每一行套一层 [LocateHighlight]。
class LocateCurrentSong extends StatefulWidget {
  const LocateCurrentSong({
    super.key,
    required this.controller,
    required this.listKey,
    required this.songs,
    required this.child,
  });

  final ScrollController controller;
  final GlobalKey listKey;

  /// 列表里实际显示的歌，顺序和行一致。
  final List<Song> songs;
  final Widget child;

  @override
  State<LocateCurrentSong> createState() => _LocateCurrentSongState();
}

class _LocateCurrentSongState extends State<LocateCurrentSong>
    with SingleTickerProviderStateMixin {
  static const _buttonSize = 44.0;
  static const _margin = 16.0;

  /// 那一行停在可见区域从上往下这个比例的位置。
  static const _anchor = 0.4;

  int _index = -1;
  bool _show = false;

  final _flashIndex = ValueNotifier<int?>(null);
  late final _flash =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _flashIndex.value = null;
      });

  /// 两下闪：亮、回落一点、再亮、慢慢褪掉。
  late final _flashValue = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 12,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.25,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 18,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.25,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 16,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 54,
    ),
  ]).animate(_flash);

  @override
  void dispose() {
    _flash.dispose();
    _flashIndex.dispose();
    super.dispose();
  }

  RenderSliverFixedExtentBoxAdaptor? get _sliver {
    final sliver = widget.listKey.currentContext?.findRenderObject();
    return sliver is RenderSliverFixedExtentBoxAdaptor &&
            sliver.geometry != null
        ? sliver
        : null;
  }

  double get _bottomInset => MediaQuery.paddingOf(context).bottom;

  /// 那一行的中线在不在屏幕上露出来的那段里（扣掉顶上钉住的头部和底下的播放条）。
  bool _onScreen(RenderSliverFixedExtentBoxAdaptor sliver, int i) {
    final c = sliver.constraints;
    final extent = sliver.itemExtent!;
    final center = extent * i + extent / 2;
    return center >= c.scrollOffset + c.overlap &&
        center <= c.scrollOffset + c.remainingPaintExtent - _bottomInset;
  }

  bool _scheduled = false;

  /// 滚动通知发出时列表还没按新位置排版，等这一帧排完再看；同一帧里只看一次。
  void _scheduleUpdate() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _update();
    });
  }

  void _update() {
    if (!mounted) return;
    final sliver = _sliver;
    final show = _index >= 0 && sliver != null && !_onScreen(sliver, _index);
    if (show != _show) setState(() => _show = show);
  }

  Future<void> _locate() async {
    final sliver = _sliver;
    final i = _index;
    if (sliver == null || i < 0 || !widget.controller.hasClients) return;
    final pos = widget.controller.position;
    final extent = sliver.itemExtent!;
    final top = MediaQuery.paddingOf(context).top + GlassBackScaffold.topInset;
    final visible = pos.viewportDimension - top - _bottomInset;
    final target =
        (sliver.constraints.precedingScrollExtent +
                extent * i +
                extent / 2 -
                top -
                visible * _anchor)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    // 远的先一下跳到离目标一屏多的地方，只滑最后这段：整段几千像素塞进半秒，
    // 一帧要跳好几行，看着一顿一顿的，减速也看不出来
    final lead = pos.viewportDimension * 1.2;
    final distance = target - pos.pixels;
    if (distance.abs() > lead) pos.jumpTo(target - lead * distance.sign);
    final ratio = (target - pos.pixels).abs() / lead;
    // 一开始就冲出去，快到时慢慢刹住
    await pos.animateTo(
      target,
      duration: Duration(milliseconds: (260 + 240 * ratio).round()),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || i != _index) return;
    final after = _sliver;
    // 中途被手拖走了就不闪
    if (after == null || !_onScreen(after, i)) return;
    _flashIndex.value = i;
    _flash.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final mid = context.select<PlayerController, String?>(
      (p) => p.current?.mid,
    );
    _index = mid == null ? -1 : widget.songs.indexWhere((s) => s.mid == mid);
    // 切歌、列表筛选变了以后等这一帧排好版再看要不要显示
    _scheduleUpdate();
    final scheme = Theme.of(context).colorScheme;
    final bottom = _bottomInset + _margin;
    return KanadeGlass.backdropScope(
      child: Stack(
        children: [
          Positioned.fill(
            child: KanadeGlass.backdropSource(
              // 只有这颗钮在取样，留出透镜和模糊的边
              captureBounds: (size) => Rect.fromLTRB(
                size.width - _margin - _buttonSize - 32,
                size.height - bottom - _buttonSize - 32,
                size.width,
                size.height - bottom + 32,
              ),
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.depth == 0) _scheduleUpdate();
                  return false;
                },
                child: _Scope(
                  flashIndex: _flashIndex,
                  flash: _flashValue,
                  child: widget.child,
                ),
              ),
            ),
          ),
          Positioned(
            right: _margin,
            bottom: bottom,
            child: IgnorePointer(
              ignoring: !_show,
              child: GlassMaterialize(
                visible: _show,
                // 藏起来以后整个拿掉，Windows 上不再每帧截图
                maintainState: false,
                child: GlassIconButton(
                  size: _buttonSize,
                  useOwnLayer: true,
                  settings: KanadeGlass.navigationSettings(context),
                  quality: KanadeGlass.navigationQuality,
                  semanticLabel: AppLocalizations.of(context).locateCurrentSong,
                  onPressed: _locate,
                  icon: Icon(
                    Icons.my_location_rounded,
                    size: 20,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Scope extends InheritedWidget {
  const _Scope({
    required this.flashIndex,
    required this.flash,
    required super.child,
  });

  final ValueNotifier<int?> flashIndex;
  final Animation<double> flash;

  @override
  bool updateShouldNotify(_Scope old) =>
      old.flashIndex != flashIndex || old.flash != flash;
}

/// 定位到这一行后背景闪两下。外面没有 [LocateCurrentSong] 时原样显示 [child]。
class LocateHighlight extends StatelessWidget {
  const LocateHighlight({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_Scope>();
    if (scope == null) return child;
    final color = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<int?>(
      valueListenable: scope.flashIndex,
      child: child,
      builder: (context, flashing, child) => flashing != index
          ? child!
          : AnimatedBuilder(
              animation: scope.flash,
              child: child,
              builder: (context, child) => DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2 * scope.flash.value),
                ),
                child: child,
              ),
            ),
    );
  }
}
