import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../settings/locale_controller.dart';
import '../settings/theme_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import '../update/app_update.dart';
import 'foryou_settings_page.dart';
import 'glass_dropdown.dart';
import 'kanade_dialog.dart';
import 'smooth_scroll.dart';
import 'theme_reveal.dart';
import 'toast.dart';
import 'update_dialog.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const SettingsPage());

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// 设置里能选的默认音质，按官方顺序从免费到 SVIP 排列；缺解码器的档位不显示。
final _qualities = [
  Quality.low,
  Quality.standard,
  Quality.aicodec,
  Quality.high,
  Quality.lossless,
  Quality.hires,
  Quality.dolby,
  Quality.atmos51,
  Quality.atmos71,
  Quality.atmos,
  Quality.master,
  Quality.ra360,
  Quality.dts,
].where((q) => api.qualitySupported(quality: q)).toList();

/// 切歌淡入淡出的档位（秒），0 表示关闭。
const _fades = [0, 1, 2, 3, 5];

/// 歌曲缓存上限的预设档位（MB），0 表示关闭。
const _limits = [0, 512, 1024, 2048, 4096, 8192];

const _languageNames = {'zh': '简体中文', 'en': 'English'};

const _themeIcons = {
  ThemeMode.system: Icons.brightness_auto_outlined,
  ThemeMode.light: Icons.light_mode_outlined,
  ThemeMode.dark: Icons.dark_mode_outlined,
};

/// 内容区宽过这个就左边分类、右边内容。
const _wideWidth = 720.0;

String _sizeText(int bytes) {
  const mb = 1024 * 1024;
  if (bytes < mb) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / mb / 1024).toStringAsFixed(2)} GB';
}

String _limitText(AppLocalizations l, int mb) => switch (mb) {
  0 => l.audioCacheOff,
  _ when mb % 1024 == 0 => '${mb ~/ 1024} GB',
  _ => '$mb MB',
};

String _fadeText(AppLocalizations l, int seconds) =>
    seconds == 0 ? l.songFadeOff : l.songFadeSeconds('$seconds');

String _themeText(AppLocalizations l, ThemeMode m) => switch (m) {
  ThemeMode.system => l.themeSystem,
  ThemeMode.light => l.themeLight,
  ThemeMode.dark => l.themeDark,
};

/// 一个分类：标题、左侧分类栏的图标、卡片里的各行，以及卡片下面单独的一块（退出登录）。
typedef _Section = ({
  String title,
  IconData icon,
  List<Widget> rows,
  Widget? after,
});

class _SettingsPageState extends State<SettingsPage> {
  int _limitMb = api.getAudioCacheLimitMb();
  int? _audioSize;
  int? _apiSize;
  final _scroll = SmoothScrollController();
  final _sectionKeys = List.generate(5, (_) => GlobalKey());
  final _themeIconKeys = {for (final m in ThemeMode.values) m: GlobalKey()};
  final _qualityMenu = GlobalKey<GlassDropdownState<Quality>>();
  final _languageMenu = GlobalKey<GlassDropdownState<String>>();
  final _limitMenu = GlobalKey<GlassDropdownState<int>>();
  String? _version;
  var _checking = false;
  UpdateCheckResult? _checked;
  var _preview = AppUpdate.preview;
  var _mirror = AppUpdate.mirror;
  var _sectionCount = 0;
  var _current = 0;
  var _wide = false;

  /// 点左边分类后正在滚过去。
  var _jumping = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_spy);
    _loadSizes();
    AppUpdate.currentVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await checkForUpdate(context, manual: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checked = result;
    });
    if (result == UpdateCheckResult.failed) {
      showToast(
        context,
        AppLocalizations.of(context).updateCheckFailed,
        kind: ToastKind.error,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSizes() async {
    final audio = await context.read<PlayerController>().audioCacheInfo();
    final other = await api.getApiCacheSize();
    if (!mounted) return;
    setState(() {
      _audioSize = audio.bytes;
      _limitMb = audio.limitMb;
      _apiSize = other;
    });
  }

  /// 宽屏时左边高亮滚到的那一类：顶到上沿附近的最后一类，滚到底就是最后一类。
  void _spy() {
    if (!_wide || !_scroll.hasClients || _jumping) return;
    final pos = _scroll.position;
    var current = 0;
    if (pos.pixels >= pos.maxScrollExtent - 2) {
      current = _sectionCount - 1;
    } else {
      for (var i = 0; i < _sectionCount; i++) {
        final box = _sectionKeys[i].currentContext?.findRenderObject();
        if (box == null) continue;
        final top = RenderAbstractViewport.of(box)
            .getOffsetToReveal(box, 0)
            .offset;
        if (top - 40 <= pos.pixels) current = i;
      }
    }
    if (current != _current) setState(() => _current = current);
  }

  /// 点左边分类滚过去：距离越远滚得越久，途中高亮停在点的那一类，不在经过的分类上乱跳。
  void _jump(int i) {
    final box = _sectionKeys[i].currentContext?.findRenderObject();
    if (box == null || !_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = RenderAbstractViewport.of(box)
        .getOffsetToReveal(box, 0)
        .offset
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    final distance = (target - pos.pixels).abs();
    setState(() => _current = i);
    if (distance < 1) return;
    _jumping = true;
    _scroll
        .animateTo(
          target,
          duration: Duration(
            milliseconds: (280 + distance / 5).clamp(280, 560).round(),
          ),
          curve: Curves.easeInOutCubic,
        )
        .whenComplete(() {
          _jumping = false;
          // 中途被滚轮或拖动打断时，按停下的位置重新高亮
          if (mounted && (_scroll.position.pixels - target).abs() > 1) _spy();
        });
  }

  Future<bool> _confirm(
    String text,
    String action, {
    required IconData icon,
    bool danger = false,
  }) async {
    final l = AppLocalizations.of(context);
    final ok = await showKanadeDialog<bool>(
      context,
      builder: (context) => KanadeDialog(
        icon: icon,
        danger: danger,
        title: text,
        actions: [
          KanadeDialogAction(
            label: action,
            primary: true,
            danger: danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          KanadeDialogAction(
            label: l.cancel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// -1 表示自定义。
  Future<void> _selectLimit(int v) async {
    final player = context.read<PlayerController>();
    int? mb = v;
    if (v < 0) {
      // 等菜单缩回去再弹输入框
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      mb = await _customLimit();
    }
    if (mb == null) return;
    await player.setAudioCacheLimit(mb);
    if (!mounted) return;
    await _loadSizes();
  }

  Future<int?> _customLimit() {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: _limitMb > 0 ? '$_limitMb' : '',
    );
    return showKanadeDialog<int>(
      context,
      builder: (context) {
        void submit() =>
            Navigator.of(context).pop(int.tryParse(controller.text));
        return KanadeDialog(
          icon: Icons.sd_storage_outlined,
          title: l.audioCacheCustomTitle,
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: kanadeFieldDecoration(
              context,
              suffix: l.audioCacheCustomUnit,
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            KanadeDialogAction(label: l.ok, primary: true, onPressed: submit),
            KanadeDialogAction(
              label: l.cancel,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _clearAudio() async {
    final l = AppLocalizations.of(context);
    final player = context.read<PlayerController>();
    if (!await _confirm(
      l.clearAudioCacheConfirm,
      l.clear,
      icon: Icons.music_off_outlined,
    )) {
      return;
    }
    await player.clearAudioCache();
    if (!mounted) return;
    await _loadSizes();
    if (mounted) showToast(context, l.cacheCleared, kind: ToastKind.success);
  }

  Future<void> _clearApi() async {
    final l = AppLocalizations.of(context);
    if (!await _confirm(
      l.clearApiCacheConfirm,
      l.clear,
      icon: Icons.cleaning_services_outlined,
    )) {
      return;
    }
    await api.clearCache();
    await _loadSizes();
    if (mounted) showToast(context, l.cacheCleared, kind: ToastKind.success);
  }

  Future<void> _logout() async {
    final l = AppLocalizations.of(context);
    if (!await _confirm(
      l.logoutConfirm,
      l.logout,
      icon: Icons.logout_rounded,
      danger: true,
    )) {
      return;
    }
    if (!mounted) return;
    await context.read<AuthController>().logout();
    if (mounted) Navigator.of(context).pop();
  }

  Widget _storage(AppLocalizations l, ColorScheme scheme) {
    final size = _audioSize;
    final muted = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                size == null ? '…' : _sizeText(size),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _limitMb == 0
                    ? l.audioCacheDisabled
                    : l.audioCacheOfLimit(_limitText(l, _limitMb)),
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: size == null || _limitMb == 0
                ? 0
                : (size / (_limitMb * 1024 * 1024)).clamp(0, 1),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: scheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${l.audioCacheSize} · ${l.audioCacheLimitHint}',
                  style: muted,
                ),
              ),
              const SizedBox(width: 12),
              _ClearButton(
                onPressed: size == null || size == 0 ? null : _clearAudio,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final locale = context.watch<LocaleController>().locale;
    final themeMode = context.watch<ThemeController>().mode;
    final defaultQuality = context.select<PlayerController, Quality>(
      (p) => p.defaultQuality,
    );
    final fade = context.select<PlayerController, int>((p) => p.fade.inSeconds);
    final loggedIn = context.select<AuthController, bool>((a) => a.loggedIn);
    // 空字符串表示跟随系统
    final languageCodes = [
      '',
      for (final locale in AppLocalizations.supportedLocales)
        locale.languageCode,
    ];
    String languageText(String c) =>
        c.isEmpty ? l.languageSystem : _languageNames[c] ?? c;

    final List<_Section> sections = [
      (
        title: l.settingsPlayback,
        icon: Icons.play_circle_outline,
        rows: [
          _Item(
            icon: Icons.high_quality_outlined,
            title: l.defaultQuality,
            hint: l.defaultQualityHint,
            value: GlassDropdown<Quality>(
              key: _qualityMenu,
              title: l.defaultQuality,
              values: _qualities,
              selected: defaultQuality,
              label: (q) => qualityLabel(l, q),
              onSelected: context.read<PlayerController>().setDefaultQuality,
              child: _Value(qualityLabel(l, defaultQuality)),
            ),
            onTap: () => _qualityMenu.currentState?.open(),
          ),
          _SegmentedItem(
            icon: Icons.graphic_eq,
            title: l.songFade,
            hint: l.songFadeHint,
            segments: [
              for (final s in _fades)
                _Segment(
                  selected: s == fade,
                  onTap: () => context.read<PlayerController>().setFade(
                    Duration(seconds: s),
                  ),
                  child: Text(_fadeText(l, s)),
                ),
            ],
          ),
        ],
        after: null,
      ),
      (
        title: l.settingsAppearance,
        icon: Icons.palette_outlined,
        rows: [
          _SegmentedItem(
            icon: Icons.contrast,
            title: l.theme,
            segments: [
              for (final m in ThemeMode.values)
                _Segment(
                  selected: m == themeMode,
                  onTap: () => ThemeModeIcon.select(
                    _themeIconKeys[m]!.currentContext!,
                    m,
                    _themeIcons[m]!,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ThemeModeIcon(
                        _themeIcons[m]!,
                        key: _themeIconKeys[m],
                        size: 17,
                        color: m == themeMode
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _themeText(l, m),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          _Item(
            icon: Icons.translate,
            title: l.language,
            value: GlassDropdown<String>(
              key: _languageMenu,
              title: l.language,
              values: languageCodes,
              selected: locale?.languageCode ?? '',
              label: languageText,
              onSelected: (c) => context.read<LocaleController>().setLocale(
                c.isEmpty ? null : Locale(c),
              ),
              child: _Value(languageText(locale?.languageCode ?? '')),
            ),
            onTap: () => _languageMenu.currentState?.open(),
          ),
        ],
        after: null,
      ),
      (
        title: l.settingsStorage,
        icon: Icons.storage_outlined,
        rows: [
          _storage(l, scheme),
          _Item(
            icon: Icons.tune,
            title: l.audioCacheLimit,
            value: GlassDropdown<int>(
              key: _limitMenu,
              title: l.audioCacheLimit,
              values: const [..._limits, -1],
              selected: _limits.contains(_limitMb) ? _limitMb : -1,
              label: (mb) => mb < 0
                  ? '${l.audioCacheCustom}${_limits.contains(_limitMb) ? '' : ' (${_limitText(l, _limitMb)})'}'
                  : _limitText(l, mb),
              onSelected: _selectLimit,
              child: _Value(_limitText(l, _limitMb)),
            ),
            onTap: () => _limitMenu.currentState?.open(),
          ),
          _Item(
            icon: Icons.dataset_outlined,
            title: l.apiCacheSize,
            hint:
                '${l.apiCacheSizeHint} · ${_apiSize == null ? '…' : _sizeText(_apiSize!)}',
            trailing: _ClearButton(
              onPressed: _apiSize == null || _apiSize == 0 ? null : _clearApi,
            ),
          ),
        ],
        after: null,
      ),
      if (loggedIn)
        (
          title: l.settingsAccount,
          icon: Icons.person_outline,
          rows: [
            _Item(
              icon: Icons.dashboard_customize_outlined,
              title: l.foryouSettings,
              hint: l.foryouSettingsHint,
              onTap: () =>
                  Navigator.of(context).push(ForyouSettingsPage.route()),
            ),
          ],
          after: _Card(
            children: [
              InkWell(
                onTap: _logout,
                child: SizedBox(
                  height: 52,
                  child: Center(
                    child: Text(
                      l.logout,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.error,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      (
        title: l.settingsAbout,
        icon: Icons.info_outline,
        rows: [
          _Item(
            icon: Icons.system_update_alt_rounded,
            title: l.checkUpdate,
            hint: _version == null ? null : l.currentVersion("v$_version"),
            value: _Value(
              _checking
                  ? l.updateChecking
                  : _checked == UpdateCheckResult.upToDate
                  ? l.upToDate
                  : "",
            ),
            onTap: _checkUpdate,
          ),
          _Item(
            icon: Icons.science_outlined,
            title: l.updatePreview,
            hint: l.updatePreviewHint,
            onTap: () =>
                setState(() => AppUpdate.preview = _preview = !_preview),
            trailing: Switch(
              value: _preview,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) =>
                  setState(() => AppUpdate.preview = _preview = v),
            ),
          ),
          _Item(
            icon: Icons.public,
            title: l.updateMirror,
            hint: l.updateMirrorHint,
            onTap: () => setState(() => AppUpdate.mirror = _mirror = !_mirror),
            trailing: Switch(
              value: _mirror,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => setState(() => AppUpdate.mirror = _mirror = v),
            ),
          ),
        ],
        after: null,
      ),
    ];
    _sectionCount = sections.length;
    if (_current >= _sectionCount) _current = _sectionCount - 1;

    Widget group(int i, {required bool wide}) {
      final s = sections[i];
      return KeyedSubtree(
        key: _sectionKeys[i],
        child: _Group(
          title: s.title,
          rows: s.rows,
          after: s.after,
          wide: wide,
          first: i == 0,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: GlassDropdown.backdrop(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _wide = constraints.maxWidth >= _wideWidth;
            if (!_wide) {
              return SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < sections.length; i++)
                      group(i, wide: false),
                    const BottomSpacer(),
                  ],
                ),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 200,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 12, 16),
                    // 选中的底色是单独的一块，换分类时上下滑过去
                    child: Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          top: _current * _CategoryTab.extent,
                          left: 0,
                          right: 0,
                          height: _CategoryTab.height,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            for (var i = 0; i < sections.length; i++)
                              _CategoryTab(
                                icon: sections[i].icon,
                                title: sections[i].title,
                                selected: i == _current,
                                onTap: () => _jump(i),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 32, 0),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < sections.length; i++)
                              group(i, wide: true),
                            const BottomSpacer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 下拉选项平时的样子：灰色的当前值加箭头。
class _Value extends StatelessWidget {
  const _Value(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: TextStyle(fontSize: 14, color: muted)),
        Icon(Icons.chevron_right, size: 20, color: muted),
      ],
    );
  }
}

/// 一组设置：灰色小标题（宽屏是大一点的黑字）+ 一张圆角卡片。
class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.rows,
    required this.after,
    required this.wide,
    required this.first,
  });

  final String title;
  final List<Widget> rows;
  final Widget? after;
  final bool wide;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: first ? (wide ? 0 : 4) : (wide ? 28 : 18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, wide ? 10 : 8),
            child: Text(
              title,
              style: wide
                  ? TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    )
                  : TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
            ),
          ),
          _Card(children: rows),
          if (after case final after?) ...[const SizedBox(height: 18), after],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 每行左边的图标小方块。
class _Tile extends StatelessWidget {
  const _Tile(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          // Windows 上中文 w500 会一个字粗一个字细，用 w600
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              hint,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// 一行设置：图标、标题和说明，右边是当前值（下拉菜单）、箭头，或者自己的按钮。
class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    this.hint,
    this.value,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? hint;

  /// 自己带箭头，有它时不再加箭头。
  final Widget? value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final value = this.value;
    final trailing = this.trailing;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              _Tile(icon),
              const SizedBox(width: 14),
              Expanded(
                child: _Label(title: title, hint: hint),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                value,
              ] else if (onTap != null)
                Icon(Icons.chevron_right, size: 20, color: muted),
              if (trailing != null) ...[const SizedBox(width: 12), trailing],
            ],
          ),
        ),
      ),
    );
  }
}

/// 选项少的设置：标题下面一排直接点选。
class _SegmentedItem extends StatelessWidget {
  const _SegmentedItem({
    required this.icon,
    required this.title,
    this.hint,
    required this.segments,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final List<_Segment> segments;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Tile(icon),
              const SizedBox(width: 14),
              Expanded(
                child: _Label(title: title, hint: hint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: segments),
            ),
          ),
        ],
      ),
    );
  }
}

/// 选中是白底黑字（浅色是黑底白字）。
class _Segment extends StatelessWidget {
  const _Segment({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    return Expanded(
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selected ? null : onTap,
          child: SizedBox(
            height: 32,
            child: Center(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                maxLines: 1,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurface,
        disabledBackgroundColor: scheme.surfaceContainerHigh,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(AppLocalizations.of(context).clear),
    );
  }
}

/// 宽屏左边的分类，点了滚到那一类。和桌面侧栏一样不要按下的水波纹。
/// 选中的底色不在这里画，由外面那块滑动的底色负责；这里只让字和图标的颜色跟着渐变。
class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  static const height = 40.0;
  static const _gap = 2.0;

  /// 每一项占的高度，滑动底色按它算位置。
  static const extent = height + _gap;

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          // 悬停色不能跟着选中变：鼠标还在上面时 InkWell 不会换掉已经画上的悬停色，
          // 点了以后会把旧的深色盖在白色选中块上，直到鼠标移开。
          // 用前景色的淡叠加，在选中块上自然看不出来。
          hoverColor: scheme.onSurface.withValues(alpha: 0.06),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // 换深浅色时直接变，不渐变：圆形切换动画里看得到新画面，渐变会露出一瞬间看不清的字
              child: TweenAnimationBuilder<Color?>(
                key: ValueKey(theme.brightness),
                tween: ColorTween(
                  end: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
                duration: const Duration(milliseconds: 200),
                builder: (context, color, _) => Row(
                  children: [
                    Icon(icon, size: 19, color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
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
