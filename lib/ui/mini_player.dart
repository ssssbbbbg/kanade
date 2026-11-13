import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'glass.dart';
import 'play_pause_button.dart';
import 'player_background.dart';
import 'player_route.dart';
import 'widgets.dart';

/// 浮在底部导航上方的玻璃胶囊播放条。外壳用 Positioned 给它当前的矩形，
/// 形状的过渡由外壳驱动：[faceOpacity] 是歌名和按钮的显示程度，[coverShift] 把封面从左端挪到右端；
/// [round] 时是导航栏旁边的圆球，只剩封面，点一下 [onExpand] 恢复。
/// 胶囊上点一下或按住往上拖打开播放页，手机上左右滑切歌。
/// 里面的按钮都是普通按钮：玻璃里再套玻璃会双重折射，还费 GPU。
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({
    super.key,
    this.round = false,
    this.faceOpacity = 1,
    this.coverShift = 0,
    this.capsuleWidth,
    this.onExpand,
    this.barAnchor,
    this.grouped = false,
    this.faceStagger = false,
  });

  static const height = 64.0;
  static const _coverSize = 44.0;
  static const _circleCover = 46.0;

  /// 底部导航上方那条播放条的锚点，播放页从这里变形出来。
  static final anchor = newAnchor();

  /// 另外摆一条播放条时（比如从播放页进的歌手页）给它自己的锚点。
  static PlayerBarAnchor newAnchor() => PlayerBarAnchor(
    coverRadius: _coverSize / 2,
    face: (_) =>
        const Material(type: MaterialType.transparency, child: _MiniFace()),
  );

  /// 不给就是 [MiniPlayer.anchor]。
  final PlayerBarAnchor? barAnchor;

  final bool round;
  final double faceOpacity;
  final double coverShift;

  /// 胶囊状态的宽度。歌名按它排版，收成圆的途中只被裁掉，不会重新换行。
  final double? capsuleWidth;

  final VoidCallback? onExpand;

  /// 玻璃不自己建一层，加入外面的 [AdaptiveLiquidGlassLayer]，和导航栏融成一块。
  final bool grouped;

  /// 歌名和按钮按 [faceOpacity] 错开出现，而不是整块一起淡入淡出。
  final bool faceStagger;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> with TickerProviderStateMixin {
  /// 左右滑时歌名跟着手指的位移。
  late final _swipe = AnimationController.unbounded(vsync: this);
  late final _anchor = widget.barAnchor ?? MiniPlayer.anchor;
  late final _drag = PlayerBarDrag(_anchor, this);
  late final _visibility = Listenable.merge([_anchor.hidden, _anchor.growing]);

  @override
  void dispose() {
    _swipe.dispose();
    super.dispose();
  }

  /// 松手才切：歌名滑出去，换成下一首从另一边滑进来；不够远就弹回。
  Future<void> _onSwipeEnd(DragEndDetails d) async {
    final p = context.read<PlayerController>();
    final v = d.velocity.pixelsPerSecond.dx;
    final dx = _swipe.value;
    final next = dx < -56 || v < -500;
    final previous = !next && (dx > 56 || v > 500);
    if (!next && !previous) {
      await _swipe.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    unawaited(next ? p.next() : p.previous());
    const out = 140.0;
    await _swipe.animateTo(
      next ? -out : out,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeIn,
    );
    if (!mounted) return;
    _swipe.value = next ? out : -out;
    await _swipe.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = context.select<PlayerController, Song?>((p) => p.current);
    if (song == null) return const SizedBox.shrink();
    prefetchPlayerArt(context, song);
    final round = widget.round;
    final swipe = touchPlatform && !round;
    final bar = GestureDetector(
      key: _anchor.barKey,
      behavior: HitTestBehavior.opaque,
      onTap: round
          ? widget.onExpand
          : () => PlayerRoute.open(context, anchor: _anchor),
      onVerticalDragUpdate: round ? null : (d) => _drag.update(context, d),
      onVerticalDragEnd: round
          ? null
          : (d) => _drag.end(context, d.velocity.pixelsPerSecond.dy),
      onVerticalDragCancel: round ? null : () => _drag.end(context, 0),
      onHorizontalDragStart: swipe ? (_) => _swipe.stop() : null,
      onHorizontalDragUpdate: swipe ? (d) => _swipe.value += d.delta.dx : null,
      onHorizontalDragEnd: swipe ? _onSwipeEnd : null,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          // 胶囊里 44，圆球和导航栏那么高时 46
          final d = lerpDouble(
            MiniPlayer._coverSize,
            MiniPlayer._circleCover,
            ((MiniPlayer.height - h) / 6).clamp(0.0, 1.0),
          )!;
          final face = widget.faceOpacity.clamp(0.0, 1.0);
          final content = Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                if (widget.faceOpacity > 0)
                  Positioned(
                    left: 0,
                    top: (h - MiniPlayer.height) / 2,
                    width: widget.capsuleWidth ?? w,
                    height: MiniPlayer.height,
                    child: widget.faceStagger
                        ? _MiniFace(swipe: _swipe, reveal: face)
                        : Opacity(
                            opacity: face,
                            child: _MiniFace(swipe: _swipe),
                          ),
                  ),
                Positioned(
                  // 封面平时待在左端的半圆里，收成圆时是右边缩进来
                  left: lerpDouble(
                    (h - d) / 2,
                    w - (h + d) / 2,
                    widget.coverShift,
                  ),
                  top: (h - d) / 2,
                  width: d,
                  height: d,
                  child: KeyedSubtree(
                    key: _anchor.coverKey,
                    child: Cover(
                      song.coverUrl,
                      size: d,
                      radius: d / 2,
                      keepPrevious: true,
                    ),
                  ),
                ),
              ],
            ),
          );
          // 变形开头玻璃跟着长成播放页的形状，歌名和封面这时由转场层画
          return PlayerBarGrowth(
            anchor: _anchor,
            builder: (growing, shapeT) {
              final shape = LiquidRoundedRectangle(
                borderRadius: PlayerMorph.radiusAt(math.min(w, h), shapeT),
              );
              final inner = Opacity(
                opacity: growing ? 0 : 1,
                child: PlayerBarGrowth.pin(content),
              );
              if (!widget.grouped) {
                return GlassContainer(
                  useOwnLayer: true,
                  settings: KanadeGlass.navigationSettings(context),
                  quality: KanadeGlass.navigationQuality,
                  shape: shape,
                  clipBehavior: Clip.antiAlias,
                  child: inner,
                );
              }
              // 分组的玻璃连同里面的内容都由外面的玻璃层来画，外面套 Opacity 藏不住；
              // 播放页盖上来时干脆不挂玻璃，只留透明的内容占位
              return ValueListenableBuilder(
                valueListenable: _anchor.hidden,
                child: inner,
                builder: (_, hidden, inner) => hidden && !growing
                    ? inner!
                    : GlassContainer(
                        quality: KanadeGlass.navigationQuality,
                        shape: shape,
                        clipBehavior: Clip.antiAlias,
                        child: inner,
                      ),
              );
            },
          );
        },
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

/// 胶囊上除封面以外的部分：歌名、播放键（桌面没有手势，再加上一首 / 下一首）、进度线。
class _MiniFace extends StatelessWidget {
  const _MiniFace({this.swipe, this.reveal});

  final Animation<double>? swipe;

  /// 给了就错开出现：歌名先从左边滑进来，按钮晚一点弹出来；不给就是整块一起显示。
  final double? reveal;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final song = p.current;
    if (song == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final reveal = this.reveal;
    final titleIn = reveal == null
        ? 1.0
        : const Interval(0, 0.7).transform(reveal.clamp(0.0, 1.0));
    final buttonsIn = reveal == null
        ? 1.0
        : const Interval(0.3, 1).transform(reveal.clamp(0.0, 1.0));
    Widget pop(Widget button) => buttonsIn >= 1
        ? button
        : Opacity(
            opacity: buttonsIn,
            child: Transform.scale(
              scale: 0.6 + 0.4 * Curves.easeOutBack.transform(buttonsIn),
              child: button,
            ),
          );
    Widget title = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          song.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        Text(
          p.error == null
              ? singerNames(song)
              : playerErrorText(AppLocalizations.of(context), p.error!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: p.error != null ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final swipe = this.swipe;
    if (swipe != null) {
      title = ClipRect(
        child: AnimatedBuilder(
          animation: swipe,
          child: title,
          builder: (_, title) => Transform.translate(
            offset: Offset(swipe.value, 0),
            child: Opacity(
              opacity: (1 - swipe.value.abs() / 140).clamp(0.0, 1.0),
              child: title,
            ),
          ),
        ),
      );
    }
    if (titleIn < 1) {
      title = Opacity(
        opacity: titleIn,
        child: Transform.translate(
          offset: Offset((1 - titleIn) * -10, 0),
          child: title,
        ),
      );
    }
    return Stack(
      children: [
        Row(
          children: [
            const SizedBox(width: 10 + MiniPlayer._coverSize + 12),
            Expanded(child: title),
            if (!touchPlatform)
              pop(
                IconButton(
                  onPressed: p.previous,
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            pop(
              PlayPauseButton(
                dimension: 40,
                playing: p.playing,
                loading: p.loading || p.buffering,
                onPressed: p.toggle,
              ),
            ),
            if (!touchPlatform)
              pop(
                IconButton(
                  onPressed: p.next,
                  icon: Icon(Icons.skip_next_rounded, color: scheme.onSurface),
                ),
              ),
            // 手机上播放键和胶囊右端的半圆同心
            SizedBox(width: touchPlatform ? 12 : 8),
          ],
        ),
        // 进度线只画在胶囊的直边上；手机上不画
        if (!touchPlatform)
          Positioned(
            left: MiniPlayer.height / 2,
            right: MiniPlayer.height / 2,
            bottom: 0,
            child: Opacity(
              opacity: titleIn,
              child: ValueListenableBuilder(
                valueListenable: p.position,
                builder: (_, pos, _) => LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
                  value: p.duration.inMilliseconds == 0
                      ? 0
                      : (pos.inMilliseconds / p.duration.inMilliseconds).clamp(
                          0.0,
                          1.0,
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
