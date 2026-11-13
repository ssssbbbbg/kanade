//! 根据 QQ 歌曲文件信息和当前账号的取链接结果生成音质列表。

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};
use tokio::task::JoinSet;

use super::client::{core, ANDROID_VERSION};
use super::dts;
use super::encrypted_audio::{verify_encrypted_audio, EncryptedAudio};
use super::error::ApiError;
use super::nac;
use super::parse::{n, s};
use super::qmc::Qmc;
use super::ra360;
use crate::api::types::{Quality, QualityOption, QualityUnavailableReason as Reason, SongUrl};

struct Format {
    quality: Quality,
    prefix: &'static str,
    ext: &'static str,
    field: &'static str,
    index: Option<usize>,
}

// size_new 的已知格式映射参考 QQMusicApi，显示哪些档位由歌曲响应决定。
const FORMATS: &[Format] = &[
    Format {
        quality: Quality::Dts,
        prefix: "DT03",
        ext: "mp4",
        field: "size_new",
        index: Some(9),
    },
    Format {
        quality: Quality::Ra360,
        prefix: "RA04",
        ext: "mp4",
        field: "size_360ra",
        index: Some(3),
    },
    Format {
        quality: Quality::Master,
        prefix: "AI00",
        ext: "flac",
        field: "size_new",
        index: Some(0),
    },
    Format {
        quality: Quality::Atmos,
        prefix: "Q000",
        ext: "flac",
        field: "size_new",
        index: Some(1),
    },
    Format {
        quality: Quality::Atmos71,
        prefix: "Q003",
        ext: "ogg",
        field: "size_new",
        index: Some(6),
    },
    Format {
        quality: Quality::Atmos51,
        prefix: "Q001",
        ext: "flac",
        field: "size_new",
        index: Some(2),
    },
    Format {
        quality: Quality::Dolby,
        prefix: "D004",
        ext: "mp4",
        field: "size_dolby",
        index: None,
    },
    Format {
        quality: Quality::Hires,
        prefix: "RS01",
        ext: "flac",
        field: "size_hires",
        index: None,
    },
    Format {
        quality: Quality::Lossless,
        prefix: "F000",
        ext: "flac",
        field: "size_flac",
        index: None,
    },
    Format {
        quality: Quality::Ogg640,
        prefix: "O801",
        ext: "ogg",
        field: "size_new",
        index: Some(5),
    },
    Format {
        quality: Quality::High,
        prefix: "M800",
        ext: "mp3",
        field: "size_320mp3",
        index: None,
    },
    Format {
        quality: Quality::Ogg320,
        prefix: "O800",
        ext: "ogg",
        field: "size_new",
        index: Some(3),
    },
    Format {
        quality: Quality::Aicodec,
        prefix: "TL01",
        ext: "nac",
        field: "size_new",
        index: Some(7),
    },
    Format {
        quality: Quality::Aac192,
        prefix: "C600",
        ext: "m4a",
        field: "size_192aac",
        index: None,
    },
    Format {
        quality: Quality::Ogg192,
        prefix: "O600",
        ext: "ogg",
        field: "size_192ogg",
        index: None,
    },
    Format {
        quality: Quality::Standard,
        prefix: "M500",
        ext: "mp3",
        field: "size_128mp3",
        index: None,
    },
    Format {
        quality: Quality::Low,
        prefix: "C400",
        ext: "m4a",
        field: "size_96aac",
        index: None,
    },
    Format {
        quality: Quality::Ogg96,
        prefix: "O400",
        ext: "ogg",
        field: "size_96ogg",
        index: None,
    },
    Format {
        quality: Quality::Aac48,
        prefix: "C200",
        ext: "m4a",
        field: "size_48aac",
        index: None,
    },
];

fn unsupported_reason(quality: Quality) -> Option<Reason> {
    match quality {
        Quality::Aicodec if !nac::available() => Some(Reason::Unsupported),
        Quality::Dts if !dts::available() => Some(Reason::Unverified),
        Quality::Ra360 if !ra360::available() => Some(Reason::Unsupported),
        _ => None,
    }
}

/// 这台设备能否播放该音质（DTS:X、360RA、NAC 需要额外的解码器）。
pub fn supported(quality: Quality) -> bool {
    unsupported_reason(quality).is_none()
}

pub(super) fn uses_plain_source(quality: Quality) -> bool {
    // D004 is AC-4. The player can decode the E-AC-3 from D0M1.
    // RA04 is only granted to the Android client version, see `ra360_source`.
    !matches!(quality, Quality::Dolby | Quality::Aicodec | Quality::Ra360)
}

pub(super) fn requires_pcm(quality: Quality) -> bool {
    matches!(quality, Quality::Dts | Quality::Aicodec | Quality::Ra360)
}

fn ensure_playable(quality: Quality) -> Result<()> {
    match unsupported_reason(quality) {
        Some(Reason::Unverified) => bail!(ApiError::UnverifiedFormat),
        Some(_) => bail!(ApiError::UnsupportedFormat),
        None => Ok(()),
    }
}

pub fn file_name(quality: Quality, media_mid: &str) -> Result<String> {
    ensure_playable(quality)?;
    let format = FORMATS
        .iter()
        .find(|f| f.quality == quality)
        .context(ApiError::UnsupportedFormat)?;
    Ok(format!(
        "{}{media_mid}{media_mid}.{}",
        format.prefix, format.ext
    ))
}

pub fn playback_chain(quality: Quality) -> Result<Vec<Quality>> {
    ensure_playable(quality)?;
    let fallback: &[Quality] = match quality {
        Quality::Aac48 => &[],
        Quality::Low | Quality::Ogg96 => &[Quality::Low],
        Quality::Standard | Quality::Ogg192 | Quality::Aac192 => &[Quality::Standard, Quality::Low],
        Quality::High | Quality::Ogg320 | Quality::Ogg640 | Quality::Aicodec => {
            &[Quality::High, Quality::Standard, Quality::Low]
        }
        _ => &[
            Quality::Lossless,
            Quality::High,
            Quality::Standard,
            Quality::Low,
        ],
    };
    let mut chain = vec![quality];
    chain.extend(fallback.iter().copied().filter(|q| *q != quality));
    Ok(chain)
}

/// 比 `quality` 低一档的音质，用于播不了时自动降级；已经是最低档时为 None。
pub fn lower(quality: Quality) -> Option<Quality> {
    playback_chain(quality).ok()?.get(1).copied()
}

/// 歌曲缓存索引里记录的音质标识。
pub fn cache_key(quality: Quality) -> String {
    format!("{quality:?}")
}

pub fn from_cache_key(key: &str) -> Option<Quality> {
    FORMATS
        .iter()
        .map(|f| f.quality)
        .find(|q| cache_key(*q) == key)
}

pub fn extension(quality: Quality) -> &'static str {
    if requires_pcm(quality) {
        return "wav";
    }
    FORMATS
        .iter()
        .find(|f| f.quality == quality)
        .map_or("bin", |f| f.ext)
}

fn options_from_file(file: &Value) -> Vec<QualityOption> {
    FORMATS
        .iter()
        // 编码格式不等于用户音质档位；保留格式映射供取链接使用，菜单只列音质档位。
        .filter(|format| {
            !matches!(
                format.quality,
                Quality::Ogg640
                    | Quality::Ogg320
                    | Quality::Ogg192
                    | Quality::Ogg96
                    | Quality::Aac192
                    | Quality::Aac48
            )
        })
        .filter_map(|format| {
            let size = match format.index {
                Some(index) => n(&file[format.field][index]),
                None => n(&file[format.field]),
            };
            let has_hq_ogg = format.quality == Quality::High && n(&file["size_new"][3]) > 0;
            (size > 0 || has_hq_ogg).then(|| QualityOption {
                quality: format.quality,
                available: false,
                reason: Some(unsupported_reason(format.quality).unwrap_or(Reason::NoLink)),
            })
        })
        .collect()
}

fn grant<'a>(data: &'a Value, filename: &str) -> Result<&'a Value> {
    data["midurlinfo"]
        .as_array()
        .context(ApiError::bad_response(
            "quality response is missing midurlinfo",
        ))?
        .iter()
        .find(|item| item["filename"].as_str() == Some(filename))
        .context(ApiError::bad_response(
            "quality response is missing the requested file",
        ))
}

fn grant_result(item: &Value) -> Result<i64> {
    item["result"].as_i64().context(ApiError::bad_response(
        "quality response is missing grant result",
    ))
}

fn unavailable_reason(item: &Value) -> Result<Reason> {
    Ok(match grant_result(item)? {
        104003 => Reason::NoPermission,
        104013 => Reason::DeviceRestricted,
        _ => Reason::NoLink,
    })
}

pub async fn stream_available(url: &str) -> Result<bool> {
    Ok(core().http.head(url).send().await?.status().is_success())
}

pub(super) struct EncryptedFormat {
    prefix: &'static str,
    vs_index: Option<usize>,
    pub(super) audio: EncryptedAudio,
}

pub(super) fn encrypted_format(quality: Quality) -> Option<EncryptedFormat> {
    use EncryptedAudio::{Flac, Mp4, Nac, Ogg};
    let (prefix, vs_index, audio) = match quality {
        Quality::Master => ("AIM0", Some(3), Flac),
        Quality::Atmos => ("Q0M0", Some(29), Flac),
        Quality::Lossless => ("F0M0", None, Flac),
        Quality::High => ("O8M0", None, Ogg),
        Quality::Dolby => ("D0M1", None, Mp4),
        Quality::Dts if dts::available() => ("DTM3", Some(30), Mp4),
        Quality::Aicodec if nac::available() => ("TLM1", Some(28), Nac),
        _ => return None,
    };
    Some(EncryptedFormat {
        prefix,
        vs_index,
        audio,
    })
}

impl EncryptedFormat {
    fn file_name(&self, id: &str) -> String {
        let ext = match self.audio {
            EncryptedAudio::Flac => "mflac",
            EncryptedAudio::Ogg => "mgg",
            EncryptedAudio::Nac => "mnac",
            EncryptedAudio::Mp4 => "mmp4",
        };
        format!("{}{id}.{ext}", self.prefix)
    }

    fn file_id<'a>(&self, media_mid: &'a str, track: &'a Value) -> Option<&'a str> {
        match self.vs_index {
            Some(index) => track["vs"][index].as_str().filter(|id| !id.is_empty()),
            None => Some(media_mid),
        }
    }
}

pub(super) async fn encrypted_source(
    mid: &str,
    media_mid: &str,
    quality: Quality,
    track: Option<&Value>,
) -> std::result::Result<SongUrl, Reason> {
    let c = core();
    let session = c.session().ok_or(Reason::NoPermission)?;
    let format = encrypted_format(quality).ok_or(Reason::Unsupported)?;
    let fetched;
    let track = match track {
        Some(track) => track,
        None => {
            fetched = quality_track(mid, true)
                .await
                .map_err(|_| Reason::VerifyFailed)?;
            &fetched["tracks"][0]
        }
    };
    let media_mid = track["file"]["media_mid"]
        .as_str()
        .filter(|id| !id.is_empty())
        .unwrap_or(if media_mid.is_empty() { mid } else { media_mid });
    let file_id = format.file_id(media_mid, track).ok_or(Reason::NoLink)?;
    let filename = format.file_name(file_id);
    let param = json!({
        "uin": session.uin, "guid": c.desktop_guid, "ctx": 1,
        "songmid": [mid], "songtype": [0], "filename": [&filename],
        "musicfile": [format.file_name(media_mid)], "checklimit": 0,
        "downloadfrom": 0, "nettype": "", "referer": "y.qq.com", "scene": 0,
    });
    let data = c
        .desktop_musicu("music.vkey.GetEVkey", "CgiGetEVkey", param)
        .await
        .map_err(|_| Reason::VerifyFailed)?;
    let item = grant(&data, &filename).map_err(|_| Reason::VerifyFailed)?;
    let result = grant_result(item).map_err(|_| Reason::VerifyFailed)?;
    let purl = item["purl"].as_str().filter(|url| !url.is_empty());
    let Some(purl) = purl.filter(|_| result == 0) else {
        return Err(unavailable_reason(item).unwrap_or(Reason::VerifyFailed));
    };
    let ekey = item["ekey"].as_str().ok_or(Reason::NoLink)?;
    let cipher = Qmc::from_ekey(ekey).map_err(|_| Reason::NoLink)?;
    let url = if purl.starts_with("https://") {
        purl.to_owned()
    } else {
        let sip = data["sip"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .find(|url| url.starts_with("https://"))
            .unwrap_or("https://isure.stream.qqmusic.qq.com/");
        format!(
            "{}/{}",
            sip.trim_end_matches('/'),
            purl.trim_start_matches('/')
        )
    };
    match verify_encrypted_audio(&c.http, &url, &cipher, format.audio).await {
        Ok(true) => Ok(SongUrl {
            url,
            quality,
            ekey: Some(ekey.to_owned()),
        }),
        Ok(false) => Err(Reason::FileUnavailable),
        Err(_) => Err(Reason::VerifyFailed),
    }
}

/// 360RA 的文件大小和链接只对 Android 客户端版本号开放；PC 和旧版本号的
/// `size_360ra` 是空数组，取链接返回 104003。
fn android_comm() -> Value {
    json!({ "cv": ANDROID_VERSION, "v": ANDROID_VERSION })
}

async fn ra360_sizes(mid: &str) -> Result<Value> {
    let c = core();
    let track = c
        .cached(&format!("quality-track-android:{mid}"), 600, || {
            let param =
                json!({ "ctx": 0, "client": 1, "types": [0], "modify_stamp": [0], "mids": [mid] });
            c.musicu_with_comm(
                "music.trackInfo.UniformRuleCtrl",
                "CgiGetTrackInfo",
                param,
                android_comm(),
            )
        })
        .await?;
    Ok(track["tracks"][0]["file"]["size_360ra"].clone())
}

pub(super) async fn ra360_source(
    mid: &str,
    media_mid: &str,
) -> std::result::Result<SongUrl, Reason> {
    let c = core();
    let filename = file_name(Quality::Ra360, media_mid).map_err(|_| Reason::Unsupported)?;
    let param = json!({
        "guid": c.guid, "uin": c.uin(), "loginflag": 1, "platform": "20", "ctx": 0,
        "songmid": [mid], "songtype": [0], "filename": [&filename],
    });
    let data = c
        .musicu_with_comm("music.vkey.GetVkey", "UrlGetVkey", param, android_comm())
        .await
        .map_err(|_| Reason::VerifyFailed)?;
    let item = grant(&data, &filename).map_err(|_| Reason::VerifyFailed)?;
    let purl = s(&item["purl"]);
    if grant_result(item).map_err(|_| Reason::VerifyFailed)? != 0 || purl.is_empty() {
        return Err(unavailable_reason(item).unwrap_or(Reason::VerifyFailed));
    }
    let sip = data["sip"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .find(|url| url.starts_with("https://"))
        .or_else(|| data["sip"][0].as_str())
        .ok_or(Reason::NoLink)?;
    let url = format!("{sip}{purl}");
    match stream_available(&url).await {
        Ok(true) => Ok(SongUrl {
            url,
            quality: Quality::Ra360,
            ekey: None,
        }),
        Ok(false) => Err(Reason::FileUnavailable),
        Err(_) => Err(Reason::VerifyFailed),
    }
}

async fn quality_track(mid: &str, desktop: bool) -> Result<Value> {
    let c = core();
    c.cached(&format!("quality-track:{mid}"), 600, || async {
        let param =
            json!({ "ctx": 0, "client": 1, "types": [0], "modify_stamp": [0], "mids": [mid] });
        if desktop {
            c.desktop_musicu("music.trackInfo.UniformRuleCtrl", "CgiGetTrackInfo", param)
                .await
        } else {
            c.musicu("music.trackInfo.UniformRuleCtrl", "CgiGetTrackInfo", param)
                .await
        }
    })
    .await
}

pub async fn song_qualities(mid: &str) -> Result<Vec<QualityOption>> {
    let c = core();
    let desktop = c.session().is_some();
    let tracks = quality_track(mid, desktop).await?;
    let track = &tracks["tracks"][0];
    let file = &track["file"];
    if !file.is_object() {
        bail!(ApiError::bad_response(
            "track response is missing file info"
        ));
    }
    let mut options = if ra360::available() {
        let mut file = file.clone();
        file["size_360ra"] = ra360_sizes(mid).await.unwrap_or_default();
        options_from_file(&file)
    } else {
        options_from_file(file)
    };
    let media_mid = s(&file["media_mid"]);
    let media_mid = if media_mid.is_empty() {
        mid
    } else {
        &media_mid
    };
    if desktop && nac::available() && track["vs"][28].as_str().is_some_and(|id| !id.is_empty()) {
        let result = encrypted_source(mid, media_mid, Quality::Aicodec, Some(track)).await;
        if let Some(option) = options
            .iter_mut()
            .find(|option| option.quality == Quality::Aicodec)
        {
            option.available = result.is_ok();
            option.reason = result.err();
        } else if result.is_ok() {
            options.push(QualityOption {
                quality: Quality::Aicodec,
                available: true,
                reason: None,
            });
            options.sort_by_key(|option| FORMATS.iter().position(|f| f.quality == option.quality));
        }
    }
    let files: Vec<_> = options
        .iter()
        .enumerate()
        .filter(|(_, option)| {
            uses_plain_source(option.quality) && unsupported_reason(option.quality).is_none()
        })
        .map(|(index, option)| Ok((index, file_name(option.quality, media_mid)?)))
        .collect::<Result<_>>()?;
    let param = json!({
        "guid": if desktop { &c.desktop_guid } else { &c.guid },
        "uin": c.uin(),
        "loginflag": 1,
        "platform": "20",
        "ctx": 0,
        "filename": files.iter().map(|(_, name)| name).collect::<Vec<_>>(),
        "songmid": vec![mid; files.len()],
        "songtype": vec![0; files.len()],
    });
    let apis: &[(&str, &str)] = if desktop {
        &[("music.vkey.GetVkey", "UrlGetVkey")]
    } else {
        &[
            ("music.vkey.GetVkey", "UrlGetVkey"),
            ("vkey.GetVkeyServer", "CgiGetVkey"),
        ]
    };
    let mut urls: Vec<Option<String>> = vec![None; options.len()];
    let mut responded = files.is_empty();
    let mut last_error = None;
    for &(module, method) in apis {
        if files.iter().all(|(index, _)| urls[*index].is_some()) {
            break;
        }
        let response = if desktop {
            c.desktop_musicu(module, method, param.clone()).await
        } else {
            c.musicu(module, method, param.clone()).await
        };
        let data = match response {
            Ok(data) => data,
            Err(error) => {
                last_error = Some(error);
                continue;
            }
        };
        responded = true;
        for (index, filename) in &files {
            if urls[*index].is_some() {
                continue;
            }
            let item = grant(&data, filename)?;
            let purl = s(&item["purl"]);
            let result = grant_result(item)?;
            if result == 0 && !purl.is_empty() && s(&item["ekey"]).is_empty() {
                let sip = data["sip"]
                    .as_array()
                    .context(ApiError::bad_response("quality response is missing sip"))?
                    .iter()
                    .filter_map(Value::as_str)
                    .find(|url| url.starts_with("https://"))
                    .or_else(|| data["sip"][0].as_str())
                    .context(ApiError::bad_response(
                        "quality response has no CDN address",
                    ))?;
                urls[*index] = Some(format!("{sip}{purl}"));
            } else {
                options[*index].reason = Some(unavailable_reason(item)?);
            }
        }
    }
    if !responded {
        return Err(
            last_error.unwrap_or_else(|| ApiError::bad_response("quality request failed").into())
        );
    }
    if last_error.is_some() {
        for (index, _) in &files {
            if urls[*index].is_none() {
                options[*index].reason = Some(Reason::VerifyFailed);
            }
        }
    }
    let pending: Vec<_> = urls
        .into_iter()
        .enumerate()
        .filter_map(|(index, url)| url.map(|url| (index, url)))
        .collect();
    // HEAD 不下载音频正文；限制并发，防止切歌时同时建立过多 CDN 连接。
    for chunk in pending.chunks(4) {
        let mut checks = JoinSet::new();
        for (index, url) in chunk {
            let (index, url) = (*index, url.clone());
            checks.spawn(async move { (index, stream_available(&url).await) });
        }
        while let Some(check) = checks.join_next().await {
            let (index, available) = check?;
            options[index].available = available?;
            options[index].reason = (!options[index].available).then_some(Reason::FileUnavailable);
        }
    }
    if let Some(option) = options.iter_mut().find(|option| {
        option.quality == Quality::Ra360 && unsupported_reason(option.quality).is_none()
    }) {
        let result = ra360_source(mid, media_mid).await;
        option.available = result.is_ok();
        option.reason = result.err();
    }
    if desktop {
        for option in options.iter_mut().filter(|option| {
            !option.available
                && option.quality != Quality::Aicodec
                && encrypted_format(option.quality).is_some()
        }) {
            let result = encrypted_source(mid, media_mid, option.quality, Some(track)).await;
            if result.is_ok() || !uses_plain_source(option.quality) {
                option.available = result.is_ok();
                option.reason = result.err();
            }
        }
    }
    Ok(options)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uses_per_quality_ids_for_encrypted_files() {
        let mut vs = vec![""; 31];
        vs[3] = "master";
        vs[29] = "atmos";
        vs[30] = "dts";
        let track = json!({ "vs": vs });
        for (quality, expected) in [
            (Quality::Master, "AIM0master.mflac"),
            (Quality::Atmos, "Q0M0atmos.mflac"),
            (Quality::Lossless, "F0M0media.mflac"),
            (Quality::High, "O8M0media.mgg"),
            (Quality::Dolby, "D0M1media.mmp4"),
        ] {
            let format = encrypted_format(quality).unwrap();
            assert_eq!(
                format.file_name(format.file_id("media", &track).unwrap()),
                expected
            );
        }
        assert_eq!(
            encrypted_format(Quality::Master)
                .unwrap()
                .file_id("media", &Value::Null),
            None
        );
        assert!(encrypted_format(Quality::Hires).is_none());
        assert!(encrypted_format(Quality::Aicodec).is_none());
        if let Some(format) = encrypted_format(Quality::Dts) {
            assert_eq!(
                format.file_name(format.file_id("media", &track).unwrap()),
                "DTM3dts.mmp4"
            );
        }
        assert!(EncryptedAudio::Mp4.matches_header(b"\0\0\0\x18ftyp"));
        assert!(!EncryptedAudio::Mp4.matches_header(b"fLaC\0\0\0\0"));
    }

    #[test]
    fn lists_quality_tiers_instead_of_all_codec_variants() {
        // “月声尽，心灯明”：旧列表把 6 个额外编码格式也展示成了音质档位。
        let options = options_from_file(&json!({
            "size_new": [4096, 4096, 4096, 1024, 0, 2048, 4096, 0, 0, 0],
            "size_flac": 4096,
            "size_320mp3": 1024,
            "size_192aac": 768,
            "size_192ogg": 768,
            "size_128mp3": 512,
            "size_96aac": 384,
            "size_96ogg": 384,
            "size_48aac": 192,
        }));
        let qualities: Vec<_> = options.iter().map(|option| option.quality).collect();
        assert_eq!(
            qualities,
            vec![
                Quality::Master,
                Quality::Atmos,
                Quality::Atmos71,
                Quality::Atmos51,
                Quality::Lossless,
                Quality::High,
                Quality::Standard,
                Quality::Low,
            ]
        );
        // 没有 Hi-Res 文件时也不能为了补齐档位而添加它。
        assert!(!qualities.contains(&Quality::Hires));
    }

    #[test]
    fn only_lists_formats_present_in_qq_metadata() {
        let options = options_from_file(&json!({
            "size_128mp3": 1024,
            "size_flac": 0,
            "size_dolby": 128,
            "size_new": [4096, 0, 0, 0, 128, 0, 0, 512, 0, 256],
        }));
        let qualities: Vec<_> = options.iter().map(|option| option.quality).collect();
        assert_eq!(
            qualities,
            vec![
                Quality::Dts,
                Quality::Master,
                Quality::Dolby,
                Quality::Aicodec,
                Quality::Standard
            ]
        );
        assert!([0, 2, 3].iter().all(|&index| !options[index].available));
        assert_eq!(options[2].reason, Some(Reason::NoLink));
        assert_eq!(
            options[0].reason,
            Some(if dts::available() {
                Reason::NoLink
            } else {
                Reason::Unverified
            })
        );
        assert_eq!(options[3].reason, Some(Reason::Unsupported));
        assert!(options_from_file(&json!({})).is_empty());
        let hq_only = options_from_file(&json!({ "size_new": [0, 0, 0, 512] }));
        assert_eq!(hq_only.len(), 1);
        assert_eq!(hq_only[0].quality, Quality::High);
    }

    #[test]
    fn lists_360ra_from_the_android_file_sizes() {
        // Mood：Android 版本号返回 RA01–RA04 四个大小，RA04 是最后一个。
        let options = options_from_file(&json!({
            "size_360ra": [5953591, 11807232, 18854392, 28217972],
            "size_new": [0, 0, 0, 0, 0, 0, 0, 0, 0, 256],
        }));
        let qualities: Vec<_> = options.iter().map(|option| option.quality).collect();
        assert_eq!(qualities, vec![Quality::Dts, Quality::Ra360]);
        assert_eq!(
            options[1].reason,
            Some(if ra360::available() {
                Reason::NoLink
            } else {
                Reason::Unsupported
            })
        );
        assert!(options_from_file(&json!({ "size_360ra": [] })).is_empty());
        assert!(!uses_plain_source(Quality::Ra360));
        assert!(requires_pcm(Quality::Ra360));
        assert_eq!(extension(Quality::Ra360), "wav");
        if ra360::available() {
            assert_eq!(file_name(Quality::Ra360, "m").unwrap(), "RA04mm.mp4");
        }
    }

    #[test]
    fn rejects_missing_grants_and_distinguishes_permission_denials() {
        let data =
            json!({ "midurlinfo": [{ "filename": "M800test.mp3", "result": 104003, "purl": "" }] });
        assert_eq!(
            unavailable_reason(grant(&data, "M800test.mp3").unwrap()).unwrap(),
            Reason::NoPermission
        );
        assert!(grant(&data, "F000test.flac").is_err());
        assert!(unavailable_reason(&json!({})).is_err());
    }

    #[test]
    fn keeps_existing_fallback_order_and_handles_new_formats() {
        assert_eq!(
            playback_chain(Quality::High).unwrap(),
            vec![Quality::High, Quality::Standard, Quality::Low]
        );
        assert_eq!(
            playback_chain(Quality::Master).unwrap(),
            vec![
                Quality::Master,
                Quality::Lossless,
                Quality::High,
                Quality::Standard,
                Quality::Low
            ]
        );
        assert_eq!(
            playback_chain(Quality::Ogg96).unwrap(),
            vec![Quality::Ogg96, Quality::Low]
        );
        assert_eq!(
            playback_chain(Quality::Aac48).unwrap(),
            vec![Quality::Aac48]
        );
        assert_eq!(
            playback_chain(Quality::Ogg640).unwrap(),
            vec![
                Quality::Ogg640,
                Quality::High,
                Quality::Standard,
                Quality::Low
            ]
        );
        assert_eq!(
            file_name(Quality::Master, "test").unwrap(),
            "AI00testtest.flac"
        );
        assert_eq!(
            file_name(Quality::Hires, "test").unwrap(),
            "RS01testtest.flac"
        );
        assert_eq!(playback_chain(Quality::Dts).is_ok(), dts::available());
        assert!(!uses_plain_source(Quality::Dolby));
        assert_eq!(lower(Quality::Dolby), Some(Quality::Lossless));
    }
}
