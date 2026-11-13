import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n_ext.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import '../update/app_update.dart';
import 'kanade_dialog.dart';
import 'sheet.dart';

/// 发现新版本时的弹窗：说明 → 下载进度 → 失败，三步在同一个弹窗里切换，高度平滑过渡。
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo info,
  String current,
) => showKanadeDialog<void>(
  context,
  builder: (_) => _UpdateDialog(info: info, current: current),
);

enum _Failure { network, corrupted, notWritable, install }

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info, required this.current});

  final UpdateInfo info;
  final String current;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  late final _assets = AppUpdate.assetsFor(widget.info);
  var _choice = 0;
  var _downloading = false;
  String? _source;
  var _received = 0;
  final _clock = Stopwatch();
  _Failure? _failure;
  String? _detail;
  StreamSubscription<UpdateEvent>? _events;

  UpdateInfo get _info => widget.info;

  @override
  void dispose() {
    if (_downloading) api.cancelUpdateDownload();
    _events?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final asset = _assets[_choice];
    if (asset.name.endsWith('.zip') && !AppUpdate.canReplaceFiles()) {
      setState(() => _failure = _Failure.notWritable);
      return;
    }
    final path = await AppUpdate.downloadPath(asset);
    if (!mounted) return;
    setState(() {
      _downloading = true;
      _failure = null;
      _source = null;
      _received = 0;
    });
    await _events?.cancel();
    _events = api
        .downloadUpdate(
          tag: _info.tag,
          asset: asset,
          dest: path,
          mirror: AppUpdate.mirror,
        )
        .listen((e) => _onEvent(e, path));
  }

  Future<void> _onEvent(UpdateEvent e, String path) async {
    if (!mounted) return;
    switch (e) {
      case UpdateEvent_Connected(:final source):
        _clock
          ..reset()
          ..start();
        setState(() {
          _source = source;
          _received = 0;
        });
      case UpdateEvent_Progress(:final received):
        setState(() => _received = received);
      case UpdateEvent_Done():
        // Windows 上打开安装后直接退出 App，不会回到这里
        final ok = await AppUpdate.install(path);
        if (!mounted) return;
        if (ok) {
          Navigator.of(context).pop();
        } else {
          _fail(_Failure.install);
        }
      case UpdateEvent_Corrupted():
        _fail(_Failure.corrupted);
      case UpdateEvent_Failed(:final error):
        _fail(_Failure.network, errorText(AppLocalizations.of(context), error));
      case UpdateEvent_Cancelled():
        break;
    }
  }

  void _fail(_Failure failure, [String? detail]) => setState(() {
    _downloading = false;
    _failure = failure;
    _detail = detail;
  });

  void _openBrowser() {
    launchUrl(
      Uri.parse('${AppUpdate.releasesUrl}/tag/${_info.tag}'),
      mode: LaunchMode.externalApplication,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      // 下载中只能点「取消」关掉，免得误触弹窗外面
      canPop: !_downloading,
      child: _failure != null
          ? _failed(l)
          : _downloading
          ? _progress(l)
          : _intro(l),
    );
  }

  Widget _intro(AppLocalizations l) {
    final pop = Navigator.of(context).pop;
    return KanadeDialog(
      animateSize: true,
      icon: Icons.system_update_alt_rounded,
      title: l.updateAvailable(_info.tag),
      message: [
        if (_info.prerelease) l.updatePreviewBadge,
        l.updateCurrent('v${widget.current}'),
        l.updateDate(_info.date),
      ].join(' · '),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Notes(_info.notes),
          if (_assets.length > 1)
            for (final (i, a) in _assets.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _Option(
                  selected: i == _choice,
                  title: a.name.endsWith('.zip')
                      ? l.updateArchive
                      : l.updateInstaller,
                  size: _mb(a.size),
                  hint: a.name.endsWith('.zip')
                      ? l.updateArchiveHint
                      : l.updateInstallerHint,
                  onTap: () => setState(() => _choice = i),
                ),
              ),
        ],
      ),
      actions: [
        _assets.isEmpty
            ? KanadeDialogAction(
                label: l.updateOpenBrowser,
                primary: true,
                onPressed: _openBrowser,
              )
            : KanadeDialogAction(
                label: l.updateNow,
                primary: true,
                onPressed: _start,
              ),
        KanadeDialogAction(label: l.later, onPressed: pop),
        KanadeDialogAction(
          label: l.updateSkip,
          onPressed: () {
            AppUpdate.skip(_info.tag);
            pop();
          },
        ),
      ],
    );
  }

  Widget _progress(AppLocalizations l) {
    final scheme = Theme.of(context).colorScheme;
    final (_, fill) = sheetColors(scheme);
    final total = _assets[_choice].size;
    final seconds = _clock.elapsedMilliseconds / 1000;
    final speed = _source == null || seconds < 0.5 ? null : _received / seconds;
    final muted = TextStyle(
      fontSize: 12.5,
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return KanadeDialog(
      animateSize: true,
      icon: Icons.download_rounded,
      title: l.updateDownloading(_info.tag),
      message: l.updateDownloadingHint,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: total == 0 || _source == null ? null : _received / total,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            color: scheme.onSurface,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('${_mb(_received)} / ${_mb(total)}', style: muted),
              const Spacer(),
              if (speed != null) Text('${_mb(speed.round())}/s', style: muted),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.public, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _source == null
                        ? l.updateConnecting
                        : l.updateSource(_source!),
                    style: muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        KanadeDialogAction(
          label: l.cancel,
          onPressed: () {
            api.cancelUpdateDownload();
            setState(() => _downloading = false);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _failed(AppLocalizations l) {
    final failure = _failure!;
    final installer = _assets.indexWhere((a) => !a.name.endsWith('.zip'));
    return KanadeDialog(
      animateSize: true,
      icon: Icons.error_outline_rounded,
      danger: true,
      title: l.updateFailed,
      message: switch (failure) {
        _Failure.network => '${l.updateNetworkFailed}\n$_detail',
        _Failure.corrupted => l.updateCorrupted,
        _Failure.notWritable => l.updateNotWritable,
        _Failure.install => l.updateInstallFailed,
      },
      actions: [
        if (failure == _Failure.notWritable && installer >= 0)
          KanadeDialogAction(
            label: l.updateUseInstaller,
            primary: true,
            onPressed: () {
              _choice = installer;
              _start();
            },
          )
        else
          KanadeDialogAction(label: l.retry, primary: true, onPressed: _start),
        KanadeDialogAction(label: l.updateOpenBrowser, onPressed: _openBrowser),
        KanadeDialogAction(
          label: l.close,
          onPressed: Navigator.of(context).pop,
        ),
      ],
    );
  }
}

/// 更新说明。发布流程生成的是 Markdown：标题行加粗，列表换成圆点，完整对比的链接不显示。
class _Notes extends StatelessWidget {
  const _Notes(this.notes);

  final String notes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (_, fill) = sheetColors(scheme);
    final lines = [
      for (final raw in notes.split('\n'))
        if (raw.trim() case final line
            when line.isNotEmpty && !line.startsWith('**'))
          line,
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              if (line.startsWith('#'))
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Text(
                    line.replaceFirst(RegExp(r'^#+\s*'), ''),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Text(
                  line.replaceFirst(RegExp(r'^[-*]\s+'), '· '),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Windows 上选安装包还是压缩包。
class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.title,
    required this.size,
    required this.hint,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String size;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.onSurface : scheme.outline,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      width: selected ? 5 : 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: title,
                        children: [TextSpan(text: '  $size', style: muted)],
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(hint, style: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 启动时（只在发布版）和设置里手动检查。`manual` 时把「已是最新」和失败也告诉用户。
Future<UpdateCheckResult> checkForUpdate(
  BuildContext context, {
  bool manual = false,
}) async {
  final (UpdateInfo, String)? found;
  try {
    found = await AppUpdate.check();
  } catch (e) {
    return UpdateCheckResult.failed;
  }
  if (found == null) return UpdateCheckResult.upToDate;
  final (info, current) = found;
  if (!manual && AppUpdate.skipped == info.tag) {
    return UpdateCheckResult.upToDate;
  }
  if (context.mounted && (Platform.isWindows || Platform.isAndroid)) {
    await showUpdateDialog(context, info, current);
  }
  return UpdateCheckResult.found;
}

enum UpdateCheckResult { upToDate, found, failed }
