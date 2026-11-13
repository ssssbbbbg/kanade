// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Kanade';

  @override
  String get tabDiscover => 'Discover';

  @override
  String get tabSearch => 'Search';

  @override
  String get tabMine => 'Me';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get windowClose => 'Close';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get themeToDark => 'Switch to dark';

  @override
  String get themeToLight => 'Switch to light';

  @override
  String get retry => 'Retry';

  @override
  String get loading => 'Loading';

  @override
  String get cancel => 'Cancel';

  @override
  String loadFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get recommendedPlaylists => 'Recommended playlists';

  @override
  String get recommendedSongs => 'Picked for you';

  @override
  String get discoverRecommend => 'For you';

  @override
  String get discoverToplists => 'Charts';

  @override
  String get radioGuessYouLike => 'Guess you like';

  @override
  String get radioRadar => 'Discovery mode';

  @override
  String radioFailed(String error) {
    return 'Couldn\'t start the radio: $error';
  }

  @override
  String feedColumnTitle(String name) {
    return 'Picked for $name';
  }

  @override
  String viewAllSongs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'View all $count songs',
      one: 'View 1 song',
    );
    return '$_temp0';
  }

  @override
  String updatedAt(String period) {
    return 'Updated $period';
  }

  @override
  String playAll(int count) {
    return 'Play all ($count)';
  }

  @override
  String songCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
    );
    return '$_temp0';
  }

  @override
  String get searchHint => 'Search songs, artists, albums, videos';

  @override
  String get recognizeSong => 'Recognize song';

  @override
  String get recognizeListening => 'Listening…';

  @override
  String get recognizeHint => 'Hold the microphone near the music';

  @override
  String recognizeElapsed(int seconds) {
    return '${seconds}s';
  }

  @override
  String get recognizeNotFound => 'Couldn\'t recognize this song';

  @override
  String get recognizeAgain => 'Try again';

  @override
  String get recognizeNoMic => 'Microphone access denied';

  @override
  String get recognizeBubble => 'Enable floating button';

  @override
  String get recognizeBubbleHint => 'Keep recognizing after switching apps';

  @override
  String get searchPrompt => 'Type a keyword and press Enter';

  @override
  String get searchHot => 'Trending';

  @override
  String get searchRecommended => 'You might like';

  @override
  String get filterSongsHint => 'Search title or artist';

  @override
  String get locateCurrentSong => 'Locate the playing song';

  @override
  String get searchNoResults => 'No results found';

  @override
  String searchFailed(String error) {
    return 'Search failed: $error';
  }

  @override
  String searchTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs in total',
      one: '1 song in total',
    );
    return '$_temp0';
  }

  @override
  String get quality => 'Quality';

  @override
  String get qualityLoading => 'Loading qualities';

  @override
  String qualityFailed(String error) {
    return 'Failed to load qualities: $error';
  }

  @override
  String get qualityFailedRetry => 'Failed to load qualities, tap to retry';

  @override
  String get qualityNoneForSong => 'No qualities available for this song';

  @override
  String get qualityNone => 'No qualities available';

  @override
  String qualityWithReason(String quality, String reason) {
    return '$quality ($reason)';
  }

  @override
  String get qualityLow => 'Smooth 96k';

  @override
  String get qualityStandard => 'Standard 128k';

  @override
  String get qualityHigh => 'High 320k';

  @override
  String get qualityLossless => 'Lossless FLAC';

  @override
  String get qualityMaster => 'Master';

  @override
  String get qualityAtmos => 'Premium';

  @override
  String get qualityAtmos51 => 'Premium Surround 5.1';

  @override
  String get qualityAtmos71 => 'Premium Surround 7.1';

  @override
  String get qualityDolby => 'Dolby Atmos';

  @override
  String get qualityOgg320 => 'High OGG 320k';

  @override
  String get qualityAiCodec => 'AI audio';

  @override
  String get reasonUnsupported => 'format not supported by the player';

  @override
  String get reasonUnverified => 'not yet verified for playback';

  @override
  String get reasonNoPermission => 'no access on this account';

  @override
  String get reasonDeviceRestricted => 'restricted on this device';

  @override
  String get reasonNoLink => 'no link available';

  @override
  String get reasonVerifyFailed => 'check failed, try again later';

  @override
  String get reasonFileUnavailable => 'audio file unavailable';

  @override
  String get logout => 'Log out';

  @override
  String get notLoggedIn => 'Not logged in';

  @override
  String get loginMethods => 'Choose how to log in';

  @override
  String get loginQqHint => 'Scan with QQ on your phone';

  @override
  String get loginWechatHint => 'Scan with WeChat';

  @override
  String get loginQqMusicHint => 'Confirm in the QQ Music app';

  @override
  String get loginPrompt =>
      'Log in to sync your playlists and play songs your account has access to';

  @override
  String get loginQq => 'Log in with QQ';

  @override
  String get loginWechat => 'Log in with WeChat';

  @override
  String get loginQqMusic => 'Log in with QQ Music app';

  @override
  String get loginCookie => 'Log in with cookie';

  @override
  String get noPlaylists => 'No playlists yet';

  @override
  String get qrLoading => 'Loading QR code…';

  @override
  String get qrScanHintQq => 'Scan with QQ on your phone';

  @override
  String get qrScanHintWechat => 'Scan with WeChat on your phone';

  @override
  String get qrScanHintQqMusic =>
      'Scan with the QQ Music app. You\'ll be logged in as that app\'s account.';

  @override
  String get qrScanned => 'Scanned. Confirm on your phone';

  @override
  String get qrExpired => 'QR code expired';

  @override
  String get qrRefused => 'Login was cancelled on your phone';

  @override
  String get qrRefresh => 'Refresh QR code';

  @override
  String get qrOpenQq => 'Log in with QQ app';

  @override
  String get qrQqNotInstalled => 'Couldn\'t open QQ. Is the QQ app installed?';

  @override
  String get qrSaveImage => 'Save QR code';

  @override
  String get qrSavedQq =>
      'Saved to gallery. In QQ\'s Scan, pick the image from your album.';

  @override
  String get qrOpenQqMusic => 'Authorize in QQ Music app';

  @override
  String get qrQqMusicNotInstalled =>
      'Couldn\'t open QQ Music. Is the QQ Music app installed?';

  @override
  String get qrWechatSameDeviceTip =>
      'WeChat can\'t log in on the same phone. If your QQ Music app uses a WeChat account, use \"Log in with QQ Music app\" instead.';

  @override
  String qrSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String qrFailed(String error) {
    return 'Failed to get QR code: $error';
  }

  @override
  String get cookieLoginTitle => 'Cookie login';

  @override
  String get cookieLoginHint =>
      'Log in at y.qq.com in a browser, then copy the Cookie from developer tools and paste it here (it must include uin and qm_keyst).';

  @override
  String get login => 'Log in';

  @override
  String get swipeForLyrics => '← Swipe left for lyrics';

  @override
  String get noLyrics => 'No lyrics';

  @override
  String get modeSequence => 'Repeat all';

  @override
  String get modeRepeatOne => 'Repeat one';

  @override
  String get modeShuffle => 'Shuffle';

  @override
  String get lyrics => 'Lyrics';

  @override
  String get upNext => 'Up next';

  @override
  String get playNext => 'Play next';

  @override
  String get queuedNext => 'Will play next';

  @override
  String get alreadyPlaying => 'Already playing';

  @override
  String get volume => 'Volume';

  @override
  String get queue => 'Queue';

  @override
  String get removeFromQueue => 'Remove from queue';

  @override
  String get reorderQueue => 'Drag to reorder';

  @override
  String playbackError(String error) {
    return 'Playback error: $error';
  }

  @override
  String songUnplayable(String song, String error) {
    return 'Can\'t play \"$song\": $error';
  }

  @override
  String get errorNotLoggedIn => 'Not logged in';

  @override
  String get errorNoPlayableUrl =>
      'No playable link (login or VIP may be required)';

  @override
  String errorLoginFailed(String detail) {
    return 'Login failed: $detail';
  }

  @override
  String errorInvalidCookie(String field) {
    return 'Cookie is missing $field';
  }

  @override
  String errorServer(String code, String api) {
    return 'Server returned error code $code ($api)';
  }

  @override
  String errorBadResponse(String detail) {
    return 'Unexpected server response: $detail';
  }

  @override
  String errorNetwork(String detail) {
    return 'Network error: $detail';
  }

  @override
  String errorInternal(String detail) {
    return 'Internal error: $detail';
  }

  @override
  String get previousSong => 'Previous';

  @override
  String get nextSong => 'Next';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get like => 'Like';

  @override
  String get unlike => 'Unlike';

  @override
  String get likeShort => 'Like';

  @override
  String get likedShort => 'Liked';

  @override
  String get liked => 'Added to Liked Songs';

  @override
  String get unliked => 'Removed from Liked Songs';

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String addedToPlaylist(String name) {
    return 'Added to \"$name\"';
  }

  @override
  String get removeFromPlaylist => 'Remove from playlist';

  @override
  String removedFromPlaylist(String name) {
    return 'Removed from \"$name\"';
  }

  @override
  String actionFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get loginRequired => 'Please log in on the Mine tab first';

  @override
  String get noMyPlaylists => 'No playlists to add to';

  @override
  String get more => 'More';

  @override
  String singerNamed(String name) {
    return 'Artist: $name';
  }

  @override
  String albumNamed(String name) {
    return 'Album: $name';
  }

  @override
  String get comments => 'Comments';

  @override
  String get commentsRecommended => 'Recommended';

  @override
  String get noComments => 'No comments yet';

  @override
  String commentCount(String count) {
    return '$count comments';
  }

  @override
  String get timeJustNow => 'Just now';

  @override
  String timeMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String timeHoursAgo(int count) {
    return '$count h ago';
  }

  @override
  String timeDaysAgo(int count) {
    return '$count d ago';
  }

  @override
  String get replies => 'Replies';

  @override
  String replyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count replies',
      one: '1 reply',
    );
    return '$_temp0';
  }

  @override
  String replyTo(String name) {
    return 'Reply to $name: ';
  }

  @override
  String get loadMore => 'Load more';

  @override
  String get tabSongs => 'Songs';

  @override
  String get tabAlbums => 'Albums';

  @override
  String publishedOn(String date) {
    return 'Released $date';
  }

  @override
  String get settings => 'Settings';

  @override
  String get settingsPlayback => 'Playback';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsStorage => 'Storage';

  @override
  String get settingsAccount => 'Account';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String audioCacheOfLimit(Object limit) {
    return '/ $limit limit';
  }

  @override
  String get audioCacheDisabled => 'Caching is off';

  @override
  String get foryouSettings => 'Customize For You';

  @override
  String get foryouSettingsHint =>
      'Choose the cards in the top row of Recommend, synced with QQ Music on phones';

  @override
  String get foryouChoose => 'Choose what to show or hide';

  @override
  String get save => 'Save';

  @override
  String get foryouSaved => 'Saved';

  @override
  String foryouSaveFailed(Object error) {
    return 'Failed to save: $error';
  }

  @override
  String get defaultQuality => 'Default quality';

  @override
  String get defaultQualityHint =>
      'Falls back to a lower quality when unavailable or unplayable';

  @override
  String get songFade => 'Playback transition';

  @override
  String get songFadeHint =>
      'Fades volume when switching songs, pausing and resuming';

  @override
  String get songFadeOff => 'Off';

  @override
  String songFadeSeconds(Object seconds) {
    return '$seconds s';
  }

  @override
  String get audioCacheLimit => 'Song cache limit';

  @override
  String get audioCacheLimitHint =>
      'Songs are saved while playing; least recently played are removed first';

  @override
  String get audioCacheOff => 'Off';

  @override
  String get audioCacheCustom => 'Custom';

  @override
  String get audioCacheCustomTitle => 'Custom cache limit';

  @override
  String get audioCacheCustomUnit => 'MB';

  @override
  String get audioCacheSize => 'Song cache';

  @override
  String get apiCacheSize => 'Other cache';

  @override
  String get apiCacheSizeHint => 'Playlists, search results, lyrics and more';

  @override
  String get clear => 'Clear';

  @override
  String get clearAudioCacheConfirm => 'Clear all cached songs?';

  @override
  String get clearApiCacheConfirm =>
      'Clear cached playlists, search results, lyrics and more?';

  @override
  String get cacheCleared => 'Cleared';

  @override
  String get logoutConfirm => 'Log out?';

  @override
  String get sessionEndedTitle => 'You\'ve been logged out';

  @override
  String get sessionExpired =>
      'Your login expired, so you were logged out. Log in again to keep syncing playlists and playing VIP songs.';

  @override
  String get sessionRevoked =>
      'QQ Music ended your login before it expired, so you were logged out.';

  @override
  String get sessionRejected =>
      'QQ Music no longer accepts this login, so you were logged out.';

  @override
  String get sessionCausesTitle => 'Possible causes';

  @override
  String get sessionCauseOtherDevice =>
      'Your account logged in on another device and replaced this one';

  @override
  String get sessionCauseDeviceRemoved =>
      'This device was removed in QQ Music\'s device management';

  @override
  String get sessionCausePassword => 'The account password was changed';

  @override
  String get sessionCauseExpired => 'The login passed its expiry time';

  @override
  String get loginAgain => 'Log in again';

  @override
  String get later => 'Later';

  @override
  String get ok => 'OK';

  @override
  String get likedSongs => 'Liked songs';

  @override
  String get recentPlays => 'Recently played';

  @override
  String get myPlaylists => 'My playlists';

  @override
  String get playlistsCreated => 'Created';

  @override
  String get playlistsCollected => 'Saved';

  @override
  String get shufflePlay => 'Shuffle';

  @override
  String get seeAll => 'See all';

  @override
  String get refresh => 'Refresh';

  @override
  String get renamePlaylist => 'Rename';

  @override
  String get deletePlaylist => 'Delete playlist';

  @override
  String get delete => 'Delete';

  @override
  String get playlistNameHint => 'Playlist name';

  @override
  String deletePlaylistConfirm(String name) {
    return 'Delete playlist \"$name\"? This can\'t be undone.';
  }

  @override
  String get playlistRenamed => 'Renamed';

  @override
  String get playlistDeleted => 'Playlist deleted';

  @override
  String get nothingPlaying => 'Nothing playing';

  @override
  String get searchKindSong => 'Songs';

  @override
  String get searchKindSinger => 'Artists';

  @override
  String get searchKindAlbum => 'Albums';

  @override
  String get searchKindPlaylist => 'Playlists';

  @override
  String get searchKindVideo => 'Videos';

  @override
  String get recentKindRadar => 'Music radar';

  @override
  String get recentKindAudiobook => 'Audiobooks';

  @override
  String get searchKindLyric => 'Lyrics';

  @override
  String searchTotalItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String singerStats(int songs, int albums) {
    return '$songs songs · $albums albums';
  }

  @override
  String get searchKindUser => 'Users';

  @override
  String get mvUnavailable => 'This video can\'t be played right now';

  @override
  String get watchMv => 'Watch MV';

  @override
  String get findSimilarSongs => 'Find similar songs';

  @override
  String similarSongsTitle(String name) {
    return 'Songs similar to $name';
  }

  @override
  String userFansFollows(String fans, String follows) {
    return '$fans followers · $follows following';
  }

  @override
  String userBriefStats(String fans, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$fans followers · $_temp0';
  }

  @override
  String userPlaylists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$_temp0';
  }

  @override
  String get userNoPlaylists => 'No public playlists';

  @override
  String userFans(String fans) {
    return '$fans followers';
  }

  @override
  String get singerFeatured => 'Featured';

  @override
  String get singerSelectedAlbums => 'Selected albums';

  @override
  String get follow => 'Follow';

  @override
  String get followed => 'Following';

  @override
  String get createPlaylist => 'Create playlist';

  @override
  String get create => 'Create';

  @override
  String get playlistSyncHint => 'Syncs to your QQ Music account';

  @override
  String get playlistCreated => 'Playlist created';

  @override
  String get savedPlaylists => 'Saved playlists';

  @override
  String get savedAlbums => 'Saved albums';

  @override
  String get userPrivate => 'This content is private';

  @override
  String get noItems => 'No items';

  @override
  String get newest => 'Newest';

  @override
  String get hottest => 'Most popular';

  @override
  String get userLikes => 'Liked';

  @override
  String get singerAbout => 'About';

  @override
  String get singerBio => 'Biography';

  @override
  String get singerGuard => 'Guardians';

  @override
  String get statFans => 'Followers';

  @override
  String get statFollows => 'Following';

  @override
  String get statPlaylists => 'Playlists';

  @override
  String get showMore => 'More';

  @override
  String get showLess => 'Less';

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours hr $minutes min';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String filterFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs found',
      one: '1 song found',
    );
    return '$_temp0';
  }

  @override
  String playFiltered(int count) {
    return 'Play $count';
  }

  @override
  String get featuredVideos => 'Featured videos';

  @override
  String alsoListening(String name) {
    return 'Fans of $name also listen to';
  }

  @override
  String get relatedPlaylists => 'Related playlists';

  @override
  String get anotherBatch => 'Show others';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String sleepTimerUntil(String time) {
    return 'Stops at $time';
  }

  @override
  String get sleepTimerWaiting => 'Stops after this song';

  @override
  String get sleepTimerWaitingShort => 'After song';

  @override
  String get sleepTimerCustomHint => 'Custom length';

  @override
  String get sleepTimerMinutes => 'min';

  @override
  String get sleepTimerStart => 'Start';

  @override
  String get sleepAfterSong => 'Finish the current song';

  @override
  String get sleepTimerOff => 'Turn off timer';

  @override
  String get close => 'Close';

  @override
  String get settingsAbout => 'About';

  @override
  String get checkUpdate => 'Check for updates';

  @override
  String currentVersion(String version) {
    return 'Current version $version';
  }

  @override
  String get updateChecking => 'Checking…';

  @override
  String get upToDate => 'Up to date';

  @override
  String get updateCheckFailed =>
      'Couldn\'t check for updates. Try again later.';

  @override
  String get updatePreview => 'Get preview updates';

  @override
  String get updatePreviewHint =>
      'Also notify about beta versions, which may be unstable';

  @override
  String get updateMirror => 'Download updates through a mirror';

  @override
  String get updateMirrorHint =>
      'Skips GitHub entirely and uses mirrors instead';

  @override
  String updateAvailable(String version) {
    return '$version is available';
  }

  @override
  String get updatePreviewBadge => 'Preview';

  @override
  String updateCurrent(String version) {
    return 'Current $version';
  }

  @override
  String updateDate(String date) {
    return 'Released $date';
  }

  @override
  String get updateInstaller => 'Installer';

  @override
  String get updateInstallerHint =>
      'Runs the installer over the current version';

  @override
  String get updateArchive => 'Zip archive';

  @override
  String get updateArchiveHint => 'Replaces the files after the app quits';

  @override
  String get updateNow => 'Update now';

  @override
  String get updateSkip => 'Skip this version';

  @override
  String updateDownloading(String version) {
    return 'Downloading $version';
  }

  @override
  String get updateDownloadingHint =>
      'It will be verified and installed when done';

  @override
  String get updateConnecting => 'Connecting…';

  @override
  String updateSource(String source) {
    return 'Source: $source';
  }

  @override
  String get updateFailed => 'Update failed';

  @override
  String get updateNetworkFailed =>
      'The download didn\'t finish. Check your connection and retry, or switch the mirror setting.';

  @override
  String get updateCorrupted =>
      'The file failed verification, so the download source may be at fault. Nothing was installed.';

  @override
  String get updateNotWritable =>
      'Kanade can\'t replace files in its folder. Use the installer instead.';

  @override
  String get updateInstallFailed => 'Couldn\'t open the installer.';

  @override
  String get updateUseInstaller => 'Use the installer';

  @override
  String get updateOpenBrowser => 'Download in browser';
}
