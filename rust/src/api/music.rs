//! Dart 侧调用的接口。具体实现在 crate::qq。
//! 错误统一转换成 ApiError 错误码，由 Dart 侧翻译。

use crate::api::error::ApiError;
use crate::api::types::*;
use crate::frb_generated::StreamSink;
use crate::qq::audio_cache::cache;
use crate::qq::{
    client, detail, history, library, login, music, mv, quality, recognize, social, user,
};

// 错误转换与会话副作用只在 API 边界组合；复核请求不经过此处。
fn api_error(error: anyhow::Error) -> ApiError {
    let error = ApiError::from(error);
    if error.is_auth_rejected() {
        client::suspect_session();
    }
    error
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// 设置数据目录（SQLite 缓存和登录态存放处）。启动时调用一次。
pub fn init_core(data_dir: String) -> Result<(), ApiError> {
    Ok(client::init(std::path::Path::new(&data_dir)).map_err(api_error)?)
}

/// Android 界面与播放进程共用数据库，音频缓存只由播放进程打开。
pub fn init_ui_core(data_dir: String) -> Result<(), ApiError> {
    Ok(client::init_store(std::path::Path::new(&data_dir)).map_err(api_error)?)
}

/// 按分类搜索第 `page` 页（从 1 开始）。
pub async fn search(
    keyword: String,
    kind: SearchKind,
    page: u32,
    page_size: u32,
) -> Result<SearchResult, ApiError> {
    Ok(music::search(&keyword, kind, page, page_size)
        .await
        .map_err(api_error)?)
}

pub async fn get_hot_search() -> Result<HotSearch, ApiError> {
    Ok(music::hot_search().await.map_err(api_error)?)
}

pub async fn get_search_suggestions(query: String) -> Result<Vec<SearchSuggestion>, ApiError> {
    Ok(music::search_suggestions(&query).await.map_err(api_error)?)
}

/// 歌曲的相似推荐，`song_id` 是歌曲数字 ID。
pub async fn get_similar_songs(song_id: i64) -> Result<Vec<Song>, ApiError> {
    Ok(music::similar_songs(song_id).await.map_err(api_error)?)
}

/// 播放页右滑的歌曲信息页。
pub async fn get_song_page(song_id: i64, song_mid: String) -> Result<SongPage, ApiError> {
    Ok(detail::song_page(song_id, &song_mid)
        .await
        .map_err(api_error)?)
}

/// 信息页「相关歌单」换一批，`exclude` 是已经显示过的歌单 ID。
pub async fn get_related_playlists(
    song_id: i64,
    exclude: Vec<String>,
) -> Result<RelatedPlaylists, ApiError> {
    Ok(detail::related_playlists(song_id, &exclude)
        .await
        .map_err(api_error)?)
}

pub async fn get_song_url(
    mid: String,
    media_mid: String,
    quality: Quality,
) -> Result<SongUrl, ApiError> {
    Ok(music::song_url(&mid, &media_mid, quality)
        .await
        .map_err(api_error)?)
}

/// 这台设备能否播放该音质；DTS:X、360RA、NAC 缺少解码器时为 false。
#[flutter_rust_bridge::frb(sync)]
pub fn quality_supported(quality: Quality) -> bool {
    quality::supported(quality)
}

/// 比 `quality` 低一档的音质；已是最低档时为 None。拿到链接却播不了时用来降级重试。
#[flutter_rust_bridge::frb(sync)]
pub fn lower_quality(quality: Quality) -> Option<Quality> {
    quality::lower(quality)
}

/// 本地缓存的这首歌这个音质的文件路径。
#[flutter_rust_bridge::frb(sync)]
pub fn get_cached_audio(mid: String, quality: Quality) -> Option<String> {
    cache().lookup(&mid, quality)
}

/// 这首歌任一音质的缓存（没网时用）。
#[flutter_rust_bridge::frb(sync)]
pub fn get_any_cached_audio(mid: String) -> Option<CachedAudio> {
    cache()
        .lookup_any(&mid)
        .map(|(path, quality)| CachedAudio { path, quality })
}

/// 缓存文件播不了时删掉。
#[flutter_rust_bridge::frb(sync)]
pub fn remove_cached_audio(mid: String, quality: Quality) {
    cache().remove(&mid, quality)
}

/// 加密音频走本机解密。普通音频在启用缓存时走边播边存的本机地址。
#[flutter_rust_bridge::frb(sync)]
pub fn stream_audio(
    mid: String,
    quality: Quality,
    url: String,
    ekey: Option<String>,
) -> Result<String, ApiError> {
    Ok(cache()
        .stream(&mid, quality, &url, ekey.as_deref())
        .map_err(api_error)?)
}

/// 等待需要整曲解码的音源准备好，再交给播放器。
pub async fn wait_for_decoded_audio(url: String) -> Result<(), ApiError> {
    Ok(cache().wait_for_decoded(&url).await.map_err(api_error)?)
}

/// 歌曲缓存上限（MB），0 表示关闭。
#[flutter_rust_bridge::frb(sync)]
pub fn get_audio_cache_limit_mb() -> i64 {
    crate::qq::audio_cache::limit_mb()
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_audio_cache_limit_mb(mb: i64) -> Result<(), ApiError> {
    Ok(cache().set_limit_mb(mb).map_err(api_error)?)
}

/// 歌曲缓存占用的字节数。
pub fn get_audio_cache_size() -> i64 {
    cache().size()
}

pub fn clear_audio_cache() {
    cache().clear()
}

/// 接口数据缓存占用的字节数。
pub fn get_api_cache_size() -> i64 {
    client::core().store.cache_size()
}

pub async fn get_song_qualities(mid: String) -> Result<Vec<QualityOption>, ApiError> {
    Ok(quality::song_qualities(&mid).await.map_err(api_error)?)
}

pub async fn get_lyric(mid: String, id: i64) -> Result<Lyric, ApiError> {
    Ok(music::lyric(&mid, id).await.map_err(api_error)?)
}

pub async fn get_song_chorus(id: i64) -> Result<Option<ChorusRange>, ApiError> {
    Ok(music::chorus(id).await.map_err(api_error)?)
}

/// 听歌识曲：`pcm` 是从开始录到现在的全部录音（8 kHz、16 位小端、单声道），
/// 同一次识别的多次调用传同一个 `session_id`。还没认出来时返回 None，继续录音再试。
pub async fn recognize_song(session_id: i64, pcm: Vec<u8>) -> Result<Option<Song>, ApiError> {
    Ok(recognize::recognize(session_id, &pcm)
        .await
        .map_err(api_error)?)
}

pub async fn get_toplists() -> Result<Vec<TopListGroup>, ApiError> {
    Ok(music::toplists().await.map_err(api_error)?)
}

pub async fn get_toplist_detail(top_id: i64, period: String) -> Result<TopListDetail, ApiError> {
    Ok(music::toplist_detail(top_id, &period)
        .await
        .map_err(api_error)?)
}

pub async fn get_recommend_feed() -> Result<RecommendFeed, ApiError> {
    Ok(music::recommend_feed().await.map_err(api_error)?)
}

/// 「自定义推荐页」：首页最上面那排卡片可以显示哪些（需要登录）。
pub async fn get_foryou_config() -> Result<Vec<ForyouItem>, ApiError> {
    Ok(music::foryou_config().await.map_err(api_error)?)
}

/// 保存「自定义推荐页」，`chosen` 是勾选项的 id；固定项不受影响。
pub async fn save_foryou_config(chosen: Vec<String>) -> Result<(), ApiError> {
    Ok(music::save_foryou_config(&chosen)
        .await
        .map_err(api_error)?)
}

/// 单独刷新首页的一个栏目，`refresh` 取自该栏目的 `RecommendSection.refresh`（不能为空）。
pub async fn refresh_recommend_section(refresh: String) -> Result<RecommendSection, ApiError> {
    Ok(music::refresh_recommend_section(&refresh)
        .await
        .map_err(api_error)?)
}

/// 猜你喜欢电台的下一批歌（需要登录）。
pub async fn get_guess_you_like() -> Result<Vec<Song>, ApiError> {
    Ok(music::guess_you_like().await.map_err(api_error)?)
}

/// 刷歌模式的第 `page` 批歌，`seed` 来自 `RecommendFeed.radar_seed`。
/// 个性电台（最近播放里的音乐雷达）的下一批歌。
pub async fn get_radio_songs(id: i64) -> Result<Vec<Song>, ApiError> {
    Ok(music::radio_songs(id).await.map_err(api_error)?)
}

pub async fn get_radar_songs(seed: Vec<i64>, page: u32) -> Result<Vec<Song>, ApiError> {
    Ok(music::radar_songs(&seed, page).await.map_err(api_error)?)
}

/// 首页的专属乐流第 `page` 页（从 1 开始），`seen` 是之前各页 `seen` 的合集（需要登录）。
/// 返回的卡片为空表示没有更多了。
pub async fn get_feed_column(page: u32, seen: Vec<String>) -> Result<FeedColumnPage, ApiError> {
    Ok(music::feed_column(page, &seen).await.map_err(api_error)?)
}

pub async fn get_playlist_detail(id: String) -> Result<PlaylistDetail, ApiError> {
    Ok(music::playlist_detail(&id).await.map_err(api_error)?)
}

pub async fn get_user_playlists() -> Result<Vec<PlaylistBrief>, ApiError> {
    Ok(music::user_playlists().await.map_err(api_error)?)
}

/// 歌手资料，附带第一页歌曲和专辑。
pub async fn get_singer_detail(mid: String) -> Result<SingerDetail, ApiError> {
    Ok(detail::singer_detail(&mid).await.map_err(api_error)?)
}

/// 歌手歌曲翻页，`begin` 从 0 开始。
pub async fn get_singer_songs(mid: String, begin: u32, num: u32) -> Result<Vec<Song>, ApiError> {
    Ok(detail::singer_songs(&mid, begin, num)
        .await
        .map_err(api_error)?)
}

pub async fn get_singer_albums(
    mid: String,
    begin: u32,
    num: u32,
) -> Result<Vec<AlbumBrief>, ApiError> {
    Ok(detail::singer_albums(&mid, begin, num)
        .await
        .map_err(api_error)?)
}

pub async fn get_singer_social(mid: String) -> Result<SingerSocial, ApiError> {
    Ok(detail::singer_social(&mid).await.map_err(api_error)?)
}

pub async fn get_singer_video_tags(mid: String) -> Result<Vec<VideoTag>, ApiError> {
    Ok(detail::singer_video_tags(&mid).await.map_err(api_error)?)
}

pub async fn get_singer_videos(
    mid: String,
    name: String,
    tag: i64,
    order: u32,
    begin: u32,
    num: u32,
) -> Result<SingerVideoPage, ApiError> {
    Ok(detail::singer_videos(&mid, &name, tag, order, begin, num)
        .await
        .map_err(api_error)?)
}

pub async fn set_singer_followed(mid: String, followed: bool) -> Result<(), ApiError> {
    Ok(social::set_followed(&mid, true, followed)
        .await
        .map_err(api_error)?)
}

pub async fn set_user_followed(euin: String, followed: bool) -> Result<(), ApiError> {
    Ok(social::set_followed(&euin, false, followed)
        .await
        .map_err(api_error)?)
}

pub async fn get_album_detail(mid: String) -> Result<AlbumDetail, ApiError> {
    Ok(detail::album_detail(&mid).await.map_err(api_error)?)
}

/// MV 资料和各清晰度的播放地址，`vid` 是视频搜索结果里的字符串 VID。
pub async fn get_mv_detail(vid: String) -> Result<MvDetail, ApiError> {
    Ok(mv::mv_detail(&vid).await.map_err(api_error)?)
}

/// 其他用户的主页资料，`euin` 来自用户搜索结果。
pub async fn get_user_profile(euin: String) -> Result<UserProfile, ApiError> {
    Ok(user::user_profile(&euin).await.map_err(api_error)?)
}

/// 其他用户的公开歌单，`page` 从 0 开始；`creator` 是填进歌单卡片的用户名。
pub async fn get_user_public_playlists(
    euin: String,
    creator: String,
    page: u32,
    page_size: u32,
) -> Result<UserPlaylistPage, ApiError> {
    Ok(user::user_playlists(&euin, &creator, page, page_size)
        .await
        .map_err(api_error)?)
}

pub async fn get_user_assets(
    euin: String,
    kind: UserAssetKind,
    page: u32,
    page_size: u32,
) -> Result<UserAssetPage, ApiError> {
    Ok(user::user_assets(&euin, kind, page, page_size)
        .await
        .map_err(api_error)?)
}

/// 推荐 / 最热 / 最新评论。`cursor` 第一页传空字符串，之后传上一页返回的 `cursor`。
pub async fn get_comment_feed(
    target: CommentTarget,
    id: i64,
    sort: CommentSort,
    cursor: String,
) -> Result<CommentFeed, ApiError> {
    Ok(detail::comment_feed(target, id, sort, &cursor)
        .await
        .map_err(api_error)?)
}

/// 某条评论下的回复，翻页方式同 `get_comment_feed`。
pub async fn get_reply_feed(root_id: String, cursor: String) -> Result<CommentFeed, ApiError> {
    Ok(detail::reply_feed(&root_id, &cursor)
        .await
        .map_err(api_error)?)
}

/// 自己创建的歌单（需要登录），加入歌单时选择用。
pub async fn get_my_playlists() -> Result<Vec<MyPlaylist>, ApiError> {
    Ok(library::my_playlists().await.map_err(api_error)?)
}

pub async fn create_playlist(name: String) -> Result<MyPlaylist, ApiError> {
    Ok(library::create_playlist(&name).await.map_err(api_error)?)
}

/// “我喜欢”里的歌曲 id（需要登录）。
pub async fn get_liked_song_ids() -> Result<Vec<i64>, ApiError> {
    Ok(library::liked_song_ids().await.map_err(api_error)?)
}

/// 红心 / 取消红心（需要登录）。
pub async fn set_song_liked(song_id: i64, liked: bool) -> Result<(), ApiError> {
    Ok(library::set_song_liked(song_id, liked)
        .await
        .map_err(api_error)?)
}

pub async fn add_song_to_playlist(dir_id: i64, song_id: i64) -> Result<(), ApiError> {
    Ok(library::add_to_playlist(dir_id, song_id)
        .await
        .map_err(api_error)?)
}

pub async fn remove_song_from_playlist(dir_id: i64, song_id: i64) -> Result<(), ApiError> {
    Ok(library::remove_from_playlist(dir_id, song_id)
        .await
        .map_err(api_error)?)
}

/// 改名自己的歌单（“我喜欢”除外）。
pub async fn rename_playlist(dir_id: i64, name: String) -> Result<(), ApiError> {
    Ok(library::rename_playlist(dir_id, &name)
        .await
        .map_err(api_error)?)
}

/// 删除整个自己的歌单（“我喜欢”除外）。
pub async fn delete_playlist(dir_id: i64) -> Result<(), ApiError> {
    Ok(library::delete_playlist(dir_id).await.map_err(api_error)?)
}

/// 云端最近播放的歌曲（需要登录），从新到旧。
pub async fn get_recent_plays() -> Result<Vec<Song>, ApiError> {
    Ok(history::recent_plays().await.map_err(api_error)?)
}

/// 云端最近播放的专辑、歌单、视频、有声节目（需要登录）。
pub async fn get_recent_collections() -> Result<RecentCollections, ApiError> {
    Ok(history::recent_collections().await.map_err(api_error)?)
}

/// 上报一次播放到云端最近播放（需要登录）。
pub async fn report_play(song_id: i64) -> Result<(), ApiError> {
    Ok(history::report_play(song_id).await.map_err(api_error)?)
}

pub async fn create_login_qr(kind: LoginKind) -> Result<QrCode, ApiError> {
    Ok(match kind {
        LoginKind::Qq => login::create_qr().await.map_err(api_error)?,
        LoginKind::Wechat => login::create_wx_qr().await.map_err(api_error)?,
        LoginKind::QqMusic => login::create_tme_qr().await.map_err(api_error)?,
    })
}

/// 同一台手机跳转 QQ 登录的票据；拿到后用 `poll_login_qr(LoginKind::Qq, ...)` 轮询。
pub async fn create_qq_app_login() -> Result<QrCode, ApiError> {
    Ok(login::create_app_qr().await.map_err(api_error)?)
}

pub async fn poll_login_qr(kind: LoginKind, qrsig: String) -> Result<QrStatus, ApiError> {
    Ok(match kind {
        LoginKind::Qq => login::poll_qr(&qrsig).await.map_err(api_error)?,
        LoginKind::Wechat => login::poll_wx_qr(&qrsig).await.map_err(api_error)?,
        LoginKind::QqMusic => login::poll_tme_qr(&qrsig).await.map_err(api_error)?,
    })
}

pub async fn login_with_cookie(cookie: String) -> Result<UserInfo, ApiError> {
    Ok(login::login_with_cookie(&cookie).await.map_err(api_error)?)
}

#[flutter_rust_bridge::frb(sync)]
pub fn current_user() -> Option<UserInfo> {
    client::core().session().map(|s| login::user_of(&s))
}

/// 登录凭证被服务器拒绝、已自动退出登录时推送原因。只在界面进程订阅。
pub fn watch_session_end(sink: StreamSink<SessionEndReason>) {
    client::on_session_end(move |reason| {
        let _ = sink.add(reason);
    });
}

/// 向服务器复核当前登录态，失效时通过 `watch_session_end` 推送。启动时调用。
pub async fn check_session() {
    client::verify_session().await
}

pub fn logout() -> Result<(), ApiError> {
    Ok(client::core().set_session(None).map_err(api_error)?)
}

pub fn clear_cache() -> Result<(), ApiError> {
    Ok(client::core().store.cache_clear().map_err(api_error)?)
}

/// 读取界面偏好（如语言），存放在 kv 表的 `pref:` 前缀下。
#[flutter_rust_bridge::frb(sync)]
pub fn get_pref(key: String) -> Option<String> {
    client::core().store.kv_get(&format!("pref:{key}"))
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_pref(key: String, value: String) -> Result<(), ApiError> {
    Ok(client::core()
        .store
        .kv_set(&format!("pref:{key}"), &value)
        .map_err(api_error)?)
}

/// 读最新版本的清单；`preview` 时包含预览版，`mirror` 时只走镜像。
pub async fn get_latest_update(preview: bool, mirror: bool) -> Result<UpdateInfo, ApiError> {
    Ok(crate::update::latest(preview, mirror).await.map_err(api_error)?)
}

/// 把 `tag` 发布里的 `asset` 下载到 `dest`，下完核对校验码。以结束事件收尾。
pub async fn download_update(
    tag: String,
    asset: UpdateAsset,
    dest: String,
    mirror: bool,
    sink: StreamSink<UpdateEvent>,
) {
    crate::update::download(&tag, &asset, std::path::Path::new(&dest), mirror, |e| {
        let _ = sink.add(e);
    })
    .await
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_update_download() {
    crate::update::cancel()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn api_boundary_only_checks_rejected_credentials() {
        for code in ["1000", "Some(1000)", "2000"] {
            let before = client::SESSION_CHECKS.with(|count| count.get());
            let error = anyhow::Error::new(ApiError::ServerError {
                api: "test".into(),
                code: code.into(),
            })
            .context("request context");
            let mapped = api_error(error);
            assert!(matches!(mapped, ApiError::ServerError { api, code: actual }
                if api == "test" && actual == code));
            assert_eq!(
                client::SESSION_CHECKS.with(|count| count.get()) - before,
                if code == "2000" { 0 } else { 1 }
            );
        }
        let before = client::SESSION_CHECKS.with(|count| count.get());
        let mapped = api_error(anyhow::anyhow!("local failure"));
        assert!(matches!(mapped, ApiError::Internal { .. }));
        let mapped = api_error(anyhow::Error::new(ApiError::NotLoggedIn));
        assert!(matches!(mapped, ApiError::NotLoggedIn));
        assert_eq!(client::SESSION_CHECKS.with(|count| count.get()), before);
    }
}
