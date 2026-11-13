import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_controller.dart';
import '../auth/qr_login_controller.dart';
import '../data/data_ext.dart';
import '../l10n/l10n_ext.dart';
import '../library/library_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/error.dart';
import '../src/rust/api/types.dart';
import 'kanade_dialog.dart';
import 'keyed_route.dart';
import 'playlist_actions.dart';
import 'settings_page.dart';
import 'recent_page.dart';
import 'smooth_scroll.dart';
import 'song_list_page.dart';
import 'theme.dart';
import 'toast.dart';
import 'user_page.dart';
import 'widgets.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.user;
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // 不要“我的”大标题，右上角只留设置
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: l.settings,
            style: IconButton.styleFrom(
              backgroundColor: scheme.surfaceContainerHigh,
            ),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(SettingsPage.route()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: user == null
          ? const _LoggedOut()
          : _LoggedIn(user, key: ValueKey(user.uin)),
    );
  }
}

class _LoggedOut extends StatelessWidget {
  const _LoggedOut();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    void qr(LoginKind kind) => showKanadeDialog<void>(
      context,
      builder: (_) => QrLoginDialog(kind: kind),
    );
    // 头部和已登录时的头像栏对齐，登录后页面不跳
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.outline, width: 2),
                ),
                child: CircleAvatar(
                  radius: 27,
                  backgroundColor: scheme.surfaceContainerHigh,
                  child: Icon(
                    Icons.person_outline,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.notLoggedIn,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.loginPrompt,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            l.loginMethods,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
        _LoginMethod(
          icon: Icons.qr_code,
          title: l.loginQq,
          hint: l.loginQqHint,
          primary: true,
          onTap: () => qr(LoginKind.qq),
        ),
        _LoginMethod(
          icon: Icons.qr_code_2,
          title: l.loginWechat,
          hint: l.loginWechatHint,
          onTap: () => qr(LoginKind.wechat),
        ),
        _LoginMethod(
          icon: Icons.music_note,
          title: l.loginQqMusic,
          hint: l.loginQqMusicHint,
          onTap: () => qr(LoginKind.qqMusic),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
            ),
            onPressed: () => showKanadeDialog<void>(
              context,
              builder: (_) => const CookieLoginDialog(),
            ),
            child: Text(l.loginCookie),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// 未登录页的一行登录方式。primary 的那行图标用抗色，其余灰色。
class _LoginMethod extends StatelessWidget {
  const _LoginMethod({
    required this.icon,
    required this.title,
    required this.hint,
    this.primary = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: primary
                      ? KanadeColors.lime
                      : scheme.surfaceContainerHighest,
                  child: Icon(
                    icon,
                    size: 20,
                    color: primary ? Colors.black : scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoggedIn extends StatefulWidget {
  const _LoggedIn(this.user, {super.key});

  final UserInfo user;

  @override
  State<_LoggedIn> createState() => _LoggedInState();
}

/// 全部歌单（含收藏的），以及自建歌单按 tid 查到的可写信息。
typedef _Playlists = (List<PlaylistBrief>, Map<String, MyPlaylist>);

/// 自建歌单的可写信息拿不到时，只是没有改名/删除入口，列表照常显示。
Future<_Playlists> _loadPlaylists(LibraryController library) async {
  final own = library.myPlaylists().then(
    (l) => {for (final p in l) p.tid.toString(): p},
    onError: (_) => <String, MyPlaylist>{},
  );
  final all = await api.getUserPlaylists();
  return (all, await own);
}

class _LoggedInState extends State<_LoggedIn> {
  /// false：自己创建的；true：收藏别人的。
  bool _collected = false;
  bool _creating = false;
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _isCreated(PlaylistBrief p) =>
      p.creator.isEmpty || p.creator == widget.user.nickname;

  /// “我喜欢”是 dirId 201 的那个自建歌单，点开时才去取它的 id。
  Future<void> _openLiked() async {
    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      final liked = (await context.read<LibraryController>().myPlaylists())
          .where(isLikedPlaylist)
          .firstOrNull;
      if (liked != null) {
        nav.push(SongListPage.playlist(liked.tid.toString(), liked.name));
      }
    } catch (e) {
      Toast.show(overlay, l.loadFailed(errorText(l, e)), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final user = widget.user;
    final likedCount = context.select<LibraryController, int>(
      (c) => c.likedCount,
    );
    final playlistsVersion = context.select<LibraryController, int>(
      (c) => c.playlistsVersion,
    );
    return ListView(
      controller: _scroll,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Row(
            children: [
              GestureDetector(
                onTap: () =>
                    openPage(context, UserPage.route(user.uin, user.nickname)),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 27,
                    backgroundColor: scheme.surfaceContainerHigh,
                    backgroundImage: user.avatarUrl.isEmpty
                        ? null
                        : NetworkImage(httpsUrl(user.avatarUrl)),
                    child: user.avatarUrl.isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID ${user.uin}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _QuickTile(
                  icon: Icon(Icons.favorite, color: scheme.primary),
                  label: l.likedSongs,
                  trailing: likedCount > 0 ? '$likedCount' : null,
                  onTap: _openLiked,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickTile(
                  icon: const Icon(Icons.history),
                  label: l.recentPlays,
                  onTap: () => Navigator.of(context).push(RecentPage.route()),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.myPlaylists,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: l.createPlaylist,
                icon: const Icon(Icons.add_rounded),
                onPressed: _creating
                    ? null
                    : () async {
                        setState(() => _creating = true);
                        try {
                          await createPlaylist(context);
                        } finally {
                          if (mounted) setState(() => _creating = false);
                        }
                      },
              ),
              Pill(
                label: l.playlistsCreated,
                selected: !_collected,
                onTap: () => setState(() => _collected = false),
              ),
              const SizedBox(width: 6),
              Pill(
                label: l.playlistsCollected,
                selected: _collected,
                onTap: () => setState(() => _collected = true),
              ),
            ],
          ),
        ),
        AsyncView<_Playlists>(
          // 改名、删除、加删歌之后重新加载
          key: ValueKey(playlistsVersion),
          load: () => _loadPlaylists(context.read<LibraryController>()),
          builder: (context, data) {
            final (all, own) = data;
            final lists = all
                .where((p) => _isCreated(p) != _collected)
                .toList();
            if (lists.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    l.noPlaylists,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final p in lists)
                  ListTile(
                    leading: Cover(p.coverUrl, size: 52, radius: 12),
                    title: Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (p.songCount > 0) l.songCount(p.songCount),
                        if (!_isCreated(p)) p.creator,
                      ].join(' · '),
                    ),
                    trailing: canEditPlaylist(own[p.id])
                        ? IconButton(
                            tooltip: l.more,
                            icon: Icon(
                              Icons.more_vert,
                              color: scheme.onSurfaceVariant,
                            ),
                            onPressed: () =>
                                showPlaylistActions(context, own[p.id]!),
                          )
                        : Icon(
                            Icons.chevron_right,
                            color: scheme.onSurfaceVariant,
                          ),
                    onTap: () =>
                        openPage(context, SongListPage.playlist(p.id, p.title)),
                    onLongPress: canEditPlaylist(own[p.id])
                        ? () => showPlaylistActions(context, own[p.id]!)
                        : null,
                  ),
              ],
            );
          },
        ),
        // ListView 自己会加上玻璃条盖住的底部 padding
        const SizedBox(height: 16),
      ],
    );
  }
}

/// “我喜欢 / 最近播放”这种大号入口卡片。onTap 为空时显示成暂不可用。
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 92,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  icon,
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (trailing != null)
                        Text(
                          trailing!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QrLoginDialog extends StatefulWidget {
  const QrLoginDialog({super.key, required this.kind});

  final LoginKind kind;

  @override
  State<QrLoginDialog> createState() => _QrLoginDialogState();
}

const _appLogin = MethodChannel('kanade/app_login');

class _QrLoginDialogState extends State<QrLoginDialog> {
  late final _login = QrLoginController(
    widget.kind,
    onSuccess: (user) {
      context.read<AuthController>().onLoggedIn(user);
      Navigator.of(context).pop();
    },
  );

  QrCode? get _qr => _login.qr;
  bool get _expired => _login.expired;
  Object? get _error => _login.error;

  @override
  void initState() {
    super.initState();
    _login.addListener(_onLoginChanged);
    _login.refresh();
  }

  void _onLoginChanged() => setState(() {});

  @override
  void dispose() {
    _login.removeListener(_onLoginChanged);
    _login.dispose();
    super.dispose();
  }

  String _status(AppLocalizations l) {
    return switch (_login.state) {
      QrLoginState.loading => l.qrLoading,
      QrLoginState.loadFailed => l.qrFailed(errorText(l, _error!)),
      QrLoginState.waiting => switch (widget.kind) {
        LoginKind.qq => l.qrScanHintQq,
        LoginKind.wechat => l.qrScanHintWechat,
        LoginKind.qqMusic => l.qrScanHintQqMusic,
      },
      QrLoginState.scanned => l.qrScanned,
      QrLoginState.expired => l.qrExpired,
      QrLoginState.refused => l.qrRefused,
      // LoginFailed 的文案本身就带“登录失败”
      QrLoginState.failed =>
        _error is ApiError_LoginFailed
            ? errorText(l, _error!)
            : l.errorLoginFailed(errorText(l, _error!)),
    };
  }

  /// 申请一张跳转专用票据交给手机 QQ（等同于用 QQ 扫了码），确认后 QQ 通过 schemacallback 切回本 App，
  /// 登录结果仍由现有的 ptqrlogin 轮询拿到。
  Future<void> _openQq() async {
    final old = _qr;
    if (old == null) return;
    final QrCode ticket;
    try {
      final prepared = await _login.prepareQqAppLogin();
      if (prepared == null) return;
      ticket = prepared;
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        showToast(context, l.qrFailed(errorText(l, e)), kind: ToastKind.error);
      }
      return;
    }
    if (!mounted) return;
    final target = Uri.parse(
      'wtloginmqq://ptlogin/qlogin?qrcode=${Uri.encodeComponent(ticket.url)}'
      '&schemacallback=${Uri.encodeComponent('kanade-auth://authorize/qq')}',
    );
    if (!await _launch(target, 'com.tencent.mobileqq') && mounted) {
      showToast(context, AppLocalizations.of(context).qrQqNotInstalled);
    }
  }

  /// 在 QQ 音乐内打开二维码对应的授权页（等同于用 QQ 音乐扫了码），点“登录”后轮询即可拿到 App 当前账号。
  Future<void> _openQqMusic() async {
    final url = _qr?.url ?? '';
    if (url.isEmpty) return;
    final target = Uri.parse(
      'qqmusic://qq.com/ui/openUrl?p=${Uri.encodeComponent(jsonEncode({'url': url}))}',
    );
    if (!await _launch(target, 'com.tencent.qqmusic') && mounted) {
      showToast(context, AppLocalizations.of(context).qrQqMusicNotInstalled);
    }
  }

  /// 安卓上必须指定包名打开，见 MainActivity。
  Future<bool> _launch(Uri target, String package) async {
    try {
      return defaultTargetPlatform == TargetPlatform.android
          ? await _appLogin.invokeMethod<bool>('open', {
                  'url': target.toString(),
                  'package': package,
                }) ??
                false
          : await launchUrl(target, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveImage() async {
    final qr = _qr;
    if (qr == null) return;
    final l = AppLocalizations.of(context);
    try {
      await Gal.putImageBytes(
        qr.image,
        name: 'kanade_login_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) showToast(context, l.qrSavedQq, kind: ToastKind.success);
    } catch (e) {
      if (mounted) {
        showToast(context, l.qrSaveFailed('$e'), kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final ready = _qr != null && !_expired;
    final muted = TextStyle(
      fontSize: 13.5,
      height: 1.5,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return KanadeDialog(
      title: switch (widget.kind) {
        LoginKind.qq => l.loginQq,
        LoginKind.wechat => l.loginWechat,
        LoginKind.qqMusic => l.loginQqMusic,
      },
      content: Column(
        children: [
          // 白底圆角卡片，深色模式下二维码也好扫
          Container(
            width: 220,
            height: 220,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: _qr == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.black54),
                  )
                : Opacity(
                    opacity: _expired ? 0.15 : 1,
                    child: Image.memory(
                      _qr!.image,
                      filterQuality: FilterQuality.none,
                      fit: BoxFit.contain,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Text(_status(l), textAlign: TextAlign.center, style: muted),
          // 微信拒绝识别相册里的登录码，本机没有办法完成
          if (mobile && ready && widget.kind == LoginKind.wechat) ...[
            const SizedBox(height: 8),
            Text(
              l.qrWechatSameDeviceTip,
              textAlign: TextAlign.center,
              style: muted.copyWith(fontSize: 12.5),
            ),
          ],
        ],
      ),
      actions: [
        if (_expired)
          KanadeDialogAction(
            label: l.qrRefresh,
            primary: true,
            icon: Icons.refresh_rounded,
            onPressed: _login.refresh,
          ),
        if (mobile && ready && widget.kind == LoginKind.qq) ...[
          KanadeDialogAction(
            label: l.qrOpenQq,
            primary: true,
            icon: Icons.open_in_new_rounded,
            onPressed: _openQq,
          ),
          KanadeDialogAction(
            label: l.qrSaveImage,
            icon: Icons.save_alt_rounded,
            onPressed: _saveImage,
          ),
        ],
        if (mobile && ready && widget.kind == LoginKind.qqMusic)
          KanadeDialogAction(
            label: l.qrOpenQqMusic,
            primary: true,
            icon: Icons.open_in_new_rounded,
            onPressed: _openQqMusic,
          ),
        KanadeDialogAction(
          label: l.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class CookieLoginDialog extends StatefulWidget {
  const CookieLoginDialog({super.key});

  @override
  State<CookieLoginDialog> createState() => _CookieLoginDialogState();
}

class _CookieLoginDialogState extends State<CookieLoginDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthController>().loginWithCookie(_controller.text);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return KanadeDialog(
      icon: Icons.cookie_outlined,
      title: l.cookieLoginTitle,
      message: l.cookieLoginHint,
      content: TextField(
        controller: _controller,
        maxLines: 4,
        style: const TextStyle(fontSize: 13),
        decoration: kanadeFieldDecoration(
          context,
          error: _error == null ? null : errorText(l, _error!),
        ),
      ),
      actions: [
        KanadeDialogAction(
          label: l.login,
          primary: true,
          onPressed: _busy ? null : _submit,
        ),
        KanadeDialogAction(
          label: l.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
