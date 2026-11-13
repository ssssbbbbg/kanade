import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'keyed_route.dart';
import 'mv_controls.dart';
import 'singer_page.dart';
import 'user_page.dart';
import 'widgets.dart';

/// MV 播放页：上面是 16:9 播放器（自己的控制层，返回键也在里面），下面是资料。
/// 打开时暂停正在放的歌，离开时不自动恢复。
class MvPage extends StatelessWidget {
  const MvPage({super.key, required this.vid, required this.title});

  final String vid;
  final String title;

  static Route<void> route(String vid, String title) => MaterialPageRoute(
    builder: (_) => MvPage(vid: vid, title: title),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // 加载中和加载失败时用这个返回；加载好以后被播放器盖住，由控制层里的返回接手
            const Positioned(top: 8, left: 8, child: _BackButton()),
            AsyncView<MvDetail>(
              load: () => api.getMvDetail(vid: vid),
              builder: (context, d) => _Body(d),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => IconButton(
    style: IconButton.styleFrom(
      backgroundColor: Colors.black54,
      foregroundColor: Colors.white,
    ),
    icon: const Icon(Icons.chevron_left_rounded),
    onPressed: () => Navigator.of(context).maybePop(),
  );
}

class _Body extends StatefulWidget {
  const _Body(this.d);

  final MvDetail d;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  /// 默认 720P：比 1080P 省流量，手机和窗口里都够清楚。
  static const _defaultHeight = 720;

  final _player = Player(
    configuration: const PlayerConfiguration(title: 'Kanade MV'),
  );
  late final _controller = VideoController(_player);

  /// 全屏页里的控制层也要跟着变，所以用通知而不是 setState。
  final _stream = ValueNotifier<MvStream?>(null);

  /// 清晰度菜单从高到低。
  late final _streams = [...widget.d.streams]
    ..sort((a, b) => b.height.compareTo(a.height));

  @override
  void initState() {
    super.initState();
    final streams = widget.d.streams;
    if (streams.isEmpty) return;
    context.read<PlayerController>().pause();
    _play(
      streams.lastWhere(
        (s) => s.height <= _defaultHeight,
        orElse: () => streams.first,
      ),
      Duration.zero,
    );
  }

  @override
  void dispose() {
    _player.dispose();
    _stream.dispose();
    super.dispose();
  }

  void _play(MvStream stream, Duration start) {
    _stream.value = stream;
    _player.open(Media(stream.url, start: start));
  }

  /// 换清晰度时从当前位置接着放。
  void _switch(MvStream stream) {
    if (stream == _stream.value) return;
    _play(stream, _player.state.position);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final d = widget.d;
    return ListView(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: d.streams.isEmpty
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Cover(d.coverUrl, radius: 0),
                    ColoredBox(
                      color: Colors.black54,
                      child: Center(
                        child: Text(
                          l.mvUnavailable,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    const Positioned(top: 8, left: 8, child: _BackButton()),
                  ],
                )
              : Video(
                  controller: _controller,
                  controls: (_) => MvControls(
                    player: _player,
                    title: d.name,
                    streams: _streams,
                    stream: _stream,
                    onStream: _switch,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            d.name,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            [
              if (d.uploader.isNotEmpty) d.uploader,
              if (d.playCount > BigInt.zero)
                '▶ ${formatCount(l, d.playCount.toInt())}',
              if (d.publishDate.isNotEmpty) d.publishDate,
            ].join(' · '),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
        for (final s in d.singers)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Material(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: s.mid.isEmpty
                    ? null
                    : () => openPage(context, SingerPage.route(s.mid, s.name)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      ClipOval(
                        child: Cover(singerAvatar(s.mid), size: 40, radius: 0),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (d.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: IntroText(d.description),
          ),
        const BottomSpacer(),
      ],
    );
  }
}
