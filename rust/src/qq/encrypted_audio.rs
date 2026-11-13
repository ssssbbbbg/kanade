//! 加密音频的格式识别与远端文件头验证，供音质判断和流式播放共用。

use anyhow::Result;
use reqwest::{header, Response, StatusCode};

use super::qmc::Qmc;

const REFERER: &str = "https://y.qq.com/";

#[derive(Clone, Copy)]
pub(super) enum EncryptedAudio {
    Flac,
    Ogg,
    Nac,
    Mp4,
}

impl EncryptedAudio {
    pub(super) fn matches_header(self, header: &[u8; 8]) -> bool {
        match self {
            Self::Flac => header.starts_with(b"fLaC"),
            Self::Ogg => header.starts_with(b"OggS"),
            Self::Nac => header.starts_with(b"NAC_"),
            Self::Mp4 => &header[4..] == b"ftyp",
        }
    }

    pub(super) fn mime(self) -> &'static str {
        match self {
            Self::Flac => "audio/flac",
            Self::Ogg => "audio/ogg",
            Self::Nac => "audio/wav",
            Self::Mp4 => "audio/mp4",
        }
    }
}

pub(super) fn content_range(resp: &Response) -> Option<(usize, usize, usize)> {
    let value = resp
        .headers()
        .get(header::CONTENT_RANGE)?
        .to_str()
        .ok()?
        .strip_prefix("bytes ")?;
    let (bounds, total) = value.split_once('/')?;
    let (start, end) = bounds.split_once('-')?;
    let (start, end, total) = (start.parse().ok()?, end.parse().ok()?, total.parse().ok()?);
    (start <= end && end < total).then_some((start, end, total))
}

pub(super) async fn verify_encrypted_audio(
    http: &reqwest::Client,
    url: &str,
    cipher: &Qmc,
    audio: EncryptedAudio,
) -> Result<bool> {
    let mut resp = http
        .get(url)
        .header(header::REFERER, REFERER)
        .header(header::ACCEPT_ENCODING, "identity")
        .header(header::RANGE, "bytes=0-7")
        .send()
        .await?;
    if resp.status() != StatusCode::PARTIAL_CONTENT
        || !matches!(content_range(&resp), Some((0, 7, _)))
    {
        return Ok(false);
    }
    let mut magic = [0; 8];
    let mut read = 0;
    while read < magic.len() {
        let Some(chunk) = resp.chunk().await? else {
            return Ok(false);
        };
        let count = chunk.len().min(magic.len() - read);
        magic[read..read + count].copy_from_slice(&chunk[..count]);
        read += count;
    }
    cipher.decrypt(&mut magic, 0);
    Ok(audio.matches_header(&magic))
}
