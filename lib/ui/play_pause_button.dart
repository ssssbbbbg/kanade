import 'package:flutter/material.dart';

/// 播放和暂停之间来回形变的图标。
class PlayPauseIcon extends StatefulWidget {
  const PlayPauseIcon({
    super.key,
    required this.playing,
    this.size,
    this.color,
  });

  final bool playing;
  final double? size;
  final Color? color;

  @override
  State<PlayPauseIcon> createState() => _PlayPauseIconState();
}

class _PlayPauseIconState extends State<PlayPauseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.playing ? 1 : 0,
  );
  late final _progress = CurvedAnimation(
    parent: _c,
    curve: Curves.easeInOutCubic,
  );

  @override
  void didUpdateWidget(PlayPauseIcon old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      widget.playing ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedIcon(
      icon: AnimatedIcons.play_pause,
      progress: _progress,
      size: widget.size,
      color: widget.color,
    );
  }
}

/// 播放条上的柠檬绿播放键。加载时按钮不消失：稍微缩小、图标变淡，外面绕一圈细弧在转。
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({
    super.key,
    required this.dimension,
    required this.playing,
    required this.loading,
    required this.onPressed,
  });

  final double dimension;
  final bool playing;
  final bool loading;
  final VoidCallback onPressed;

  static const _ringGap = 6.0;
  static const _duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            left: -_ringGap,
            top: -_ringGap,
            right: -_ringGap,
            bottom: -_ringGap,
            child: AnimatedSwitcher(
              duration: _duration,
              // 不加载时整个转圈拿掉，免得它在透明状态下一直刷新
              child: loading
                  ? CircularProgressIndicator(
                      strokeWidth: 2,
                      strokeCap: StrokeCap.round,
                      color: scheme.primary,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Positioned.fill(
            child: AnimatedScale(
              scale: loading ? 0.86 : 1,
              duration: _duration,
              curve: Curves.easeOutCubic,
              child: IgnorePointer(
                ignoring: loading,
                child: IconButton.filled(
                  padding: EdgeInsets.zero,
                  onPressed: onPressed,
                  // 玻璃层会改写继承的图标颜色，这里显式指定
                  icon: AnimatedOpacity(
                    opacity: loading ? 0.45 : 1,
                    duration: _duration,
                    child: PlayPauseIcon(
                      playing: playing,
                      color: scheme.onPrimary,
                    ),
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
