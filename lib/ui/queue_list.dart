import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'widgets.dart';

/// 播放队列列表：点一首播放，每行可以移除、按住右边的手柄拖动排序。
/// 播放页和桌面播放栏的队列弹窗共用。
class QueueList extends StatelessWidget {
  const QueueList({
    super.key,
    required this.controller,
    required this.color,
    required this.dragColor,
    this.physics,
    this.padding = const EdgeInsets.fromLTRB(12, 4, 12, 40),
    this.onHandleDown,
  });

  static const extent = 64.0;

  /// 打开时让当前这首露在第二行。
  static double initialOffset(int index) => max(0, (index - 1) * extent);

  final ScrollController controller;

  /// 文字和图标的颜色，其他深浅都从它推出来。
  final Color color;

  /// 拖动中那一行的底色，要够实，盖住下面挪动的行。
  final Color dragColor;
  final ScrollPhysics? physics;
  final EdgeInsets padding;

  /// 在拖动手柄上按下；外面自己看手势的（播放页往下拉翻回）借此让开。
  final VoidCallback? onHandleDown;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    return ReorderableListView.builder(
      scrollController: controller,
      physics: physics,
      itemExtent: extent,
      padding: padding,
      buildDefaultDragHandles: false,
      itemCount: p.queue.length,
      onReorderItem: p.moveQueue,
      proxyDecorator: (child, _, _) => Material(
        color: dragColor,
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
      itemBuilder: (_, i) => QueueTile(
        key: ObjectKey(p.queue[i]),
        index: i,
        song: p.queue[i],
        color: color,
        current: i == p.index,
        played: i < p.index,
        playing: p.playing,
        onTap: () => p.playAt(i),
        onRemove: () => p.removeAt(i),
        onHandleDown: onHandleDown,
      ),
    );
  }
}

/// 队列封面只有 46px，按显示尺寸解码，不用解出整张 300px 原图。
/// 提前加载和列表显示用同一个对象，图片缓存才对得上。
ImageProvider queueCover(BuildContext context, Song song) => ResizeImage(
  NetworkImage(httpsUrl(song.coverUrl)),
  width: (46 * MediaQuery.devicePixelRatioOf(context)).round(),
);

class QueueTile extends StatefulWidget {
  const QueueTile({
    super.key,
    required this.index,
    required this.song,
    required this.color,
    required this.current,
    required this.played,
    required this.playing,
    required this.onTap,
    required this.onRemove,
    this.onHandleDown,
  });

  final int index;
  final Song song;
  final Color color;
  final bool current;
  final bool played;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onHandleDown;

  @override
  State<QueueTile> createState() => _QueueTileState();
}

class _QueueTileState extends State<QueueTile> {
  /// 手机没有悬停，移除和手柄一直显示；桌面上鼠标移到这一行才出来。
  static final _alwaysShowActions = Platform.isAndroid;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final song = widget.song;
    final color = widget.color;
    final showActions = _alwaysShowActions || _hover;
    // 已播放的歌用颜色变淡，不用 Opacity 图层
    final fg = widget.played ? 0.45 : 1.0;
    final actionColor = color.withValues(alpha: 0.6);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: color.withValues(alpha: 0.1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.fromLTRB(12, 8, showActions ? 4 : 12, 8),
            decoration: BoxDecoration(
              color: widget.current
                  ? color.withValues(alpha: 0.12)
                  : color.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    SizedBox.square(
                      dimension: 46,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image(
                          image: queueCover(context, song),
                          fit: BoxFit.cover,
                          color: widget.played ? const Color(0x73FFFFFF) : null,
                          colorBlendMode: BlendMode.modulate,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: color.withValues(alpha: 0.12)),
                        ),
                      ),
                    ),
                    if (widget.current)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: NowPlayingBars(playing: widget.playing),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: widget.current
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: color.withValues(alpha: fg),
                        ),
                      ),
                      Text(
                        singerNames(song),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: color.withValues(alpha: 0.6 * fg),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_alwaysShowActions && !showActions)
                  Text(
                    formatDuration(Duration(seconds: song.durationSecs)),
                    style: TextStyle(
                      fontSize: 12,
                      color: color.withValues(alpha: 0.38 * fg),
                    ),
                  ),
                if (showActions) ...[
                  IconButton(
                    tooltip: l.removeFromQueue,
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onRemove,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: actionColor,
                    ),
                  ),
                  Listener(
                    onPointerDown: (_) => widget.onHandleDown?.call(),
                    child: ReorderableDragStartListener(
                      index: widget.index,
                      child: Tooltip(
                        message: l.reorderQueue,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: SizedBox(
                            width: 36,
                            height: 40,
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              size: 20,
                              color: actionColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 正在播放的跳动音柱。
class NowPlayingBars extends StatefulWidget {
  const NowPlayingBars({super.key, required this.playing});

  final bool playing;

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(NowPlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) _c.repeat();
    if (!widget.playing) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.2),
              width: 3,
              height: widget.playing
                  ? 5 +
                        11 *
                            (0.5 +
                                0.5 *
                                    sin(
                                      _c.value * 2 * pi * (i.isEven ? 2 : 3) +
                                          i * 1.3,
                                    ))
                  : 4,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
