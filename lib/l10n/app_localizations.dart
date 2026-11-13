import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'Kanade'**
  String get appTitle;

  /// No description provided for @tabDiscover.
  ///
  /// In zh, this message translates to:
  /// **'发现'**
  String get tabDiscover;

  /// No description provided for @tabSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get tabSearch;

  /// No description provided for @tabMine.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get tabMine;

  /// No description provided for @windowMinimize.
  ///
  /// In zh, this message translates to:
  /// **'最小化'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In zh, this message translates to:
  /// **'最大化'**
  String get windowMaximize;

  /// No description provided for @windowRestore.
  ///
  /// In zh, this message translates to:
  /// **'向下还原'**
  String get windowRestore;

  /// No description provided for @windowClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get windowClose;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @themeToDark.
  ///
  /// In zh, this message translates to:
  /// **'切换到深色'**
  String get themeToDark;

  /// No description provided for @themeToLight.
  ///
  /// In zh, this message translates to:
  /// **'切换到浅色'**
  String get themeToLight;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'加载中'**
  String get loading;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @loadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败：{error}'**
  String loadFailed(String error);

  /// No description provided for @recommendedPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'推荐歌单'**
  String get recommendedPlaylists;

  /// No description provided for @recommendedSongs.
  ///
  /// In zh, this message translates to:
  /// **'为你推荐'**
  String get recommendedSongs;

  /// No description provided for @discoverRecommend.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get discoverRecommend;

  /// No description provided for @discoverToplists.
  ///
  /// In zh, this message translates to:
  /// **'排行榜'**
  String get discoverToplists;

  /// No description provided for @radioGuessYouLike.
  ///
  /// In zh, this message translates to:
  /// **'猜你喜欢'**
  String get radioGuessYouLike;

  /// No description provided for @radioRadar.
  ///
  /// In zh, this message translates to:
  /// **'刷歌模式'**
  String get radioRadar;

  /// No description provided for @radioFailed.
  ///
  /// In zh, this message translates to:
  /// **'电台没取到歌：{error}'**
  String radioFailed(String error);

  /// No description provided for @feedColumnTitle.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」的专属乐流'**
  String feedColumnTitle(String name);

  /// No description provided for @viewAllSongs.
  ///
  /// In zh, this message translates to:
  /// **'查看全部 {count} 首'**
  String viewAllSongs(int count);

  /// 榜单期数
  ///
  /// In zh, this message translates to:
  /// **'更新于 {period}'**
  String updatedAt(String period);

  /// No description provided for @playAll.
  ///
  /// In zh, this message translates to:
  /// **'播放全部 ({count})'**
  String playAll(int count);

  /// No description provided for @songCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 首'**
  String songCount(int count);

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索歌曲、歌手、专辑、视频'**
  String get searchHint;

  /// No description provided for @recognizeSong.
  ///
  /// In zh, this message translates to:
  /// **'听歌识曲'**
  String get recognizeSong;

  /// No description provided for @recognizeListening.
  ///
  /// In zh, this message translates to:
  /// **'正在听…'**
  String get recognizeListening;

  /// No description provided for @recognizeHint.
  ///
  /// In zh, this message translates to:
  /// **'让麦克风靠近正在播放的音乐'**
  String get recognizeHint;

  /// No description provided for @recognizeElapsed.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒'**
  String recognizeElapsed(int seconds);

  /// No description provided for @recognizeNotFound.
  ///
  /// In zh, this message translates to:
  /// **'没听出来是哪首歌'**
  String get recognizeNotFound;

  /// No description provided for @recognizeAgain.
  ///
  /// In zh, this message translates to:
  /// **'再识别一次'**
  String get recognizeAgain;

  /// No description provided for @recognizeNoMic.
  ///
  /// In zh, this message translates to:
  /// **'没有麦克风权限'**
  String get recognizeNoMic;

  /// No description provided for @recognizeBubble.
  ///
  /// In zh, this message translates to:
  /// **'开启悬浮按钮'**
  String get recognizeBubble;

  /// No description provided for @recognizeBubbleHint.
  ///
  /// In zh, this message translates to:
  /// **'切到别的软件也能接着识曲'**
  String get recognizeBubbleHint;

  /// No description provided for @searchPrompt.
  ///
  /// In zh, this message translates to:
  /// **'输入关键词后回车搜索'**
  String get searchPrompt;

  /// No description provided for @searchHot.
  ///
  /// In zh, this message translates to:
  /// **'热搜榜'**
  String get searchHot;

  /// No description provided for @searchRecommended.
  ///
  /// In zh, this message translates to:
  /// **'猜你想搜'**
  String get searchRecommended;

  /// No description provided for @filterSongsHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索歌名、歌手'**
  String get filterSongsHint;

  /// No description provided for @locateCurrentSong.
  ///
  /// In zh, this message translates to:
  /// **'定位到正在播放'**
  String get locateCurrentSong;

  /// No description provided for @searchNoResults.
  ///
  /// In zh, this message translates to:
  /// **'没有找到相关结果'**
  String get searchNoResults;

  /// No description provided for @searchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败：{error}'**
  String searchFailed(String error);

  /// No description provided for @searchTotal.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 首'**
  String searchTotal(int count);

  /// No description provided for @quality.
  ///
  /// In zh, this message translates to:
  /// **'音质'**
  String get quality;

  /// No description provided for @qualityLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在获取音质'**
  String get qualityLoading;

  /// No description provided for @qualityFailed.
  ///
  /// In zh, this message translates to:
  /// **'音质获取失败：{error}'**
  String qualityFailed(String error);

  /// No description provided for @qualityFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'音质获取失败，点击重试'**
  String get qualityFailedRetry;

  /// No description provided for @qualityNoneForSong.
  ///
  /// In zh, this message translates to:
  /// **'歌曲暂无可用音质'**
  String get qualityNoneForSong;

  /// No description provided for @qualityNone.
  ///
  /// In zh, this message translates to:
  /// **'暂无可用音质'**
  String get qualityNone;

  /// No description provided for @qualityWithReason.
  ///
  /// In zh, this message translates to:
  /// **'{quality}（{reason}）'**
  String qualityWithReason(String quality, String reason);

  /// No description provided for @qualityLow.
  ///
  /// In zh, this message translates to:
  /// **'流畅 96k'**
  String get qualityLow;

  /// No description provided for @qualityStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准 128k'**
  String get qualityStandard;

  /// No description provided for @qualityHigh.
  ///
  /// In zh, this message translates to:
  /// **'高品质 320k'**
  String get qualityHigh;

  /// No description provided for @qualityLossless.
  ///
  /// In zh, this message translates to:
  /// **'无损 FLAC'**
  String get qualityLossless;

  /// No description provided for @qualityMaster.
  ///
  /// In zh, this message translates to:
  /// **'臻品母带'**
  String get qualityMaster;

  /// No description provided for @qualityAtmos.
  ///
  /// In zh, this message translates to:
  /// **'臻品音质'**
  String get qualityAtmos;

  /// No description provided for @qualityAtmos51.
  ///
  /// In zh, this message translates to:
  /// **'臻品全景声 5.1'**
  String get qualityAtmos51;

  /// No description provided for @qualityAtmos71.
  ///
  /// In zh, this message translates to:
  /// **'臻品全景声 7.1'**
  String get qualityAtmos71;

  /// No description provided for @qualityDolby.
  ///
  /// In zh, this message translates to:
  /// **'杜比全景声'**
  String get qualityDolby;

  /// No description provided for @qualityOgg320.
  ///
  /// In zh, this message translates to:
  /// **'高品质 OGG 320k'**
  String get qualityOgg320;

  /// No description provided for @qualityAiCodec.
  ///
  /// In zh, this message translates to:
  /// **'AI 音质'**
  String get qualityAiCodec;

  /// No description provided for @reasonUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'播放器暂不支持此格式'**
  String get reasonUnsupported;

  /// No description provided for @reasonUnverified.
  ///
  /// In zh, this message translates to:
  /// **'暂未通过播放验证'**
  String get reasonUnverified;

  /// No description provided for @reasonNoPermission.
  ///
  /// In zh, this message translates to:
  /// **'当前账号无权限'**
  String get reasonNoPermission;

  /// No description provided for @reasonDeviceRestricted.
  ///
  /// In zh, this message translates to:
  /// **'播放设备受限'**
  String get reasonDeviceRestricted;

  /// No description provided for @reasonNoLink.
  ///
  /// In zh, this message translates to:
  /// **'暂无可用链接'**
  String get reasonNoLink;

  /// No description provided for @reasonVerifyFailed.
  ///
  /// In zh, this message translates to:
  /// **'音质验证失败，请稍后重试'**
  String get reasonVerifyFailed;

  /// No description provided for @reasonFileUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'音频文件暂不可用'**
  String get reasonFileUnavailable;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logout;

  /// No description provided for @notLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get notLoggedIn;

  /// No description provided for @loginMethods.
  ///
  /// In zh, this message translates to:
  /// **'选择登录方式'**
  String get loginMethods;

  /// No description provided for @loginQqHint.
  ///
  /// In zh, this message translates to:
  /// **'用手机 QQ 扫一扫'**
  String get loginQqHint;

  /// No description provided for @loginWechatHint.
  ///
  /// In zh, this message translates to:
  /// **'用微信扫一扫'**
  String get loginWechatHint;

  /// No description provided for @loginQqMusicHint.
  ///
  /// In zh, this message translates to:
  /// **'在 QQ 音乐 App 里确认'**
  String get loginQqMusicHint;

  /// No description provided for @loginPrompt.
  ///
  /// In zh, this message translates to:
  /// **'登录后可以同步你的歌单，并播放账号有权限的歌曲'**
  String get loginPrompt;

  /// No description provided for @loginQq.
  ///
  /// In zh, this message translates to:
  /// **'QQ 扫码登录'**
  String get loginQq;

  /// No description provided for @loginWechat.
  ///
  /// In zh, this message translates to:
  /// **'微信扫码登录'**
  String get loginWechat;

  /// No description provided for @loginQqMusic.
  ///
  /// In zh, this message translates to:
  /// **'QQ 音乐授权登录'**
  String get loginQqMusic;

  /// No description provided for @loginCookie.
  ///
  /// In zh, this message translates to:
  /// **'使用 Cookie 登录'**
  String get loginCookie;

  /// No description provided for @noPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'还没有歌单'**
  String get noPlaylists;

  /// No description provided for @qrLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在获取二维码…'**
  String get qrLoading;

  /// No description provided for @qrScanHintQq.
  ///
  /// In zh, this message translates to:
  /// **'请使用手机 QQ 扫码'**
  String get qrScanHintQq;

  /// No description provided for @qrScanHintWechat.
  ///
  /// In zh, this message translates to:
  /// **'请使用手机微信扫码'**
  String get qrScanHintWechat;

  /// No description provided for @qrScanHintQqMusic.
  ///
  /// In zh, this message translates to:
  /// **'请使用 QQ 音乐 App 扫码，将登录 App 当前的账号'**
  String get qrScanHintQqMusic;

  /// No description provided for @qrScanned.
  ///
  /// In zh, this message translates to:
  /// **'已扫码，请在手机上确认'**
  String get qrScanned;

  /// No description provided for @qrExpired.
  ///
  /// In zh, this message translates to:
  /// **'二维码已过期'**
  String get qrExpired;

  /// No description provided for @qrRefused.
  ///
  /// In zh, this message translates to:
  /// **'已在手机上取消登录'**
  String get qrRefused;

  /// No description provided for @qrRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新二维码'**
  String get qrRefresh;

  /// No description provided for @qrOpenQq.
  ///
  /// In zh, this message translates to:
  /// **'跳转 QQ 登录'**
  String get qrOpenQq;

  /// No description provided for @qrQqNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'无法打开 QQ，请确认已安装手机 QQ'**
  String get qrQqNotInstalled;

  /// No description provided for @qrSaveImage.
  ///
  /// In zh, this message translates to:
  /// **'保存二维码'**
  String get qrSaveImage;

  /// No description provided for @qrSavedQq.
  ///
  /// In zh, this message translates to:
  /// **'已保存到相册，在 QQ「扫一扫」右上角选择相册图片即可'**
  String get qrSavedQq;

  /// No description provided for @qrOpenQqMusic.
  ///
  /// In zh, this message translates to:
  /// **'跳转 QQ 音乐授权'**
  String get qrOpenQqMusic;

  /// No description provided for @qrQqMusicNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'无法打开 QQ 音乐，请确认已安装 QQ 音乐 App'**
  String get qrQqMusicNotInstalled;

  /// No description provided for @qrWechatSameDeviceTip.
  ///
  /// In zh, this message translates to:
  /// **'微信不支持本机登录。如果 QQ 音乐 App 登的是微信号，可以改用「QQ 音乐授权登录」'**
  String get qrWechatSameDeviceTip;

  /// No description provided for @qrSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String qrSaveFailed(String error);

  /// No description provided for @qrFailed.
  ///
  /// In zh, this message translates to:
  /// **'获取二维码失败：{error}'**
  String qrFailed(String error);

  /// No description provided for @cookieLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'Cookie 登录'**
  String get cookieLoginTitle;

  /// No description provided for @cookieLoginHint.
  ///
  /// In zh, this message translates to:
  /// **'在浏览器登录 y.qq.com 后，从开发者工具复制 Cookie 粘贴到这里（需要包含 uin 和 qm_keyst）。'**
  String get cookieLoginHint;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @swipeForLyrics.
  ///
  /// In zh, this message translates to:
  /// **'← 左滑查看歌词'**
  String get swipeForLyrics;

  /// No description provided for @noLyrics.
  ///
  /// In zh, this message translates to:
  /// **'暂无歌词'**
  String get noLyrics;

  /// No description provided for @modeSequence.
  ///
  /// In zh, this message translates to:
  /// **'列表循环'**
  String get modeSequence;

  /// No description provided for @modeRepeatOne.
  ///
  /// In zh, this message translates to:
  /// **'单曲循环'**
  String get modeRepeatOne;

  /// No description provided for @modeShuffle.
  ///
  /// In zh, this message translates to:
  /// **'随机播放'**
  String get modeShuffle;

  /// No description provided for @lyrics.
  ///
  /// In zh, this message translates to:
  /// **'歌词'**
  String get lyrics;

  /// No description provided for @upNext.
  ///
  /// In zh, this message translates to:
  /// **'接下来播放'**
  String get upNext;

  /// No description provided for @playNext.
  ///
  /// In zh, this message translates to:
  /// **'下一首播放'**
  String get playNext;

  /// No description provided for @queuedNext.
  ///
  /// In zh, this message translates to:
  /// **'已添加到下一首播放'**
  String get queuedNext;

  /// No description provided for @alreadyPlaying.
  ///
  /// In zh, this message translates to:
  /// **'正在播放这首歌'**
  String get alreadyPlaying;

  /// No description provided for @volume.
  ///
  /// In zh, this message translates to:
  /// **'音量'**
  String get volume;

  /// No description provided for @queue.
  ///
  /// In zh, this message translates to:
  /// **'播放队列'**
  String get queue;

  /// No description provided for @removeFromQueue.
  ///
  /// In zh, this message translates to:
  /// **'从队列移除'**
  String get removeFromQueue;

  /// No description provided for @reorderQueue.
  ///
  /// In zh, this message translates to:
  /// **'拖动调整顺序'**
  String get reorderQueue;

  /// No description provided for @playbackError.
  ///
  /// In zh, this message translates to:
  /// **'播放出错：{error}'**
  String playbackError(String error);

  /// No description provided for @songUnplayable.
  ///
  /// In zh, this message translates to:
  /// **'《{song}》无法播放：{error}'**
  String songUnplayable(String song, String error);

  /// No description provided for @errorNotLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'尚未登录'**
  String get errorNotLoggedIn;

  /// No description provided for @errorNoPlayableUrl.
  ///
  /// In zh, this message translates to:
  /// **'没有可用的播放链接（可能需要登录或会员）'**
  String get errorNoPlayableUrl;

  /// No description provided for @errorLoginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败：{detail}'**
  String errorLoginFailed(String detail);

  /// No description provided for @errorInvalidCookie.
  ///
  /// In zh, this message translates to:
  /// **'Cookie 里没有 {field}'**
  String errorInvalidCookie(String field);

  /// No description provided for @errorServer.
  ///
  /// In zh, this message translates to:
  /// **'服务器返回错误码 {code}（{api}）'**
  String errorServer(String code, String api);

  /// No description provided for @errorBadResponse.
  ///
  /// In zh, this message translates to:
  /// **'服务器响应异常：{detail}'**
  String errorBadResponse(String detail);

  /// No description provided for @errorNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络错误：{detail}'**
  String errorNetwork(String detail);

  /// No description provided for @errorInternal.
  ///
  /// In zh, this message translates to:
  /// **'内部错误：{detail}'**
  String errorInternal(String detail);

  /// No description provided for @previousSong.
  ///
  /// In zh, this message translates to:
  /// **'上一首'**
  String get previousSong;

  /// No description provided for @nextSong.
  ///
  /// In zh, this message translates to:
  /// **'下一首'**
  String get nextSong;

  /// No description provided for @play.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get pause;

  /// No description provided for @like.
  ///
  /// In zh, this message translates to:
  /// **'收藏到我喜欢'**
  String get like;

  /// No description provided for @unlike.
  ///
  /// In zh, this message translates to:
  /// **'取消喜欢'**
  String get unlike;

  /// No description provided for @likeShort.
  ///
  /// In zh, this message translates to:
  /// **'喜欢'**
  String get likeShort;

  /// No description provided for @likedShort.
  ///
  /// In zh, this message translates to:
  /// **'已喜欢'**
  String get likedShort;

  /// No description provided for @liked.
  ///
  /// In zh, this message translates to:
  /// **'已添加到我喜欢'**
  String get liked;

  /// No description provided for @unliked.
  ///
  /// In zh, this message translates to:
  /// **'已取消喜欢'**
  String get unliked;

  /// No description provided for @addToPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'加入歌单'**
  String get addToPlaylist;

  /// No description provided for @addedToPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'已加入「{name}」'**
  String addedToPlaylist(String name);

  /// No description provided for @removeFromPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'从歌单中删除'**
  String get removeFromPlaylist;

  /// No description provided for @removedFromPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'已从「{name}」删除'**
  String removedFromPlaylist(String name);

  /// No description provided for @actionFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{error}'**
  String actionFailed(String error);

  /// No description provided for @loginRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先在「我的」页登录'**
  String get loginRequired;

  /// No description provided for @noMyPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'没有可加入的歌单'**
  String get noMyPlaylists;

  /// No description provided for @more.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @singerNamed.
  ///
  /// In zh, this message translates to:
  /// **'歌手：{name}'**
  String singerNamed(String name);

  /// No description provided for @albumNamed.
  ///
  /// In zh, this message translates to:
  /// **'专辑：{name}'**
  String albumNamed(String name);

  /// No description provided for @comments.
  ///
  /// In zh, this message translates to:
  /// **'评论'**
  String get comments;

  /// No description provided for @commentsRecommended.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get commentsRecommended;

  /// No description provided for @noComments.
  ///
  /// In zh, this message translates to:
  /// **'还没有评论'**
  String get noComments;

  /// No description provided for @commentCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条评论'**
  String commentCount(String count);

  /// No description provided for @timeJustNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 分钟前'**
  String timeMinutesAgo(int count);

  /// No description provided for @timeHoursAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 小时前'**
  String timeHoursAgo(int count);

  /// No description provided for @timeDaysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 天前'**
  String timeDaysAgo(int count);

  /// No description provided for @replies.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get replies;

  /// No description provided for @replyCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条回复'**
  String replyCount(int count);

  /// No description provided for @replyTo.
  ///
  /// In zh, this message translates to:
  /// **'回复 {name}：'**
  String replyTo(String name);

  /// No description provided for @loadMore.
  ///
  /// In zh, this message translates to:
  /// **'加载更多'**
  String get loadMore;

  /// No description provided for @tabSongs.
  ///
  /// In zh, this message translates to:
  /// **'歌曲'**
  String get tabSongs;

  /// No description provided for @tabAlbums.
  ///
  /// In zh, this message translates to:
  /// **'专辑'**
  String get tabAlbums;

  /// No description provided for @publishedOn.
  ///
  /// In zh, this message translates to:
  /// **'发行于 {date}'**
  String publishedOn(String date);

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @settingsPlayback.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get settingsPlayback;

  /// No description provided for @settingsAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearance;

  /// No description provided for @settingsStorage.
  ///
  /// In zh, this message translates to:
  /// **'存储'**
  String get settingsStorage;

  /// No description provided for @settingsAccount.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get settingsAccount;

  /// No description provided for @theme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @audioCacheOfLimit.
  ///
  /// In zh, this message translates to:
  /// **'/ 上限 {limit}'**
  String audioCacheOfLimit(Object limit);

  /// No description provided for @audioCacheDisabled.
  ///
  /// In zh, this message translates to:
  /// **'缓存已关闭'**
  String get audioCacheDisabled;

  /// No description provided for @foryouSettings.
  ///
  /// In zh, this message translates to:
  /// **'自定义推荐页'**
  String get foryouSettings;

  /// No description provided for @foryouSettingsHint.
  ///
  /// In zh, this message translates to:
  /// **'首页最上面那排卡片显示哪些，和手机版 QQ 音乐同步'**
  String get foryouSettingsHint;

  /// No description provided for @foryouChoose.
  ///
  /// In zh, this message translates to:
  /// **'可选择显示/隐藏以下内容'**
  String get foryouChoose;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @foryouSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get foryouSaved;

  /// No description provided for @foryouSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String foryouSaveFailed(Object error);

  /// No description provided for @defaultQuality.
  ///
  /// In zh, this message translates to:
  /// **'默认音质'**
  String get defaultQuality;

  /// No description provided for @defaultQualityHint.
  ///
  /// In zh, this message translates to:
  /// **'选的音质没有或播不了时会自动降低'**
  String get defaultQualityHint;

  /// No description provided for @songFade.
  ///
  /// In zh, this message translates to:
  /// **'播放过渡'**
  String get songFade;

  /// No description provided for @songFadeHint.
  ///
  /// In zh, this message translates to:
  /// **'切歌、暂停和继续播放时音量渐变'**
  String get songFadeHint;

  /// No description provided for @songFadeOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get songFadeOff;

  /// No description provided for @songFadeSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒'**
  String songFadeSeconds(Object seconds);

  /// No description provided for @audioCacheLimit.
  ///
  /// In zh, this message translates to:
  /// **'歌曲缓存上限'**
  String get audioCacheLimit;

  /// No description provided for @audioCacheLimitHint.
  ///
  /// In zh, this message translates to:
  /// **'边听边存，超出后删除最久没听的歌'**
  String get audioCacheLimitHint;

  /// No description provided for @audioCacheOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get audioCacheOff;

  /// No description provided for @audioCacheCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get audioCacheCustom;

  /// No description provided for @audioCacheCustomTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义缓存上限'**
  String get audioCacheCustomTitle;

  /// No description provided for @audioCacheCustomUnit.
  ///
  /// In zh, this message translates to:
  /// **'MB'**
  String get audioCacheCustomUnit;

  /// No description provided for @audioCacheSize.
  ///
  /// In zh, this message translates to:
  /// **'歌曲缓存'**
  String get audioCacheSize;

  /// No description provided for @apiCacheSize.
  ///
  /// In zh, this message translates to:
  /// **'其他缓存'**
  String get apiCacheSize;

  /// No description provided for @apiCacheSizeHint.
  ///
  /// In zh, this message translates to:
  /// **'歌单、搜索、歌词等数据'**
  String get apiCacheSizeHint;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get clear;

  /// No description provided for @clearAudioCacheConfirm.
  ///
  /// In zh, this message translates to:
  /// **'清除所有已缓存的歌曲？'**
  String get clearAudioCacheConfirm;

  /// No description provided for @clearApiCacheConfirm.
  ///
  /// In zh, this message translates to:
  /// **'清除歌单、搜索、歌词等缓存数据？'**
  String get clearApiCacheConfirm;

  /// No description provided for @cacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除'**
  String get cacheCleared;

  /// No description provided for @logoutConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定退出登录？'**
  String get logoutConfirm;

  /// No description provided for @sessionEndedTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录已失效'**
  String get sessionEndedTitle;

  /// No description provided for @sessionExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录已超过有效期，已自动退出。重新登录后就能继续同步歌单和播放会员歌曲。'**
  String get sessionExpired;

  /// No description provided for @sessionRevoked.
  ///
  /// In zh, this message translates to:
  /// **'登录还没到期就被 QQ 音乐注销了，已自动退出。'**
  String get sessionRevoked;

  /// No description provided for @sessionRejected.
  ///
  /// In zh, this message translates to:
  /// **'QQ 音乐不再接受当前的登录，已自动退出。'**
  String get sessionRejected;

  /// No description provided for @sessionCausesTitle.
  ///
  /// In zh, this message translates to:
  /// **'可能的原因'**
  String get sessionCausesTitle;

  /// No description provided for @sessionCauseOtherDevice.
  ///
  /// In zh, this message translates to:
  /// **'账号在其他设备登录，这里被挤下线'**
  String get sessionCauseOtherDevice;

  /// No description provided for @sessionCauseDeviceRemoved.
  ///
  /// In zh, this message translates to:
  /// **'在「登录设备管理」里删除了这台设备'**
  String get sessionCauseDeviceRemoved;

  /// No description provided for @sessionCausePassword.
  ///
  /// In zh, this message translates to:
  /// **'修改了账号密码'**
  String get sessionCausePassword;

  /// No description provided for @sessionCauseExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录超过了有效期'**
  String get sessionCauseExpired;

  /// No description provided for @loginAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新登录'**
  String get loginAgain;

  /// No description provided for @later.
  ///
  /// In zh, this message translates to:
  /// **'稍后'**
  String get later;

  /// No description provided for @ok.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get ok;

  /// No description provided for @likedSongs.
  ///
  /// In zh, this message translates to:
  /// **'我喜欢'**
  String get likedSongs;

  /// No description provided for @recentPlays.
  ///
  /// In zh, this message translates to:
  /// **'最近播放'**
  String get recentPlays;

  /// No description provided for @myPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'我的歌单'**
  String get myPlaylists;

  /// No description provided for @playlistsCreated.
  ///
  /// In zh, this message translates to:
  /// **'创建的'**
  String get playlistsCreated;

  /// No description provided for @playlistsCollected.
  ///
  /// In zh, this message translates to:
  /// **'收藏的'**
  String get playlistsCollected;

  /// No description provided for @shufflePlay.
  ///
  /// In zh, this message translates to:
  /// **'随机播放'**
  String get shufflePlay;

  /// No description provided for @seeAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get seeAll;

  /// No description provided for @refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get refresh;

  /// No description provided for @renamePlaylist.
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get renamePlaylist;

  /// No description provided for @deletePlaylist.
  ///
  /// In zh, this message translates to:
  /// **'删除歌单'**
  String get deletePlaylist;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @playlistNameHint.
  ///
  /// In zh, this message translates to:
  /// **'歌单名'**
  String get playlistNameHint;

  /// No description provided for @deletePlaylistConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除歌单「{name}」吗？删除后无法恢复。'**
  String deletePlaylistConfirm(String name);

  /// No description provided for @playlistRenamed.
  ///
  /// In zh, this message translates to:
  /// **'已重命名'**
  String get playlistRenamed;

  /// No description provided for @playlistDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除歌单'**
  String get playlistDeleted;

  /// No description provided for @nothingPlaying.
  ///
  /// In zh, this message translates to:
  /// **'还没有在播放的歌'**
  String get nothingPlaying;

  /// No description provided for @searchKindSong.
  ///
  /// In zh, this message translates to:
  /// **'歌曲'**
  String get searchKindSong;

  /// No description provided for @searchKindSinger.
  ///
  /// In zh, this message translates to:
  /// **'歌手'**
  String get searchKindSinger;

  /// No description provided for @searchKindAlbum.
  ///
  /// In zh, this message translates to:
  /// **'专辑'**
  String get searchKindAlbum;

  /// No description provided for @searchKindPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'歌单'**
  String get searchKindPlaylist;

  /// No description provided for @searchKindVideo.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get searchKindVideo;

  /// No description provided for @recentKindRadar.
  ///
  /// In zh, this message translates to:
  /// **'音乐雷达'**
  String get recentKindRadar;

  /// No description provided for @recentKindAudiobook.
  ///
  /// In zh, this message translates to:
  /// **'有声'**
  String get recentKindAudiobook;

  /// No description provided for @searchKindLyric.
  ///
  /// In zh, this message translates to:
  /// **'歌词'**
  String get searchKindLyric;

  /// No description provided for @searchTotalItems.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 个结果'**
  String searchTotalItems(int count);

  /// No description provided for @singerStats.
  ///
  /// In zh, this message translates to:
  /// **'{songs} 首歌 · {albums} 张专辑'**
  String singerStats(int songs, int albums);

  /// No description provided for @searchKindUser.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get searchKindUser;

  /// No description provided for @mvUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'这个视频暂时无法播放'**
  String get mvUnavailable;

  /// No description provided for @watchMv.
  ///
  /// In zh, this message translates to:
  /// **'观看 MV'**
  String get watchMv;

  /// No description provided for @findSimilarSongs.
  ///
  /// In zh, this message translates to:
  /// **'查找相似歌曲'**
  String get findSimilarSongs;

  /// No description provided for @similarSongsTitle.
  ///
  /// In zh, this message translates to:
  /// **'与《{name}》相似的歌曲'**
  String similarSongsTitle(String name);

  /// No description provided for @userFansFollows.
  ///
  /// In zh, this message translates to:
  /// **'粉丝 {fans} · 关注 {follows}'**
  String userFansFollows(String fans, String follows);

  /// No description provided for @userBriefStats.
  ///
  /// In zh, this message translates to:
  /// **'粉丝 {fans} · 歌单 {count}'**
  String userBriefStats(String fans, int count);

  /// No description provided for @userPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'歌单 {count}'**
  String userPlaylists(int count);

  /// No description provided for @userNoPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'没有公开的歌单'**
  String get userNoPlaylists;

  /// No description provided for @userFans.
  ///
  /// In zh, this message translates to:
  /// **'粉丝 {fans}'**
  String userFans(String fans);

  /// No description provided for @singerFeatured.
  ///
  /// In zh, this message translates to:
  /// **'精选'**
  String get singerFeatured;

  /// No description provided for @singerSelectedAlbums.
  ///
  /// In zh, this message translates to:
  /// **'精选专辑'**
  String get singerSelectedAlbums;

  /// No description provided for @follow.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get follow;

  /// No description provided for @followed.
  ///
  /// In zh, this message translates to:
  /// **'已关注'**
  String get followed;

  /// No description provided for @createPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'新建歌单'**
  String get createPlaylist;

  /// No description provided for @create.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get create;

  /// No description provided for @playlistSyncHint.
  ///
  /// In zh, this message translates to:
  /// **'会同步到你的 QQ 音乐账号'**
  String get playlistSyncHint;

  /// No description provided for @playlistCreated.
  ///
  /// In zh, this message translates to:
  /// **'已新建歌单'**
  String get playlistCreated;

  /// No description provided for @savedPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'收藏歌单'**
  String get savedPlaylists;

  /// No description provided for @savedAlbums.
  ///
  /// In zh, this message translates to:
  /// **'收藏专辑'**
  String get savedAlbums;

  /// No description provided for @userPrivate.
  ///
  /// In zh, this message translates to:
  /// **'内容未公开'**
  String get userPrivate;

  /// No description provided for @noItems.
  ///
  /// In zh, this message translates to:
  /// **'暂无内容'**
  String get noItems;

  /// No description provided for @newest.
  ///
  /// In zh, this message translates to:
  /// **'最新'**
  String get newest;

  /// No description provided for @hottest.
  ///
  /// In zh, this message translates to:
  /// **'最热'**
  String get hottest;

  /// No description provided for @userLikes.
  ///
  /// In zh, this message translates to:
  /// **'我喜欢'**
  String get userLikes;

  /// No description provided for @singerAbout.
  ///
  /// In zh, this message translates to:
  /// **'详情'**
  String get singerAbout;

  /// No description provided for @singerBio.
  ///
  /// In zh, this message translates to:
  /// **'简介'**
  String get singerBio;

  /// No description provided for @singerGuard.
  ///
  /// In zh, this message translates to:
  /// **'守护'**
  String get singerGuard;

  /// No description provided for @statFans.
  ///
  /// In zh, this message translates to:
  /// **'粉丝'**
  String get statFans;

  /// No description provided for @statFollows.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get statFollows;

  /// No description provided for @statPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'歌单'**
  String get statPlaylists;

  /// No description provided for @showMore.
  ///
  /// In zh, this message translates to:
  /// **'展开'**
  String get showMore;

  /// No description provided for @showLess.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get showLess;

  /// No description provided for @durationHoursMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时 {minutes} 分'**
  String durationHoursMinutes(int hours, int minutes);

  /// No description provided for @durationMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String durationMinutes(int minutes);

  /// No description provided for @filterFound.
  ///
  /// In zh, this message translates to:
  /// **'找到 {count} 首'**
  String filterFound(int count);

  /// No description provided for @playFiltered.
  ///
  /// In zh, this message translates to:
  /// **'播放这 {count} 首'**
  String playFiltered(int count);

  /// No description provided for @featuredVideos.
  ///
  /// In zh, this message translates to:
  /// **'精选视频'**
  String get featuredVideos;

  /// No description provided for @alsoListening.
  ///
  /// In zh, this message translates to:
  /// **'听「{name}」的也在听'**
  String alsoListening(String name);

  /// No description provided for @relatedPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'相关歌单'**
  String get relatedPlaylists;

  /// No description provided for @anotherBatch.
  ///
  /// In zh, this message translates to:
  /// **'换一批'**
  String get anotherBatch;

  /// No description provided for @sleepTimer.
  ///
  /// In zh, this message translates to:
  /// **'定时关闭'**
  String get sleepTimer;

  /// No description provided for @sleepTimerUntil.
  ///
  /// In zh, this message translates to:
  /// **'{time} 停止播放'**
  String sleepTimerUntil(String time);

  /// No description provided for @sleepTimerWaiting.
  ///
  /// In zh, this message translates to:
  /// **'这首放完后停止'**
  String get sleepTimerWaiting;

  /// No description provided for @sleepTimerWaitingShort.
  ///
  /// In zh, this message translates to:
  /// **'播完停'**
  String get sleepTimerWaitingShort;

  /// No description provided for @sleepTimerCustomHint.
  ///
  /// In zh, this message translates to:
  /// **'自定义时长'**
  String get sleepTimerCustomHint;

  /// No description provided for @sleepTimerMinutes.
  ///
  /// In zh, this message translates to:
  /// **'分钟'**
  String get sleepTimerMinutes;

  /// No description provided for @sleepTimerStart.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get sleepTimerStart;

  /// No description provided for @sleepAfterSong.
  ///
  /// In zh, this message translates to:
  /// **'播完整首再停止'**
  String get sleepAfterSong;

  /// No description provided for @sleepTimerOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭定时'**
  String get sleepTimerOff;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @settingsAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsAbout;

  /// No description provided for @checkUpdate.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get checkUpdate;

  /// No description provided for @currentVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前版本 {version}'**
  String currentVersion(String version);

  /// No description provided for @updateChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查…'**
  String get updateChecking;

  /// No description provided for @upToDate.
  ///
  /// In zh, this message translates to:
  /// **'已是最新'**
  String get upToDate;

  /// No description provided for @updateCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败，稍后再试'**
  String get updateCheckFailed;

  /// No description provided for @updatePreview.
  ///
  /// In zh, this message translates to:
  /// **'接收预览版更新'**
  String get updatePreview;

  /// No description provided for @updatePreviewHint.
  ///
  /// In zh, this message translates to:
  /// **'测试版也会提醒，可能不稳定'**
  String get updatePreviewHint;

  /// No description provided for @updateMirror.
  ///
  /// In zh, this message translates to:
  /// **'通过镜像下载更新'**
  String get updateMirror;

  /// No description provided for @updateMirrorHint.
  ///
  /// In zh, this message translates to:
  /// **'打开后不连接 GitHub，全部走镜像'**
  String get updateMirrorHint;

  /// No description provided for @updateAvailable.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本 {version}'**
  String updateAvailable(String version);

  /// No description provided for @updatePreviewBadge.
  ///
  /// In zh, this message translates to:
  /// **'预览版'**
  String get updatePreviewBadge;

  /// No description provided for @updateCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前 {version}'**
  String updateCurrent(String version);

  /// No description provided for @updateDate.
  ///
  /// In zh, this message translates to:
  /// **'{date} 发布'**
  String updateDate(String date);

  /// No description provided for @updateInstaller.
  ///
  /// In zh, this message translates to:
  /// **'安装包'**
  String get updateInstaller;

  /// No description provided for @updateInstallerHint.
  ///
  /// In zh, this message translates to:
  /// **'运行安装程序覆盖更新'**
  String get updateInstallerHint;

  /// No description provided for @updateArchive.
  ///
  /// In zh, this message translates to:
  /// **'压缩包'**
  String get updateArchive;

  /// No description provided for @updateArchiveHint.
  ///
  /// In zh, this message translates to:
  /// **'退出后自动替换文件'**
  String get updateArchiveHint;

  /// No description provided for @updateNow.
  ///
  /// In zh, this message translates to:
  /// **'立即更新'**
  String get updateNow;

  /// No description provided for @updateSkip.
  ///
  /// In zh, this message translates to:
  /// **'跳过这个版本'**
  String get updateSkip;

  /// No description provided for @updateDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载 {version}'**
  String updateDownloading(String version);

  /// No description provided for @updateDownloadingHint.
  ///
  /// In zh, this message translates to:
  /// **'下载完会自动校验并安装'**
  String get updateDownloadingHint;

  /// No description provided for @updateConnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在连接下载源…'**
  String get updateConnecting;

  /// No description provided for @updateSource.
  ///
  /// In zh, this message translates to:
  /// **'下载源：{source}'**
  String updateSource(String source);

  /// No description provided for @updateFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新失败'**
  String get updateFailed;

  /// No description provided for @updateNetworkFailed.
  ///
  /// In zh, this message translates to:
  /// **'没能下载下来。检查网络后重试，或在设置里切换镜像。'**
  String get updateNetworkFailed;

  /// No description provided for @updateCorrupted.
  ///
  /// In zh, this message translates to:
  /// **'文件校验没通过，可能是下载源出了问题。没有安装任何东西。'**
  String get updateCorrupted;

  /// No description provided for @updateNotWritable.
  ///
  /// In zh, this message translates to:
  /// **'没有权限替换程序目录里的文件，请改用安装包。'**
  String get updateNotWritable;

  /// No description provided for @updateInstallFailed.
  ///
  /// In zh, this message translates to:
  /// **'没能打开安装程序。'**
  String get updateInstallFailed;

  /// No description provided for @updateUseInstaller.
  ///
  /// In zh, this message translates to:
  /// **'改用安装包'**
  String get updateUseInstaller;

  /// No description provided for @updateOpenBrowser.
  ///
  /// In zh, this message translates to:
  /// **'在浏览器中下载'**
  String get updateOpenBrowser;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
