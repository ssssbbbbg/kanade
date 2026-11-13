//! 真实接口冒烟测试：cargo test --test live -- --ignored --nocapture

use rust_lib_kanade::api::types::Quality;
use rust_lib_kanade::qq::{client, login, music};

fn desktop_test_har() -> serde_json::Value {
    let path = std::env::var_os("QQMUSIC_TEST_HAR").expect("请通过 QQMUSIC_TEST_HAR 指定本地登录抓包");
    let text = std::fs::read_to_string(path).expect("无法读取本地 HAR");
    serde_json::from_str(text.trim_start_matches('\u{feff}')).expect("HAR 格式错误")
}

// 只在显式运行 PC 冒烟测试时，将本地 HAR 中的登录态放入测试进程的内存数据库。
fn use_desktop_test_login() {
    let har = desktop_test_har();
    let comm = har["log"]["entries"].as_array().expect("HAR 缺少请求列表").iter().find_map(|entry| {
        let post = &entry["request"]["postData"];
        let raw = post["text"].as_str().or_else(|| post["params"][0]["value"].as_str())?;
        let body: serde_json::Value = serde_json::from_str(raw).ok()?;
        let comm = &body["comm"];
        (!comm["authst"].as_str()?.is_empty()).then(|| comm.clone())
    }).expect("HAR 中没有登录态");
    client::core().set_session(Some(client::Session::new(
        comm["uin"].as_str().expect("登录态缺少 uin").into(),
        comm["authst"].as_str().expect("登录态缺少 authst").into(),
        comm["tmeLoginType"].as_i64().expect("登录态缺少 tmeLoginType") as i32,
        0,
    ))).unwrap();
}

/// 只读：新歌手页、自己的资料，以及抓包中已有公开歌单用户的收藏分页。
#[tokio::test]
#[ignore = "需要本地 HAR 登录态和网络；不执行任何关注或歌单写入"]
async fn desktop_singer_social_and_user_assets() {
    use rust_lib_kanade::{api::types::UserAssetKind, qq::{detail, user}};
    use_desktop_test_login();
    let mid = "002wbPaC0L9C3A";
    let singer = detail::singer_detail(mid).await.unwrap();
    assert!(!singer.selected_albums.is_empty());
    let social = detail::singer_social(mid).await.unwrap();
    assert!(social.fans_count > 0 && !social.guard_title.is_empty());
    let tags = detail::singer_video_tags(mid).await.unwrap();
    assert!(tags.iter().any(|t| t.id == 0));
    let first = detail::singer_videos(mid, &singer.name, 0, 0, 0, 5).await.unwrap();
    let next = detail::singer_videos(mid, &singer.name, 0, 0, 5, 5).await.unwrap();
    assert_eq!(first.videos.len(), 5);
    assert!(!next.videos.is_empty());
    assert!(first.videos.iter().all(|v| !v.vid.is_empty() && !v.name.is_empty()));
    assert!(next.videos.iter().all(|v| first.videos.iter().all(|p| p.vid != v.vid)));
    let hot = detail::singer_videos(mid, &singer.name, 0, 1, 0, 5).await.unwrap();
    let hot_next = detail::singer_videos(mid, &singer.name, 0, 1, 5, 5).await.unwrap();
    assert_eq!((hot.videos.len(), hot_next.videos.len()), (5, 5));
    assert_ne!(first.videos.iter().map(|v| &v.vid).collect::<Vec<_>>(), hot.videos.iter().map(|v| &v.vid).collect::<Vec<_>>());
    assert!(hot_next.videos.iter().all(|v| hot.videos.iter().all(|p| p.vid != v.vid)));
    let own = user::user_profile(&client::core().uin()).await.unwrap();
    assert!(own.is_self && !own.euin.is_empty());
    let har = desktop_test_har();
    let target = har["log"]["entries"].as_array().unwrap().iter().find_map(|e| {
        if !e["request"]["url"].as_str()?.contains("fcg_get_profile_homepage") { return None; }
        let r: serde_json::Value = serde_json::from_str(e["response"]["content"]["text"].as_str()?).ok()?;
        (r["data"]["mydiss"]["num"].as_u64()? > 0).then(|| r["data"]["creator"]["encrypt_uin"].as_str().unwrap().to_string())
    }).expect("HAR 中需要有公开歌单的用户主页样本");
    let profile = user::user_profile(&target).await.unwrap();
    assert!(!profile.name.is_empty() && profile.playlist_count > 0 && !profile.is_self);
    let saved = user::user_assets(&target, UserAssetKind::Playlist, 0, 3).await.unwrap();
    let next = user::user_assets(&target, UserAssetKind::Playlist, 1, 3).await.unwrap();
    assert!(!saved.hidden && saved.has_more && saved.playlists.len() == 3);
    assert!(next.playlists.iter().all(|p| saved.playlists.iter().all(|first| p.id != first.id)));
    let albums = user::user_assets(&target, UserAssetKind::Album, 0, 3).await.unwrap();
    assert!(!albums.albums.is_empty() && !albums.albums[0].mid.is_empty() && !albums.albums[0].name.is_empty());
    let created = user::user_playlists(&target, &profile.name, 0, 30).await.unwrap();
    assert!(!created.playlists.is_empty(), "主页宣称存在公开歌单，但分页列表为空");
    client::core().set_session(None).unwrap();
    // 两套上游主页的匿名请求均已返回 1000；明确要求登录，不能伪装成空的公开主页。
    assert!(matches!(rust_lib_kanade::qq::error::ApiError::from(user::user_profile(&target).await.unwrap_err()),
        rust_lib_kanade::qq::error::ApiError::NotLoggedIn));
    assert!(!rust_lib_kanade::qq::social::singer_followed(mid).await.unwrap());
    println!("Read-only singer metadata, social counts, video pagination, self/public profiles and saved asset pagination passed.");
}

#[tokio::test]
#[ignore]
async fn desktop_quality_tiers_for_reported_song() {
    use_desktop_test_login();
    let result = music::search_songs("月声尽，心灯明", 1, 10).await.unwrap();
    let song = result.songs.iter().find(|song| song.name.contains("月声尽") && song.name.contains("心灯明"))
        .expect("没有找到报告中的歌曲");
    let options = rust_lib_kanade::qq::quality::song_qualities(&song.mid).await.unwrap();
    let qualities: Vec<_> = options.iter().filter(|option| option.available).map(|option| option.quality).collect();
    assert!(!qualities.is_empty(), "当前测试账号没有可播放档位");
    assert!(options.iter().all(|option| !matches!(option.quality,
        Quality::Ogg640 | Quality::Ogg320 | Quality::Ogg192 | Quality::Ogg96 | Quality::Aac192 | Quality::Aac48
    )), "底层编码格式不应成为独立音质档位");
    println!("{}: playable quality tiers = {qualities:?}", song.name);
}

#[tokio::test]
#[ignore = "仅只读；需要本地 HAR 及 QQMUSIC_TEST_ASSET_TARGETS 指定的公开视频用户样本"]
async fn desktop_user_liked_songs_and_videos() {
    use rust_lib_kanade::{api::types::UserAssetKind, qq::user};
    use_desktop_test_login();
    let har = desktop_test_har();
    let target = har["log"]["entries"].as_array().unwrap().iter().find_map(|e| {
        if !e["request"]["url"].as_str()?.contains("fcg_get_profile_homepage") { return None; }
        let r: serde_json::Value = serde_json::from_str(e["response"]["content"]["text"].as_str()?).ok()?;
        let liked = r["data"]["mymusic"].as_array()?.iter().find(|c| c["type"].as_u64() == Some(1))?;
        (liked["num0"].as_u64()? > 0).then(|| r["data"]["creator"]["encrypt_uin"].as_str().unwrap().to_string())
    }).expect("HAR 中需要非空的我喜欢歌曲样本");
    let first = user::user_assets(&target, UserAssetKind::Song, 0, 3).await.unwrap();
    let next = user::user_assets(&target, UserAssetKind::Song, 1, 3).await.unwrap();
    assert_eq!((first.songs.len(), next.songs.len()), (3, 3));
    assert!(first.has_more && !first.hidden);
    assert!(first.songs.iter().all(|s| !s.mid.is_empty() && !s.name.is_empty()));
    assert!(next.songs.iter().all(|s| first.songs.iter().all(|p| p.mid != s.mid)));
    let beyond_thousand = user::user_assets(&target, UserAssetKind::Song, 400, 3).await.unwrap();
    assert_eq!(beyond_thousand.songs.len(), 3, "喜欢歌曲不能被原歌单详情的 1000 首范围截断");
    let path = std::env::var_os("QQMUSIC_TEST_ASSET_TARGETS").expect("需要本地公开视频用户样本文件");
    let targets: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let target = targets["video_user"].as_str().unwrap();
    let first = user::user_assets(target, UserAssetKind::Video, 0, 2).await.unwrap();
    let next = user::user_assets(target, UserAssetKind::Video, 1, 2).await.unwrap();
    assert_eq!((first.videos.len(), next.videos.len()), (2, 1));
    assert!(first.has_more && !next.has_more && !first.hidden);
    assert!(first.videos.iter().all(|v| !v.vid.is_empty() && !v.name.is_empty()));
    // 旧收藏可能已失效，实际样本存在 status=0、封面为空但标题和 VID 仍保留的条目。
    assert!(first.videos.iter().any(|v| !v.cover_url.is_empty()));
    assert!(next.videos.iter().all(|v| first.videos.iter().all(|p| p.vid != v.vid)));
    println!("Nonempty liked songs and videos, pagination and media identifiers verified read-only.");
}

#[tokio::test]
#[ignore]
async fn desktop_dynamic_qualities() {
    use_desktop_test_login();
    let har = desktop_test_har();
    let mid = har["log"]["entries"].as_array().unwrap().iter().find_map(|entry| {
        let text = entry["response"]["content"]["text"].as_str()?;
        let response: serde_json::Value = serde_json::from_str(text).ok()?;
        response["music.search.SearchCgiService"]["data"]["body"]["song"]["list"][0]["mid"].as_str().map(str::to_string)
    }).expect("HAR 中没有搜索歌曲样本");
    let options = rust_lib_kanade::qq::quality::song_qualities(&mid).await.unwrap();
    assert!(options.len() > 4, "未返回扩展音质");
    assert!(options.iter().any(|option| option.quality == Quality::Master));
    assert!(options.iter().filter(|option| matches!(option.quality, Quality::Aicodec | Quality::Dts | Quality::Dolby)).all(|option| !option.available));
    let selected = options.iter().find(|option| option.available && matches!(option.quality, Quality::Master | Quality::Hires | Quality::Atmos | Quality::Atmos51 | Quality::Atmos71)).expect("当前样本没有可播放的扩展音质");
    let track = client::core().desktop_musicu("music.trackInfo.UniformRuleCtrl", "CgiGetTrackInfo", serde_json::json!({
        "ctx": 0, "client": 1, "types": [0], "modify_stamp": [0], "mids": [mid],
    })).await.unwrap();
    let media_mid = track["tracks"][0]["file"]["media_mid"].as_str().unwrap();
    let url = music::song_url(&mid, media_mid, selected.quality).await.unwrap();
    assert_eq!(url.quality, selected.quality);
    let response = reqwest::Client::new().get(&url.url).header("Range", "bytes=0-1023").send().await.unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::PARTIAL_CONTENT);
    let bytes = response.bytes().await.unwrap();
    assert!(bytes.starts_with(b"fLaC") || bytes.starts_with(b"OggS"));
}

#[tokio::test]
#[ignore]
async fn desktop_search_pagination() {
    use_desktop_test_login();
    let first = music::search_songs("piano", 1, 5).await.unwrap();
    let second = music::search_songs("piano", 2, 5).await.unwrap();
    assert!(first.total >= 10);
    assert_eq!(first.songs.len(), 5);
    assert_eq!(second.songs.len(), 5);
    assert!(first.songs.iter().all(|song| !song.mid.is_empty() && !song.media_mid.is_empty() && !song.name.is_empty()));
    let first_mids: Vec<_> = first.songs.iter().map(|song| &song.mid).collect();
    let second_mids: Vec<_> = second.songs.iter().map(|song| &song.mid).collect();
    assert_ne!(first_mids, second_mids);
}

#[tokio::test]
#[ignore]
async fn desktop_category_search_pagination() {
    use rust_lib_kanade::api::types::{SearchKind, SearchResult};
    fn ids(kind: SearchKind, r: &SearchResult) -> Vec<String> {
        match kind {
            SearchKind::Song | SearchKind::Lyric => r.songs.iter().map(|x| x.mid.clone()).collect(),
            SearchKind::Singer => r.singers.iter().map(|x| x.mid.clone()).collect(),
            SearchKind::Album => r.albums.iter().map(|x| x.mid.clone()).collect(),
            SearchKind::Playlist => r.playlists.iter().map(|x| x.id.clone()).collect(),
            SearchKind::Video => r.videos.iter().map(|x| x.vid.clone()).collect(),
            SearchKind::User => r.users.iter().map(|x| x.euin.clone()).collect(),
        }
    }
    use_desktop_test_login();
    for kind in [SearchKind::Song, SearchKind::Album, SearchKind::Playlist, SearchKind::Video, SearchKind::Lyric, SearchKind::Singer, SearchKind::User] {
        let first = music::search("周杰伦", kind, 1, 10).await.unwrap();
        let first_ids = ids(kind, &first);
        assert!(!first_ids.is_empty(), "{kind:?} 第一页为空");
        if kind == SearchKind::Lyric {
            assert_eq!(first.lyric_snippets.len(), first.songs.len());
        }
        // 用户的 euin 是账号标识，不打印
        let sample = if kind == SearchKind::User { vec![] } else { first_ids[..first_ids.len().min(3)].to_vec() };
        println!("{kind:?}: total={} has_more={} first={sample:?}", first.total, first.has_more);
        if !first.has_more {
            continue;
        }
        let second = music::search("周杰伦", kind, 2, 10).await.unwrap();
        let second_ids = ids(kind, &second);
        assert!(!second_ids.is_empty(), "{kind:?} 第二页为空");
        assert!(second_ids.iter().all(|id| !first_ids.contains(id)), "{kind:?} 第二页与第一页重复");
    }
}

#[tokio::test]
#[ignore]
async fn desktop_user_homepage_playlists() {
    use rust_lib_kanade::api::types::SearchKind;
    use rust_lib_kanade::qq::user;
    use_desktop_test_login();
    let users = music::search("周杰伦", SearchKind::User, 1, 10).await.unwrap().users;
    let mut checked = false;
    for u in users.iter().filter(|u| u.playlist_count > 10).take(1) {
        let profile = user::user_profile(&u.euin).await.unwrap();
        assert!(!profile.name.is_empty());
        assert!(profile.playlist_count > 10, "主页没有歌单标签");
        let first = user::user_playlists(&u.euin, &profile.name, 0, 10).await.unwrap();
        let second = user::user_playlists(&u.euin, &profile.name, 1, 10).await.unwrap();
        assert!(first.has_more && !second.playlists.is_empty());
        assert!(second.playlists.iter().all(|p| first.playlists.iter().all(|q| q.id != p.id)), "歌单第二页与第一页重复");
        let detail = music::playlist_detail(&first.playlists[0].id).await.unwrap();
        assert!(!detail.songs.is_empty(), "用户歌单打不开");
        println!("{}: {} 个歌单，第一个《{}》{} 首", profile.name, profile.playlist_count, detail.title, detail.songs.len());
        checked = true;
    }
    assert!(checked, "搜索结果里没有带歌单的用户");
}

#[tokio::test]
#[ignore]
async fn desktop_mv_streams() {
    use rust_lib_kanade::api::types::SearchKind;
    use rust_lib_kanade::qq::mv;
    use_desktop_test_login();
    let videos = music::search("周杰伦", SearchKind::Video, 1, 10).await.unwrap().videos;
    let official = videos.iter().find(|v| !v.uploaded).expect("没有官方 MV");
    let d = mv::mv_detail(&official.vid).await.unwrap();
    assert!(!d.name.is_empty() && d.duration_secs > 0);
    assert!(!d.streams.is_empty(), "{} 没有可播放的清晰度", d.name);
    let low = &d.streams[0];
    let response = reqwest::Client::new().get(&low.url).header("Range", "bytes=0-1023").send().await.unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::PARTIAL_CONTENT);
    let bytes = response.bytes().await.unwrap();
    assert_eq!(&bytes[4..8], b"ftyp", "不是 MP4");
    println!("{}: {:?}", d.name, d.streams.iter().map(|x| x.height).collect::<Vec<_>>());
    // 用户上传的视频走同一套接口
    let uploaded = music::search("鸣潮", SearchKind::Video, 1, 20).await.unwrap().videos;
    for v in uploaded.iter().filter(|v| v.uploaded).take(2) {
        let d = mv::mv_detail(&v.vid).await.unwrap();
        println!("上传 {}: {:?}", d.name, d.streams.iter().map(|x| x.height).collect::<Vec<_>>());
    }
}

/// 只读验证歌曲搜索的 VID 能打开 MV，并取得同一首歌的相似推荐。
#[tokio::test]
#[ignore = "需要本地 HAR 登录态和网络；只读"]
async fn desktop_song_mv_and_similar_songs() {
    use rust_lib_kanade::{api::music as api, qq::mv};
    use_desktop_test_login();
    let result = music::search_songs("Turning Around", 1, 40).await.unwrap();
    let song = result.songs.iter().find(|song| song.id == 667137632).expect("没有找到抓包歌曲");
    assert!(!song.mv_vid.is_empty());
    let video = mv::mv_detail(&song.mv_vid).await.unwrap();
    assert_eq!(video.vid, song.mv_vid);
    assert!(!video.streams.is_empty(), "歌曲关联 MV 没有可播放的流");
    let similar = api::get_similar_songs(song.id).await.unwrap();
    assert!(!similar.is_empty());
    assert!(similar.iter().all(|track| track.id > 0 && !track.mid.is_empty() && !track.name.is_empty()));
    println!("Song MV and similar songs passed: {} streams, {} similar tracks", video.streams.len(), similar.len());
}

#[tokio::test]
#[ignore]
async fn desktop_search_and_stream() {
    use_desktop_test_login();
    let result = music::search_songs("纯音乐 钢琴", 1, 20).await.unwrap();
    let candidates: Vec<_> = result.songs.iter().filter(|song| !song.vip).take(3).collect();
    assert!(!candidates.is_empty(), "没有找到用于验证的普通歌曲");
    let mut playable = None;
    for song in candidates {
        if let Ok(url) = music::song_url(&song.mid, &song.media_mid, Quality::High).await {
            playable = Some(url);
            break;
        }
    }
    let url = playable.expect("普通歌曲均未返回 PC 播放链接");
    let response = reqwest::Client::new()
        .get(&url.url)
        .header("Range", "bytes=0-1023")
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::PARTIAL_CONTENT);
    let bytes = response.bytes().await.unwrap();
    assert_eq!(bytes.len(), 1024);
    let is_mp3 = bytes.starts_with(b"ID3") || (bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0);
    let is_m4a = &bytes[4..8] == b"ftyp";
    assert!(is_mp3 || is_m4a, "播放链接返回的内容不是普通 MP3 / M4A 音频");
}

#[tokio::test]
#[ignore]
async fn anonymous_search() {
    assert!(client::core().session().is_none());
    let result = music::search_songs("piano", 1, 5).await.unwrap();
    assert!(result.total > 0);
    assert_eq!(result.songs.len(), 5);
}

#[tokio::test]
#[ignore]
async fn search_and_play() {
    let r = music::search_songs("周杰伦 晴天", 1, 5).await.unwrap();
    println!("total={} first={:?}", r.total, r.songs.first());
    let song = r.songs.iter().find(|s| !s.vip).unwrap_or(&r.songs[0]).clone();
    let url = music::song_url(&song.mid, &song.media_mid, Quality::High).await;
    println!("url for {} ({}): {:?}", song.name, song.mid, url);
    let lyric = music::lyric(&song.mid, song.id).await.unwrap();
    println!("lyric lines={} first={:?}", lyric.lines.len(), lyric.lines.get(5));
}

#[tokio::test]
#[ignore]
async fn free_song_url() {
    // 搜索若干首，找一首非会员歌曲验证播放链接
    let r = music::search_songs("纯音乐 钢琴", 1, 20).await.unwrap();
    for s in r.songs.iter().filter(|s| !s.vip).take(3) {
        println!("{} vip={} -> {:?}", s.name, s.vip, music::song_url(&s.mid, &s.media_mid, Quality::Standard).await.map(|u| (u.quality, u.url.len())));
    }
}

#[tokio::test]
#[ignore]
async fn toplists_and_playlists() {
    let groups = music::toplists().await.unwrap();
    let first = &groups[0].lists[0];
    println!("groups={} first={:?}", groups.len(), first);
    let d = music::toplist_detail(first.top_id, &first.period).await.unwrap();
    println!("toplist {} songs={} first={:?}", d.title, d.songs.len(), d.songs.first().map(|s| &s.name));
    let feed = music::recommend_feed().await.unwrap();
    let rec: Vec<_> = feed.sections.into_iter().flat_map(|s| s.playlists).collect();
    println!("recommend={} first={:?}", rec.len(), rec.first());
    // 未登录时“每日30首”入口的 id 是 "0"，取不到详情
    if let Some(p) = rec.iter().find(|p| p.id != "0") {
        let pd = music::playlist_detail(&p.id).await.unwrap();
        println!("playlist {} songs={}", pd.title, pd.songs.len());
    }
}

#[tokio::test]
#[ignore]
async fn qr_create() {
    let qr = login::create_qr().await.unwrap();
    println!("qr png bytes={} qrsig len={}", qr.image.len(), qr.qrsig.len());
    println!("poll: {:?}", login::poll_qr(&qr.qrsig).await);
}

#[tokio::test]
#[ignore]
async fn print_free_url() {
    let r = music::search_songs("夜的钢琴曲5", 1, 5).await.unwrap();
    let s = r.songs.iter().find(|s| !s.vip).unwrap();
    println!("URL={}", music::song_url(&s.mid, &s.media_mid, Quality::High).await.unwrap().url);
}


#[tokio::test]
#[ignore]
async fn wx_qr_create() {
    let qr = login::create_wx_qr().await.unwrap();
    println!("wx qr bytes={} head={:02x?} uuid={}", qr.image.len(), &qr.image[..4], qr.qrsig);
    println!("poll: {:?}", login::poll_wx_qr(&qr.qrsig).await);
}

/// 只读：自己的歌单里应能找到“我喜欢”（dirid 201）。不会发送写请求。
#[tokio::test]
#[ignore]
async fn desktop_my_playlists_include_liked() {
    use_desktop_test_login();
    let lists = rust_lib_kanade::qq::library::my_playlists().await.unwrap();
    assert!(lists.iter().any(|p| p.dir_id == rust_lib_kanade::qq::library::LIKED_DIR_ID), "没有找到我喜欢");
    let liked = rust_lib_kanade::qq::library::liked_song_ids().await.unwrap();
    println!("playlists={} liked songs={}", lists.len(), liked.len());
}

/// 使用写操作的请求封装调用只读接口，验证网关和请求结构，不改动账号数据。
#[tokio::test]
#[ignore]
async fn desktop_private_transport_with_readonly_call() {
    use_desktop_test_login();
    let data = client::core().desktop_private("music.vipcgi.VipBannerCgi", "QueryVipBanner", serde_json::json!({})).await.unwrap();
    assert!(data.get("banner").is_some(), "PC 请求封装没有返回预期的只读数据");
}

/// 只读：云端最近播放能取到带 mid 的歌曲；顺带看较小的 requestCnt 是否被接受。
#[tokio::test]
#[ignore]
async fn desktop_recent_plays() {
    use_desktop_test_login();
    let songs = rust_lib_kanade::qq::history::recent_plays().await.unwrap();
    assert!(!songs.is_empty() && songs.iter().all(|s| !s.mid.is_empty()), "最近播放为空或缺少 mid");
    let small = client::core()
        .desktop_private("music.musicasset.PlayRecentlyRead", "GetPlayRecentlyInfo", serde_json::json!({"requestCnt": 300, "type": 2, "updateTime": 0}))
        .await.unwrap();
    println!("recent={} requestCnt300: code={} songs={}", songs.len(), small["code"], small["data"]["songList"].as_array().map_or(0, |a| a.len()));
}

/// 只读：Android 端各最近播放分类（全部、专辑、歌单、电台、MV、有声）走 PC 通道是否同样有数据。
#[tokio::test]
#[ignore]
async fn desktop_recent_play_categories() {
    // 用登录数据库的副本，测试进程使用独立的内存 Store。
    let path = std::env::var_os("QQMUSIC_TEST_SESSION_DB").expect("需要明确指定当前登录数据库的副本");
    let db = rusqlite::Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
    let raw: String = db.query_row("SELECT value FROM kv WHERE key='session'", [], |row| row.get(0)).unwrap();
    drop(db);
    client::core().set_session(Some(serde_json::from_str(&raw).unwrap())).unwrap();
    for (kind, field) in [(2, "songList"), (1, "allItems"), (3, "albumList"), (4, "geDanList"), (5, "radioList"), (6, "mvList"), (10, ""), (12, "listenBookList")] {
        let data = match client::core()
            .desktop_private("music.musicasset.PlayRecentlyRead", "GetPlayRecentlyInfo", serde_json::json!({"requestCnt": 2500, "type": kind, "updateTime": 0}))
            .await
        {
            Ok(data) => data,
            Err(e) => {
                println!("type={kind} error={e}");
                continue;
            }
        };
        let list = &data["data"][field];
        let summary = match kind {
            1 => format!("nums={} albums={} playlists={} books={}", list["nums"], list["albumList"].as_array().map_or(0, |a| a.len()), list["geDanList"].as_array().map_or(0, |a| a.len()), list["listenBookList"].as_array().map_or(0, |a| a.len())),
            _ => format!("items={}", list.as_array().map_or(0, |a| a.len())),
        };
        println!("type={kind} code={} updateTime={} {summary}", data["code"], data["updateTime"]);
    }
    let c = rust_lib_kanade::qq::history::recent_collections().await.unwrap();
    assert!(c.albums.iter().all(|a| !a.mid.is_empty()) && c.videos.iter().all(|v| !v.vid.is_empty()));
    println!(
        "collections albums={} playlists={} videos={} books={} (with episode {}) radios={}",
        c.albums.len(), c.playlists.len(), c.videos.len(), c.books.len(), c.books.iter().filter(|b| b.episode.is_some()).count(), c.radios.len()
    );
    for r in &c.radios {
        println!("radio {} songs={}", r.id, rust_lib_kanade::qq::music::radio_songs(r.id).await.unwrap().len());
    }
}

/// 只读：登录后首页每个能单独刷新的栏目都换成新内容。
#[tokio::test]
#[ignore]
async fn desktop_refresh_recommend_sections() {
    let path = std::env::var_os("QQMUSIC_TEST_SESSION_DB").expect("需要明确指定当前登录数据库的副本");
    let db = rusqlite::Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
    let raw: String = db.query_row("SELECT value FROM kv WHERE key='session'", [], |row| row.get(0)).unwrap();
    drop(db);
    client::core().set_session(Some(serde_json::from_str(&raw).unwrap())).unwrap();
    let feed = music::recommend_feed().await.unwrap();
    // 官方首页登录后有三个歌曲栏目，第 1 页一个、第 2 页两个
    let song_sections = feed.sections.iter().filter(|s| !s.songs.is_empty()).count();
    assert!(song_sections >= 3, "{:?}", feed.sections.iter().map(|s| &s.title).collect::<Vec<_>>());
    let refreshable: Vec<_> = feed.sections.iter().filter(|s| !s.refresh.is_empty()).collect();
    assert!(!refreshable.is_empty(), "{:?}", feed.sections.iter().map(|s| &s.title).collect::<Vec<_>>());
    for old in refreshable {
        let new = music::refresh_recommend_section(&old.refresh).await.unwrap();
        println!("{} -> {} songs={} playlists={}", old.title, new.title, new.songs.len(), new.playlists.len());
        assert!(!new.refresh.is_empty());
        let ids = |s: &rust_lib_kanade::api::types::RecommendSection| s.songs.iter().map(|x| x.id).collect::<Vec<_>>();
        assert_ne!(ids(old), ids(&new));
    }
}

/// 与应用登录上下文相同的写请求封装调用只读接口，不改动账号数据。
#[tokio::test]
#[ignore]
async fn mobile_write_transport_with_readonly_call() {
    use_desktop_test_login();
    let data = client::core().mobile_write("music.vipcgi.VipBannerCgi", "QueryVipBanner", serde_json::json!({})).await.unwrap();
    assert!(data.get("banner").is_some(), "Android 写请求封装没有返回预期的只读数据");
}

/// 只读：登录后推荐评论能一直翻到第一页给出的 id 用完，中间不重复。
#[tokio::test]
#[ignore]
async fn desktop_recommended_comments_paging() {
    use rust_lib_kanade::{api::types::{CommentSort, CommentTarget}, qq::detail};
    use_desktop_test_login();
    let mut seen = std::collections::HashSet::new();
    let (mut cursor, mut pages) = (String::new(), 0);
    loop {
        let feed = detail::comment_feed(CommentTarget::Song, 121345659, CommentSort::Recommend, &cursor).await.unwrap();
        assert!(!feed.comments.is_empty() && feed.total > 0, "推荐第 {pages} 页为空");
        assert!(feed.comments.iter().all(|c| seen.insert(c.id.clone())), "推荐第 {pages} 页与前面重复");
        pages += 1;
        if !feed.has_more { break }
        cursor = feed.cursor;
    }
    println!("recommended pages={pages} comments={}", seen.len());
    assert!(pages > 3, "登录后推荐应当能翻页");
}

/// 仅在用户同意后显式运行：只测试报告中的一首未收藏歌曲，随后恢复原状态。
#[tokio::test]
#[ignore]
async fn desktop_like_iris_and_restore() {
    use rust_lib_kanade::qq::library;
    assert_eq!(std::env::var("QQMUSIC_TEST_ALLOW_LIKE_IRIS").as_deref(), Ok("1"), "需要用户同意真实收藏并恢复");
    let path = std::env::var_os("QQMUSIC_TEST_SESSION_DB").expect("需要明确指定当前登录数据库");
    let db = rusqlite::Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
    let raw: String = db.query_row("SELECT value FROM kv WHERE key='session'", [], |row| row.get(0)).unwrap();
    let session: client::Session = serde_json::from_str(&raw).unwrap();
    drop(db);
    // 测试进程使用独立的内存 Store，不改动应用保存的登录态。
    client::core().set_session(Some(session)).unwrap();
    async fn liked() -> anyhow::Result<bool> {
        let data = client::core().mobile_write("music.musicasset.SongFavRead", "IsSongFanByMid",
            serde_json::json!({"v_songMid": ["004Ytrah01J9gS"]})).await?;
        data["m_fan"]["004Ytrah01J9gS"].as_bool().ok_or_else(|| anyhow::anyhow!("missing favorite status"))
    }
    assert!(!liked().await.unwrap(), "目标歌曲已经收藏，停止测试以保留原状态");
    let add = library::set_song_liked(634598738, true).await;
    let after_add = liked().await;
    // 初始状态已确认未收藏。成功或结果不明确时均恢复，不重试添加。
    let restore = if !matches!(after_add, Ok(false)) || add.is_ok() {
        library::set_song_liked(634598738, false).await
    } else { Ok(()) };
    let after_restore = liked().await;
    assert!(restore.is_ok() && matches!(after_restore, Ok(false)), "未能确认恢复未收藏状态，请在官方客户端核对该曲");
    assert!(add.is_ok(), "收藏请求失败：{add:?}");
    assert!(matches!(after_add, Ok(true)), "写入后未确认已收藏：{after_add:?}");
    println!("reported song: favorite confirmed, original unliked state restored");
}

/// 只读验证 ag-1 请求加密、签名、Cookie 以及响应解码，不提交收藏或取消收藏。
#[tokio::test]
#[ignore]
async fn signed_web_transport_with_readonly_call() {
    use_desktop_test_login();
    let data = client::core().signed_web_musicu("music.vipcgi.VipBannerCgi", "QueryVipBanner", serde_json::json!({})).await.unwrap();
    assert!(data.get("banner").is_some(), "签名加密通道没有返回预期的只读数据");
}
