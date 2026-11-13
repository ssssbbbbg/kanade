//! 搜索、播放链接、歌词、榜单、歌单。

use anyhow::{bail, Context, Result};
use base64::Engine;
use serde_json::{json, Value};

use super::client::core;
use super::error::ApiError;
use super::parse::{self, first_s, n, s};
use super::lyric;
use super::sign::hash33;
use super::quality::{file_name, playback_chain, stream_available};
use crate::api::types::*;

fn search_id() -> String {
    // Windows 客户端抓包中的 searchid 为 37 位大写十六进制字符串。
    format!("{}{:05X}", uuid::Uuid::new_v4().simple(), rand::random::<u32>() & 0xfffff).to_uppercase()
}

pub async fn search_songs(keyword: &str, page: u32, page_size: u32) -> Result<SearchResult> {
    search(keyword, SearchKind::Song, page, page_size).await
}

/// 歌曲更多菜单的“查找相似歌曲”，按上游顺序返回。
pub async fn similar_songs(song_id: i64) -> Result<Vec<Song>> {
    let data = core().musicu("music.recommend.TrackRelationServer", "GetSimilarSongs", json!({"songid": song_id})).await?;
    similar_song_list(&data)
}

fn similar_song_list(data: &Value) -> Result<Vec<Song>> {
    let code = data["retcode"].as_i64().context(ApiError::bad_response("similar songs response has no retcode"))?;
    if code != 0 {
        bail!(ApiError::ServerError { api: "music.recommend.TrackRelationServer.GetSimilarSongs".into(), code: code.to_string() });
    }
    let list = data["vecSong"].as_array().context(ApiError::bad_response("similar songs response has no vecSong"))?;
    Ok(list.iter().filter_map(|item| parse::song(&item["track"])).collect())
}

/// 各分类在 Windows 客户端抓包中的 search_type、remoteplace，以及结果在 `body` 下的字段名。
fn search_spec(kind: SearchKind) -> (u32, &'static str, &'static str) {
    match kind {
        SearchKind::Song => (0, "txt.newclient.top", "song"),
        SearchKind::Singer => (1, "sizer.newclient.singer", "singer"),
        SearchKind::Album => (2, "sizer.newclient.album", "album"),
        SearchKind::Playlist => (3, "sizer.newclient.playlist", "songlist"),
        SearchKind::Video => (4, "sizer.newclient.mv", "mv"),
        SearchKind::Lyric => (7, "txt.newclient.top", "song"),
        SearchKind::User => (8, "sizer.newclient.users", "user"),
    }
}

/// 分类搜索，`page` 从 1 开始。歌曲搜索未登录时沿用旧接口；
/// 旧接口没有其他分类，其他分类始终走 PC 接口。
pub async fn search(keyword: &str, kind: SearchKind, page: u32, page_size: u32) -> Result<SearchResult> {
    let c = core();
    let desktop = c.session().is_some() || kind != SearchKind::Song;
    let (search_type, remoteplace, group) = search_spec(kind);
    let key = if desktop {
        format!("search:desktop:{search_type}:{keyword}:{page}:{page_size}")
    } else {
        format!("search:{keyword}:{page}:{page_size}")
    };
    let data = c
        .cached(&key, 600, || async {
            if desktop {
                let d = c.desktop_musicu(
                    "music.search.SearchCgiService",
                    "DoSearchForQQMusicDesktop",
                    json!({
                        "query": keyword,
                        "search_type": search_type,
                        "num_per_page": page_size,
                        "page_num": page,
                        "remoteplace": remoteplace,
                        "searchid": search_id(),
                        "grp": 1,
                    }),
                ).await?;
                let meta = &d["meta"];
                return Ok(json!({ "list": d["body"][group]["list"], "total": meta["sum"], "nextpage": meta["nextpage"] }));
            }
            let d = c.get_json(
                "https://c.y.qq.com/soso/fcgi-bin/client_search_cp",
                &[
                    ("w", keyword.to_string()),
                    ("p", page.to_string()),
                    ("n", page_size.to_string()),
                    ("format", "json".into()),
                ],
            ).await?;
            let song = &d["data"]["song"];
            Ok(json!({ "list": song["list"], "total": song["totalnum"] }))
        })
        .await?;
    Ok(search_result(kind, keyword, page, page_size, &data))
}

fn search_result(kind: SearchKind, keyword: &str, page: u32, page_size: u32, data: &Value) -> SearchResult {
    let list = &data["list"];
    let items = list.as_array().map(Vec::as_slice).unwrap_or_default();
    let total = n(&data["total"]) as u32;
    // 歌手搜索最后一页 nextpage 为 -1；旧接口没有这个字段，按总数估算
    let has_more = !items.is_empty()
        && match &data["nextpage"] {
            Value::Null => page * page_size < total,
            next => n(next) > 0,
        };
    let mut r = SearchResult {
        songs: vec![],
        lyric_snippets: vec![],
        singers: vec![],
        albums: vec![],
        playlists: vec![],
        videos: vec![],
        users: vec![],
        total,
        has_more,
    };
    match kind {
        SearchKind::Song => r.songs = parse::songs(list),
        SearchKind::Lyric => {
            for item in items {
                if let Some(song) = parse::song(item) {
                    r.lyric_snippets.push(lyric_snippet(item, keyword));
                    r.songs.push(song);
                }
            }
        }
        SearchKind::Singer => {
            r.singers = items
                .iter()
                .map(|x| SingerBrief {
                    mid: s(&x["singerMID"]),
                    name: s(&x["singerName"]),
                    avatar_url: parse::singer_cover(&s(&x["singerMID"])),
                    song_count: n(&x["songNum"]) as u32,
                    album_count: n(&x["albumNum"]) as u32,
                })
                .filter(|x| !x.mid.is_empty())
                .collect()
        }
        SearchKind::Album => {
            r.albums = items
                .iter()
                .map(|x| {
                    let singers: Vec<String> = x["singer_list"].as_array().into_iter().flatten().map(|x| s(&x["name"])).filter(|x| !x.is_empty()).collect();
                    AlbumBrief {
                        mid: s(&x["albumMID"]),
                        name: s(&x["albumName"]),
                        cover_url: parse::album_cover(&s(&x["albumMID"])),
                        publish_date: s(&x["publicTime"]),
                        singer_name: if singers.is_empty() { s(&x["singerName"]) } else { singers.join(" / ") },
                    }
                })
                .filter(|x| !x.mid.is_empty())
                .collect()
        }
        SearchKind::Playlist => {
            r.playlists = items
                .iter()
                .map(|x| PlaylistBrief {
                    id: s(&x["dissid"]),
                    title: s(&x["dissname"]),
                    cover_url: s(&x["imgurl"]),
                    song_count: n(&x["song_count"]) as u32,
                    play_count: n(&x["listennum"]) as u64,
                    creator: s(&x["creator"]["name"]),
                })
                .filter(|x| !x.id.is_empty() && x.id != "0")
                .collect()
        }
        SearchKind::Video => {
            r.videos = items
                .iter()
                .map(|x| {
                    let uploader = s(&x["uploader_nick"]);
                    let singer = s(&x["singer_name"]);
                    VideoBrief {
                        vid: s(&x["v_id"]),
                        name: s(&x["mv_name"]),
                        cover_url: s(&x["mv_pic_url"]),
                        duration_secs: n(&x["duration"]) as u32,
                        play_count: n(&x["play_count"]) as u64,
                        uploaded: singer.is_empty() && !uploader.is_empty(),
                        creator: if singer.is_empty() { uploader } else { singer },
                    }
                })
                .filter(|x| !x.vid.is_empty())
                .collect()
        }
        SearchKind::User => {
            r.users = items
                .iter()
                .map(|x| UserBrief {
                    euin: s(&x["encrypt_uin"]),
                    name: s(&x["title"]),
                    // iconurl 是认证角标，不是头像
                    avatar_url: s(&x["pic"]),
                    fans_count: n(&x["fans_num"]) as u64,
                    playlist_count: n(&x["diss_num"]) as u32,
                    description: s(&x["identify_title"]),
                })
                .filter(|x| !x.euin.is_empty())
                .collect()
        }
    }
    r
}

/// 歌词搜索的 `lyric` / `lyric_hilight` 实测常为空，歌词文本在 `content` 里，
/// 第一行是“歌名 - 歌手”。取包含关键词的前两行；没有就用高亮字段去掉标签。
fn lyric_snippet(item: &Value, keyword: &str) -> String {
    let needle = keyword.trim().to_lowercase();
    let content = s(&item["content"]);
    let matched: Vec<&str> = content
        .lines()
        .skip(1)
        .map(str::trim)
        .filter(|line| !needle.is_empty() && line.to_lowercase().contains(&needle))
        .collect();
    // 搜人名时命中的多是“曲：周杰伦”这类署名行，有真正的歌词行就优先用
    let is_credit = |line: &&str| line.chars().take(16).any(|c| c == '：' || c == ':');
    let lyrics: Vec<&str> = matched.iter().copied().filter(|l| !is_credit(l)).collect();
    let hits: Vec<&str> = if lyrics.is_empty() { matched } else { lyrics }.into_iter().take(2).collect();
    if !hits.is_empty() {
        return hits.join(" / ");
    }
    first_s(item, &["lyric_hilight", "lyric"]).replace("<em>", "").replace("</em>", "").lines().map(str::trim).filter(|x| !x.is_empty()).take(2).collect::<Vec<_>>().join(" / ")
}

fn hot_keywords(list: &Value) -> Vec<HotKeyword> {
    list.as_array()
        .map(|a| {
            a.iter()
                .map(|k| HotKeyword { title: s(&k["title"]), query: s(&k["query"]), description: s(&k["description"]) })
                .filter(|k| !k.query.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

/// Windows 客户端的热搜；登录后额外带个性化的“猜你想搜”。
pub async fn hot_search() -> Result<HotSearch> {
    let c = core();
    let uin: i64 = c.uin().parse().unwrap_or(0);
    let data = c
        .cached(&format!("hotkey:desktop:{uin}"), 600, || {
            c.desktop_musicu(
                "tencent_musicsoso_hotkey.HotkeyService",
                "GetHotkeyForQQMusicPC",
                json!({ "search_id": "", "uin": uin }),
            )
        })
        .await?;
    Ok(HotSearch { hot: hot_keywords(&data["vec_hotkey"]), recommended: hot_keywords(&data["vec_reckey"]) })
}

/// Windows 客户端的搜索联想，支持拼音和首字母。
pub async fn search_suggestions(query: &str) -> Result<Vec<SearchSuggestion>> {
    let c = core();
    let data = c
        .cached(&format!("smartbox:desktop:{query}"), 600, || {
            c.desktop_musicu(
                "music.smartboxCgi.SmartBoxCgi",
                "GetSmartBoxResultForPc",
                json!({ "num_per_page": 4, "query": query, "search_id": search_id() }),
            )
        })
        .await?;
    let data = &data["data"];
    let mut out = Vec::new();
    for (kind, group, list) in [
        (SuggestionKind::Song, "song", "song_list"),
        (SuggestionKind::Singer, "singer", "singer_list"),
        (SuggestionKind::Album, "album", "album_list"),
    ] {
        for item in data[group][list].as_array().into_iter().flatten() {
            let title = s(&item["name"]);
            if title.is_empty() {
                continue;
            }
            let subtitle = if kind == SuggestionKind::Singer { String::new() } else { s(&item["singer"]) };
            out.push(SearchSuggestion { kind, title, subtitle });
        }
    }
    Ok(out)
}

/// 从请求的音质开始逐级降级，直到拿到可用链接。
pub async fn song_url(mid: &str, media_mid: &str, quality: Quality) -> Result<SongUrl> {
    let chain = playback_chain(quality)?;
    let c = core();
    let desktop = c.session().is_some();
    let vkey_apis: &[(&str, &str)] = if desktop {
        &[("music.vkey.GetVkey", "UrlGetVkey")]
    } else {
        &[("music.vkey.GetVkey", "UrlGetVkey"), ("vkey.GetVkeyServer", "CgiGetVkey")]
    };
    let mut last_err = None;
    let mut got_response = false;
    for &q in &chain {
        let plain_apis = if super::quality::uses_plain_source(q) {
            vkey_apis
        } else {
            &[]
        };
        for &(module, method) in plain_apis {
            let mut param = json!({
                "guid": if desktop { &c.desktop_guid } else { &c.guid },
                "songmid": [mid],
                "songtype": [0],
                "uin": c.uin(),
                "loginflag": 1,
                "platform": "20",
                "filename": [file_name(q, media_mid)?],
            });
            let response = if desktop {
                param["ctx"] = json!(0);
                c.desktop_musicu(module, method, param).await
            } else {
                c.musicu(module, method, param).await
            };
            let data = match response {
                Ok(d) => {
                    got_response = true;
                    d
                }
                Err(e) => {
                    last_err = Some(e);
                    continue;
                }
            };
            let item = &data["midurlinfo"][0];
            let purl = s(&item["purl"]);
            if !purl.is_empty() && s(&item["ekey"]).is_empty() {
                let sip = data["sip"]
                    .as_array()
                    .and_then(|a| a.iter().map(s).find(|x| x.starts_with("https")).or_else(|| a.first().map(s)))
                    .unwrap_or_else(|| "https://isure.stream.qqmusic.qq.com/".into());
                let url = format!("{sip}{purl}");
                if !matches!(q, Quality::Low | Quality::Standard | Quality::High | Quality::Lossless) && !stream_available(&url).await? {
                    continue;
                }
                return Ok(SongUrl {
                    url,
                    quality: q,
                    ekey: None,
                });
            }
        }
        if desktop && super::quality::encrypted_format(q).is_some() {
            if let Ok(source) = super::quality::encrypted_source(mid, media_mid, q, None).await {
                return Ok(source);
            }
        }
        if q == Quality::Ra360 {
            if let Ok(source) = super::quality::ra360_source(mid, media_mid).await {
                return Ok(source);
            }
        }
    }
    // 全部请求都失败说明是网络等问题，原样报出；否则就是没有权限
    match last_err {
        Some(e) if !got_response => Err(e),
        _ => bail!(ApiError::NoPlayableUrl),
    }
}

fn b64_text(v: &Value) -> String {
    let raw = s(v);
    if raw.is_empty() {
        return raw;
    }
    base64::engine::general_purpose::STANDARD
        .decode(raw.as_bytes())
        .ok()
        .and_then(|b| String::from_utf8(b).ok())
        .unwrap_or(raw)
}

pub async fn lyric(mid: &str, id: i64) -> Result<Lyric> {
    let c = core();
    let data = c
        .cached(&format!("lyric:{mid}"), 7 * 86400, || async {
            let r = c
                .musicu(
                    "music.musichallSong.PlayLyricInfo",
                    "GetPlayLyricInfo",
                    json!({ "songMID": mid, "songID": id, "trans": 1, "roma": 0, "crypt": 0, "qrc": 0 }),
                )
                .await;
            match r {
                Ok(d) if !s(&d["lyric"]).is_empty() => Ok(json!({ "lyric": b64_text(&d["lyric"]), "trans": b64_text(&d["trans"]) })),
                _ => {
                    let d = c
                        .get_json(
                            "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg",
                            &[("songmid", mid.to_string()), ("format", "json".into()), ("nobase64", "1".into()), ("g_tk", "5381".into())],
                        )
                        .await?;
                    Ok(json!({ "lyric": s(&d["lyric"]), "trans": s(&d["trans"]) }))
                }
            }
        })
        .await?;
    Ok(lyric::build(&s(&data["lyric"]), &s(&data["trans"])))
}

/// 歌曲信息里的 `file.try_begin` / `try_end` 就是官方客户端标出的高潮片段，没有时是 0。
pub async fn chorus(id: i64) -> Result<Option<ChorusRange>> {
    let c = core();
    let file = c.cached(&format!("chorus:{id}"), 7 * 86400, || async { Ok(tracks_by_id(&[id]).await?[0]["file"].clone()) }).await?;
    Ok(chorus_range(&file))
}

fn chorus_range(file: &Value) -> Option<ChorusRange> {
    let (start_ms, end_ms) = (n(&file["try_begin"]) as u32, n(&file["try_end"]) as u32);
    (end_ms > start_ms).then_some(ChorusRange { start_ms, end_ms })
}

pub async fn toplists() -> Result<Vec<TopListGroup>> {
    let c = core();
    let data = c
        .cached("toplists", 3600, || c.musicu("musicToplist.ToplistInfoServer", "GetAll", json!({})))
        .await?;
    let groups = data["group"].as_array().cloned().unwrap_or_default();
    Ok(groups
        .iter()
        .map(|g| TopListGroup {
            name: first_s(g, &["groupName"]),
            lists: g["toplist"]
                .as_array()
                .map(|a| {
                    a.iter()
                        .map(|t| TopList {
                            top_id: n(&t["topId"]),
                            title: s(&t["title"]),
                            cover_url: first_s(t, &["frontPicUrl", "headPicUrl", "mbFrontPicUrl"]),
                            period: s(&t["period"]),
                            preview: t["song"]
                                .as_array()
                                .map(|x| x.iter().take(3).map(|x| format!("{} - {}", s(&x["title"]), s(&x["singerName"]))).collect())
                                .unwrap_or_default(),
                        })
                        .collect()
                })
                .unwrap_or_default(),
        })
        .collect())
}

pub async fn toplist_detail(top_id: i64, period: &str) -> Result<TopListDetail> {
    let c = core();
    let data = c
        .cached(&format!("toplist:{top_id}:{period}"), 1800, || {
            c.musicu(
                "musicToplist.ToplistInfoServer",
                "GetDetail",
                json!({ "topId": top_id, "offset": 0, "num": 100, "period": period }),
            )
        })
        .await?;
    let info = &data["data"];
    Ok(TopListDetail {
        top_id,
        title: s(&info["title"]),
        cover_url: first_s(info, &["frontPicUrl", "headPicUrl"]),
        description: s(&info["intro"]),
        period: s(&info["period"]),
        songs: parse::songs(&data["songInfoList"]),
    })
}

/// Windows 客户端内嵌推荐页（QBCore webkit）的公参，与原生搜索的 ct=19 不同。
/// 登录后带上账号和 g_tk，推荐结果才是个性化的。
pub(crate) fn webkit_comm() -> Value {
    let c = core();
    let g_tk = c.session().map(|s| hash33(&s.musickey, 5381)).unwrap_or(5381);
    json!({
        "ct": 20,
        "cv": 2276,
        "platform": "wk_v17",
        "uin": c.uin(),
        "g_tk": g_tk,
        "g_tk_new_20200303": g_tk,
        "needNewCode": 1,
        "notice": 0,
    })
}

/// 推荐卡片里的歌曲只有 id，没有播放所需的 mid，按 id 批量补全。
pub(super) async fn tracks_by_id(ids: &[i64]) -> Result<Value> {
    if ids.is_empty() {
        return Ok(json!([]));
    }
    let data = core()
        .musicu("music.trackInfo.UniformRuleCtrl", "CgiGetTrackInfo", json!({ "ids": ids, "types": vec![0; ids.len()] }))
        .await?;
    Ok(data["tracks"].clone())
}

/// 首页推荐和专属乐流用新版 Android 客户端（20.09）的公参：栏目才带能单独刷新的 `refresh_param`，
/// 第 1 页之后也才有专属乐流。抓包和实测见 docs/qqmusic-feed-column-capture.md、docs/qqmusic-home-refresh-capture.md。
fn android_feed_comm() -> Value {
    json!({"cv": "20090808", "v": "20090808", "chid": "73387"})
}

/// 请求首页推荐的一页，`param` 给出页码等，`ext` 这里补上。官方每次进首页、下拉都重新取，这里也不缓存。
async fn recommend_page(mut param: Value) -> Result<Value> {
    let c = core();
    // 不带 is_20_style 时栏目没有 refresh_param
    param["v_uniq"] = json!([]);
    param["ext"] = json!({"is_20_style": "1", "has_login": if c.session().is_some() { "1" } else { "0" }});
    c.musicu_with_comm("music.recommend.RecommendFeed", "get_recommend_feed", param, android_feed_comm()).await
}

/// 把栏目转成区块，歌曲卡只有 id，统一补全一次。
async fn recommend_sections(shelves: &[&Value]) -> Result<Vec<RecommendSection>> {
    let ids: Vec<i64> =
        shelves.iter().flat_map(|shelf| shelf_cards(shelf)).filter(|c| n(&c["type"]) == 200).map(|c| n(&c["id"])).filter(|id| *id > 0).collect();
    let tracks = parse::songs(&tracks_by_id(&ids).await?).into_iter().map(|s| (s.id, s)).collect();
    Ok(shelves.iter().filter_map(|shelf| recommend_section(shelf, &tracks)).collect())
}

/// 首页个性推荐（v_shelf → v_niche → v_card）。保留能直接用的歌曲卡（type 200）
/// 和歌单卡（type 500，含“每日30首”等入口），再记下刷歌模式入口的起始歌曲；节目等跳过。
/// 官方首页的歌曲栏目分在两页：第 1 页一个，第 2 页还有两个（第 2 页另带专属乐流的第一批，专属乐流另外取）。
/// 第 2 页的 `v_cache` 是第 1 页的栏目 id，`s_num` 是栏目数，和官方一样。
pub async fn recommend_feed() -> Result<RecommendFeed> {
    let first = recommend_page(json!({ "direction": 0, "page": 1, "s_num": 0, "v_cache": [] })).await?;
    let shown: Vec<String> = shelves(&first).map(|shelf| s(&shelf["id"])).collect();
    let second = recommend_page(json!({ "direction": 1, "page": 2, "s_num": shown.len(), "v_cache": shown })).await?;
    let all: Vec<&Value> = shelves(&first).chain(shelves(&second).filter(|shelf| s(&shelf["id"]) != FEED_COLUMN_SHELF)).collect();
    let sections = recommend_sections(&all).await?;
    let (radar_seed, radar_cover) = radar_entry(&first).unwrap_or_default();
    Ok(RecommendFeed { sections, radar_seed, radar_cover })
}

/// 单独刷新首页的一个栏目，`refresh` 是该栏目的 [`RecommendSection::refresh`]，原样带回；
/// 服务端只返回这一栏的新内容，标题也可能换了。第 2 页的栏目也是这样刷新。
pub async fn refresh_recommend_section(refresh: &str) -> Result<RecommendSection> {
    let info: Value = serde_json::from_str(refresh).context(ApiError::bad_response("invalid recommend refresh_param"))?;
    let feed = recommend_page(json!({ "direction": 0, "page": 1, "s_num": 0, "v_cache": [], "refresh_info": info })).await?;
    let shelves: Vec<&Value> = shelves(&feed).collect();
    recommend_sections(&shelves)
        .await?
        .into_iter()
        .next()
        .context(ApiError::bad_response("refreshed recommend shelf has no songs or playlists"))
}

/// 一个栏目里没有能显示的歌曲或歌单时为 None。
fn recommend_section(shelf: &Value, tracks: &std::collections::HashMap<i64, Song>) -> Option<RecommendSection> {
    let title = s(&shelf["title_template"]).replace("{String}", &s(&shelf["title_content"])).trim().to_string();
    let shelf_cards: Vec<&Value> = shelf_cards(shelf).collect();
    let songs: Vec<Song> = shelf_cards
        .iter()
        .filter(|c| n(&c["type"]) == 200)
        .filter_map(|c| tracks.get(&n(&c["id"])).cloned())
        .collect();
    let playlists: Vec<PlaylistBrief> = shelf_cards
        .iter()
        .filter(|c| n(&c["type"]) == 500 && !s(&c["id"]).is_empty())
        .map(|c| PlaylistBrief {
            id: s(&c["id"]),
            title: s(&c["title"]),
            cover_url: s(&c["cover"]),
            song_count: 0,
            play_count: n(&c["cnt"]) as u64,
            // 入口卡（每日30首等）的副标题是其中一首歌，普通歌单为空
            creator: s(&c["subtitle"]),
        })
        .collect();
    // 顶上那排（301）和未登录时的栏目 ModuleID 为空，不能单独刷新
    let refresh = &shelf["refresh_param"];
    let refresh = if s(&refresh["ModuleID"]).is_empty() { String::new() } else { refresh.to_string() };
    (!songs.is_empty() || !playlists.is_empty()).then_some(RecommendSection { title, songs, playlists, refresh })
}

const FORYOU_MODULE: &str = "music.recommend.RecommendWidget";

/// 「自定义推荐页」的原始列表。`ChoseStatus`：-1 固定显示，1 已勾选，2 未勾选。
async fn foryou_selections() -> Result<Vec<Value>> {
    let c = core();
    c.session().context(ApiError::NotLoggedIn)?;
    let data = c.musicu_with_comm(FORYOU_MODULE, "GetForyouConfigItems", json!({ "Cmd": "0" }), android_feed_comm()).await?;
    Ok(data["Selections"].as_array().cloned().unwrap_or_default())
}

/// 固定项和歌单卡（type 500）Kanade 首页能显示；其余是官方 App 里的小游戏、网页和专属功能，不列出。
fn foryou_listed(x: &Value) -> bool {
    n(&x["ChoseStatus"]) == -1 || n(&x["ItemType"]) == 500
}

/// 首页最上面那排卡片的可选项（只含 Kanade 能显示的），需要登录。抓包见 docs/qqmusic-home-refresh-capture.md。
pub async fn foryou_config() -> Result<Vec<ForyouItem>> {
    Ok(foryou_selections()
        .await?
        .iter()
        .filter(|x| foryou_listed(x))
        .map(|x| ForyouItem { id: s(&x["Id"]), title: s(&x["Title"]), fixed: n(&x["ChoseStatus"]) == -1, chosen: n(&x["ChoseStatus"]) == 1 })
        .collect())
}

/// 保存勾选：官方把整张列表连同每项的 ChoseStatus 原样发回，这里先取一次最新列表再改状态。
/// 没列出的项保持原状，不动手机版的选择。
pub async fn save_foryou_config(chosen: &[String]) -> Result<()> {
    let mut items = foryou_selections().await?;
    for x in items.iter_mut().filter(|x| n(&x["ChoseStatus"]) != -1 && foryou_listed(x)) {
        x["ChoseStatus"] = json!(if chosen.contains(&s(&x["Id"])) { 1 } else { 2 });
    }
    let data = core()
        .musicu_write_with_comm(FORYOU_MODULE, "SaveForyouConfigItems", json!({ "Selections": items }), android_feed_comm())
        .await?;
    if n(&data["Code"]) != 0 {
        bail!(ApiError::ServerError { api: format!("{FORYOU_MODULE}.SaveForyouConfigItems"), code: s(&data["Code"]) });
    }
    Ok(())
}

/// 专属乐流（栏目 315）只有新版 Android 客户端（20.09）的版本号才返回，旧版本号给的是另一套栏目。
const FEED_COLUMN_SHELF: &str = "315";

/// 专属乐流第 `page` 页（从 1 开始），`seen` 是之前各页返回的 `seen` 合在一起。需要登录。
/// 首页推荐的第 1 页里没有这个栏目，从推荐的第 2 页开始才是，所以服务端页码要加 1。
pub async fn feed_column(page: u32, seen: &[String]) -> Result<FeedColumnPage> {
    let c = core();
    c.session().context(ApiError::NotLoggedIn)?;
    let data = c
        .musicu_with_comm(
            "music.recommend.RecommendFeed",
            "get_recommend_feed",
            json!({
                "direction": 1,
                "page": page + 1,
                "s_num": page + 1,
                "v_cache": [],
                "v_uniq": seen,
                "ext": {"is_20_style": "1", "has_login": "1", "TwoColPages_proxy": "1", "IsTwoColumnFlow_proxy": "1", "two_col_page_proxy": "1"},
            }),
            android_feed_comm(),
        )
        .await?;
    let cards: Vec<&Value> = data["v_shelf"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|shelf| s(&shelf["id"]) == FEED_COLUMN_SHELF)
        .flat_map(|shelf| shelf["v_niche"].as_array().into_iter().flatten())
        .flat_map(|niche| niche["v_card"].as_array().into_iter().flatten())
        .collect();
    // 组卡只带第一首的完整信息，整页的组卡歌曲一次补全
    let group_ids: Vec<i64> = cards
        .iter()
        .filter(|c| n(&c["subtype"]) == 206)
        .flat_map(|c| c["card_extra_info"]["SongList"].as_array().into_iter().flatten().map(|x| n(&x["ID"])))
        .filter(|id| *id > 0)
        .collect();
    let tracks: std::collections::HashMap<i64, Song> =
        parse::songs(&tracks_by_id(&group_ids).await?).into_iter().map(|s| (s.id, s)).collect();
    Ok(feed_column_page(&cards, &tracks))
}

fn feed_column_page(cards: &[&Value], tracks: &std::collections::HashMap<i64, Song>) -> FeedColumnPage {
    let seen = cards.iter().map(|c| format!("{}_{}_{}", n(&c["type"]), n(&c["subtype"]), s(&c["id"]))).collect();
    let cards = cards
        .iter()
        .filter_map(|c| match (n(&c["type"]), n(&c["subtype"])) {
            (200, 0) => Some(FeedCard {
                kind: FeedCardKind::Song,
                title: String::new(),
                tag: s(&c["tags"][0]["Tag"]),
                songs: vec![parse::song(&c["card_extra_info"]["Tracks"][0])?],
                playlist: None,
            }),
            (200, 206) => {
                let songs: Vec<Song> = c["card_extra_info"]["SongList"]
                    .as_array()?
                    .iter()
                    .filter_map(|x| tracks.get(&n(&x["ID"])).cloned())
                    .collect();
                (!songs.is_empty()).then(|| FeedCard {
                    kind: FeedCardKind::Group,
                    title: s(&c["title"]),
                    tag: String::new(),
                    songs,
                    playlist: None,
                })
            }
            (500, _) if !s(&c["id"]).is_empty() => Some(FeedCard {
                kind: FeedCardKind::Playlist,
                title: s(&c["title"]),
                tag: String::new(),
                songs: vec![],
                playlist: Some(PlaylistBrief {
                    id: s(&c["id"]),
                    title: s(&c["title"]),
                    cover_url: s(&c["cover"]),
                    song_count: 0,
                    play_count: n(&c["cnt"]) as u64,
                    creator: String::new(),
                }),
            }),
            _ => None,
        })
        .collect();
    FeedColumnPage { cards, seen }
}

/// 刷歌模式入口卡的跳转形如 `qqmusic://qq.com/ui/jumpToRadarMode?p={"EntranceSongs":[id],...}`。
/// 返回起始歌曲和卡片封面（动态的专辑图，可能为空）。
fn radar_entry(feed: &Value) -> Option<(Vec<i64>, String)> {
    cards(feed)
        .filter_map(|c| {
            let scheme = s(&c["scheme"]);
            if !scheme.contains("jumpToRadarMode") {
                return None;
            }
            let p = url::Url::parse(&scheme).ok()?.query_pairs().find(|(k, _)| k == "p")?.1.into_owned();
            let p: Value = serde_json::from_str(&p).ok()?;
            let ids: Vec<i64> = p["EntranceSongs"].as_array()?.iter().map(n).filter(|id| *id > 0).collect();
            Some((ids, s(&c["cover"])))
        })
        .find(|(ids, _)| !ids.is_empty())
}

/// 猜你喜欢电台的下一批歌，需要登录。每次调用都是新的一批，不缓存。
pub async fn guess_you_like() -> Result<Vec<Song>> {
    radio_songs(GUESS_YOU_LIKE_RADIO).await
}

/// 「猜你喜欢」个性电台的 id，最近播放的音乐雷达里也是它。
pub const GUESS_YOU_LIKE_RADIO: i64 = 99;

/// 个性电台的下一批歌。
pub async fn radio_songs(id: i64) -> Result<Vec<Song>> {
    let data = core()
        .musicu_with_comm(
            "music.radioProxy.MbTrackRadioSvr",
            "get_radio_track",
            json!({ "id": id, "num": 5, "from": 0, "scene": 0, "song_ids": [] }),
            webkit_comm(),
        )
        .await?;
    Ok(parse::songs(&data["tracks"]))
}

/// 刷歌模式（雷达）：按起始歌曲取第 `page` 批相似歌曲，从 1 开始。
pub async fn radar_songs(seed: &[i64], page: u32) -> Result<Vec<Song>> {
    let data = core()
        .musicu_with_comm(
            "music.recommend.TrackRelationServer",
            "GetRadarSong",
            json!({ "Page": page, "ReqType": 0, "FavSongs": [], "EntranceSongs": seed }),
            webkit_comm(),
        )
        .await?;
    let tracks: Vec<Value> = data["VecSongs"].as_array().into_iter().flatten().map(|x| x["Track"].clone()).collect();
    Ok(parse::songs(&Value::Array(tracks)))
}

fn shelves(feed: &Value) -> impl Iterator<Item = &Value> {
    feed["v_shelf"].as_array().into_iter().flatten()
}

fn shelf_cards(shelf: &Value) -> impl Iterator<Item = &Value> {
    shelf["v_niche"].as_array().into_iter().flatten().flat_map(|niche| niche["v_card"].as_array().into_iter().flatten())
}

fn cards(feed: &Value) -> impl Iterator<Item = &Value> {
    shelves(feed).flat_map(shelf_cards)
}

pub async fn playlist_detail(id: &str) -> Result<PlaylistDetail> {
    let c = core();
    let disstid: i64 = id.parse().unwrap_or(0);
    let data = c
        // “每日30首”这类歌单因人而异，缓存按账号区分
        .cached(&format!("playlist:{}:{id}", c.uin()), 600, || {
            c.musicu(
                "music.srfDissInfo.aiDissInfo",
                "uniform_get_Dissinfo",
                json!({
                    "disstid": disstid,
                    "enc_host_uin": "",
                    "tag": 1,
                    "userinfo": 1,
                    "song_begin": 0,
                    "song_num": 1000,
                    "onlysonglist": 0,
                    "orderlist": 1,
                }),
            )
        })
        .await?;
    let dir = &data["dirinfo"];
    Ok(PlaylistDetail {
        id: id.to_string(),
        title: s(&dir["title"]),
        cover_url: s(&dir["picurl"]),
        description: s(&dir["desc"]),
        creator: first_s(&dir["creator"], &["nick"]),
        songs: parse::songs(&data["songlist"]),
    })
}

/// 当前登录用户创建的歌单（含“我喜欢”）和收藏的歌单。
pub async fn user_playlists() -> Result<Vec<PlaylistBrief>> {
    let c = core();
    let Some(sess) = c.session() else { bail!(ApiError::NotLoggedIn) };
    let mut out = Vec::new();

    let created = c
        .get_json(
            "https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss",
            &[("hostuin", sess.uin.clone()), ("sin", "0".into()), ("size", "200".into()), ("format", "json".into())],
        )
        .await?;
    if let Some(list) = created["data"]["disslist"].as_array() {
        out.extend(list.iter().filter(|p| n(&p["tid"]) != 0).map(|p| PlaylistBrief {
            id: s(&p["tid"]),
            title: s(&p["diss_name"]),
            cover_url: s(&p["diss_cover"]),
            song_count: n(&p["song_cnt"]) as u32,
            play_count: n(&p["listen_num"]) as u64,
            creator: sess.nickname.clone(),
        }));
    }

    let fav = c
        .get_json(
            "https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg",
            &[
                ("ct", "20".into()),
                ("cid", "205360956".into()),
                ("userid", sess.uin.clone()),
                ("reqtype", "3".into()),
                ("sin", "0".into()),
                ("ein", "200".into()),
                ("format", "json".into()),
            ],
        )
        .await;
    if let Ok(fav) = fav {
        if let Some(list) = fav["data"]["cdlist"].as_array() {
            out.extend(list.iter().map(|p| PlaylistBrief {
                id: s(&p["dissid"]),
                title: s(&p["dissname"]),
                cover_url: s(&p["logo"]),
                song_count: n(&p["songnum"]) as u32,
                play_count: n(&p["listennum"]) as u64,
                creator: first_s(p, &["nickname"]),
            }));
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chorus_range_comes_from_try_fields() {
        let r = chorus_range(&json!({"try_begin": 72998, "try_end": 104743})).unwrap();
        assert_eq!((r.start_ms, r.end_ms), (72998, 104743));
        assert!(chorus_range(&json!({"try_begin": 0, "try_end": 0})).is_none());
        assert!(chorus_range(&json!({})).is_none());
    }

    #[test]
    fn lists_only_foryou_items_kanade_can_show() {
        let listed = |v: Value| foryou_listed(&v);
        assert!(listed(json!({ "ChoseStatus": -1, "ItemType": 700 })));
        assert!(listed(json!({ "ChoseStatus": 2, "ItemType": 500 })));
        assert!(!listed(json!({ "ChoseStatus": 1, "ItemType": 900 })));
    }

    #[test]
    fn parses_feed_column_cards() {
        let feed = json!([
            {"id": "376471754", "type": 200, "subtype": 0, "tags": [{"Tag": "“男女对唱”"}],
             "card_extra_info": {"Tracks": [{"id": 376471754, "mid": "0026MOow3oTkqr", "name": "Midnight Crisis"}]}},
            {"id": "1052115", "type": 200, "subtype": 206, "title": "重温曾经你最爱听的歌",
             "card_extra_info": {"SongList": [{"ID": 1052115}, {"ID": 512682454}, {"ID": 999}]}},
            {"id": "9525416362", "type": 500, "subtype": 0, "title": "歌单", "cover": "https://c", "cnt": 53012},
            {"id": "1", "type": 1100, "subtype": 1100},
        ]);
        let cards: Vec<&Value> = feed.as_array().unwrap().iter().collect();
        let tracks = parse::songs(&json!([{"id": 1052115, "mid": "00384U752Rv92T"}, {"id": 512682454, "mid": "000EH0I44RZINq"}]))
            .into_iter()
            .map(|s| (s.id, s))
            .collect();
        let page = feed_column_page(&cards, &tracks);
        assert_eq!(page.seen, ["200_0_376471754", "200_206_1052115", "500_0_9525416362", "1100_1100_1"]);
        assert_eq!(page.cards.len(), 3);
        assert_eq!((page.cards[0].kind, page.cards[0].tag.as_str(), page.cards[0].songs[0].mid.as_str()), (FeedCardKind::Song, "“男女对唱”", "0026MOow3oTkqr"));
        // 补全不到的歌跳过，组里剩下两首
        assert_eq!((page.cards[1].kind, page.cards[1].songs.len()), (FeedCardKind::Group, 2));
        let playlist = page.cards[2].playlist.as_ref().unwrap();
        assert_eq!((page.cards[2].kind, playlist.id.as_str(), playlist.play_count), (FeedCardKind::Playlist, "9525416362", 53012));
    }

    #[test]
    fn similar_songs_use_nested_tracks_and_preserve_order_and_mv() {
        let data = json!({"retcode": 0, "vecSong": [
            {"track": {"id": 11, "mid": "first", "mv": {"id": 0, "vid": "video"}}},
            {"track": {"id": 22, "mid": "second"}},
        ], "vecSongNew": null});
        let songs = similar_song_list(&data).unwrap();
        assert_eq!(songs.iter().map(|s| s.id).collect::<Vec<_>>(), vec![11, 22]);
        assert_eq!(songs[0].mv_vid, "video");
        assert!(similar_song_list(&json!({"retcode": 0, "vecSong": []})).unwrap().is_empty());
    }

    #[test]
    fn similar_songs_reject_failed_or_malformed_results() {
        for data in [json!({"retcode": 1000, "vecSong": []}), json!({"vecSong": []}), json!({"retcode": 0})] {
            assert!(similar_song_list(&data).is_err());
        }
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn fetches_hot_search() {
        let hot = hot_search().await.unwrap();
        assert!(!hot.hot.is_empty());
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn fetches_radar_songs() {
        // 未登录时推荐页没有刷歌入口，用抓包里入口给过的歌曲 id
        assert!(!radar_songs(&[104420880], 1).await.unwrap().is_empty());
    }

    #[test]
    fn extracts_radar_seed_from_entry_card() {
        let feed = json!({ "v_shelf": [{ "v_niche": [{ "v_card": [
            { "type": 900, "cover": "https://y.gtimg.cn/c.jpg", "scheme": "qqmusic://qq.com/ui/jumpToRadarMode?p=%7B%22EntranceSongs%22%3A%5B104420880%5D%2C%22Page%22%3A%221%22%7D" }
        ] }] }] });
        assert_eq!(radar_entry(&feed), Some((vec![104420880], "https://y.gtimg.cn/c.jpg".into())));
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn fetches_recommend_feed_with_playable_songs() {
        let sections = recommend_feed().await.unwrap().sections;
        let songs: Vec<_> = sections.iter().flat_map(|x| &x.songs).collect();
        assert!(!songs.is_empty(), "{sections:?}");
        assert!(songs.iter().all(|s| !s.mid.is_empty()));
        assert!(sections.iter().any(|x| !x.playlists.is_empty()));
    }

    #[test]
    fn parses_category_search_results() {
        let singers = json!({ "list": [{ "singerMID": "003xSwHe0xtkZI", "singerName": "jixwang", "songNum": 168, "albumNum": 34 }], "total": 19, "nextpage": -1 });
        let r = search_result(SearchKind::Singer, "鸣潮", 1, 28, &singers);
        assert_eq!((r.singers[0].name.as_str(), r.singers[0].song_count, r.has_more), ("jixwang", 168, false));

        let albums = json!({ "list": [{ "albumMID": "00087mKB1xbyP2", "albumName": "定玄", "publicTime": "2026-06-26", "singerName": "x",
            "singer_list": [{ "name": "鸣潮先约电台" }] }], "total": 251, "nextpage": 2 });
        let r = search_result(SearchKind::Album, "鸣潮", 1, 30, &albums);
        assert_eq!(r.albums[0].singer_name, "鸣潮先约电台");
        assert!(r.has_more);

        let playlists = json!({ "list": [{ "dissid": "9629670386", "dissname": "锁暝", "imgurl": "https://a/b", "song_count": 276,
            "listennum": 315007, "creator": { "name": "艾德" } }], "total": 300, "nextpage": 2 });
        let r = search_result(SearchKind::Playlist, "鸣潮", 1, 21, &playlists);
        assert_eq!((r.playlists[0].id.as_str(), r.playlists[0].creator.as_str()), ("9629670386", "艾德"));

        let videos = json!({ "list": [
            { "v_id": "004cp3hL2EXB5u", "mv_id": 2447344, "mv_name": "心月辞·何所往", "mv_pic_url": "http://y.gtimg.cn/x.jpg",
              "duration": 169, "play_count": 4906, "singer_name": "鸣潮先约电台/苏诗丁", "uploader_nick": "" },
            { "v_id": "011MCPJI0R8LSV", "mv_name": "过场动画", "singer_name": "", "uploader_nick": "漂子" },
        ], "total": 443, "nextpage": 2 });
        let r = search_result(SearchKind::Video, "鸣潮", 1, 56, &videos);
        assert_eq!(r.videos[0].vid, "004cp3hL2EXB5u");
        assert!(!r.videos[0].uploaded && r.videos[1].uploaded);
        assert_eq!(r.videos[1].creator, "漂子");
    }

    #[test]
    fn lyric_snippet_skips_title_line() {
        let item = json!({ "mid": "000bjZqH448qnK", "name": "远航星的告别", "lyric": "", "lyric_hilight": "",
            "content": "远航星的告别 - 鸣潮先约电台\n词：Xulai\n出品：鸣潮先约电台\nThat snowflake once fell on my nose" });
        let r = search_result(SearchKind::Lyric, "snowflake", 1, 10, &json!({ "list": [item], "total": 1000, "nextpage": 2 }));
        assert_eq!(r.lyric_snippets, vec!["That snowflake once fell on my nose".to_string()]);
        assert_eq!(r.songs.len(), 1);
        assert_eq!(lyric_snippet(&json!({ "content": "a - b", "lyric_hilight": "<em>你</em>好\n世界" }), "你"), "你好 / 世界");
        let credits = json!({ "content": "晴天 - 周杰伦\n词：周杰伦\n曲：周杰伦\n周杰伦说过的话" });
        assert_eq!(lyric_snippet(&credits, "周杰伦"), "周杰伦说过的话");
        assert_eq!(lyric_snippet(&json!({ "content": "晴天 - 周杰伦\n词：周杰伦" }), "周杰伦"), "词：周杰伦");
    }

    #[test]
    fn legacy_song_search_estimates_more_pages() {
        let r = search_result(SearchKind::Song, "x", 1, 2, &json!({ "list": [{ "mid": "a" }, { "mid": "b" }], "total": 3 }));
        assert!(r.has_more);
        let r = search_result(SearchKind::Song, "x", 2, 2, &json!({ "list": [{ "mid": "c" }], "total": 3 }));
        assert!(!r.has_more);
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn suggests_from_pinyin_initials() {
        let list = search_suggestions("yhbk").await.unwrap();
        assert!(list.iter().any(|x| x.kind == SuggestionKind::Song && x.title.contains("有何不可")), "{list:?}");
    }
}
