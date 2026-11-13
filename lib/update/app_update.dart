import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';

/// 软件更新的偏好和安装。版本清单、下载、校验在 Rust 侧（`rust/src/update.rs`）。
abstract final class AppUpdate {
  static const releasesUrl = 'https://github.com/LuckyLxi/kanade/releases';
  static const _channel = MethodChannel('kanade/update');

  static Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  static bool get preview => api.getPref(key: 'update_preview') == '1';
  static set preview(bool on) =>
      api.setPref(key: 'update_preview', value: on ? '1' : '0');

  /// 打开后版本清单和安装包都从镜像取，不连 GitHub。
  static bool get mirror => api.getPref(key: 'update_mirror') == '1';
  static set mirror(bool on) =>
      api.setPref(key: 'update_mirror', value: on ? '1' : '0');

  /// 选了「跳过这个版本」的 tag，启动时不再提醒它。
  static String? get skipped => api.getPref(key: 'update_skip');
  static void skip(String tag) => api.setPref(key: 'update_skip', value: tag);

  /// 比当前版本新时返回清单，否则 null。
  static Future<(UpdateInfo, String)?> check() async {
    final current = await currentVersion();
    final info = await api.getLatestUpdate(preview: preview, mirror: mirror);
    if (compareVersions(info.tag, current) <= 0) return null;
    return (info, current);
  }

  /// 当前平台能用的安装文件，Windows 上安装包在前。
  static List<UpdateAsset> assetsFor(UpdateInfo info) {
    final suffixes = Platform.isWindows
        ? ['-windows-x64-setup.exe', '-windows-x64.zip']
        : ['-android-arm64-v8a.apk'];
    return [
      for (final s in suffixes) ...info.assets.where((a) => a.name.endsWith(s)),
    ];
  }

  /// 下载到的位置。Android 必须在缓存目录的 update/ 下，FileProvider 只开放了这里。
  static Future<String> downloadPath(UpdateAsset asset) async {
    final dir = Platform.isAndroid
        ? (await getTemporaryDirectory()).path
        : Directory.systemTemp.path;
    return '$dir${Platform.pathSeparator}${Platform.isAndroid ? 'update' : 'kanade-update'}'
        '${Platform.pathSeparator}${asset.name}';
  }

  /// 压缩包更新要替换程序目录里的文件，装在 Program Files 这类目录下时没有权限。
  static bool canReplaceFiles() {
    final probe = File(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}.kanade-update-probe',
    );
    try {
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// 打开安装：Android 调起系统安装器；Windows 启动安装程序或替换脚本后退出 App。
  /// 返回 false 表示没能打开。
  static Future<bool> install(String path) async {
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<bool>('install', {'path': path}) ??
          false;
    }
    try {
      if (path.endsWith('.zip')) {
        await _replaceFromZip(path);
      } else {
        // 按原来的安装方式装：装在用户目录下的不需要管理员权限
        final local = Platform.environment['LOCALAPPDATA'];
        final perUser =
            local != null &&
            Platform.resolvedExecutable.toLowerCase().startsWith(
              local.toLowerCase(),
            );
        await Process.start(path, [
          '/SILENT',
          '/SP-',
          '/NOCANCEL',
          perUser ? '/CURRENTUSER' : '/ALLUSERS',
        ], mode: ProcessStartMode.detached);
      }
    } on ProcessException {
      return false;
    }
    exit(0);
  }

  /// 后台脚本等 App 退出后把压缩包里的文件覆盖到程序目录，再重新打开。
  /// 进程退出后文件可能还被占用一会儿，复制失败会重试。脚本里不写中文：
  /// Windows PowerShell 5.1 按系统编码读没有 BOM 的脚本。
  static Future<void> _replaceFromZip(String zip) async {
    final exe = File(Platform.resolvedExecutable);
    final script = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}kanade-update.ps1',
    );
    await script.writeAsString(_replaceScript);
    await Process.start('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
      '-ProcessId',
      '$pid',
      '-Zip',
      zip,
      '-Dir',
      exe.parent.path,
      '-Exe',
      exe.uri.pathSegments.last,
    ], mode: ProcessStartMode.detached);
  }
}

const _replaceScript = r'''
param([int]$ProcessId, [string]$Zip, [string]$Dir, [string]$Exe)
$ErrorActionPreference = 'Stop'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('kanade-update-' + [guid]::NewGuid())
Expand-Archive -LiteralPath $Zip -DestinationPath $tmp -Force
try { Wait-Process -Id $ProcessId -Timeout 30 } catch {}
for ($i = 0; $i -lt 20; $i++) {
  try { Copy-Item -Path (Join-Path $tmp '*') -Destination $Dir -Recurse -Force; break }
  catch { Start-Sleep -Milliseconds 500 }
}
Remove-Item -LiteralPath $tmp, $Zip -Recurse -Force -ErrorAction SilentlyContinue
Start-Process -FilePath (Join-Path $Dir $Exe)
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
''';

/// 比较 `v1.2.3-beta.1` 这样的版本号（前面的 v 可有可无，+ 后面的构建号忽略）。
/// 正式版比同号的预览版新。
int compareVersions(String a, String b) {
  (List<int>, List<String>) parse(String v) {
    v = v.trim().replaceFirst(RegExp('^[vV]'), '').split('+').first;
    final dash = v.indexOf('-');
    final core = dash < 0 ? v : v.substring(0, dash);
    final pre = dash < 0 ? <String>[] : v.substring(dash + 1).split('.');
    return ([for (final p in core.split('.')) int.tryParse(p) ?? 0], pre);
  }

  final (ca, pa) = parse(a);
  final (cb, pb) = parse(b);
  for (var i = 0; i < 3; i++) {
    final x = i < ca.length ? ca[i] : 0;
    final y = i < cb.length ? cb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  if (pa.isEmpty || pb.isEmpty) return pb.length.compareTo(pa.length).sign;
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = int.tryParse(pa[i]);
    final y = int.tryParse(pb[i]);
    final c = x != null && y != null
        ? x.compareTo(y)
        : x != null
        ? -1
        : y != null
        ? 1
        : pa[i].compareTo(pb[i]);
    if (c != 0) return c.sign;
  }
  return pa.length.compareTo(pb.length);
}
