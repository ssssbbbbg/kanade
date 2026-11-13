import 'package:intl/intl.dart';

import '../player/player_error.dart';
import '../src/rust/api/error.dart';
import '../src/rust/api/types.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// Rust 返回的错误码 → 当前语言的文案。
String errorText(AppLocalizations l, Object e) => switch (e) {
  ApiError_NotLoggedIn() => l.errorNotLoggedIn,
  ApiError_NoPlayableUrl() => l.errorNoPlayableUrl,
  ApiError_UnsupportedFormat() => l.reasonUnsupported,
  ApiError_UnverifiedFormat() => l.reasonUnverified,
  ApiError_LoginFailed(:final detail) => l.errorLoginFailed(detail),
  ApiError_InvalidCookie(:final missing) => l.errorInvalidCookie(missing),
  ApiError_ServerError(:final api, :final code) => l.errorServer(code, api),
  ApiError_BadResponse(:final detail) => l.errorBadResponse(detail),
  ApiError_Network(:final detail) => l.errorNetwork(detail),
  ApiError_Internal(:final detail) => l.errorInternal(detail),
  _ => e.toString().split('\n').first,
};

String playerErrorText(AppLocalizations l, PlayerError e) => switch (e) {
  PlaybackFailed(:final song, :final cause) => l.songUnplayable(
    song.name,
    errorText(l, cause),
  ),
  StreamFailed(:final message) => l.playbackError(message),
};

String qualityLabel(AppLocalizations l, Quality q) => switch (q) {
  Quality.low => l.qualityLow,
  Quality.standard => l.qualityStandard,
  Quality.high => l.qualityHigh,
  Quality.lossless => l.qualityLossless,
  Quality.master => l.qualityMaster,
  Quality.hires => 'Hi-Res',
  Quality.atmos => l.qualityAtmos,
  Quality.atmos51 => l.qualityAtmos51,
  Quality.atmos71 => l.qualityAtmos71,
  Quality.dolby => l.qualityDolby,
  Quality.dts => 'DTS:X',
  Quality.ra360 => '360 Reality Audio',
  Quality.ogg640 => 'OGG 640k',
  Quality.ogg320 => l.qualityOgg320,
  Quality.ogg192 => 'OGG 192k',
  Quality.ogg96 => 'OGG 96k',
  Quality.aac192 => 'AAC 192k',
  Quality.aac48 => 'AAC 48k',
  Quality.aicodec => l.qualityAiCodec,
};

String qualityReasonText(AppLocalizations l, QualityUnavailableReason r) =>
    switch (r) {
      QualityUnavailableReason.unsupported => l.reasonUnsupported,
      QualityUnavailableReason.unverified => l.reasonUnverified,
      QualityUnavailableReason.noPermission => l.reasonNoPermission,
      QualityUnavailableReason.deviceRestricted => l.reasonDeviceRestricted,
      QualityUnavailableReason.noLink => l.reasonNoLink,
      QualityUnavailableReason.verifyFailed => l.reasonVerifyFailed,
      QualityUnavailableReason.fileUnavailable => l.reasonFileUnavailable,
    };

/// 播放量：中文用 万 / 亿，其它语言用 intl 的紧凑格式（1.2M）。
String formatCount(AppLocalizations l, int n) {
  if (l.localeName != 'zh') {
    return NumberFormat.compact(locale: l.localeName).format(n);
  }
  return n >= 100000000
      ? '${(n / 100000000).toStringAsFixed(1)}亿'
      : n >= 10000
      ? '${(n / 10000).toStringAsFixed(1)}万'
      : '$n';
}
