import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'desktop_queue_popup.dart';
import 'glass.dart';
import 'play_pause_button.dart';
import 'player_background.dart';
import 'player_route.dart';
import 'playlist_actions.dart';
import 'smooth_scroll.dart';
import 'song_actions.dart';
import 'widgets.dart';

/// 桌面宽屏的左侧栏：三个标签 + 我的歌单。实心卡片，不用玻璃（它不浮在内容上）。
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelect,
    required this.onOpenPlaylist,
  });

  static const width = 228.0;

  final List<(IconData, IconData, String)> destinations;
  final int selected;
  final ValueChanged<int> onSelect;
  final void Function(PlaylistBrief) onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final user = context.select<AuthController, UserInfo?>((a) => a.user);
    final playlistsVersion = context.select<LibraryController, int>(
      (c) => c.playlistsVersion,
    );
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                // 选中的底色是单独一块，切换时从原来的按钮上下滑到新按钮
                AnimatedPositioned(
                  duration: _NavItem.motion,
                  curve: Curves.easeOutCubic,
                  left: 0,
                  right: 0,
                  top: selected * (_NavItem.height + _NavItem.gap),
                  height: _NavItem.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, d) in destinations.indexed)
                      _NavItem(
                        icon: i == selected ? d.$2 : d.$1,
                        label: d.$3,
                        selected: i == selected,
                        onTap: () => onSelect(i),
                      ),
                  ],
                ),
              ],
            ),
            if (user != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
                ),
                child: Divider(height: 1, color: scheme.outlineVariant),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                child: Text(
                  l.myPlaylists,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                // 换账号、歌单被改动后重新拉取
                child: _SidebarPlaylists(
                  key: ValueKey((user.uin, playlistsVersion)),
                  onOpen: onOpenPlaylist,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const height = 42.0;
  static const gap = 4.0;
  static const motion = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 选中态：白底黑字；底色由侧栏画，这里只跟着它渐变文字颜色
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        end: selected ? scheme.onSecondaryContainer : scheme.onSurface,
      ),
      duration: motion,
      curve: Curves.easeOutCubic,
      builder: (context, fg, _) => Padding(
        padding: const EdgeInsets.only(bottom: gap),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarPlaylists extends StatefulWidget {
  const _SidebarPlaylists({super.key, required this.onOpen});

  final void Function(PlaylistBrief) onOpen;

  @override
  State<_SidebarPlaylists> createState() => _SidebarPlaylistsState();
}

class _SidebarPlaylistsState extends State<_SidebarPlaylists> {
  late final Future<List<PlaylistBrief>> _lists = api.getUserPlaylists();
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 右键：自建歌单（“我喜欢”除外）可以改名、删除。
  Future<void> _showActions(PlaylistBrief p) async {
    final own = await context.read<LibraryController>().ownPlaylist(p.id);
    if (mounted && canEditPlaylist(own)) {
      await showPlaylistActions(context, own!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return FutureBuilder<List<PlaylistBrief>>(
      future: _lists,
      // 侧栏只是快捷入口，加载失败就留空，完整列表在“我的”里
      builder: (context, snap) => ListView(
        controller: _scroll,
        padding: EdgeInsets.zero,
        children: [
          for (final p in snap.data ?? const <PlaylistBrief>[])
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.onOpen(p),
              onSecondaryTap: () => _showActions(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Cover(p.coverUrl, size: 36, radius: 8),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (p.songCount > 0)
                            Text(
                              l.songCount(p.songCount),
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 桌面底部整宽的玻璃播放栏：左边歌曲信息，中间播放控制和进度，右边队列和音量。
/// 玻璃里只放普通控件，并且图标颜色要显式给（玻璃层会改写继承的图标颜色）。
class DesktopPlayerBar extends StatefulWidget {
  const DesktopPlayerBar({super.key, this.barAnchor});

  static const height = 84.0;

  /// 窗口底部那条播放栏的锚点，播放页从这里变形出来。
  static final anchor = newAnchor();

  /// 另外摆一条播放栏时（比如从播放页进的歌手页）给它自己的锚点。
  static PlayerBarAnchor newAnchor() {
    late final PlayerBarAnchor a;
    a = PlayerBarAnchor(
      coverRadius: 12,
      face: (_) => Material(
        type: MaterialType.transparency,
        child: _DesktopBarContent(anchor: a, showCover: false),
      ),
    );
    return a;
  }

  /// 不给就是 [DesktopPlayerBar.anchor]。
  final PlayerBarAnchor? barAnchor;

  @override
  State<DesktopPlayerBar> createState() => _DesktopPlayerBarState();
}

class _DesktopPlayerBarState extends State<DesktopPlayerBar>
    with TickerProviderStateMixin {
  late final _anchor = widget.barAnchor ?? DesktopPlayerBar.anchor;
  late final _drag = PlayerBarDrag(_anchor, this);
  late final _visibility = Listenable.merge([_anchor.hidden, _anchor.growing]);

  @override
  Widget build(BuildContext context) {
    final hasSong = context.select<PlayerController, bool>(
      (p) => p.current != null,
    );
    final bar = GestureDetector(
      key: _anchor.barKey,
      // 栏里的空白处也要接住点击，不能漏到下面的列表上
      behavior: HitTestBehavior.opaque,
      // 点空白处打开播放页；栏里的按钮和滑条会先接住自己的点击
      onTap: hasSong ? () => PlayerRoute.open(context, anchor: _anchor) : null,
      // 按住往上拖打开播放页
      onVerticalDragUpdate: hasSong ? (d) => _drag.update(context, d) : null,
      onVerticalDragEnd: hasSong
          ? (d) => _drag.end(context, d.velocity.pixelsPerSecond.dy)
          : null,
      onVerticalDragCancel: hasSong ? () => _drag.end(context, 0) : null,
      child: SizedBox(
        height: DesktopPlayerBar.height,
        // 变形开头玻璃跟着长成播放页的形状，栏里的内容这时由转场层画
        child: PlayerBarGrowth(
          anchor: _anchor,
          builder: (growing, shapeT) => GlassContainer(
            useOwnLayer: true,
            settings: KanadeGlass.navigationSettings(context),
            quality: KanadeGlass.navigationQuality,
            shape: LiquidRoundedRectangle(
              borderRadius: PlayerMorph.radiusAt(
                DesktopPlayerBar.height,
                shapeT,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Opacity(
              opacity: growing ? 0 : 1,
              child: PlayerBarGrowth.pin(
                Material(
                  type: MaterialType.transparency,
                  child: hasSong
                      ? _DesktopBarContent(anchor: _anchor, showCover: true)
                      : const _DesktopBarIdle(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // 播放页盖在上面时由转场层画它，这里藏起来；变形开头只留长大的玻璃
    return ListenableBuilder(
      listenable: _visibility,
      child: bar,
      builder: (_, bar) => Opacity(
        opacity: _anchor.hidden.value && _anchor.growing.value == null ? 0 : 1,
        child: bar,
      ),
    );
  }
}

/// 播放栏里的内容。[showCover] 为 false 时是变形转场画的副本，封面由转场层单独飞。
class _DesktopBarContent extends StatelessWidget {
  const _DesktopBarContent({required this.anchor, required this.showCover});

  final PlayerBarAnchor anchor;
  final bool showCover;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final song = p.current;
    if (song == null) return const SizedBox.shrink();
    prefetchPlayerArt(context, song);
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final liked = context.select<LibraryController, bool>(
      (c) => c.isLiked(song),
    );
    final muted = scheme.onSurfaceVariant;

    return Padding(
      // 两端是半圆，内容往里收一点
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          SizedBox(
            width: 300,
            child: Row(
              children: [
                // 封面和歌名的点击交给外层播放栏打开播放页，不画水波纹
                showCover
                    ? KeyedSubtree(
                        key: anchor.coverKey,
                        child: Cover(song.coverUrl, size: 54, radius: 12),
                      )
                    : const SizedBox.square(dimension: 54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        p.error == null
                            ? singerNames(song)
                            : playerErrorText(l, p.error!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: p.error != null ? scheme.error : muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: liked ? l.unlike : l.like,
                  onPressed: () => toggleLike(context, song),
                  icon: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: liked ? scheme.primary : muted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: switch (p.mode) {
                        PlayMode.sequence => l.modeSequence,
                        PlayMode.repeatOne => l.modeRepeatOne,
                        PlayMode.shuffle => l.modeShuffle,
                      },
                      onPressed: p.cycleMode,
                      icon: Icon(
                        switch (p.mode) {
                          PlayMode.sequence => Icons.repeat_rounded,
                          PlayMode.repeatOne => Icons.repeat_one_rounded,
                          PlayMode.shuffle => Icons.shuffle_rounded,
                        },
                        size: 20,
                        color: p.mode == PlayMode.sequence
                            ? muted
                            : scheme.onSurface,
                      ),
                    ),
                    IconButton(
                      onPressed: p.previous,
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        color: scheme.onSurface,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 4),
                    PlayPauseButton(
                      dimension: 44,
                      playing: p.playing,
                      loading: p.loading || p.buffering,
                      onPressed: p.toggle,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: p.next,
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: scheme.onSurface,
                        size: 26,
                      ),
                    ),
                    // 占位，让播放键落在正中
                    const SizedBox(width: 48),
                  ],
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: const _ProgressRow(),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 260,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                DesktopQueueButton(color: muted),
                const SizedBox(width: 4),
                Icon(
                  p.volume == 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  size: 20,
                  color: muted,
                ),
                SizedBox(
                  width: 110,
                  child: _ThinSlider(
                    value: p.volume / 100,
                    color: scheme.onSurface,
                    label: l.volume,
                    onChanged: (v) => p.setVolume(v * 100),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 还没放过歌时的播放栏：占位封面、提示文字和不能点的播放键。
class _DesktopBarIdle extends StatelessWidget {
  const _DesktopBarIdle();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          SizedBox(
            width: 300,
            child: Row(
              children: [
                const Cover('', size: 54, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).nothingPlaying,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const IconButton(
                  onPressed: null,
                  icon: Icon(Icons.skip_previous_rounded, size: 26),
                ),
                const SizedBox(width: 4),
                SizedBox.square(
                  dimension: 44,
                  child: IconButton.filled(
                    padding: EdgeInsets.zero,
                    onPressed: null,
                    icon: Icon(Icons.play_arrow_rounded, color: muted),
                  ),
                ),
                const SizedBox(width: 4),
                const IconButton(
                  onPressed: null,
                  icon: Icon(Icons.skip_next_rounded, size: 26),
                ),
              ],
            ),
          ),
          const SizedBox(width: 260),
        ],
      ),
    );
  }
}

/// 进度条 + 两侧时间。拖动时只改本地值，松手才 seek。
class _ProgressRow extends StatefulWidget {
  const _ProgressRow();

  @override
  State<_ProgressRow> createState() => _ProgressRowState();
}

class _ProgressRowState extends State<_ProgressRow> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = context.read<PlayerController>();
    final total = context.select<PlayerController, Duration>((p) => p.duration);
    final chorusMs = context.select<PlayerController, int?>(
      (p) => p.chorus?.startMs,
    );
    final scheme = Theme.of(context).colorScheme;
    final timeStyle = TextStyle(
      fontSize: 11,
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ValueListenableBuilder(
      valueListenable: p.position,
      builder: (context, pos, _) {
        final ms = total.inMilliseconds;
        final value =
            _drag ??
            (ms == 0 ? 0.0 : (pos.inMilliseconds / ms).clamp(0.0, 1.0));
        return Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                formatDuration(Duration(milliseconds: (value * ms).round())),
                textAlign: TextAlign.right,
                style: timeStyle,
              ),
            ),
            Expanded(
              child: _ThinSlider(
                value: value,
                color: scheme.primary,
                mark: chorusMs != null && chorusMs < ms ? chorusMs / ms : null,
                onChanged: (v) => setState(() => _drag = v),
                onChangeEnd: (v) {
                  p.seek(Duration(milliseconds: (v * ms).round()));
                  setState(() => _drag = null);
                },
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(formatDuration(total), style: timeStyle),
            ),
          ],
        );
      },
    );
  }
}

class _ThinSlider extends StatelessWidget {
  const _ThinSlider({
    required this.value,
    required this.color,
    required this.onChanged,
    this.onChangeEnd,
    this.label,
    this.mark,
  });

  final double value;
  final Color color;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? label;

  /// 轨道里标一个小点的位置（0–1），进度条用来标高潮开始处。
  final double? mark;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: color,
        inactiveTrackColor: Theme.of(context).colorScheme.onSurface
            .withValues(alpha: 0.16),
        thumbColor: color,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        trackShape: mark == null
            ? const RoundedRectSliderTrackShape()
            : _MarkedTrackShape(mark!),
      ),
      child: Slider(
        value: value,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
        semanticFormatterCallback: label == null
            ? null
            : (v) => '$label ${(v * 100).round()}',
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

/// 在轨道里画一个和轨道等高、约两倍宽的小胶囊，比底色亮一档；已播放处用深色。
class _MarkedTrackShape extends RoundedRectSliderTrackShape {
  const _MarkedTrackShape(this.mark);

  final double mark;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final x = rect.left + rect.width * mark;
    final h = rect.height;
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, rect.center.dy),
          width: h * 1.8,
          height: h,
        ),
        Radius.circular(h / 2),
      ),
      Paint()
        ..color = x <= thumbCenter.dx
            ? Colors.black.withValues(alpha: 0.25)
            : sliderTheme.inactiveTrackColor!.withValues(alpha: 0.45),
    );
  }
}
