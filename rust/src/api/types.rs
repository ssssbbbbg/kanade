//! 暴露给 Dart 的数据结构。

use crate::api::error::ApiError;

#[derive(Debug, Clone)]
pub struct Singer {
    pub mid: String,
    pub name: String,
}

#[derive(Debug, Clone)]
pub struct Song {
    pub id: i64,
    pub mid: String,
    pub name: String,
    pub singers: Vec<Singer>,
    pub album_mid: String,
    pub album_name: String,
    pub duration_secs: u32,
    /// 拼接播放文件名用的 media_mid，大多数情况下和 mid 一样。
    pub media_mid: String,
    pub cover_url: String,
    /// 需要会员才能播放。
    pub vip: bool,
    pub has_hq: bool,
    pub has_flac: bool,
    /// 歌曲关联的视频 VID；数字 mv.id 为 0 时也可能有值。
    pub mv_vid: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Quality {
    /// AAC 96kbps（C400 .m4a），非会员最容易拿到
    Low,
    /// MP3 128kbps（M500）
    Standard,
    /// MP3 320kbps（M800）
    High,
    /// FLAC（F000）
    Lossless,
    Master,
    Hires,
    Atmos,
    Atmos51,
    Atmos71,
    Dolby,
    Dts,
    /// 360 Reality Audio（RA04 .mp4，MPEG-H 3D Audio）
    Ra360,
    Ogg640,
    Ogg320,
    Ogg192,
    Ogg96,
    Aac192,
    Aac48,
    Aicodec,
}

/// 音质不可用的原因，文案由 Dart 侧翻译。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QualityUnavailableReason {
    /// 播放器暂不支持此格式
    Unsupported,
    /// 暂未通过播放验证
    Unverified,
    /// 当前账号无权限
    NoPermission,
    /// 播放设备受限
    DeviceRestricted,
    /// 暂无可用链接
    NoLink,
    /// 音质验证失败，请稍后重试
    VerifyFailed,
    /// 音频文件暂不可用
    FileUnavailable,
}

#[derive(Debug, Clone)]
pub struct QualityOption {
    pub quality: Quality,
    pub available: bool,
    /// 无权限、文件不可用或播放器尚未支持的原因；可用时为 None。
    pub reason: Option<QualityUnavailableReason>,
}

#[derive(Clone)]
pub struct SongUrl {
    pub url: String,
    /// 实际拿到的音质（请求的音质不可用时会自动降级）。
    pub quality: Quality,
    /// 加密音源的密钥，由调用方交给本机音频中转。
    pub ekey: Option<String>,
}

impl std::fmt::Debug for SongUrl {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SongUrl")
            .field("quality", &self.quality)
            .finish_non_exhaustive()
    }
}

/// 本地缓存的歌曲文件。
#[derive(Debug, Clone)]
pub struct CachedAudio {
    pub path: String,
    pub quality: Quality,
}

#[derive(Debug, Clone)]
pub struct LyricLine {
    pub time_ms: u32,
    pub text: String,
    /// 翻译，没有就是空字符串。
    pub trans: String,
}

#[derive(Debug, Clone)]
pub struct Lyric {
    pub lines: Vec<LyricLine>,
    /// 纯文本歌词（没有时间轴），lines 为空时用它。
    pub plain: String,
}

/// 高潮片段，毫秒。见 docs/qqmusic-chorus-capture.md。
#[derive(Debug, Clone)]
pub struct ChorusRange {
    pub start_ms: u32,
    pub end_ms: u32,
}

#[derive(Debug, Clone)]
pub struct PlaylistBrief {
    pub id: String,
    pub title: String,
    pub cover_url: String,
    pub song_count: u32,
    pub play_count: u64,
    pub creator: String,
}

#[derive(Debug, Clone)]
pub struct PlaylistDetail {
    pub id: String,
    pub title: String,
    pub cover_url: String,
    pub description: String,
    pub creator: String,
    pub songs: Vec<Song>,
}

#[derive(Debug, Clone)]
pub struct TopList {
    pub top_id: i64,
    pub title: String,
    pub cover_url: String,
    pub period: String,
    /// 榜单前几名的预览，形如“歌名 - 歌手”。
    pub preview: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct TopListGroup {
    pub name: String,
    pub lists: Vec<TopList>,
}

#[derive(Debug, Clone)]
pub struct TopListDetail {
    pub top_id: i64,
    pub title: String,
    pub cover_url: String,
    pub description: String,
    pub period: String,
    pub songs: Vec<Song>,
}

/// 搜索分类，对应 Windows 客户端搜索结果页的标签。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SearchKind {
    Song,
    Singer,
    Album,
    Playlist,
    /// 官方 MV 和用户上传的视频混在一起。
    Video,
    /// 按歌词搜歌，结果仍是歌曲，另附命中的歌词片段。
    Lyric,
    User,
}

#[derive(Debug, Clone)]
pub struct UserBrief {
    /// 加密的账号编号（encrypt_uin），打开用户主页用；搜索结果里没有明文账号。
    pub euin: String,
    pub name: String,
    pub avatar_url: String,
    pub fans_count: u64,
    pub playlist_count: u32,
    /// 认证说明，比如“《鸣潮》先约电台团队推出的电台栏目”，可能为空。
    pub description: String,
}

#[derive(Debug, Clone)]
pub struct UserProfile {
    pub euin: String,
    pub name: String,
    pub avatar_url: String,
    pub fans_count: u64,
    pub follow_count: u64,
    /// 简介，即认证说明（QQ 音乐没有用户自写的简介）；没认证为空。
    pub intro: String,
    /// 公开歌单数；主页没有歌单标签时为 0。
    pub playlist_count: u32,
    pub followed: bool,
    pub is_self: bool,
    pub playlists_hidden: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UserAssetKind {
    Song,
    Playlist,
    Album,
    Video,
}

#[derive(Debug, Clone, Default)]
pub struct UserAssetPage {
    pub songs: Vec<Song>,
    pub playlists: Vec<PlaylistBrief>,
    pub albums: Vec<AlbumBrief>,
    pub videos: Vec<VideoBrief>,
    pub has_more: bool,
    pub hidden: bool,
}

#[derive(Debug, Clone)]
pub struct UserPlaylistPage {
    pub playlists: Vec<PlaylistBrief>,
    pub has_more: bool,
}

/// MV 的一档清晰度。
#[derive(Debug, Clone)]
pub struct MvStream {
    /// 画面高度：360 / 480 / 720 / 1080。
    pub height: u32,
    pub url: String,
    pub size: u64,
}

#[derive(Debug, Clone)]
pub struct MvDetail {
    pub vid: String,
    pub name: String,
    pub cover_url: String,
    pub singers: Vec<Singer>,
    /// 用户上传的视频才有。
    pub uploader: String,
    pub duration_secs: u32,
    pub play_count: u64,
    /// 形如 2026-09-17，可能为空。
    pub publish_date: String,
    pub description: String,
    /// 从低到高；没有权限或下架时为空。
    pub streams: Vec<MvStream>,
}

#[derive(Debug, Clone)]
pub struct VideoBrief {
    /// 字符串 VID，取 MV 详情和播放地址用；不能用数字 mv_id 代替。
    pub vid: String,
    pub name: String,
    pub cover_url: String,
    pub duration_secs: u32,
    pub play_count: u64,
    /// 官方 MV 是歌手名，用户上传的是上传者昵称。
    pub creator: String,
    /// 用户上传，而不是官方 MV。
    pub uploaded: bool,
}

/// 播放页右滑的歌曲信息页。哪一栏没有内容就是空的。
#[derive(Debug, Clone)]
pub struct SongPage {
    /// 发行日期，`YYYY-MM-DD`。
    pub publish_date: String,
    /// 「85人在听」「本周热播」这类标签，按上游顺序。
    pub tags: Vec<SongTag>,
    /// AI 解读的标题和全文。
    pub ai_title: String,
    pub ai_content: String,
    /// 精选视频。
    pub videos: Vec<VideoBrief>,
    /// 「听「X」的也在听」里的 X。
    pub similar_from: String,
    pub similar_songs: Vec<Song>,
    pub playlists: RelatedPlaylists,
}

/// 信息页标签。有的只是一个数字（热度），要配上图标才看得懂。
#[derive(Debug, Clone)]
pub struct SongTag {
    pub text: String,
    /// 白色线条小图标，可能为空。
    pub icon_url: String,
}

#[derive(Debug, Clone)]
pub struct RelatedPlaylists {
    pub playlists: Vec<PlaylistBrief>,
    /// 还能换一批。
    pub has_more: bool,
}

#[derive(Debug, Clone)]
pub struct SingerBrief {
    pub mid: String,
    pub name: String,
    pub avatar_url: String,
    pub song_count: u32,
    pub album_count: u32,
}

/// 一页搜索结果，只有所搜分类对应的列表有内容。
#[derive(Debug, Clone)]
pub struct SearchResult {
    pub songs: Vec<Song>,
    /// 歌词搜索时与 songs 一一对应的命中歌词，没找到命中行时为空字符串；其他分类为空列表。
    pub lyric_snippets: Vec<String>,
    pub singers: Vec<SingerBrief>,
    pub albums: Vec<AlbumBrief>,
    pub playlists: Vec<PlaylistBrief>,
    pub videos: Vec<VideoBrief>,
    pub users: Vec<UserBrief>,
    pub total: u32,
    /// 还有下一页。返回条数可能多于请求的每页条数，不能用条数判断。
    pub has_more: bool,
}

/// 推荐页的一个区块；一个区块要么是歌曲，要么是歌单。
#[derive(Debug, Clone)]
pub struct RecommendSection {
    pub title: String,
    pub songs: Vec<Song>,
    pub playlists: Vec<PlaylistBrief>,
    /// 单独刷新这一栏时传给 `refresh_recommend_section`；为空表示这一栏不能单独刷新。
    pub refresh: String,
}

#[derive(Debug, Clone)]
pub struct RecommendFeed {
    pub sections: Vec<RecommendSection>,
    /// “刷歌模式”入口给的起始歌曲 id，传给 `get_radar_songs`；没有入口时为空。
    pub radar_seed: Vec<i64>,
    /// 刷歌入口卡的封面（推荐歌曲的专辑图，每次可能不同），可能为空。
    pub radar_cover: String,
}

/// 专属乐流的卡片种类。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeedCardKind {
    /// 单曲：`songs` 只有一首，`tag` 是一句评论标签（可能为空）。
    Song,
    /// 一组三首，如“重温曾经你最爱听的歌”：`title` 是组名，`songs` 是这几首。
    Group,
    /// 歌单：`playlist` 有值。
    Playlist,
}

#[derive(Debug, Clone)]
pub struct FeedCard {
    pub kind: FeedCardKind,
    pub title: String,
    pub tag: String,
    pub songs: Vec<Song>,
    pub playlist: Option<PlaylistBrief>,
}

/// 「自定义推荐页」的一项：首页最上面那排卡片里显示哪些，跟着账号走，官方手机版改了这里也跟着变。
#[derive(Debug, Clone)]
pub struct ForyouItem {
    pub id: String,
    pub title: String,
    /// 固定显示、不能取消（猜你喜欢、每日30首）。
    pub fixed: bool,
    pub chosen: bool,
}

/// 专属乐流的一页。`seen` 是这页卡片的去重标识，翻下一页时连同之前所有页的一起传回去。
#[derive(Debug, Clone)]
pub struct FeedColumnPage {
    pub cards: Vec<FeedCard>,
    pub seen: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct HotKeyword {
    pub title: String,
    /// 实际拿去搜索的词，通常和 title 一样。
    pub query: String,
    /// 比如“正在热搜”，可能为空。
    pub description: String,
}

#[derive(Debug, Clone)]
pub struct HotSearch {
    pub hot: Vec<HotKeyword>,
    /// 个性化的“猜你想搜”，只有登录后才有。
    pub recommended: Vec<HotKeyword>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SuggestionKind {
    Song,
    Singer,
    Album,
}

#[derive(Debug, Clone)]
pub struct SearchSuggestion {
    pub kind: SuggestionKind,
    pub title: String,
    /// 歌手名；歌手条目为空。
    pub subtitle: String,
}

#[derive(Debug, Clone)]
pub struct UserInfo {
    pub uin: String,
    pub nickname: String,
    pub avatar_url: String,
}

/// 登录态被服务器拒绝、已自动退出的原因。服务器只回 1000，原因按凭证有效期推断。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionEndReason {
    /// 已过凭证有效期。
    Expired,
    /// 有效期内被注销：其他设备登录挤下线、在登录设备管理里删除了本设备、改密码等。
    Revoked,
    /// 不知道凭证有效期（Cookie 登录或旧版本保存的登录态）。
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoginKind {
    Qq,
    Wechat,
    /// 用 QQ 音乐 App 授权，沿用 App 当前登录的账号（QQ 或微信）。
    QqMusic,
}

#[derive(Debug, Clone)]
pub struct QrCode {
    /// 二维码图片字节（QQ 是 PNG，微信是 JPEG）。
    pub image: Vec<u8>,
    /// 轮询时原样传回（QQ 是 qrsig，微信是 uuid）。
    pub qrsig: String,
    /// 同一台手机跳转登录用的链接：`create_qq_app_login` 的票据是 txz.qq.com 链接，
    /// QQ 音乐登录是授权页地址；其余为空。
    pub url: String,
}

#[derive(Debug, Clone)]
pub enum QrStatus {
    Waiting,
    Scanned,
    Expired,
    Refused,
    Success { user: UserInfo },
}

/// 最近播放里歌曲以外的分类，各自按最后播放时间从新到旧。
#[derive(Debug, Clone)]
pub struct RecentCollections {
    pub albums: Vec<AlbumBrief>,
    pub playlists: Vec<PlaylistBrief>,
    pub videos: Vec<VideoBrief>,
    pub books: Vec<RecentBook>,
    /// 音乐雷达：最近听过的个性电台，用 [crate::api::music::get_radio_songs] 播放。
    pub radios: Vec<RecentRadio>,
}

#[derive(Debug, Clone)]
pub struct RecentRadio {
    pub id: i64,
    pub name: String,
    pub cover_url: String,
}

/// 最近播放的有声节目；episode 是上次听到的那一集，可以直接播放。
#[derive(Debug, Clone)]
pub struct RecentBook {
    pub name: String,
    pub cover_url: String,
    pub episode: Option<Song>,
}

#[derive(Debug, Clone)]
pub struct AlbumBrief {
    pub mid: String,
    pub name: String,
    pub cover_url: String,
    /// 形如 2005-08-12，可能为空。
    pub publish_date: String,
    pub singer_name: String,
}

#[derive(Debug, Clone)]
pub struct SingerDetail {
    pub mid: String,
    pub name: String,
    pub avatar_url: String,
    /// 800×800 的大图，歌手页顶部铺满用。
    pub photo_url: String,
    pub description: String,
    /// 第一页热门歌曲，更多用 `get_singer_songs` 翻页。
    pub songs: Vec<Song>,
    pub song_total: u32,
    pub albums: Vec<AlbumBrief>,
    pub album_total: u32,
    pub selected_albums: Vec<AlbumBrief>,
}

#[derive(Debug, Clone)]
pub struct SingerSocial {
    pub fans_count: u64,
    /// 服务端展示文案，不能由文案反推精确守护人数。
    pub guard_title: String,
    pub followed: bool,
}

#[derive(Debug, Clone)]
pub struct VideoTag {
    pub id: i64,
    pub name: String,
}

#[derive(Debug, Clone)]
pub struct SingerVideoPage {
    pub videos: Vec<VideoBrief>,
    pub total: u32,
}

#[derive(Debug, Clone)]
pub struct AlbumDetail {
    pub mid: String,
    /// 数字 id，取评论用。
    pub id: i64,
    pub name: String,
    pub cover_url: String,
    pub description: String,
    pub publish_date: String,
    pub company: String,
    pub singers: Vec<Singer>,
    pub songs: Vec<Song>,
}

/// 评论挂在哪类对象下面。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommentTarget {
    /// id 是歌曲的数字 id
    Song,
    /// id 是专辑的数字 id
    Album,
}

#[derive(Debug, Clone)]
pub struct Comment {
    pub id: String,
    /// 翻页时传回的游标。
    pub seq_no: String,
    pub nick: String,
    pub avatar_url: String,
    pub content: String,
    /// Unix 秒。
    pub time_secs: i64,
    pub praise_count: u32,
    pub reply_count: u32,
    /// 回复列表里被回复的人，没有就是空字符串。
    pub reply_to: String,
    /// 评论里的图片，没有就是空字符串。
    pub pic_url: String,
    /// 图片的像素尺寸，没有图片或没给尺寸时是 0。
    pub pic_width: u32,
    pub pic_height: u32,
}

/// 评论列表的排序，对应 Android 评论页的推荐 / 最热 / 最新。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommentSort {
    /// 需要登录才能翻页，未登录只有第一页。
    Recommend,
    Hot,
    Latest,
}

/// 一页评论或回复。
#[derive(Debug, Clone)]
pub struct CommentFeed {
    pub comments: Vec<Comment>,
    /// 评论总数；回复列表里是这条评论的回复数。
    pub total: u32,
    pub has_more: bool,
    /// 取下一页时原样传回，第一页传空字符串。
    pub cursor: String,
}

/// 当前账号自己创建的歌单，加歌和红心用。
#[derive(Debug, Clone)]
pub struct MyPlaylist {
    /// 201 是“我喜欢”。
    pub dir_id: i64,
    pub tid: i64,
    pub name: String,
    pub cover_url: String,
    pub song_count: u32,
}

/// 发布页上的一个安装文件。
#[derive(Debug, Clone)]
pub struct UpdateAsset {
    pub name: String,
    pub size: i64,
    /// 小写十六进制。
    pub sha256: String,
}

/// 发布流程生成的版本清单。
#[derive(Debug, Clone)]
pub struct UpdateInfo {
    /// 发布用的 tag，如 `v1.3.0-beta.1`。
    pub tag: String,
    pub prerelease: bool,
    /// 发布日期，`YYYY-MM-DD`。
    pub date: String,
    /// Markdown 格式的更新说明。
    pub notes: String,
    pub assets: Vec<UpdateAsset>,
}

/// 下载更新时推给 Dart 的进度；每次下载以 `Done`、`Corrupted`、`Failed` 或 `Cancelled` 结束。
#[derive(Debug, Clone)]
pub enum UpdateEvent {
    /// 连上了下载源（`GitHub` 或镜像域名）。
    Connected { source: String },
    Progress { received: i64, total: i64 },
    Done,
    /// 下完的文件和清单里的校验码对不上，已删除。
    Corrupted,
    Failed { error: ApiError },
    Cancelled,
}
