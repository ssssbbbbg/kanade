import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import '../src/rust/api/types.dart';
import 'comments_page.dart';
import 'play_pause_button.dart';
import 'player_background.dart';
import 'player_detail.dart';
import 'player_lyrics.dart';
import 'player_route.dart';
import 'queue_list.dart';
import 'sleep_timer_sheet.dart';
import 'smooth_scroll.dart';
import 'song_action_sheet.dart';
import 'song_actions.dart';
import 'theme.dart';
import 'toast.dart';
import 'widgets.dart';

enum _Panel { lyrics, queue, detail }

enum _Drag { none, route, page }

const _motion = Duration(milliseconds: 550);
const _curve = Curves.easeInOutCubicEmphasized;

final _fallbackTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: fallbackPalette[1],
    brightness: Brightness.dark,
  ),
);

/// Apple Music 风格的全屏播放页：封面取色流动背景、下拉关闭，
/// 窄屏下封面会收进左上角，给歌词 / 播放队列腾地方。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, this.showQueue = false});

  /// 打开时直接显示播放队列（桌面底栏的队列按钮用）。
  final bool showQueue;

  /// 给了 [anchor] 时播放页从那个播放条变形出来，关闭时变回去；不给就从屏幕底边升上来。
  static Route<void> route({PlayerBarAnchor? anchor, bool showQueue = false}) =>
      PlayerRoute(anchor: anchor, showQueue: showQueue);

  /// Windows 首次转场前准备背景和封面投影的 GPU 绘制程序。
  static Future<void> warmUp() async {
    await warmUpPlayerBackground();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final pixelRatio =
        ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    canvas.scale(pixelRatio);
    for (final lifted in [false, true]) {
      for (final t in [0.1, 0.5, 1.0]) {
        final painter = BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [albumArtShadow(lifted: lifted).scale(t)],
        ).createBoxPainter();
        painter.paint(
          canvas,
          const Offset(100, 100),
          ImageConfiguration(size: Size.square(54 + 346 * t)),
        );
        painter.dispose();
      }
    }
    final picture = recorder.endRecording();
    try {
      final extent = (600 * pixelRatio).ceil();
      final image = picture.toImageSync(extent, extent);
      try {
        await image.toByteData();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  CoverArt? _art;
  String? _artUrl;

  /// 宽屏右侧显示队列还是歌词。
  late bool _wideQueue = widget.showQueue;

  /// 窄屏翻页的进度：0 是主页面，1 是 [_side] 那一页（队列在下面、歌词在右边、歌曲信息在左边）。
  /// 拖动时手指直接改它，封面、歌名、控件、面板的位置都由它算出来。
  late final AnimationController _page = AnimationController(
    vsync: this,
    value: widget.showQueue ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));
  late _Panel _side = widget.showQueue ? _Panel.queue : _Panel.lyrics;

  /// 窄屏内容区的大小，翻页时手指位移按它换算成进度。
  Size _area = Size.zero;

  /// 窄屏封面歌名那一块的高度，也就是控件顶边的位置。
  double _headerHeight = 0;

  List<Color> get _palette => _art?.palette ?? fallbackPalette;

  void _loadArt(String url) {
    if (url == _artUrl) return;
    _artUrl = url;
    unawaited(_precacheQueueCovers());
    if (url.isEmpty) return;
    // 迷你播放器一般已经预取好了，第一帧直接用
    final cached = cachedCoverArt(url);
    if (cached != null) {
      _art = cached;
      return;
    }
    loadCoverArt(url).then((art) {
      if (mounted && _artUrl == url) setState(() => _art = art);
    }, onError: (_) {});
  }

  /// 队列翻开时第一屏的封面提前一张一张加载好。不然十几张封面都在手指刚动的那一帧
  /// 同时发起网络请求，第一次翻开会卡一下（之后图片缓存里有了就不会）。
  Future<void> _precacheQueueCovers() async {
    // 在 build 里调用，不能用 context.read
    final p = Provider.of<PlayerController>(context, listen: false);
    final song = p.current;
    final songs = p.queue.skip(max(0, p.index - 1)).take(24).toList();
    for (final s in songs) {
      // 换歌后会从新的位置重新来一遍，这一遍不用接着做
      if (!mounted || p.current != song) return;
      await precacheImage(queueCover(context, s), context, onError: (_, _) {});
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  // ---- 窄屏翻页 ----

  /// 松手后接着手指的速度弹到位，临界阻尼不回弹。
  static final _pageSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 520,
  );

  double get _extent => _side == _Panel.queue ? _area.height : _area.width;

  void _pageDragStart(_Panel side) {
    _page.stop();
    _side = side;
  }

  /// [delta] 是手指沿翻页方向的位移（队列看竖直、歌词看水平），往主页面那边为正。
  void _pageDragUpdate(double delta) {
    if (_extent > 0) _page.value -= delta / _extent;
  }

  /// 甩得够快按方向翻，否则过了一半就翻过去、不到一半弹回来。
  void _pageDragEnd(double velocity) {
    final v = _extent > 0 ? -velocity / _extent : 0.0;
    final open = v.abs() > 1.2 ? v > 0 : _page.value > 0.5;
    // 落点要正好是 0 / 1，往回翻要用 animateBackWith，停下时才算回到主页面
    final spring = SpringSimulation(
      _pageSpring,
      _page.value,
      open ? 1 : 0,
      v,
      snapToEnd: true,
    );
    open ? _page.animateWith(spring) : _page.animateBackWith(spring);
  }

  /// 这次拖动交给谁：路由（拖动关闭播放页）还是翻页；第一次移动时按方向定下来。
  _Drag? _drag;
  Axis? _dragAxis;

  /// 队列列表在顶上被往下拉，由列表自己接管了这次拖动。
  bool _listPull = false;

  _Drag _decideVertical(bool narrow, PlayerRoute? r, double dy) {
    if (!narrow) {
      r?.dragStart();
      return r == null ? _Drag.none : _Drag.route;
    }
    if (_page.value == 0) {
      // 主页面往下拖、或者打开动画还没走完，是拖动播放页本身；往上翻到队列
      if (r != null && (dy >= 0 || r.progress < 1)) {
        r.dragStart();
        return _Drag.route;
      }
      if (dy >= 0) return _Drag.none;
      _pageDragStart(_Panel.queue);
      return _Drag.page;
    }
    // 队列页顶上往下拉回主页面；歌词页不管竖直方向
    if (_side != _Panel.queue) return _Drag.none;
    _pageDragStart(_Panel.queue);
    return _Drag.page;
  }

  /// 主页面往左翻出歌词、往右翻出歌曲信息；翻开后横向拖动都交给同一页。
  _Drag _decideHorizontal(double dx) {
    final t = _page.value;
    final side = t > 0
        ? (_side == _Panel.queue ? null : _side)
        : (dx < 0 ? _Panel.lyrics : (dx > 0 ? _Panel.detail : null));
    if (side == null) return _Drag.none;
    _pageDragStart(side);
    return _Drag.page;
  }

  /// 歌曲信息在左边，手指往右才是离开主页面，横向位移要反过来算。
  double _alongPage(Axis axis, double v) =>
      axis == Axis.horizontal && _side == _Panel.detail ? -v : v;

  Widget _gestures({required bool narrow, required Widget child}) {
    final route = ModalRoute.of(context);
    final r = route is PlayerRoute ? route : null;
    void start(Axis axis) {
      _drag = null;
      _dragAxis = axis;
    }

    void update(Axis axis, double delta) {
      if (_listPull || _dragAxis != axis) return;
      _drag ??= axis == Axis.vertical
          ? _decideVertical(narrow, r, delta)
          : _decideHorizontal(delta);
      if (_drag == _Drag.route) r!.dragUpdate(delta);
      if (_drag == _Drag.page) _pageDragUpdate(_alongPage(axis, delta));
    }

    // 点按钮时拖动手势没真正开始也会收到取消，这时 _drag 还是空的
    void end(Axis axis, double velocity) {
      if (_dragAxis != axis) return;
      if (_drag == _Drag.route) r!.dragEnd(velocity);
      if (_drag == _Drag.page) _pageDragEnd(_alongPage(axis, velocity));
      _drag = null;
      _dragAxis = null;
    }

    return GestureDetector(
      onVerticalDragStart: (_) => start(Axis.vertical),
      onVerticalDragUpdate: (d) => update(Axis.vertical, d.delta.dy),
      onVerticalDragEnd: (d) =>
          end(Axis.vertical, d.velocity.pixelsPerSecond.dy),
      onVerticalDragCancel: () => end(Axis.vertical, 0),
      onHorizontalDragStart: narrow ? (_) => start(Axis.horizontal) : null,
      onHorizontalDragUpdate: narrow
          ? (d) => update(Axis.horizontal, d.delta.dx)
          : null,
      onHorizontalDragEnd: narrow
          ? (d) => end(Axis.horizontal, d.velocity.pixelsPerSecond.dx)
          : null,
      onHorizontalDragCancel: narrow ? () => end(Axis.horizontal, 0) : null,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final song = p.current;
    if (song == null) return const Scaffold();
    final cover = bigCoverUrl(song);
    _loadArt(cover);
    final wide = MediaQuery.sizeOf(context).width >= 800;

    final page = Scaffold(
      backgroundColor: Colors.black,
      // 播放页没有输入框；弹窗里弹键盘时页面不跟着压扁、逐帧重新排版
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PlayerBackground(art: _art, animate: p.playing),
          // 背景每帧都在动，前景单独一层，避免跟着重绘
          RepaintBoundary(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: wide ? _wide(p, song, cover) : _narrow(p, song, cover),
              ),
            ),
          ),
        ],
      ),
    );

    // 窄屏翻到队列时，返回键先翻回主页面；歌词页、歌曲信息页按返回直接关掉播放页
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: _art?.theme ?? _fallbackTheme,
        child: PopScope(
          canPop: wide || _page.isDismissed || _side != _Panel.queue,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _page.animateBack(0, duration: _motion, curve: _curve);
          },
          // 下拉时整页沿着变形的路径缩回播放条，手指松开再决定关还是弹回
          child: _gestures(narrow: !wide, child: page),
        ),
      ),
    );
  }

  /// 主页面和队列 / 歌词像两页纸：控件跟着主页面翻走，面板从下面或右边跟进来，
  /// 封面和歌名按进度缩进左上角。
  Widget _narrow(PlayerController p, Song song, String cover) {
    const small = 60.0;
    // 主页面停稳时不建面板；从队列列表往下拉回来、手指还没松开时要留着，松手要靠它
    final panel = _page.isDismissed && !_listPull
        ? null
        : RepaintBoundary(
            child: switch (_side) {
              _Panel.lyrics => const LyricView(key: ValueKey('lyrics')),
              _Panel.detail => const SongDetailView(key: ValueKey('detail')),
              _Panel.queue => _QueuePanel(
                key: const ValueKey('queue'),
                onPullStart: () {
                  _listPull = true;
                  _pageDragStart(_Panel.queue);
                },
                onPull: _pageDragUpdate,
                onPullEnd: (v) {
                  setState(() => _listPull = false);
                  _pageDragEnd(v);
                },
              ),
            },
          );
    final controls = RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
        child: _ControlsArea(accent: _palette.first),
      ),
    );
    return LayoutBuilder(
      builder: (context, area) {
        _area = area.biggest;
        return AnimatedBuilder(
          animation: _page,
          builder: (context, _) {
            final t = _page.value;
            // 整页翻走的距离：队列竖着翻一屏，歌词往左、歌曲信息往右横着翻一屏
            final shift = switch (_side) {
              _Panel.queue => Offset(0, area.maxHeight),
              _Panel.lyrics => Offset(area.maxWidth, 0),
              _Panel.detail => Offset(-area.maxWidth, 0),
            };
            return Stack(
              children: [
                if (panel != null)
                  Positioned.fill(
                    top: small + 16,
                    child: Transform.translate(
                      offset: shift * (1 - t),
                      child: panel,
                    ),
                  ),
                // 从下往上排：控件先画，封面歌名盖在上面
                Column(
                  verticalDirection: VerticalDirection.up,
                  children: [
                    // 控件翻走时从顶上那条封面歌名下面钻过去，和面板一样在那条线以上看不见
                    ClipRect(
                      clipper: _ClipAbove(() => small + 16 - _headerHeight),
                      child: Transform.translate(
                        offset: -shift * t,
                        child: controls,
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          _headerHeight = c.maxHeight;
                          const pad = 28.0, titleH = 64.0;
                          final size = min(
                            c.maxWidth - pad * 2,
                            c.maxHeight - titleH - 28,
                          ).clamp(80.0, 560.0);
                          final top = max(
                            0.0,
                            (c.maxHeight - size - titleH - 24) / 2,
                          );
                          final coverRect = Rect.lerp(
                            Rect.fromLTWH(
                              (c.maxWidth - size) / 2,
                              top,
                              size,
                              size,
                            ),
                            const Rect.fromLTWH(24, 4, small, small),
                            t,
                          )!;
                          final titleRect = Rect.lerp(
                            Rect.fromLTWH(
                              pad,
                              top + size + 24,
                              c.maxWidth - pad * 2,
                              titleH,
                            ),
                            Rect.fromLTWH(
                              24 + small + 14,
                              4,
                              c.maxWidth - 24 - small - 14 - 20,
                              small,
                            ),
                            t,
                          )!;
                          return Stack(
                            children: [
                              Positioned.fromRect(
                                rect: coverRect,
                                child: _AlbumArt(
                                  url: cover,
                                  placeholderUrl: song.coverUrl,
                                  playing: p.playing,
                                  expanded: t < 0.5,
                                  t: t,
                                ),
                              ),
                              Positioned.fromRect(
                                rect: titleRect,
                                child: _TitleRow(song: song, t: t),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _wide(PlayerController p, Song song, String cover) {
    // 宽屏右侧始终有内容：默认歌词，队列按钮在歌词和队列之间切换
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(56, 8, 40, 24),
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final size = min(min(c.maxWidth, c.maxHeight), 520.0);
                      return Center(
                        child: SizedBox.square(
                          dimension: size,
                          child: _AlbumArt(
                            url: cover,
                            placeholderUrl: song.coverUrl,
                            playing: p.playing,
                            expanded: true,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(height: 64, child: _TitleRow(song: song, t: 0)),
                const SizedBox(height: 12),
                _ControlsArea(
                  accent: _palette.first,
                  queueOpen: _wideQueue,
                  onQueue: () => setState(() => _wideQueue = !_wideQueue),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 40, 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _wideQueue
                  ? const _QueuePanel(key: ValueKey('queue'))
                  : const LyricView(key: ValueKey('lyrics'), fontSize: 36),
            ),
          ),
        ),
      ],
    );
  }
}

/// 只露出 [top] 以下的部分，[top] 用本地坐标、每次画的时候现取（要等排版完才知道）。
class _ClipAbove extends CustomClipper<Rect> {
  _ClipAbove(this.top);

  final double Function() top;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-1e5, top(), 1e5, 1e5);

  @override
  bool shouldReclip(_ClipAbove old) => true;
}

/// 大封面的投影：播放时浮起来、阴影更深。飞行中的封面也用它，落地时阴影不会突然冒出来。
BoxShadow albumArtShadow({required bool lifted}) => BoxShadow(
  color: Colors.black.withValues(alpha: lifted ? 0.5 : 0.28),
  blurRadius: lifted ? 60 : 18,
  spreadRadius: lifted ? 2 : 0,
  offset: Offset(0, lifted ? 28 : 8),
);

/// 封面：暂停时缩小、播放时弹回并加深投影。
class _AlbumArt extends StatelessWidget {
  const _AlbumArt({
    required this.url,
    required this.placeholderUrl,
    required this.playing,
    required this.expanded,
    this.t = 0,
  });

  final String url;
  final String placeholderUrl;
  final bool playing;
  final bool expanded;

  /// 翻页进度：0 是主页面的大封面，1 是缩在左上角的小封面。
  final double t;

  @override
  Widget build(BuildContext context) {
    final lifted = expanded && playing;
    final radius = expanded ? 14.0 : 8.0;
    final morph = PlayerMorph.maybeOf(context);
    // 暂停缩小的幅度跟着翻页进度连续收掉，滑动途中不会突然弹一下
    final art = TweenAnimationBuilder<double>(
      tween: Tween(end: playing ? 0 : 1),
      duration: const Duration(milliseconds: 650),
      curve: playing ? Curves.easeOutBack : Curves.easeOutCubic,
      builder: (_, paused, child) =>
          Transform.scale(scale: 1 - 0.2 * paused * (1 - t), child: child),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [albumArtShadow(lifted: lifted)],
        ),
        // 打开播放页时封面从播放条飞过来，落点量的就是这里
        child: KeyedSubtree(
          key: morph?.artKey,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(
                scale: Tween(begin: 0.94, end: 1.0).animate(a),
                child: child,
              ),
            ),
            child: SizedBox.expand(
              key: ValueKey(url),
              child: Cover(url, placeholderUrl: placeholderUrl, radius: radius),
            ),
          ),
        ),
      ),
    );
    if (morph == null) return art;
    // 封面还在飞的时候这里先藏起来，落地再接上
    return ValueListenableBuilder(
      valueListenable: morph.artInFlight,
      child: art,
      builder: (_, flying, art) => Opacity(opacity: flying ? 0 : 1, child: art),
    );
  }
}

/// 歌名、歌手和按钮。[t] 是翻页进度：0 是主页面的大字，1 是缩在左上角封面旁边的小字。
class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.song, required this.t});

  final Song song;
  final double t;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final l = AppLocalizations.of(context);
    final error = p.error;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DefaultTextStyle(
                style: TextStyle(
                  fontSize: lerpDouble(22, 17, t),
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                child: _Marquee(song.name),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () => openSinger(context, song),
                child: DefaultTextStyle(
                  style: TextStyle(
                    fontSize: lerpDouble(18, 14, t),
                    fontWeight: FontWeight.w500,
                    color: error != null
                        ? const Color(0xFFFF9A9A)
                        : Colors.white60,
                  ),
                  child: Text(
                    error != null
                        ? playerErrorText(l, error)
                        : singerNames(song),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _LikeButton(song),
        const SizedBox(width: 10),
        _GlassButton(
          tooltip: l.more,
          onTap: () => showSongActions(context, song),
          child: const Icon(
            Icons.more_horiz_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ],
    );
  }
}

/// 文字超宽时来回滚动，两端渐隐。
class _Marquee extends StatefulWidget {
  const _Marquee(this.text);

  final String text;

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  static const _gap = 48.0;

  @override
  void didUpdateWidget(_Marquee old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _c.reset();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, c) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final w = tp.width, h = tp.height;
        tp.dispose();
        if (w <= c.maxWidth) {
          if (_c.isAnimating) _c.stop();
          return Text(widget.text, maxLines: 1, softWrap: false);
        }
        // 前 3 秒停住，然后匀速滚过一整段
        final travel = w + _gap;
        final scroll = Duration(milliseconds: (travel / 40 * 1000).round());
        final total = scroll + const Duration(seconds: 3);
        if (_c.duration != total || !_c.isAnimating) {
          _c.duration = total;
          _c.repeat();
        }
        final hold = 3000 / total.inMilliseconds;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            colors: [Colors.black, Colors.black, Colors.transparent],
            stops: [0, 0.88, 1],
          ).createShader(r),
          child: ClipRect(
            child: SizedBox(
              height: h,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, child) {
                  final t = _c.value < hold
                      ? 0.0
                      : (_c.value - hold) / (1 - hold);
                  return Transform.translate(
                    offset: Offset(-t * travel, 0),
                    child: child,
                  );
                },
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.text, maxLines: 1),
                      const SizedBox(width: _gap),
                      Text(widget.text, maxLines: 1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.child, required this.onTap, this.tooltip});

  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(dimension: 36, child: Center(child: child)),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton(this.song);

  final Song song;

  @override
  Widget build(BuildContext context) {
    final liked = context.watch<LibraryController>().isLiked(song);
    final l = AppLocalizations.of(context);
    return _GlassButton(
      tooltip: liked ? l.unlike : l.like,
      onTap: () => toggleLike(context, song),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.elasticOut,
        transitionBuilder: (child, a) =>
            ScaleTransition(scale: a, child: child),
        child: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(liked),
          size: 20,
          color: liked ? const Color(0xFFFF4D6D) : Colors.white,
        ),
      ),
    );
  }
}

/// 进度条 + 播放按钮一排 + 底部按钮。
class _ControlsArea extends StatelessWidget {
  const _ControlsArea({
    required this.accent,
    this.queueOpen = false,
    this.onQueue,
  });

  final Color accent;
  final bool queueOpen;

  /// 宽屏才有队列按钮；窄屏上滑打开队列、左滑打开歌词，底下只留评论。
  final VoidCallback? onQueue;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final song = context.select<PlayerController, Song?>((p) => p.current);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _ProgressBar(),
        const SizedBox(height: 6),
        const _Transport(),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ToggleIcon(
              icon: Icons.mode_comment_outlined,
              tooltip: l.comments,
              selected: false,
              accent: accent,
              onTap: song == null
                  ? () {}
                  : () => Navigator.of(context).push(CommentsPage.song(song)),
            ),
            const _SleepButton(),
            if (onQueue != null)
              _ToggleIcon(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: l.queue,
                selected: queueOpen,
                accent: accent,
                onTap: onQueue!,
              ),
          ],
        ),
      ],
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = HSLColor.fromColor(accent).withLightness(0.18).toColor();
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: 44,
          height: 36,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.9)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 22, color: selected ? dark : Colors.white70),
        ),
      ),
    );
  }
}

/// 定时关闭：开着时图标变成柠檬绿，旁边显示剩余时间。
class _SleepButton extends StatefulWidget {
  const _SleepButton();

  @override
  State<_SleepButton> createState() => _SleepButtonState();
}

class _SleepButtonState extends State<_SleepButton> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _format(Duration d) {
    final s = (d.inMilliseconds / 1000).ceil();
    final mm = '${s ~/ 60 % 60}'.padLeft(2, '0');
    final ss = '${s % 60}'.padLeft(2, '0');
    return s >= 3600 ? '${s ~/ 3600}:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final at = context.select<PlayerController, DateTime?>((p) => p.sleepAt);
    // 开着时每秒刷新一次倒计时
    if (at == null) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }
    final left = at?.difference(DateTime.now());
    final color = at != null ? KanadeColors.lime : Colors.white70;
    return Tooltip(
      message: l.sleepTimer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showSleepTimer(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.alarm_rounded, size: 22, color: color),
              if (left != null) ...[
                const SizedBox(width: 4),
                Text(
                  // 到点那一下还没停（要等这首放完，或者还没收到停下的消息）
                  left > Duration.zero ||
                          !context.read<PlayerController>().sleepAfterSong
                      ? _format(left.isNegative ? Duration.zero : left)
                      : l.sleepTimerWaitingShort,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 细进度条：按住时变粗、时间变亮，松手才跳转。
class _ThinSlider extends StatelessWidget {
  const _ThinSlider({
    required this.value,
    required this.active,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    this.chorusStart,
  });

  final double value;
  final bool active;

  /// 高潮开始处在进度条上的比例，在进度条里画一个小点。
  final double? chorusStart;
  final ValueChanged<double> onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  static const height = 7.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        double at(Offset o) => (o.dx / c.maxWidth).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => onStart(at(d.localPosition)),
          onHorizontalDragUpdate: (d) => onChanged(at(d.localPosition)),
          onHorizontalDragEnd: (_) => onEnd(),
          onHorizontalDragCancel: onEnd,
          onTapUp: (d) {
            onStart(at(d.localPosition));
            onEnd();
          },
          child: SizedBox(
            height: 28,
            child: Center(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                padding: EdgeInsets.symmetric(horizontal: active ? 0 : 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  height: active ? height * 1.9 : height,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(height),
                  ),
                  child: CustomPaint(
                    foregroundPainter: chorusStart == null
                        ? null
                        : _ChorusDot(
                            chorusStart!,
                            played: value >= chorusStart!,
                          ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: value.clamp(0.0, 1.0),
                        heightFactor: 1,
                        // 进度往前走的那头也是圆的
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(height),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 画在进度条轨道里的高潮起点：和轨道等高、约两倍宽的小胶囊，
/// 比底色亮一档；已播放处落在白色进度上，改用深色。跟着轨道一起变粗。
class _ChorusDot extends CustomPainter {
  const _ChorusDot(this.start, {required this.played});

  final double start;
  final bool played;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * start, h / 2),
          width: h * 1.8,
          height: h,
        ),
        Radius.circular(h / 2),
      ),
      Paint()
        ..color = played
            ? Colors.black.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(_ChorusDot old) =>
      old.start != start || old.played != played;
}

class _ProgressBar extends StatefulWidget {
  const _ProgressBar();

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final total = p.duration.inMilliseconds;
    final timeStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: _drag != null ? Colors.white : Colors.white54,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ValueListenableBuilder(
      valueListenable: p.position,
      builder: (_, pos, _) {
        final v = _drag ?? (total == 0 ? 0.0 : pos.inMilliseconds / total);
        final shown = Duration(milliseconds: (v * total).round());
        final c = p.chorus;
        return Column(
          children: [
            _ThinSlider(
              value: v,
              active: _drag != null,
              chorusStart: c == null || c.startMs >= total
                  ? null
                  : c.startMs / total,
              onStart: (x) => setState(() => _drag = x),
              onChanged: (x) => setState(() => _drag = x),
              onEnd: () {
                final d = _drag;
                setState(() => _drag = null);
                if (d != null && total > 0) {
                  unawaited(
                    p.seek(Duration(milliseconds: (d * total).round())),
                  );
                }
              },
            ),
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(formatDuration(shown), style: timeStyle),
                ),
                const Expanded(child: Center(child: QualityMenu())),
                SizedBox(
                  width: 56,
                  child: Text(
                    '-${formatDuration(Duration(milliseconds: max(0, total - shown.inMilliseconds)))}',
                    textAlign: TextAlign.end,
                    style: timeStyle,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 播放模式 · 上一首 · 播放 / 暂停 · 下一首 · 音量。
class _Transport extends StatelessWidget {
  const _Transport();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const _ModeButton(),
        _PressButton(
          size: 44,
          nudge: -1,
          onTap: p.previous,
          child: const Icon(
            Icons.fast_rewind_rounded,
            size: 44,
            color: Colors.white,
          ),
        ),
        _PressButton(
          size: 60,
          onTap: p.toggle,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PlayPauseIcon(playing: p.playing, size: 60, color: Colors.white),
              if (p.loading || p.buffering)
                const SizedBox.square(
                  dimension: 74,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
            ],
          ),
        ),
        _PressButton(
          size: 44,
          nudge: 1,
          onTap: p.next,
          child: const Icon(
            Icons.fast_forward_rounded,
            size: 44,
            color: Colors.white,
          ),
        ),
        const _VolumeButton(),
      ],
    );
  }
}

/// 按下时缩小并亮起圆形底；上一首 / 下一首额外往对应方向轻推一下。
/// 圆形底比按钮本身大，画在布局范围外面，不把一排按钮撑宽。
class _PressButton extends StatefulWidget {
  const _PressButton({
    required this.size,
    required this.onTap,
    required this.child,
    this.nudge = 0,
  });

  final double size;
  final VoidCallback onTap;
  final Widget child;
  final double nudge;

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton>
    with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 350),
  );
  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void dispose() {
    _press.dispose();
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.size * 1.7;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press.forward(),
      onTapCancel: _press.reverse,
      onTapUp: (_) {
        _press.reverse();
        _nudge.forward(from: 0);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: SizedBox.square(
        dimension: widget.size * 1.25,
        child: OverflowBox(
          maxWidth: box,
          maxHeight: box,
          child: AnimatedBuilder(
            animation: Listenable.merge([_press, _nudge]),
            builder: (_, child) => Container(
              width: box,
              height: box,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.16 * _press.value),
              ),
              child: Transform.translate(
                offset: Offset(
                  widget.nudge *
                      12 *
                      sin(Curves.easeOut.transform(_nudge.value) * pi),
                  0,
                ),
                child: Transform.scale(
                  scale: 1 - 0.14 * _press.value,
                  child: child,
                ),
              ),
            ),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

String _modeLabel(AppLocalizations l, PlayMode mode) => switch (mode) {
  PlayMode.sequence => l.modeSequence,
  PlayMode.repeatOne => l.modeRepeatOne,
  PlayMode.shuffle => l.modeShuffle,
};

/// 播放模式：点一下换下一种（列表循环 → 单曲循环 → 随机），换完弹个提示。
class _ModeButton extends StatelessWidget {
  const _ModeButton();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mode = context.select<PlayerController, PlayMode>((p) => p.mode);
    return Tooltip(
      message: _modeLabel(l, mode),
      child: _PressButton(
        size: 32,
        onTap: () {
          final p = context.read<PlayerController>()..cycleMode();
          showToast(context, _modeLabel(l, p.mode));
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutBack,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(
              scale: Tween(begin: 0.5, end: 1.0).animate(a),
              child: child,
            ),
          ),
          child: Icon(
            switch (mode) {
              PlayMode.sequence => Icons.repeat_rounded,
              PlayMode.repeatOne => Icons.repeat_one_rounded,
              PlayMode.shuffle => Icons.shuffle_rounded,
            },
            key: ValueKey(mode),
            size: 24,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

IconData _volumeIcon(double volume) => volume == 0
    ? Icons.volume_off_rounded
    : volume < 50
    ? Icons.volume_down_rounded
    : Icons.volume_up_rounded;

/// 音量按钮：点开时按钮本身长成一条竖着的音量条，点外面再缩回按钮。
class _VolumeButton extends StatefulWidget {
  const _VolumeButton();

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  bool _open = false;

  void _openPanel() {
    final box = context.findRenderObject()! as RenderBox;
    final route = _VolumeRoute(
      anchor: box.localToGlobal(Offset.zero) & box.size,
      player: context.read<PlayerController>(),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    );
    // 展开期间按钮藏起来，看起来就是它自己变成了音量条；缩回去落地了再露出来
    setState(() => _open = true);
    unawaited(Navigator.of(context, rootNavigator: true).push(route));
    unawaited(
      route.completed.then((_) {
        if (mounted) setState(() => _open = false);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final volume = context.select<PlayerController, double>((p) => p.volume);
    return Tooltip(
      message: l.volume,
      child: Opacity(
        opacity: _open ? 0 : 1,
        child: _PressButton(
          size: 32,
          onTap: _openPanel,
          child: Icon(_volumeIcon(volume), size: 24, color: Colors.white70),
        ),
      ),
    );
  }
}

class _VolumeRoute extends PopupRoute<void> {
  _VolumeRoute({
    required this.anchor,
    required this.player,
    required this.barrierLabel,
  });

  /// 音量按钮在屏幕上的位置，音量条从这里长出来、缩回这里。
  final Rect anchor;
  final PlayerController player;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 380);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  late final CurvedAnimation _curved = CurvedAnimation(
    parent: animation!,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _VolumePanel(
    anchor: anchor,
    player: player,
    animation: _curved,
    route: animation,
  );
}

class _VolumePanel extends StatelessWidget {
  const _VolumePanel({
    required this.anchor,
    required this.player,
    required this.animation,
    required this.route,
  });

  final Rect anchor;
  final PlayerController player;

  /// 加了曲线的进度：0 是按钮，1 是展开的音量条。
  final Animation<double> animation;

  /// 路由本身的动画，只用来判断是在展开还是在收起。
  final Animation<double> route;

  static const _width = 56.0, _height = 220.0;

  void _set(double v) => unawaited(player.setVolume(v * 100));

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final c = anchor.center;
    // 底部那一格放图标，正好盖在按钮原来的位置上
    final left = (c.dx - _width / 2).clamp(8.0, screen.width - _width - 8);
    final bottom = c.dy + _width / 2;
    final panel = Rect.fromLTRB(
      left,
      max(top + 8, bottom - _height),
      left + _width,
      bottom,
    );
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          final rect = Rect.lerp(anchor, panel, t)!;
          final radius = lerpDouble(anchor.shortestSide / 2, _width / 2, t)!;
          final content = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: IgnorePointer(
                  // 收起途中不再接受拖动
                  ignoring: route.status == AnimationStatus.reverse,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24 * t, sigmaY: 24 * t),
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.16 * t),
                        child: LayoutBuilder(
                          builder: (context, box) {
                            double at(Offset o) =>
                                (1 - o.dy / box.maxHeight).clamp(0.0, 1.0);
                            return Listener(
                              onPointerSignal: (e) {
                                if (e is PointerScrollEvent) {
                                  _set(
                                    (player.volume - e.scrollDelta.dy / 8) /
                                        100,
                                  );
                                }
                              },
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragStart: (d) =>
                                    _set(at(d.localPosition)),
                                onVerticalDragUpdate: (d) =>
                                    _set(at(d.localPosition)),
                                onTapUp: (d) => _set(at(d.localPosition)),
                                child: ListenableBuilder(
                                  listenable: player,
                                  builder: (context, _) => _VolumeFill(
                                    volume: player.volume,
                                    content: content,
                                    iconBox: lerpDouble(
                                      anchor.height,
                                      _width,
                                      t,
                                    )!,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 音量条里面：从下往上的填充、顶上的数值、底部的图标。图标被填充盖住时换成深色。
class _VolumeFill extends StatelessWidget {
  const _VolumeFill({
    required this.volume,
    required this.content,
    required this.iconBox,
  });

  final double volume;
  final double content;
  final double iconBox;

  @override
  Widget build(BuildContext context) {
    final v = volume / 100;
    return LayoutBuilder(
      builder: (context, box) {
        final filled = v * box.maxHeight;
        Color on(bool covered) =>
            Color.lerp(Colors.white70, Colors.black87, covered ? content : 0)!;
        return Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: filled,
                width: double.infinity,
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: 0.9 * content),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: content,
                child: Text(
                  '${volume.round()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: on(filled > box.maxHeight - 22),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: iconBox,
              child: Center(
                child: Icon(
                  _volumeIcon(volume),
                  size: 24,
                  color: on(filled > iconBox / 2),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 音质切换：只列出当前歌曲实际可播放的档位。
/// 点一下按钮本身会用弹簧动画长成毛玻璃菜单，和音量条同一套质感；选完再缩回按钮。
class QualityMenu extends StatefulWidget {
  const QualityMenu({super.key});

  @override
  State<QualityMenu> createState() => _QualityMenuState();
}

class _QualityMenuState extends State<QualityMenu>
    with SingleTickerProviderStateMixin {
  static const _headerHeight = 34.0;
  static const _rowHeight = 44.0;
  static const _pad = 6.0;
  static const _menuWidth = 200.0;
  static const _menuRadius = 22.0;

  // 展开带一点回弹，收起不回弹、干脆利落
  static final _openSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 380,
    ratio: 0.68,
  );
  static final _closeSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 560,
    ratio: 1,
  );

  final _link = LayerLink();
  final _chipKey = GlobalKey();
  final _portal = OverlayPortalController();

  // 0 是按钮，1 是菜单；弹簧会冲过 1 一点，所以不设上下界
  late final _c = AnimationController.unbounded(vsync: this);
  Size _chipSize = Size.zero;
  bool _expanded = false;

  /// 刚点中、还没收起的那一档，白色选中块先滑过去再收。
  Quality? _picked;

  Animation<double>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (route == _route) return;
    _route?.removeStatusListener(_onRouteStatus);
    _route = route?..addStatusListener(_onRouteStatus);
  }

  /// 播放页开始收起时菜单跟着缩回按钮，不留在最上层。
  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) unawaited(_close());
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onRouteStatus);
    _c.dispose();
    super.dispose();
  }

  void _open() {
    final box = _chipKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    setState(() {
      _chipSize = box.size;
      _expanded = true;
      _picked = null;
    });
    _portal.show();
    unawaited(
      _c.animateWith(SpringSimulation(_openSpring, _c.value, 1, _c.velocity)),
    );
  }

  Future<void> _close() async {
    if (!_expanded) return;
    _expanded = false;
    await _c.animateBackWith(
      SpringSimulation(_closeSpring, _c.value, 0, _c.velocity, snapToEnd: true),
    );
    if (!mounted || _expanded) return;
    _portal.hide();
    setState(() => _picked = null);
  }

  Future<void> _pick(PlayerController p, Quality q) async {
    setState(() => _picked = q);
    unawaited(p.setQuality(q));
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted) await _close();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final l = AppLocalizations.of(context);
    final actual = p.actualQuality;
    // 请求的音质没权限时 Rust 层会自动降级，按钮上只显示实际在播的档位
    final label = actual == null ? l.quality : qualityLabel(l, actual);
    final options = p.qualityOptions
        .where((option) => option.available)
        .toList();
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (_) => _buildMenu(p, l, label, options),
      child: CompositedTransformTarget(
        link: _link,
        // 展开期间按钮本体让给菜单，原位置留空
        child: Opacity(
          opacity: _portal.isShowing ? 0 : 1,
          child: Tooltip(
            message: p.qualitiesLoading
                ? l.qualityLoading
                : p.qualitiesError != null
                ? l.qualityFailed(errorText(l, p.qualitiesError!))
                : options.isEmpty
                ? l.qualityNoneForSong
                : l.quality,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: p.qualitiesLoading ? null : _open,
              child: Container(
                key: _chipKey,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: const ShapeDecoration(
                  color: Color(0x1FFFFFFF),
                  shape: StadiumBorder(),
                ),
                child: _chipContent(label, loading: p.qualitiesLoading),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipContent(String label, {bool loading = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.graphic_eq_rounded, size: 13, color: Colors.white70),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(left: 5),
            child: SizedBox.square(
              dimension: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.white70,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMenu(
    PlayerController p,
    AppLocalizations l,
    String label,
    List<QualityOption> options,
  ) {
    final error = p.qualitiesError != null;
    final count = error || options.isEmpty ? 1 : options.length;
    final selected = _picked ?? p.actualQuality;
    final selectedIndex = error
        ? -1
        : options.indexWhere((o) => o.quality == selected);
    final menuSize = Size(
      max(_menuWidth, _chipSize.width),
      _headerHeight + count * _rowHeight + _pad * 2,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_close()),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          // 播放页收起时按钮不再绘制，菜单别跑到左上角去
          showWhenUnlinked: false,
          // 以按钮底边中点为锚，菜单从按钮所在位置往上长出来
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.bottomCenter,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final v = _c.value;
              final t = v.clamp(0.0, 1.0);
              double fade(double from, double to) =>
                  ((v - from) / (to - from)).clamp(0.0, 1.0);
              // 选项一行接一行浮上来，行多的时候间隔压缩，保证在弹簧到位前都出来
              final step = min(0.06, 0.3 / count);
              final chipFade = 1 - fade(0, 0.3);

              Widget appear(int i, Widget child) {
                final a = Curves.easeOut.transform(
                  fade(0.3 + i * step, 0.7 + i * step),
                );
                return Opacity(
                  opacity: a,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - a)),
                    child: child,
                  ),
                );
              }

              final rows = <Widget>[
                if (error)
                  _row(
                    l.qualityFailedRetry,
                    onTap: () {
                      unawaited(p.refreshQualities());
                      unawaited(_close());
                    },
                  )
                else if (options.isEmpty)
                  _row(l.qualityNone)
                else
                  for (final option in options)
                    _row(
                      qualityLabel(l, option.quality),
                      selected: option.quality == selected,
                      onTap: () => unawaited(_pick(p, option.quality)),
                    ),
              ];

              final menu = Padding(
                padding: const EdgeInsets.all(_pad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Opacity(
                      opacity: fade(0.25, 0.65),
                      child: SizedBox(
                        height: _headerHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.graphic_eq_rounded,
                                size: 15,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l.quality,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Stack(
                      children: [
                        // 白底选中块：换档时滑到新的一行
                        if (selectedIndex >= 0)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            left: 0,
                            right: 0,
                            top: selectedIndex * _rowHeight,
                            height: _rowHeight,
                            child: Opacity(
                              opacity: fade(0.35, 0.75),
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(_menuRadius - _pad),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < rows.length; i++)
                              appear(i, rows[i]),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );

              final w = lerpDouble(_chipSize.width, menuSize.width, v)!;
              final h = lerpDouble(_chipSize.height, menuSize.height, v)!;
              return SizedBox(
                width: w,
                height: h,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_menuRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28 * t),
                        blurRadius: 30 * t,
                        offset: Offset(0, 10 * t),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      lerpDouble(_chipSize.height / 2, _menuRadius, t)!,
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24 * t, sigmaY: 24 * t),
                      child: ColoredBox(
                        color: Colors.white.withValues(
                          alpha: lerpDouble(0.12, 0.16, t)!,
                        ),
                        child: Stack(
                          children: [
                            if (chipFade > 0)
                              Positioned.fill(
                                child: Opacity(
                                  opacity: chipFade,
                                  child: Center(child: _chipContent(label)),
                                ),
                              ),
                            if (v > 0.25)
                              Positioned.fill(
                                child: OverflowBox(
                                  alignment: Alignment.bottomCenter,
                                  minWidth: menuSize.width,
                                  maxWidth: menuSize.width,
                                  minHeight: menuSize.height,
                                  maxHeight: menuSize.height,
                                  child: menu,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 「高品质 320k」拆成名字和规格两段，规格靠右用小字。
  Widget _row(String text, {bool selected = false, VoidCallback? onTap}) {
    final split = text.lastIndexOf(' ');
    final name = split > 0 ? text.substring(0, split) : text;
    final spec = split > 0 ? text.substring(split + 1) : null;
    final color = onTap == null
        ? Colors.white38
        : selected
        ? Colors.black
        : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: _rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (spec != null)
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color.withValues(alpha: selected ? 0.55 : 0.5),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  child: Text(spec),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueuePanel extends StatefulWidget {
  const _QueuePanel({super.key, this.onPullStart, this.onPull, this.onPullEnd});

  /// 窄屏：列表已经在最顶上还往下拉时，这次拖动改成翻回主页面，跟着手指走。
  /// [onPull] 给竖直位移，[onPullEnd] 给松手时的竖直速度。
  final VoidCallback? onPullStart;
  final ValueChanged<double>? onPull;
  final ValueChanged<double>? onPullEnd;

  @override
  State<_QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<_QueuePanel> {
  late final ScrollController _scroll = SmoothScrollController(
    initialScrollOffset: QueueList.initialOffset(
      context.read<PlayerController>().index,
    ),
  );

  /// 直接看手指，不进手势竞争：比列表的滚动手势先一步判断是不是在顶上往下拉。
  VelocityTracker? _tracker;
  double _moved = 0;
  bool _decided = false;
  bool _pulling = false;

  /// 这次按在了拖动手柄上。手柄里的监听比这里的 [_onDown] 先收到按下。
  bool _onHandle = false;

  void _onDown(PointerDownEvent e) {
    final onHandle = _onHandle;
    _onHandle = false;
    if (widget.onPull == null || onHandle) return;
    _tracker = VelocityTracker.withKind(e.kind)
      ..addPosition(e.timeStamp, e.position);
    _moved = 0;
    _decided = false;
  }

  void _onMove(PointerMoveEvent e) {
    final tracker = _tracker;
    if (tracker == null) return;
    tracker.addPosition(e.timeStamp, e.position);
    if (_pulling) {
      widget.onPull!(e.delta.dy);
      return;
    }
    if (_decided) return;
    _moved += e.delta.dy;
    // 比列表滚动的判定距离小，列表还没开始滚就决定好
    if (_moved.abs() < 8) return;
    _decided = true;
    final atTop =
        _scroll.hasClients &&
        _scroll.position.pixels <= _scroll.position.minScrollExtent;
    if (_moved < 0 || !atTop) return;
    // 拉的时候列表本身不能滚，换掉滚动物理也会结束列表已经开始的那次滚动
    setState(() => _pulling = true);
    widget.onPullStart!();
    widget.onPull!(_moved);
  }

  void _onUp(PointerEvent e, {required bool cancel}) {
    final tracker = _tracker;
    _tracker = null;
    if (!_pulling) return;
    setState(() => _pulling = false);
    widget.onPullEnd!(
      cancel || tracker == null ? 0 : tracker.getVelocity().pixelsPerSecond.dy,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 20, 12),
          child: Text(
            l.upNext,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0, 0.04, 0.9, 1],
            ).createShader(r),
            child: Listener(
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: (e) => _onUp(e, cancel: false),
              onPointerCancel: (e) => _onUp(e, cancel: true),
              child: QueueList(
                controller: _scroll,
                physics: _pulling ? const NeverScrollableScrollPhysics() : null,
                color: Colors.white,
                dragColor: const Color(0xF0303030),
                // 在手柄上按下是要拖动排序，不当成往下拉翻回主页面
                onHandleDown: () => _onHandle = true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
