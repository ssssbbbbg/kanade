//! 歌曲缓存。播放器从本机的中转地址取音频，中转一边转发、一边把整首歌写进缓存目录，
//! 下完后记进索引；总大小超过上限时删掉最久没听的歌。

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use anyhow::{bail, Context, Result};
use reqwest::{header, Method, StatusCode};
use tokio::io::{
    AsyncBufReadExt, AsyncReadExt, AsyncSeekExt, AsyncWrite, AsyncWriteExt, BufReader,
};
use tokio::net::TcpStream;
use tokio::runtime::Handle;
use tokio::sync::watch;

use super::client::{core, UA};
use super::encrypted_audio::{content_range, EncryptedAudio};
use super::qmc::Qmc;
use super::quality;
use super::{dts, nac, ra360};
use crate::api::types::Quality;

const LIMIT_PREF: &str = "pref:audio_cache_limit_mb";
const DEFAULT_LIMIT_MB: i64 = 1024;
const MB: i64 = 1024 * 1024;
/// 拖动进度到已下载位置之后这么远时，直接向服务器要那一段，不等后台下载。
const AHEAD: u64 = 512 * 1024;
const REFERER: &str = "https://y.qq.com/";

fn stored_limit_mb() -> i64 {
    core()
        .store
        .kv_get(LIMIT_PREF)
        .and_then(|v| v.parse().ok())
        .unwrap_or(DEFAULT_LIMIT_MB)
}

pub fn limit_mb() -> i64 {
    CACHE
        .get()
        .map_or_else(stored_limit_mb, AudioCache::limit_mb)
}

#[derive(Clone, Copy, Default)]
struct Progress {
    /// 已收到响应头并尝试创建缓存文件。
    started: bool,
    total: Option<u64>,
    downloaded: u64,
    done: bool,
    failed: bool,
}

struct Download {
    mid: String,
    quality: Quality,
    url: String,
    /// 每次下载用自己的文件名，下完记进索引才算缓存上了（没进索引的下次启动时删掉）。
    /// 不用临时文件改名：有些目录下改名会失败（Windows 报 ERROR_NOT_SAME_DEVICE）。
    file_name: String,
    progress: watch::Receiver<Progress>,
    cancelled: AtomicBool,
    cipher: Option<Qmc>,
}

enum Stream {
    Cached(Arc<Download>),
    Encrypted {
        url: String,
        cipher: Qmc,
        audio: EncryptedAudio,
    },
}

pub struct AudioCache {
    dir: PathBuf,
    limit_mb: AtomicI64,
    http: reqwest::Client,
    server: Mutex<Option<(Handle, u16)>>,
    streams: Mutex<HashMap<String, Arc<Stream>>>,
    /// 正在播放的缓存文件名，淘汰和清除时跳过。
    playing: Mutex<Option<String>>,
}

static CACHE: OnceLock<AudioCache> = OnceLock::new();

/// App 启动时调用一次；没调用时（比如单元测试）用临时目录。
pub fn init(dir: PathBuf) -> Result<()> {
    if CACHE.get().is_some() {
        return Ok(());
    }
    let _ = CACHE.set(AudioCache::new(dir)?);
    cache().cleanup();
    Ok(())
}

pub fn cache() -> &'static AudioCache {
    CACHE.get_or_init(|| {
        let dir = std::env::temp_dir().join(format!("kanade-audio-{}", std::process::id()));
        AudioCache::new(dir).unwrap()
    })
}

fn file_name(mid: &str, q: Quality, id: &str) -> String {
    format!(
        "{mid}_{}_{id}.{}",
        quality::cache_key(q),
        quality::extension(q)
    )
}

impl AudioCache {
    fn new(dir: PathBuf) -> Result<Self> {
        std::fs::create_dir_all(&dir)?;
        let limit = stored_limit_mb();
        let http = reqwest::Client::builder()
            .user_agent(UA)
            .connect_timeout(Duration::from_secs(15))
            .read_timeout(Duration::from_secs(30))
            .build()?;
        Ok(Self {
            dir,
            limit_mb: AtomicI64::new(limit),
            http,
            server: Mutex::new(None),
            streams: Mutex::new(HashMap::new()),
            playing: Mutex::new(None),
        })
    }

    /// 删掉没进索引的文件（上次没下完的）和文件已经不在的索引。
    fn cleanup(&self) {
        let store = &core().store;
        let mut known = std::collections::HashSet::new();
        for (mid, q, file, _) in store.audio_lru() {
            if self.dir.join(&file).is_file() {
                known.insert(file);
            } else {
                store.audio_delete(&mid, &q);
            }
        }
        for entry in std::fs::read_dir(&self.dir).into_iter().flatten().flatten() {
            if !known.contains(entry.file_name().to_string_lossy().as_ref()) {
                let _ = std::fs::remove_file(entry.path());
            }
        }
    }

    pub fn limit_mb(&self) -> i64 {
        self.limit_mb.load(Ordering::Relaxed)
    }

    /// 0 表示不再缓存新歌，已缓存的保留。
    pub fn set_limit_mb(&self, mb: i64) -> Result<()> {
        let mb = mb.max(0);
        core().store.kv_set(LIMIT_PREF, &mb.to_string())?;
        self.limit_mb.store(mb, Ordering::Relaxed);
        self.evict();
        Ok(())
    }

    pub fn size(&self) -> i64 {
        core().store.audio_total()
    }

    /// 本地已缓存的这首歌这个音质的文件路径。
    pub fn lookup(&self, mid: &str, q: Quality) -> Option<String> {
        let key = quality::cache_key(q);
        let file = core().store.audio_get(mid, &key)?;
        self.open_cached(mid, &key, file)
    }

    /// 这首歌任一音质的缓存，没网时用。
    pub fn lookup_any(&self, mid: &str) -> Option<(String, Quality)> {
        core()
            .store
            .audio_of(mid)
            .into_iter()
            .find_map(|(key, file)| {
                let q = quality::from_cache_key(&key)?;
                core().store.audio_get(mid, &key)?;
                Some((self.open_cached(mid, &key, file)?, q))
            })
    }

    fn open_cached(&self, mid: &str, key: &str, file: String) -> Option<String> {
        let path = self.dir.join(&file);
        if !path.is_file() {
            core().store.audio_delete(mid, key);
            return None;
        }
        self.cancel_downloads();
        *self.playing.lock().unwrap() = Some(file);
        Some(path.to_string_lossy().into_owned())
    }

    /// 缓存文件播不了时删掉它。
    pub fn remove(&self, mid: &str, q: Quality) {
        let key = quality::cache_key(q);
        if let Some(file) = core().store.audio_get(mid, &key) {
            let _ = std::fs::remove_file(self.dir.join(file));
        }
        core().store.audio_delete(mid, &key);
    }

    /// 删掉所有歌曲缓存（正在播放和删不掉的文件除外）。
    pub fn clear(&self) {
        let playing = self.playing.lock().unwrap().clone();
        let store = &core().store;
        for (mid, q, file, _) in store.audio_lru() {
            if playing.as_ref() == Some(&file) {
                continue;
            }
            match std::fs::remove_file(self.dir.join(&file)) {
                Err(e) if e.kind() != std::io::ErrorKind::NotFound => continue,
                _ => store.audio_delete(&mid, &q),
            }
        }
    }

    /// 加密音频由本机中转解密。普通音频在启用缓存时中转。
    pub fn stream(
        &'static self,
        mid: &str,
        q: Quality,
        url: &str,
        ekey: Option<&str>,
    ) -> Result<String> {
        let decode = quality::requires_pcm(q);
        let cipher = if let Some(ekey) = ekey {
            let audio = quality::encrypted_format(q)
                .context("unsupported encrypted audio quality")?
                .audio;
            let cipher = Qmc::from_ekey(ekey)?;
            if decode {
                Some(cipher)
            } else {
                let (_, port) = self.server()?;
                let id = uuid::Uuid::new_v4().simple().to_string();
                self.cancel_downloads();
                self.streams.lock().unwrap().insert(
                    id.clone(),
                    Arc::new(Stream::Encrypted {
                        url: url.to_owned(),
                        cipher,
                        audio,
                    }),
                );
                *self.playing.lock().unwrap() = None;
                return Ok(format!("http://127.0.0.1:{port}/a/{id}"));
            }
        } else {
            None
        };
        if self.limit_mb() <= 0 && !decode {
            self.cancel_downloads();
            return Ok(url.to_owned());
        }
        let (handle, port) = self.server()?;
        self.cancel_downloads();
        let id = uuid::Uuid::new_v4().simple().to_string();
        let file = file_name(mid, q, &id);
        let (tx, rx) = watch::channel(Progress::default());
        let d = Arc::new(Download {
            mid: mid.to_owned(),
            quality: q,
            url: url.to_owned(),
            file_name: file.clone(),
            progress: rx,
            cancelled: AtomicBool::new(false),
            cipher,
        });
        self.streams
            .lock()
            .unwrap()
            .insert(id.clone(), Arc::new(Stream::Cached(d.clone())));
        *self.playing.lock().unwrap() = Some(file);
        handle.spawn(self.download(d, tx));
        Ok(format!("http://127.0.0.1:{port}/a/{id}"))
    }

    /// 解码出第一段数据后再让播放器打开本地地址，解码失败时调用方可以降档。
    pub async fn wait_for_decoded(&self, url: &str) -> Result<()> {
        let (_, id) = url
            .rsplit_once("/a/")
            .context("invalid decoded audio URL")?;
        let stream = self.streams.lock().unwrap().get(id).cloned();
        let Some(Stream::Cached(d)) = stream.as_deref() else {
            bail!("decoded audio source was replaced");
        };
        let mut progress = d.progress.clone();
        let ready = progress.wait_for(|p| p.started || p.failed).await?.started;
        if !ready || d.cancelled.load(Ordering::Relaxed) {
            bail!("audio decode did not complete");
        }
        Ok(())
    }

    /// 换歌后之前没下完的歌不再下载。
    fn cancel_downloads(&self) {
        for (_, stream) in self.streams.lock().unwrap().drain() {
            if let Stream::Cached(d) = stream.as_ref() {
                d.cancelled.store(true, Ordering::Relaxed);
                if quality::requires_pcm(d.quality) {
                    let _ = std::fs::remove_file(self.dir.join(&d.file_name));
                }
            }
        }
    }

    fn server(&'static self) -> Result<(Handle, u16)> {
        let mut server = self.server.lock().unwrap();
        if let Some(s) = server.as_ref() {
            return Ok(s.clone());
        }
        let listener = std::net::TcpListener::bind("127.0.0.1:0")?;
        listener.set_nonblocking(true)?;
        let port = listener.local_addr()?.port();
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::Builder::new()
            .name("audio-cache".into())
            .spawn(move || {
                let rt = match tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                {
                    Ok(rt) => rt,
                    Err(e) => return drop(tx.send(Err(e))),
                };
                let _ = tx.send(Ok(rt.handle().clone()));
                rt.block_on(async move {
                    let Ok(listener) = tokio::net::TcpListener::from_std(listener) else {
                        return;
                    };
                    loop {
                        if let Ok((sock, _)) = listener.accept().await {
                            tokio::spawn(async move {
                                let _ = self.serve(sock).await;
                            });
                        }
                    }
                });
            })?;
        let handle = rx.recv().context("audio cache server did not start")??;
        *server = Some((handle.clone(), port));
        Ok((handle, port))
    }

    async fn download(&'static self, d: Arc<Download>, tx: watch::Sender<Progress>) {
        let decode = quality::requires_pcm(d.quality);
        let result = if decode {
            self.fetch_pcm(d.clone(), tx.clone()).await
        } else {
            self.fetch(&d, &tx).await
        };
        match result {
            Ok(size) if decode && !d.cancelled.load(Ordering::Relaxed) => {
                tx.send_modify(|p| {
                    p.started = true;
                    p.total = Some(size);
                    p.downloaded = size;
                    p.done = true;
                });
            }
            Ok(size) if !d.cancelled.load(Ordering::Relaxed) => {
                let store = &core().store;
                let key = quality::cache_key(d.quality);
                // 同一首同一音质之前的缓存文件被这次替换
                let old = store.audio_of(&d.mid).into_iter().find(|(q, _)| *q == key);
                if store
                    .audio_put(&d.mid, &key, &d.file_name, size as i64)
                    .is_ok()
                {
                    if let Some((_, old)) = old {
                        let _ = std::fs::remove_file(self.dir.join(old));
                    }
                    self.evict();
                } else {
                    let _ = std::fs::remove_file(self.dir.join(&d.file_name));
                }
                tx.send_modify(|p| {
                    p.total = Some(size);
                    p.done = true;
                });
            }
            _ => {
                let _ = std::fs::remove_file(self.dir.join(&d.file_name));
                tx.send_modify(|p| p.failed = true);
            }
        }
    }

    async fn fetch_pcm(&self, d: Arc<Download>, tx: watch::Sender<Progress>) -> Result<u64> {
        // 360RA 码率远高于其他需要解码的音质。
        let max_encoded_bytes: usize =
            if d.quality == Quality::Ra360 { 128 } else { 32 } * 1024 * 1024;
        let mut resp = self
            .http
            .get(&d.url)
            .header("Referer", REFERER)
            .send()
            .await?
            .error_for_status()?;
        let mut encoded = Vec::new();
        while let Some(chunk) = resp.chunk().await? {
            if d.cancelled.load(Ordering::Relaxed)
                || encoded.len() + chunk.len() > max_encoded_bytes
            {
                bail!("audio download cancelled or too large");
            }
            encoded.extend_from_slice(&chunk);
        }
        let output = self.dir.join(&d.file_name);
        tokio::task::spawn_blocking(move || {
            if let Some(cipher) = &d.cipher {
                cipher.decrypt(&mut encoded, 0);
            }
            // 解码器预先算好 WAV 总大小，边解边让播放器读。
            let progress = |written, total| {
                tx.send_modify(|p| {
                    p.started = true;
                    p.total = Some(total);
                    p.downloaded = written;
                })
            };
            match d.quality {
                Quality::Dts => dts::decode(&encoded, &output, &d.cancelled, &progress),
                Quality::Aicodec => nac::decode(&encoded, &output, &d.cancelled, &progress),
                Quality::Ra360 => ra360::decode(&encoded, &output, &d.cancelled, &progress),
                _ => unreachable!("only decoded qualities use this download"),
            }
        })
        .await?
    }

    /// 整首下载到临时文件，返回大小。被取消或没下完时报错。
    async fn fetch(&self, d: &Download, tx: &watch::Sender<Progress>) -> Result<u64> {
        let mut resp = self
            .http
            .get(&d.url)
            .header("Referer", REFERER)
            .send()
            .await?
            .error_for_status()?;
        let total = resp.content_length();
        let file = tokio::fs::File::create(self.dir.join(&d.file_name)).await;
        tx.send_modify(|p| {
            p.started = true;
            p.total = total;
        });
        let mut f = file?;
        let mut buf = Vec::with_capacity(256 * 1024);
        let mut written = 0u64;
        loop {
            let chunk = resp.chunk().await?;
            if d.cancelled.load(Ordering::Relaxed) {
                bail!("cancelled");
            }
            if let Some(c) = &chunk {
                buf.extend_from_slice(c);
            }
            // 第一批直接写，后续再攒批；flush 后才通知播放器读取。
            if !buf.is_empty() && (written == 0 || chunk.is_none() || buf.len() >= 64 * 1024) {
                f.write_all(&buf).await?;
                f.flush().await?;
                written += buf.len() as u64;
                buf.clear();
                tx.send_modify(|p| p.downloaded = written);
            }
            if chunk.is_none() {
                break;
            }
        }
        f.sync_all().await?;
        drop(f);
        if written == 0 || total.is_some_and(|t| t != written) {
            bail!("incomplete download");
        }
        Ok(written)
    }

    fn evict(&self) {
        let limit = self.limit_mb();
        if limit <= 0 {
            return;
        }
        let store = &core().store;
        let mut total = store.audio_total();
        let playing = self.playing.lock().unwrap().clone();
        for (mid, q, file, size) in store.audio_lru() {
            if total <= limit * MB {
                break;
            }
            if playing.as_ref() == Some(&file) {
                continue;
            }
            match std::fs::remove_file(self.dir.join(&file)) {
                Err(e) if e.kind() != std::io::ErrorKind::NotFound => continue,
                _ => store.audio_delete(&mid, &q),
            }
            total -= size;
        }
    }

    /// 处理播放器的一个 HTTP 请求（只支持 GET/HEAD 和 Range）。
    async fn serve(&self, mut sock: TcpStream) -> Result<()> {
        let (r, mut w) = sock.split();
        let mut r = BufReader::new(r);
        let mut line = String::new();
        r.read_line(&mut line).await?;
        let mut parts = line.split_whitespace();
        let head = parts.next() == Some("HEAD");
        let path = parts.next().unwrap_or_default().to_owned();
        let mut range = None;
        loop {
            let mut h = String::new();
            if r.read_line(&mut h).await? == 0 || h.trim_end().is_empty() {
                break;
            }
            if let Some((k, v)) = h.split_once(':') {
                if k.trim().eq_ignore_ascii_case("range") {
                    range = parse_range(v.trim());
                }
            }
        }
        let id = path.strip_prefix("/a/").unwrap_or_default();
        let stream = self.streams.lock().unwrap().get(id).cloned();
        let Some(stream) = stream else {
            w.write_all(
                b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            )
            .await?;
            return Ok(());
        };
        let d = match stream.as_ref() {
            Stream::Cached(d) => d,
            Stream::Encrypted { url, cipher, audio } => {
                return self
                    .serve_encrypted(url, cipher, *audio, head, range, &mut w)
                    .await;
            }
        };
        let mut rx = d.progress.clone();
        let p = *rx.wait_for(|p| p.started || p.failed).await?;
        if !p.started {
            w.write_all(
                b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            )
            .await?;
            return Ok(());
        }
        let mime = match quality::extension(d.quality) {
            "mp3" => "audio/mpeg",
            "flac" => "audio/flac",
            "ogg" => "audio/ogg",
            "wav" => "audio/wav",
            _ => "audio/mp4",
        };
        let Some(total) = p.total else {
            // 服务器没给长度时不支持拖动，按顺序转发
            let header =
                format!("HTTP/1.1 200 OK\r\nContent-Type: {mime}\r\nConnection: close\r\n\r\n");
            w.write_all(header.as_bytes()).await?;
            if !head {
                self.send_file(d, 0, None, &mut w).await?;
            }
            return Ok(());
        };
        let (start, end) = match range {
            Some((s, e)) => (s, e.unwrap_or(u64::MAX).min(total.saturating_sub(1))),
            None => (0, total.saturating_sub(1)),
        };
        if start >= total {
            let header = format!(
                "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */{total}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            );
            w.write_all(header.as_bytes()).await?;
            return Ok(());
        }
        let status = if range.is_some() {
            format!("206 Partial Content\r\nContent-Range: bytes {start}-{end}/{total}")
        } else {
            "200 OK".to_owned()
        };
        let header = format!(
            "HTTP/1.1 {status}\r\nContent-Type: {mime}\r\nContent-Length: {}\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n",
            end - start + 1
        );
        w.write_all(header.as_bytes()).await?;
        if head {
            return Ok(());
        }
        // 解码音频没有远端可转发，拖到还没解出的位置时等解码追上。
        if !quality::requires_pcm(d.quality) && start > d.progress.borrow().downloaded + AHEAD {
            self.forward(d, start, end, &mut w).await
        } else {
            self.send_file(d, start, Some(end + 1), &mut w).await
        }
    }

    async fn serve_encrypted(
        &self,
        url: &str,
        cipher: &Qmc,
        audio: EncryptedAudio,
        head: bool,
        range: Option<(u64, Option<u64>)>,
        w: &mut (impl AsyncWrite + Unpin),
    ) -> Result<()> {
        let mut req = self
            .http
            .request(if head { Method::HEAD } else { Method::GET }, url)
            .header(header::REFERER, REFERER)
            .header(header::ACCEPT_ENCODING, "identity");
        if let Some((start, end)) = range {
            req = req.header(
                header::RANGE,
                format!(
                    "bytes={start}-{}",
                    end.map_or_else(String::new, |n| n.to_string())
                ),
            );
        }
        let mut resp = req.send().await?;
        let (status, mut offset, length) = match (resp.status(), range) {
            (StatusCode::OK, None) => {
                let length = resp
                    .headers()
                    .get(header::CONTENT_LENGTH)
                    .and_then(|value| value.to_str().ok())
                    .and_then(|value| value.parse::<usize>().ok())
                    .context("encrypted stream has no content length")?;
                ("200 OK".to_owned(), 0, length)
            }
            (StatusCode::PARTIAL_CONTENT, Some((requested_start, requested_end))) => {
                let (start, end, total) =
                    content_range(&resp).context("invalid encrypted stream range")?;
                if start as u64 != requested_start
                    || end as u64 != requested_end.unwrap_or(u64::MAX).min(total as u64 - 1)
                {
                    bail!("encrypted stream returned a different range");
                }
                (
                    format!("206 Partial Content\r\nContent-Range: bytes {start}-{end}/{total}"),
                    start,
                    end - start + 1,
                )
            }
            _ => {
                w.write_all(
                    b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                )
                .await?;
                return Ok(());
            }
        };
        let mime = audio.mime();
        let header = format!("HTTP/1.1 {status}\r\nContent-Type: {mime}\r\nContent-Length: {length}\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n");
        w.write_all(header.as_bytes()).await?;
        if head {
            return Ok(());
        }
        let mut remaining = length;
        while remaining > 0 {
            let chunk = resp.chunk().await?.context("incomplete encrypted stream")?;
            let mut bytes = chunk[..chunk.len().min(remaining)].to_vec();
            cipher.decrypt(&mut bytes, offset);
            w.write_all(&bytes).await?;
            offset += bytes.len();
            remaining -= bytes.len();
        }
        Ok(())
    }

    /// 从正在下载（或已下完）的文件里读 [start, end)，没下到的部分等着。
    /// 后台下载失败时剩下的部分改为直接转发。
    async fn send_file(
        &self,
        d: &Download,
        start: u64,
        end: Option<u64>,
        w: &mut (impl AsyncWrite + Unpin),
    ) -> Result<()> {
        let Ok(mut file) = tokio::fs::File::open(self.dir.join(&d.file_name)).await else {
            return match end {
                Some(end) => self.forward(d, start, end - 1, w).await,
                None => Ok(()),
            };
        };
        file.seek(std::io::SeekFrom::Start(start)).await?;
        let mut rx = d.progress.clone();
        let mut buf = vec![0u8; 64 * 1024];
        let mut pos = start;
        while end.is_none_or(|e| pos < e) {
            let p = *rx
                .wait_for(|p| p.downloaded > pos || p.done || p.failed)
                .await?;
            if p.downloaded <= pos {
                if let (true, Some(end)) = (p.failed, end) {
                    return self.forward(d, pos, end - 1, w).await;
                }
                break;
            }
            let want =
                (p.downloaded.min(end.unwrap_or(u64::MAX)) - pos).min(buf.len() as u64) as usize;
            let n = file.read(&mut buf[..want]).await?;
            if n == 0 {
                break;
            }
            w.write_all(&buf[..n]).await?;
            pos += n as u64;
        }
        Ok(())
    }

    /// 直接向服务器要 [start, end] 这一段转给播放器。
    async fn forward(
        &self,
        d: &Download,
        start: u64,
        end: u64,
        w: &mut (impl AsyncWrite + Unpin),
    ) -> Result<()> {
        if quality::requires_pcm(d.quality) {
            bail!("decoded audio is unavailable");
        }
        let mut resp = self
            .http
            .get(&d.url)
            .header("Referer", REFERER)
            .header("Range", format!("bytes={start}-{end}"))
            .send()
            .await?
            .error_for_status()?;
        while let Some(c) = resp.chunk().await? {
            w.write_all(&c).await?;
        }
        Ok(())
    }
}

/// `bytes=起点-[终点]`；不支持只给结尾长度的写法。
fn parse_range(v: &str) -> Option<(u64, Option<u64>)> {
    let (s, e) = v
        .strip_prefix("bytes=")?
        .split(',')
        .next()?
        .split_once('-')?;
    let start = s.trim().parse().ok()?;
    let end = e.trim();
    Some((
        start,
        if end.is_empty() {
            None
        } else {
            Some(end.parse().ok()?)
        },
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::qq::encrypted_audio::verify_encrypted_audio;

    /// 假的音频服务器：支持 Range，发出第一批后等待测试放行。
    fn fake_upstream(data: Arc<Vec<u8>>) -> (String, std::sync::mpsc::Sender<()>) {
        use std::io::{BufRead, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let (resume, wait) = std::sync::mpsc::channel();
        let wait = Arc::new(Mutex::new(Some(wait)));
        std::thread::spawn(move || {
            for sock in listener.incoming().flatten() {
                let data = data.clone();
                let wait = wait.clone();
                std::thread::spawn(move || {
                    let mut r = std::io::BufReader::new(sock.try_clone().unwrap());
                    let mut range = None;
                    loop {
                        let mut h = String::new();
                        if r.read_line(&mut h).unwrap_or(0) == 0 || h.trim().is_empty() {
                            break;
                        }
                        if let Some(v) = h
                            .strip_prefix("Range:")
                            .or_else(|| h.strip_prefix("range:"))
                        {
                            range = parse_range(v.trim());
                        }
                    }
                    let mut w = sock;
                    let total = data.len();
                    let (start, end) = range.map_or((0, total - 1), |(s, e)| {
                        (s as usize, e.map_or(total - 1, |e| e as usize))
                    });
                    let head = if range.is_some() {
                        format!("HTTP/1.1 206 Partial Content\r\nContent-Range: bytes {start}-{end}/{total}\r\n")
                    } else {
                        "HTTP/1.1 200 OK\r\n".to_owned()
                    };
                    let _ = write!(
                        w,
                        "{head}Content-Length: {}\r\nConnection: close\r\n\r\n",
                        end - start + 1
                    );
                    for (i, chunk) in data[start..=end].chunks(32 * 1024).enumerate() {
                        if w.write_all(chunk).is_err() {
                            return;
                        }
                        if range.is_none() && i == 0 {
                            let signal = wait.lock().unwrap().take();
                            if signal.is_some_and(|signal| signal.recv().is_err()) {
                                return;
                            }
                        }
                        std::thread::sleep(Duration::from_millis(5));
                    }
                });
            }
        });
        (format!("http://127.0.0.1:{port}/song.mp3"), resume)
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn decrypts_audio_ranges_and_streams_without_disk_cache() {
        use crate::qq::qmc::tests::encode_test_ekey;

        let key: Vec<_> = (0..512).map(|i| (i % 251 + 1) as u8).collect();
        let ekey = encode_test_ekey(&key, true);
        let cipher = Qmc::from_ekey(&ekey).unwrap();
        let mut audio = b"OggS".to_vec();
        audio.extend((4..100_000).map(|i| (i % 251) as u8));
        let mut encrypted = audio.clone();
        cipher.decrypt(&mut encrypted, 0);
        let (upstream, resume) = fake_upstream(Arc::new(encrypted));
        let dir = std::env::temp_dir().join(format!("kanade-qmc-{}", uuid::Uuid::new_v4()));
        let cache = Box::leak(Box::new(AudioCache::new(dir.clone()).unwrap()));
        cache.limit_mb.store(0, Ordering::Relaxed);
        let http = reqwest::Client::new();

        assert!(
            verify_encrypted_audio(&http, &upstream, &cipher, EncryptedAudio::Ogg)
                .await
                .unwrap()
        );
        let local = cache
            .stream("hq", Quality::High, &upstream, Some(&ekey))
            .unwrap();
        let response = http
            .get(&local)
            .header("Range", "bytes=5080-5240")
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(
            response.headers()[header::CONTENT_RANGE],
            "bytes 5080-5240/100000"
        );
        assert_eq!(
            response.bytes().await.unwrap().as_ref(),
            &audio[5080..=5240]
        );

        let mut response = http.get(&local).send().await.unwrap();
        assert_eq!(response.headers()[header::CONTENT_TYPE], "audio/ogg");
        let first = tokio::time::timeout(Duration::from_secs(3), response.chunk())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert!(audio.starts_with(&first));
        resume.send(()).unwrap();
        let mut body = first.to_vec();
        body.extend_from_slice(&response.bytes().await.unwrap());
        assert_eq!(body, audio);
        std::fs::remove_dir(dir).unwrap();
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn streams_caches_and_evicts() {
        let data: Arc<Vec<u8>> = Arc::new((0..700_000u32).map(|i| (i % 251) as u8).collect());
        let (upstream, resume) = fake_upstream(data.clone());
        let c = cache();
        let http = reqwest::Client::new();

        let local = c.stream("mid1", Quality::High, &upstream, None).unwrap();
        assert!(local.starts_with("http://127.0.0.1:"));
        // 远处的一段：后台还没下到，走直接转发
        let r = http
            .get(&local)
            .header("Range", "bytes=600000-600999")
            .send()
            .await
            .unwrap();
        assert_eq!(r.status(), 206);
        assert_eq!(r.bytes().await.unwrap().as_ref(), &data[600_000..601_000]);
        // 上游停在第一批数据时，播放器已经能读到它。
        let mut response = http.get(&local).send().await.unwrap();
        let first = tokio::time::timeout(Duration::from_secs(3), response.chunk())
            .await
            .expect("the first chunk was held back")
            .unwrap()
            .unwrap();
        assert!(data.starts_with(&first));
        resume.send(()).unwrap();
        let mut body = first.to_vec();
        body.extend_from_slice(&response.bytes().await.unwrap());
        assert_eq!(body.as_slice(), data.as_slice());

        let mut path = None;
        for _ in 0..100 {
            path = c.lookup("mid1", Quality::High);
            if path.is_some() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        let path = path.expect("song was not cached");
        assert_eq!(std::fs::read(&path).unwrap(), *data);
        assert_eq!(c.lookup_any("mid1").map(|(_, q)| q), Some(Quality::High));
        assert_eq!(c.size(), data.len() as i64);

        // 淘汰：上限 1GB，塞两首“600MB”的假记录，最久没听的被删
        let store = &core().store;
        for mid in ["old", "new"] {
            let file = file_name(mid, Quality::Standard, "test");
            std::fs::write(c.dir.join(&file), b"x").unwrap();
            store
                .audio_put(mid, &quality::cache_key(Quality::Standard), &file, 600 * MB)
                .unwrap();
            std::thread::sleep(Duration::from_millis(5));
        }
        c.set_limit_mb(1024).unwrap();
        assert!(c.lookup("old", Quality::Standard).is_none());
        assert!(c.lookup("new", Quality::Standard).is_some());

        // 关闭后直接返回原链接
        c.set_limit_mb(0).unwrap();
        assert_eq!(
            c.stream("mid2", Quality::High, &upstream, None).unwrap(),
            upstream
        );

        c.clear();
        assert!(c.lookup("mid1", Quality::High).is_none());
    }

    #[test]
    fn parses_ranges() {
        assert_eq!(parse_range("bytes=0-"), Some((0, None)));
        assert_eq!(parse_range("bytes=100-199"), Some((100, Some(199))));
        assert_eq!(parse_range("bytes=-500"), None);
    }
}
