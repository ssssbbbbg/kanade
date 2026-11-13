//! 歌手页、专辑页和评论。都是 Windows 客户端内嵌页（ct=20）的接口。

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::client::core;
use super::error::ApiError;
use super::music::webkit_comm;
use super::parse::{self, album_cover, first_s, n, s, singer_cover};
use crate::api::types::*;

async fn webkit(module: &str, method: &str, param: Value) -> Result<Value> {
    core().musicu_with_comm(module, method, param, webkit_comm()).await
}

/// 歌手资料、第一页歌曲和专辑一起取。
pub async fn singer_detail(mid: &str) -> Result<SingerDetail> {
    let c = core();
    let data = c
        .cached(&format!("singer:selected:{mid}"), 3600, || async {
            let (info, songs, albums, selected) = tokio::join!(
                webkit(
                    "music.musichallSinger.SingerInfoInter",
                    "GetSingerDetail",
                    json!({ "singer_mids": [mid], "pic": 1, "group_singer": 1, "wiki_singer": 1, "ex_singer": 1 }),
                ),
                singer_songs_raw(mid, 0, 30),
                singer_albums_raw(mid, 0, 30),
                webkit("music.musichallAlbum.SelectedAlbumServer", "SelectedAlbumList", json!({"singerMid": mid})),
            );
            Ok(json!({ "info": info?, "songs": songs?, "albums": albums?, "selected": selected? }))
        })
        .await?;
    let singer = &data["info"]["singer_list"][0];
    let basic = &singer["basic_info"];
    let avatar = s(&singer["pic"]["pic"]);
    Ok(SingerDetail {
        mid: mid.to_string(),
        name: s(&basic["name"]),
        avatar_url: if avatar.is_empty() { singer_cover(mid) } else { avatar },
        photo_url: parse::singer_photo(mid),
        description: s(&singer["ex_info"]["desc"]),
        songs: parse::songs(&data["songs"]["songList"]),
        song_total: n(&data["songs"]["totalNum"]) as u32,
        albums: albums(&data["albums"]["albumList"]),
        album_total: n(&data["albums"]["total"]) as u32,
        selected_albums: albums(&data["selected"]["albumList"]),
    })
}

pub async fn singer_social(mid: &str) -> Result<SingerSocial> {
    let c = core();
    let query = [("singermid", mid.into()), ("utf8", "1".into()), ("format", "json".into())];
    let (fans, guard, followed) = tokio::join!(
        c.get_json("https://c6.y.qq.com/rsc/fcgi-bin/fcg_order_singer_getnum.fcg", &query),
        webkit("music.UnifiedHomepage.UnifiedHomepageSrv", "GetHomepageIconForMedal",
            json!({"SingerMid": mid, "Uin": c.uin()})),
        super::social::singer_followed(mid),
    );
    let fans = fans?;
    for field in ["code", "subcode"] {
        let code = fans[field].as_i64().context(ApiError::bad_response("singer fans result code is missing"))?;
        if code != 0 { bail!(ApiError::ServerError {api: "fcg_order_singer_getnum".into(), code: code.to_string()}); }
    }
    Ok(SingerSocial {
        fans_count: fans["num"].as_u64().context(ApiError::bad_response("singer fans count is missing"))?,
        guard_title: guard_title(&guard?),
        followed: followed?,
    })
}

fn guard_title(data: &Value) -> String {
    data["NumButtonList"].as_array().into_iter().flatten()
        .find(|item| n(&item["ButtonType"]) == 9)
        .map(|item| s(&item["ButtonInfo"]["Title"])).unwrap_or_default()
}

pub async fn singer_video_tags(mid: &str) -> Result<Vec<VideoTag>> {
    let data = webkit("MvService.MvInfoProServer", "GetSingerMvTag", json!({"singermid": mid})).await?;
    Ok(data["list"].as_array().into_iter().flatten().map(|x| VideoTag { id: n(&x["id"]), name: s(&x["name"]) }).collect())
}

pub async fn singer_videos(mid: &str, name: &str, tag: i64, order: u32, begin: u32, num: u32) -> Result<SingerVideoPage> {
    let data = webkit("MvService.MvInfoProServer", "GetSingerMvList",
        json!({"singermid": mid, "tagid": tag, "start": begin, "count": num, "order": order})).await?;
    Ok(SingerVideoPage { videos: singer_video_list(&data["list"], name), total: n(&data["total"]) as u32 })
}

fn singer_video_list(list: &Value, name: &str) -> Vec<VideoBrief> {
    list.as_array().into_iter().flatten().filter(|x| !s(&x["vid"]).is_empty()).map(|x| VideoBrief {
        vid: s(&x["vid"]), name: s(&x["title"]), cover_url: s(&x["picurl"]),
        duration_secs: n(&x["duration"]) as u32, play_count: n(&x["playcnt"]) as u64,
        creator: name.into(), uploaded: false,
    }).collect()
}

async fn singer_songs_raw(mid: &str, begin: u32, num: u32) -> Result<Value> {
    webkit(
        "music.musichallSong.SongListInter",
        "GetSingerSongList",
        json!({ "singerMid": mid, "begin": begin, "num": num, "order": 1 }),
    )
    .await
}

async fn singer_albums_raw(mid: &str, begin: u32, num: u32) -> Result<Value> {
    // order=1 按时间，抓包里另有 order=0 的请求
    webkit(
        "music.musichallAlbum.AlbumListServer",
        "GetAlbumList",
        json!({ "singerMid": mid, "order": 1, "num": num, "begin": begin }),
    )
    .await
}

/// 歌手歌曲翻页，`begin` 从 0 开始。
pub async fn singer_songs(mid: &str, begin: u32, num: u32) -> Result<Vec<Song>> {
    let c = core();
    let data = c.cached(&format!("singer_songs:{mid}:{begin}:{num}"), 3600, || singer_songs_raw(mid, begin, num)).await?;
    Ok(parse::songs(&data["songList"]))
}

pub async fn singer_albums(mid: &str, begin: u32, num: u32) -> Result<Vec<AlbumBrief>> {
    let c = core();
    let data = c.cached(&format!("singer_albums:{mid}:{begin}:{num}"), 3600, || singer_albums_raw(mid, begin, num)).await?;
    Ok(albums(&data["albumList"]))
}

fn albums(list: &Value) -> Vec<AlbumBrief> {
    list.as_array()
        .into_iter()
        .flatten()
        .filter_map(|a| {
            let mid = s(&a["albumMid"]);
            (!mid.is_empty()).then(|| AlbumBrief {
                cover_url: album_cover(&mid),
                name: s(&a["albumName"]),
                publish_date: s(&a["publishDate"]),
                singer_name: s(&a["singerName"]),
                mid,
            })
        })
        .collect()
}

pub async fn album_detail(mid: &str) -> Result<AlbumDetail> {
    let c = core();
    let data = c
        .cached(&format!("album:{mid}"), 3600, || async {
            let (info, songs) = tokio::join!(
                webkit("music.musichallAlbum.AlbumInfoServer", "GetAlbumDetail", json!({ "albumMid": mid })),
                webkit(
                    "music.musichallAlbum.AlbumSongList",
                    "GetAlbumSongList",
                    json!({ "albumMid": mid, "begin": 0, "num": 1000, "order": 2 }),
                ),
            );
            Ok(json!({ "info": info?, "songs": songs? }))
        })
        .await?;
    let info = &data["info"];
    let basic = &info["basicInfo"];
    Ok(AlbumDetail {
        mid: mid.to_string(),
        id: n(&basic["albumID"]),
        name: s(&basic["albumName"]),
        cover_url: album_cover(mid),
        description: s(&basic["desc"]),
        publish_date: s(&basic["publishDate"]),
        company: s(&info["company"]["name"]),
        singers: info["singer"]["singerList"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|x| Singer { mid: s(&x["mid"]), name: s(&x["name"]) })
            .collect(),
        songs: parse::songs(&data["songs"]["songList"]),
    })
}

fn biz_type(target: CommentTarget) -> i64 {
    match target {
        CommentTarget::Song => 1,
        CommentTarget::Album => 2,
    }
}

/// 评论正文里的表情是 `[em]e400846[/em]` 这样的代码，界面上没法显示，去掉。
/// 换行在正文里是字面的 `\n` 两个字符，还原成换行。
fn clean_content(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find("[em]") {
        out.push_str(&rest[..start]);
        match rest[start..].find("[/em]") {
            Some(end) => rest = &rest[start + end + 5..],
            None => {
                rest = &rest[start..];
                break;
            }
        }
    }
    out.push_str(rest);
    out.replace("\\n", "\n").trim().to_string()
}

fn comment(v: &Value) -> Option<Comment> {
    let id = s(&v["CmId"]);
    if id.is_empty() {
        return None;
    }
    // PicSize 是 "700x1050" 这样的字符串
    let size = s(&v["PicSize"]);
    let (pic_width, pic_height) = size.split_once('x').map_or((0, 0), |(w, h)| (w.parse().unwrap_or(0), h.parse().unwrap_or(0)));
    Some(Comment {
        id,
        seq_no: s(&v["SeqNo"]),
        nick: s(&v["Nick"]),
        avatar_url: s(&v["Avatar"]),
        content: clean_content(&s(&v["Content"])),
        time_secs: n(&v["PubTime"]),
        praise_count: n(&v["PraiseNum"]) as u32,
        reply_count: n(&v["ReplyCnt"]) as u32,
        reply_to: first_s(&v["RepliedComments"][0], &["Nick"]),
        pic_url: s(&v["Pic"]),
        pic_width,
        pic_height,
    })
}

fn comments(list: &Value) -> Vec<Comment> {
    list["Comments"].as_array().into_iter().flatten().filter_map(comment).collect()
}

const COMMENT_READ: &str = "music.globalComment.CommentRead";
const COMMENT_PAGE_SIZE: usize = 15;

/// 翻页游标，整体序列化成字符串交给界面，下一页原样传回。各列表只用到其中一部分字段。
#[derive(Default, serde::Serialize, serde::Deserialize)]
#[serde(default)]
struct CommentCursor {
    page: u32,
    /// 上一页最后一条的 CmId / SeqNo / HotScore / RecScore / RankScore。
    id: String,
    seq_no: String,
    hot_score: String,
    rec_score: String,
    rank_score: String,
    total: u32,
    total_ver: String,
    /// 只有第一页的响应带 RspVer，后续页一直传它。
    rsp_ver: String,
    /// 推荐：下一页的 RecOffset。回复：已经取到的条数。
    offset: u32,
    /// 推荐：第一页给出的后续评论 id，每页按顺序取走 15 个。
    pool: Vec<String>,
}

impl CommentCursor {
    fn parse(cursor: &str) -> Result<Self> {
        if cursor.is_empty() {
            return Ok(Self::default());
        }
        serde_json::from_str(cursor).context(ApiError::bad_response("invalid comment cursor"))
    }

    /// 记下这一页的最后一条和版本号，页码加一。
    fn advance(mut self, data: &Value) -> Self {
        if let Some(last) = data["CommentList"]["Comments"].as_array().and_then(|a| a.last()) {
            self.id = s(&last["CmId"]);
            self.seq_no = s(&last["SeqNo"]);
            self.hot_score = s(&last["HotScore"]);
            self.rec_score = s(&last["RecScore"]);
            self.rank_score = s(&last["RankScore"]);
        }
        if self.page == 0 {
            self.rsp_ver = s(&data["RspVer"]);
        }
        self.total_ver = s(&data["TotalVer"]);
        self.page += 1;
        self
    }

    fn feed(self, comments: Vec<Comment>, has_more: bool) -> CommentFeed {
        CommentFeed {
            has_more: has_more && !comments.is_empty(),
            comments,
            total: self.total,
            cursor: serde_json::to_string(&self).unwrap_or_default(),
        }
    }
}

/// 推荐 / 最热 / 最新评论，参数照抄 Android 客户端（docs/qqmusic-comments-android-capture.md）。
/// `cursor` 第一页传空字符串，之后传上一页返回的 `cursor`。
pub async fn comment_feed(target: CommentTarget, id: i64, sort: CommentSort, cursor: &str) -> Result<CommentFeed> {
    let mut cur = CommentCursor::parse(cursor)?;
    let first = cur.page == 0;
    let mut param = json!({
        "BizType": biz_type(target),
        "BizId": id.to_string(),
        "PageSize": COMMENT_PAGE_SIZE,
        "LastCommentSeqNo": cur.seq_no,
        "PicEnable": 1,
        "LastTotal": cur.total,
        "LastTotalVer": if first { "0" } else { cur.total_ver.as_str() },
        "LastRspVer": cur.rsp_ver,
        "CmListUIVer": 1,
        "AudioEnable": 1,
    });
    let method = match sort {
        CommentSort::Recommend => {
            param["RecOffset"] = json!(cur.offset);
            param["LastHotScore"] = json!(cur.hot_score);
            param["LastRecScore"] = json!(cur.rec_score);
            param["FromParentCmId"] = json!("");
            param["FromCommentId"] = json!("");
            param["Flag"] = json!(if first { 1 } else { 0 });
            if !first {
                // 后续页不是按偏移取，而是把第一页给的 id 逐批交回去换正文
                let batch: Vec<String> = cur.pool.drain(..cur.pool.len().min(COMMENT_PAGE_SIZE)).collect();
                param["PageNum"] = json!(cur.page);
                param["HashTagID"] = json!("");
                param["CommentIds"] = json!(batch);
            }
            "GetRecCommentList"
        }
        CommentSort::Hot => {
            param["PageNum"] = json!(cur.page);
            param["HotType"] = json!(6);
            param["WithTop"] = json!(0);
            param["LastHotScore"] = json!(cur.hot_score);
            param["LastCommentId"] = json!(cur.id);
            param["HashTagID"] = json!("");
            "GetHotCommentList"
        }
        CommentSort::Latest => {
            param["PageNum"] = json!(cur.page);
            param["LastCommentId"] = json!(cur.id);
            param["SelfSeeEnable"] = json!(1);
            param["HashTagID"] = json!("");
            "GetNewCommentList"
        }
    };
    let data = webkit(COMMENT_READ, method, param).await?;
    let list = &data["CommentList"];
    if first {
        cur.pool = list["CommentIds"].as_array().into_iter().flatten().map(s).collect();
    }
    cur.total = n(&data["TotalCmNum"]) as u32;
    cur.offset = n(&list["NextOffset"]) as u32;
    let has_more = match sort {
        // 推荐的 HasMore 在没有后续 id 时也是 1（未登录就是这样），以 id 是否用完为准
        CommentSort::Recommend => !cur.pool.is_empty(),
        _ => n(&list["HasMore"]) == 1,
    };
    Ok(cur.advance(&data).feed(comments(list), has_more))
}

/// 某条评论下的回复，第一页 6 条，之后每页 5 条，与 Android 客户端一致。
pub async fn reply_feed(root_id: &str, cursor: &str) -> Result<CommentFeed> {
    let mut cur = CommentCursor::parse(cursor)?;
    let data = webkit(
        COMMENT_READ,
        "GetReplyCommentList",
        json!({
            "RootCmId": root_id,
            "PageNum": cur.page,
            "PageSize": if cur.page == 0 { 6 } else { 5 },
            "LastCommentSeqNo": cur.seq_no,
            "LastRankScore": cur.rank_score,
            "RankType": 1,
            "LastRspVer": cur.rsp_ver,
            "SelfSeeEnable": 1,
            "PicEnable": 1,
            "AudioEnable": 1,
        }),
    )
    .await?;
    let list = &data["CommentList"];
    let replies = comments(list);
    // 只有第一页给回复总数；HasMore 一直是 1，所以按已取到的条数判断
    if cur.page == 0 {
        cur.total = n(&list["Total"]) as u32;
    }
    cur.offset += replies.len() as u32;
    let has_more = cur.offset < cur.total;
    Ok(cur.advance(&data).feed(replies, has_more))
}

/// 播放页右滑的歌曲信息页，参数照抄 Android 客户端（docs/qqmusic-player-detail-android-capture.md）。
/// 各栏目分开请求，某一栏失败只让它为空，全部失败才报错。
pub async fn song_page(id: i64, mid: &str) -> Result<SongPage> {
    let c = core();
    let (detail, labels, ai, videos, similar, playlists) = tokio::join!(
        c.musicu("music.musichallSong.SongInfoServer", "GetSongDetail", json!({"songMid": mid})),
        c.musicu("music.recommend.TrackRelationServer", "GetSongLabels", json!({"songid": id})),
        c.musicu(
            "music.SearchConfig.AiInterpretationSvr",
            "GetAiInterpretation",
            json!({"id": id.to_string(), "keyword": "", "custom_params": {"from": "player_leftSlide"}}),
        ),
        c.musicu("MvService.MvInfoProServer", "GetSongRelatedMv", json!({"songid": id.to_string(), "songtype": 1, "lastmvid": 0})),
        c.musicu("music.recommend.TrackRelationServer", "GetSimilarSongs", json!({"songid": id})),
        related_playlists_raw(id, &[]),
    );
    let all = [detail, labels, ai, videos, similar, playlists];
    if all.iter().all(|r| r.is_err()) {
        let [first, ..] = all;
        return Err(first.unwrap_err());
    }
    let [detail, labels, ai, videos, similar, playlists] = all.map(|r| r.unwrap_or(Value::Null));
    Ok(song_page_from(&detail, &labels, &ai, &videos, &similar, &playlists))
}

fn song_page_from(detail: &Value, labels: &Value, ai: &Value, videos: &Value, similar: &Value, playlists: &Value) -> SongPage {
    let ai = &ai["aidirect_list"][0];
    let similar = &similar["vecSongNew"][0];
    SongPage {
        publish_date: s(&detail["basic"]["album"]["pubTime"]),
        // tagTxt 为空的标签文字由官方客户端自己填（如音频参数），这里没有，不显示
        tags: labels["labels"].as_array().into_iter().flatten()
            .map(|x| SongTag { text: s(&x["tagTxt"]), icon_url: s(&x["tagIcon"]) })
            .filter(|x| !x.text.is_empty())
            .collect(),
        ai_title: s(&ai["title"]),
        ai_content: s(&ai["content"]),
        videos: related_videos(&videos["list"]),
        similar_from: s(&similar["title_content"]),
        similar_songs: similar["songs"].as_array().into_iter().flatten().filter_map(|x| parse::song(&x["track"])).collect(),
        playlists: related_playlist_list(playlists),
    }
}

/// 歌曲的相关视频。没有歌手的是用户上传的视频。
fn related_videos(list: &Value) -> Vec<VideoBrief> {
    list.as_array().into_iter().flatten().filter(|x| !s(&x["vid"]).is_empty()).map(|x| {
        let singers: Vec<String> = x["singers"].as_array().into_iter().flatten().map(|singer| s(&singer["name"])).collect();
        VideoBrief {
            vid: s(&x["vid"]), name: s(&x["title"]), cover_url: s(&x["picurl"]),
            duration_secs: 0, play_count: n(&x["playcnt"]) as u64,
            uploaded: singers.is_empty(), creator: singers.join(" / "),
        }
    }).collect()
}

/// 信息页「相关歌单」换一批：`exclude` 是已经显示过的歌单 ID，服务端不再返回它们。
pub async fn related_playlists(id: i64, exclude: &[String]) -> Result<RelatedPlaylists> {
    let data = related_playlists_raw(id, exclude).await?;
    let code = n(&data["retcode"]);
    if code != 0 {
        bail!(ApiError::ServerError { api: "music.recommend.TrackRelationServer.GetRelatedPlaylist".into(), code: code.to_string() });
    }
    Ok(related_playlist_list(&data))
}

async fn related_playlists_raw(id: i64, exclude: &[String]) -> Result<Value> {
    // 首次打开不带 vecPlaylist；换一批时带上已显示的 tid，extra_info.module 为 "1"
    let param = if exclude.is_empty() {
        json!({"songid": id})
    } else {
        let tids: Vec<i64> = exclude.iter().filter_map(|x| x.parse().ok()).collect();
        json!({"songid": id, "vecPlaylist": tids, "extra_info": {"module": "1"}})
    };
    core().musicu("music.recommend.TrackRelationServer", "GetRelatedPlaylist", param).await
}

fn related_playlist_list(data: &Value) -> RelatedPlaylists {
    let list = &data["vecPlaylistNew"][0]["playlists"];
    RelatedPlaylists {
        playlists: list.as_array().into_iter().flatten().filter(|x| n(&x["tid"]) != 0).map(|x| PlaylistBrief {
            id: s(&x["tid"]), title: s(&x["title"]), cover_url: s(&x["cover"]),
            song_count: n(&x["songNum"]) as u32, play_count: n(&x["playCnt"]) as u64, creator: s(&x["creator"]),
        }).collect(),
        has_more: n(&data["hasMore"]) == 1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn song_page_reads_each_section_and_tolerates_missing_ones() {
        let detail = json!({"basic": {"album": {"mid": "004Frxzr1rthfN", "pubTime": "2026-05-07"}}});
        let labels = json!({"labels": [
            {"tagTxt": "", "tagType": 24, "tagIcon": "https://a"}, {"tagTxt": "85人在听", "tagType": 23, "tagIcon": "https://b"},
            {"tagTxt": "本周热播", "tagType": 9},
        ]});
        let ai = json!({"aidirect_list": [{"title": "标题", "content": "正文"}]});
        let videos = json!({"hasmore": 0, "list": [
            {"mvid": 52772404, "vid": "010Sz9DR1a8FZ9", "title": "翻唱", "picurl": "http://p", "playcnt": 4010, "singers": []},
            {"mvid": 293791, "vid": "w0026q7f01a", "title": "晴天", "picurl": "http://q", "playcnt": 1, "singers": [{"name": "周杰伦"}]},
            {"mvid": 1, "vid": "", "title": "无效"},
        ]});
        let similar = json!({"retcode": 0, "vecSong": [], "vecSongNew": [{
            "title_content": "Agera",
            "songs": [{"track": {"id": 734300451, "mid": "001QXnoJ42a97l", "name": "旧绪难平", "singer": [{"mid": "0015CE5d0H9fsE", "name": "Agera"}], "album": {"mid": "000Vj5fR0eQXFQ"}}}],
        }]});
        let playlists = json!({"retcode": 0, "hasMore": 1, "vecPlaylist": [], "vecPlaylistNew": [{"playlists": [
            {"tid": 7087747817_i64, "songNum": 31, "cover": "http://c", "title": "Summer Vibes", "creator": "QQ音乐官方歌单", "playCnt": "668357"},
        ]}]});
        let page = song_page_from(&detail, &labels, &ai, &videos, &similar, &playlists);
        assert_eq!(page.publish_date, "2026-05-07");
        let tags: Vec<_> = page.tags.iter().map(|t| (t.text.as_str(), t.icon_url.as_str())).collect();
        assert_eq!(tags, [("85人在听", "https://b"), ("本周热播", "")]);
        assert_eq!((page.ai_title.as_str(), page.ai_content.as_str()), ("标题", "正文"));
        assert_eq!(page.videos.len(), 2);
        assert!(page.videos[0].uploaded && page.videos[0].creator.is_empty());
        assert!(!page.videos[1].uploaded && page.videos[1].creator == "周杰伦");
        assert_eq!(page.similar_from, "Agera");
        assert_eq!(page.similar_songs[0].mid, "001QXnoJ42a97l");
        let p = &page.playlists;
        assert!(p.has_more);
        assert_eq!((p.playlists[0].id.as_str(), p.playlists[0].play_count), ("7087747817", 668357));

        let empty = song_page_from(&Value::Null, &Value::Null, &Value::Null, &Value::Null, &Value::Null, &Value::Null);
        assert!(empty.publish_date.is_empty() && empty.tags.is_empty() && empty.videos.is_empty());
        assert!(empty.similar_songs.is_empty() && empty.playlists.playlists.is_empty() && !empty.playlists.has_more);
    }

    #[test]
    fn guard_uses_display_title_instead_of_unrelated_zero_count() {
        let data = json!({"cnt": 0, "NumButtonList": [
            {"ButtonType": 1, "ButtonInfo": {"Title": "other"}},
            {"ButtonType": 9, "ButtonInfo": {"Title": "38万乐迷守护"}},
        ]});
        assert_eq!(guard_title(&data), "38万乐迷守护");
        assert_eq!(guard_title(&json!({"cnt": 380000})), "");
    }

    #[test]
    fn singer_video_list_uses_singer_fields_and_vid() {
        let videos = singer_video_list(&json!([
            {"vid": "video-id", "mvid": 123, "title": "MV", "picurl": "https://example.test/cover", "playcnt": 42, "duration": 169},
            {"mvid": 456, "title": "no VID"},
        ]), "singer");
        assert_eq!(videos.len(), 1);
        assert_eq!((videos[0].vid.as_str(), videos[0].name.as_str(), videos[0].play_count), ("video-id", "MV", 42));
    }

    #[test]
    fn strips_emoji_codes() {
        assert_eq!(clean_content("好听[em]e400846[/em][em]e1[/em]！"), "好听！");
        assert_eq!(clean_content("[em]broken"), "[em]broken");
        assert_eq!(clean_content("一\\n二\\n"), "一\n二");
    }

    #[test]
    fn parses_reply_target() {
        let c = comment(&json!({
            "CmId": "1!abc", "SeqNo": "16", "Nick": "a", "Content": "当然了", "PubTime": 1785267626,
            "PraiseNum": 2, "ReplyCnt": 0, "RepliedComments": [{ "Nick": "b", "Content": "x" }]
        }))
        .unwrap();
        assert_eq!(c.reply_to, "b");
        assert_eq!(c.praise_count, 2);
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn fetches_singer_and_album() {
        let singer = singer_detail("002mYUgi0lXd76").await.unwrap();
        assert!(!singer.name.is_empty() && !singer.songs.is_empty() && !singer.albums.is_empty(), "{singer:?}");
        let album = album_detail("00277xRX464rH4").await.unwrap();
        assert_eq!(album.id, 113947);
        assert!(!album.songs.is_empty());
        println!("singer songs={} albums={}", singer.song_total, singer.album_total);
    }

    #[test]
    fn parses_comment_picture() {
        let c = comment(&json!({"CmId": "1", "Pic": "https://example.test/a.jpg", "PicSize": "700x1050"})).unwrap();
        assert_eq!((c.pic_url.as_str(), c.pic_width, c.pic_height), ("https://example.test/a.jpg", 700, 1050));
        let plain = comment(&json!({"CmId": "2"})).unwrap();
        assert_eq!((plain.pic_url.as_str(), plain.pic_width, plain.pic_height), ("", 0, 0));
    }

    #[test]
    fn cursor_keeps_first_rsp_ver_and_last_comment() {
        let first = CommentCursor::default().advance(&json!({
            "RspVer": "r0", "TotalVer": "t0",
            "CommentList": {"Comments": [{"CmId": "a", "SeqNo": "1"}, {"CmId": "b", "SeqNo": "2", "HotScore": "9", "RankScore": "3"}]}
        }));
        let text = first.feed(vec![], true).cursor;
        let next = CommentCursor::parse(&text).unwrap().advance(&json!({"RspVer": "", "TotalVer": "t1", "CommentList": {"Comments": []}}));
        assert_eq!((next.page, next.rsp_ver.as_str(), next.total_ver.as_str()), (2, "r0", "t1"));
        assert_eq!((next.id.as_str(), next.seq_no.as_str(), next.hot_score.as_str(), next.rank_score.as_str()), ("b", "2", "9", "3"));
        assert!(CommentCursor::parse("not json").is_err());
    }

    /// 未登录：最热、最新、回复各翻几页不重复；推荐只有第一页。
    #[tokio::test]
    #[ignore = "需要联网"]
    async fn pages_android_comment_feeds() {
        async fn pages(sort: CommentSort, target: CommentTarget, id: i64, count: usize) -> Vec<CommentFeed> {
            let mut out: Vec<CommentFeed> = vec![];
            for _ in 0..count {
                let cursor = out.last().map_or(String::new(), |f| f.cursor.clone());
                out.push(comment_feed(target, id, sort, &cursor).await.unwrap());
            }
            out
        }
        fn unique(feeds: &[CommentFeed]) -> bool {
            let mut seen = std::collections::HashSet::new();
            feeds.iter().flat_map(|f| &f.comments).all(|c| seen.insert(c.id.clone()))
        }
        for (target, id) in [(CommentTarget::Song, 121345659), (CommentTarget::Album, 113947)] {
            for sort in [CommentSort::Hot, CommentSort::Latest] {
                let feeds = pages(sort, target, id, 3).await;
                println!("{target:?} {sort:?}: {:?} unique={}", feeds.iter().map(|f| (f.comments.len(), f.has_more, f.total)).collect::<Vec<_>>(), unique(&feeds));
                // 样本专辑只有几十条评论，翻不满三页，所以只对歌曲要求每页都满
                let full = target == CommentTarget::Album || feeds.iter().all(|f| f.comments.len() == 15 && f.has_more);
                assert!(full && !feeds[0].comments.is_empty() && feeds[0].total > 0 && unique(&feeds), "{target:?} {sort:?}");
            }
            let rec = pages(CommentSort::Recommend, target, id, 1).await;
            assert!(rec[0].comments.len() == 15 && !rec[0].has_more, "{target:?} 推荐");
        }
        let hot = pages(CommentSort::Hot, CommentTarget::Song, 121345659, 1).await;
        let root = hot[0].comments.iter().find(|c| c.reply_count > 12).expect("没有回复较多的热评");
        let mut replies: Vec<CommentFeed> = vec![];
        while replies.last().is_none_or(|f| f.has_more) {
            let cursor = replies.last().map_or(String::new(), |f| f.cursor.clone());
            replies.push(reply_feed(&root.id, &cursor).await.unwrap());
        }
        let got: usize = replies.iter().map(|f| f.comments.len()).sum();
        println!("replies: cnt={} total={} pages={} got={got}", root.reply_count, replies[0].total, replies.len());
        assert!(replies[0].comments.len() == 6 && replies[1].comments.len() == 5 && unique(&replies));
        assert_eq!(got as u32, replies[0].total, "回复没有取完");
    }
}
