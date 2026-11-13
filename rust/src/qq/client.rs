//! 网络客户端、登录态和缓存的统一入口。

use std::future::Future;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{OnceLock, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use super::error::ApiError;
use super::sign::{decode_ag1, encrypt_ag1, hash33, sign};
use super::store::Store;
use crate::api::types::SessionEndReason;

pub const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36";
const MUSICU: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const MUSICS: &str = "https://u.y.qq.com/cgi-bin/musics.fcg";
const DESKTOP_MUSICU: &str = "https://u6.y.qq.com/cgi-bin/musicu.fcg";
const DESKTOP_UA: &str = "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)";
pub(super) const ANDROID_VERSION: i64 = 14090008;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub uin: String,
    pub musickey: String,
    /// 2 = QQ 登录，1 = 微信登录
    pub login_type: i32,
    #[serde(default)]
    pub nickname: String,
    #[serde(default)]
    pub avatar_url: String,
    /// musickey 到期时间（Unix 秒），0 表示不知道。
    #[serde(default)]
    pub expires_at: i64,
}

impl Session {
    pub fn new(uin: String, musickey: String, login_type: i32, expires_at: i64) -> Self {
        Self { uin, musickey, login_type, nickname: String::new(), avatar_url: String::new(), expires_at }
    }

    fn end_reason(&self, now_secs: i64) -> SessionEndReason {
        match self.expires_at {
            0 => SessionEndReason::Unknown,
            t if now_secs >= t => SessionEndReason::Expired,
            _ => SessionEndReason::Revoked,
        }
    }
}

type SessionEndHook = Box<dyn Fn(SessionEndReason) + Send + Sync>;

/// 只有注册了监听的进程（界面进程）才会自动退出登录；Android 播放进程不注册。
static SESSION_END: RwLock<Option<SessionEndHook>> = RwLock::new(None);
static VERIFYING: AtomicBool = AtomicBool::new(false);

pub fn on_session_end(hook: impl Fn(SessionEndReason) + Send + Sync + 'static) {
    *SESSION_END.write().unwrap() = Some(Box::new(hook));
}

#[cfg(test)]
thread_local! {
    pub(crate) static SESSION_CHECKS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

/// 已登录的请求收到 1000 时调用，在后台复核一次，避免个别接口的 1000 误伤登录态。
pub fn suspect_session() {
    #[cfg(test)]
    SESSION_CHECKS.with(|count| count.set(count.get() + 1));
    if SESSION_END.read().unwrap().is_none() {
        return;
    }
    if let Ok(runtime) = tokio::runtime::Handle::try_current() {
        runtime.spawn(verify_session());
    }
}

/// 用「最近播放」复核登录态（凭证失效时稳定返回 1000）；确认失效就退出登录并通知界面。
pub async fn verify_session() {
    let c = core();
    let Some(session) = c.session() else { return };
    if VERIFYING.swap(true, Ordering::SeqCst) {
        return;
    }
    let result = c
        .desktop_private(
            "music.musicasset.PlayRecentlyRead",
            "GetPlayRecentlyInfo",
            json!({ "requestCnt": 1, "type": 2, "updateTime": 0 }),
        )
        .await;
    VERIFYING.store(false, Ordering::SeqCst);
    // 直接检查错误链；会话副作用仅由 API 边界触发。
    let rejected = result.err().is_some_and(|e| e.chain().any(|c| c.downcast_ref::<ApiError>().is_some_and(ApiError::is_auth_rejected)));
    // 复核期间退出或换了账号就不动
    if !rejected || c.session().is_none_or(|s| s.musickey != session.musickey) {
        return;
    }
    if c.set_session(None).is_err() {
        return;
    }
    let _ = c.store.cache_clear();
    if let Some(hook) = SESSION_END.read().unwrap().as_ref() {
        hook(session.end_reason((now_ms() / 1000) as i64));
    }
}

pub struct Core {
    pub http: reqwest::Client,
    pub store: Store,
    pub guid: String,
    pub desktop_guid: String,
    session: RwLock<Option<Session>>,
}

static CORE: OnceLock<Core> = OnceLock::new();

/// App 启动时调用一次；没调用时（比如单元测试）使用内存数据库。
pub fn init(data_dir: &Path) -> Result<()> {
    if CORE.get().is_some() {
        return Ok(());
    }
    init_store(data_dir)?;
    super::audio_cache::init(data_dir.join("audio_cache"))
}

pub fn init_store(data_dir: &Path) -> Result<()> {
    if CORE.get().is_some() {
        return Ok(());
    }
    std::fs::create_dir_all(data_dir)?;
    let core = Core::new(Store::open(&data_dir.join("kanade.db"))?)?;
    let _ = CORE.set(core);
    Ok(())
}

pub fn core() -> &'static Core {
    CORE.get_or_init(|| Core::new(Store::in_memory().unwrap()).unwrap())
}

pub fn now_ms() -> u128 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis()
}

impl Core {
    fn new(store: Store) -> Result<Self> {
        let http = reqwest::Client::builder()
            .user_agent(UA)
            .gzip(true)
            .timeout(std::time::Duration::from_secs(15))
            .build()?;
        let guid = store.kv_get_or_insert("guid", || {
            (0..10).map(|_| rand::random::<u8>() % 10).map(|d| char::from(b'0' + d)).collect()
        })?;
        let session = store.kv_get("session").and_then(|s| serde_json::from_str(&s).ok());
        // PC 接口使用独立的 32 位 GUID，保留旧接口已有的设备标识。
        let desktop_guid = store.kv_get_or_insert("desktop_guid", || {
            uuid::Uuid::new_v4().simple().to_string().to_uppercase()
        })?;
        Ok(Self { http, store, guid, desktop_guid, session: RwLock::new(session) })
    }

    pub fn session(&self) -> Option<Session> {
        if cfg!(target_os = "android") {
            return self.store.kv_get("session").and_then(|s| serde_json::from_str(&s).ok());
        }
        self.session.read().unwrap().clone()
    }

    pub fn set_session(&self, s: Option<Session>) -> Result<()> {
        match &s {
            Some(s) => self.store.kv_set("session", &serde_json::to_string(s)?)?,
            None => self.store.kv_delete("session")?,
        }
        *self.session.write().unwrap() = s;
        Ok(())
    }

    pub fn uin(&self) -> String {
        self.session().map(|s| s.uin).unwrap_or_else(|| "0".into())
    }

    fn cookie_header(&self) -> Option<String> {
        self.session().map(|s| {
            let mut c = format!(
                "uin={0}; qqmusic_uin={0}; qqmusic_key={1}; qm_keyst={1}; tmeLoginType={2}",
                s.uin, s.musickey, s.login_type
            );
            if s.login_type == 1 {
                c.push_str(&format!("; wxuin={}", s.uin));
            }
            c
        })
    }

    fn comm(&self) -> Value {
        let mut comm = json!({
            "ct": 11,
            "cv": 13020508,
            "v": 13020508,
            "tmeAppID": "qqmusic",
            "format": "json",
            "inCharset": "utf-8",
            "outCharset": "utf-8",
            "uid": self.guid,
        });
        if let Some(s) = self.session() {
            comm["qq"] = json!(s.uin);
            comm["authst"] = json!(s.musickey);
            comm["tmeLoginType"] = json!(s.login_type.to_string());
        }
        comm
    }

    // QQ 音乐 Windows 22.76（patch 118）的搜索抓包公参。
    fn desktop_comm(&self) -> Value {
        let mut comm = json!({
            "ct": "19",
            "cv": "2276",
            "_channelid": "20",
            "_os_version": "6.2.9200-2",
            "patch": "118",
            "tmeAppID": "qqmusic",
            "guid": self.desktop_guid,
        });
        if let Some(s) = self.session() {
            comm["uin"] = json!(s.uin);
            comm["authst"] = json!(s.musickey);
            comm["tmeLoginType"] = json!(s.login_type);
        }
        comm
    }

    /// PC 请求结构走客户端内置的 musicu 网关，不需要复用抓包的 Sign/Mask。
    pub async fn desktop_musicu(&self, module: &str, method: &str, param: Value) -> Result<Value> {
        self.desktop_request(DESKTOP_MUSICU, module, module, method, param, false).await
    }

    /// 读写当前账号自己的数据（歌单、最近播放）：保留 PC 的完整请求键和 Cookie；
    /// musicu 网关不需要尚未实现的 Sign/Mask。
    pub async fn desktop_private(&self, module: &str, method: &str, param: Value) -> Result<Value> {
        self.desktop_request(DESKTOP_MUSICU, &format!("{module}.{method}"), module, method, param, true).await
    }

    /// 与应用登录时的 Android 凭证上下文一致；写操作只发一次，不走通用接口的回退重发。
    pub async fn mobile_write(&self, module: &str, method: &str, param: Value) -> Result<Value> {
        let session = self.session().context(ApiError::NotLoggedIn)?;
        let body = json!({
            "comm": mobile_write_comm(&session),
            "req_0": {"module": module, "method": method, "param": param},
        });
        let response = self.http.post(MUSICU)
            .header("User-Agent", format!("QQMusic {ANDROID_VERSION}(android 10)"))
            .header("Cookie", self.cookie_header().context(ApiError::NotLoggedIn)?)
            .json(&body).send().await?.error_for_status()?.json().await
            .context(ApiError::bad_response("failed to parse Android write response"))?;
        musicu_result(response, module, method)
    }

    /// 网页签名加密通道；当前红心使用与登录凭证匹配的 Android 客户端通道。
    pub async fn signed_web_musicu(&self, module: &str, method: &str, param: Value) -> Result<Value> {
        let session = self.session().context(ApiError::NotLoggedIn)?;
        let token = hash33(&session.musickey, 5381);
        let body = json!({
            "comm": {
                "uin": session.uin, "authst": session.musickey, "format": "json",
                "ct": 24, "cv": 4747474, "platform": "yqq.json",
                "g_tk": token, "g_tk_new_20200303": token,
                "inCharset": "utf-8", "outCharset": "utf-8", "notice": 0, "needNewCode": 1,
            },
            "req_0": {"module": module, "method": method, "param": param},
        }).to_string();
        let http = reqwest::Client::builder().redirect(reqwest::redirect::Policy::none())
            .timeout(std::time::Duration::from_secs(15)).gzip(true).build()?;
        let bytes = http.post("https://u6.y.qq.com/cgi-bin/musics.fcg")
            .query(&[("_", now_ms().to_string()), ("encoding", "ag-1".into()), ("sign", sign(&body))])
            .header("User-Agent", UA)
            .header("Referer", "https://y.qq.com/")
            .header("Origin", "https://y.qq.com")
            .header("Cookie", self.cookie_header().context(ApiError::NotLoggedIn)?)
            .header("Content-Type", "text/plain")
            .header("Accept", "application/octet-stream")
            .body(encrypt_ag1(&body)?)
            .send().await?.error_for_status()?.bytes().await?;
        let response = decode_ag1(&bytes)?;
        musicu_result(response, module, method)
    }

    async fn desktop_request(&self, url: &str, key: &str, module: &str, method: &str, param: Value, cookie: bool) -> Result<Value> {
        let body = json!({
            "comm": self.desktop_comm(),
            (key): { "module": module, "method": method, "param": param },
        });
        let mut req = self
            .http
            .post(url)
            .header("Accept", "*/*")
            .header("Accept-Language", "zh-CN")
            .header("User-Agent", DESKTOP_UA)
            .header("Content-Type", "application/x-www-form-urlencoded");
        if let Some(c) = self.cookie_header().filter(|_| cookie) {
            req = req.header("Cookie", c);
        }
        let resp: Value = req
            .body(body.to_string())
            .send()
            .await?
            .error_for_status()?
            .json()
            .await
            .context(ApiError::bad_response("failed to parse PC musicu response"))?;
        if let Some(code) = resp["code"].as_i64().filter(|code| *code != 0) {
            bail!(ApiError::ServerError { api: "musicu".into(), code: code.to_string() });
        }
        let req = &resp[key];
        match req["code"].as_i64() {
            Some(0) => Ok(req["data"].clone()),
            code => bail!(ApiError::ServerError { api: format!("{module}.{method}"), code: format!("{code:?}") }),
        }
    }

    /// 调用旧有 musicu 统一接口，返回该请求的 `data` 字段。
    pub async fn musicu(&self, module: &str, method: &str, param: Value) -> Result<Value> {
        self.musicu_with_comm(module, method, param, json!({})).await
    }

    pub async fn musicu_with_comm(&self, module: &str, method: &str, param: Value, extra_comm: Value) -> Result<Value> {
        let mut comm = self.comm();
        if let (Some(c), Some(extra)) = (comm.as_object_mut(), extra_comm.as_object()) {
            c.extend(extra.clone());
        }
        let body = json!({
            "comm": comm,
            "req_0": { "module": module, "method": method, "param": param },
        })
        .to_string();

        // 优先走带签名的 musics.fcg，失败再退回 musicu.fcg
        let signed_url = format!("{MUSICS}?_={}&sign={}", now_ms(), sign(&body));
        let resp = match self.post_musicu(&signed_url, &body).await {
            Ok(v) if v["req_0"]["code"].as_i64() == Some(0) => v,
            _ => self.post_musicu(MUSICU, &body).await?,
        };
        let req = &resp["req_0"];
        match req["code"].as_i64() {
            Some(0) => Ok(req["data"].clone()),
            code => bail!(ApiError::ServerError { api: format!("{module}.{method}"), code: format!("{code:?}") }),
        }
    }

    /// 内嵌页写操作只提交一次，不使用通用读请求的失败回退。
    pub async fn musicu_write_with_comm(&self, module: &str, method: &str, param: Value, extra_comm: Value) -> Result<Value> {
        self.session().context(ApiError::NotLoggedIn)?;
        let mut comm = self.comm();
        if let (Some(c), Some(extra)) = (comm.as_object_mut(), extra_comm.as_object()) { c.extend(extra.clone()); }
        let body = json!({"comm": comm, "req_0": {"module": module, "method": method, "param": param}}).to_string();
        musicu_result(self.post_musicu(MUSICU, &body).await?, module, method)
    }

    async fn post_musicu(&self, url: &str, body: &str) -> Result<Value> {
        let mut req = self
            .http
            .post(url)
            .header("Referer", "https://y.qq.com/")
            .header("Origin", "https://y.qq.com")
            .header("Content-Type", "application/json")
            .body(body.to_owned());
        if let Some(c) = self.cookie_header() {
            req = req.header("Cookie", c);
        }
        let text = req.send().await?.error_for_status()?.text().await?;
        serde_json::from_str(&text).with_context(|| {
            ApiError::bad_response(format!("failed to parse musicu response: {}", truncate(&text, 200)))
        })
    }

    /// 旧版 c.y.qq.com 接口，可能返回 JSONP。
    pub async fn get_json(&self, url: &str, query: &[(&str, String)]) -> Result<Value> {
        let mut req = self.http.get(url).query(query).header("Referer", "https://y.qq.com/");
        if let Some(c) = self.cookie_header() {
            req = req.header("Cookie", c);
        }
        let text = req.send().await?.error_for_status()?.text().await?;
        parse_jsonp(&text)
    }

    /// 带缓存地执行一次请求。缓存的是原始 JSON，解析逻辑改了也不会读到旧结构。
    pub async fn cached<F, Fut>(&self, key: &str, ttl_secs: i64, fetch: F) -> Result<Value>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<Value>>,
    {
        let key = format!("{}:{key}", self.uin());
        if let Some(v) = self.store.cache_get(&key).and_then(|s| serde_json::from_str(&s).ok()) {
            return Ok(v);
        }
        let v = fetch().await?;
        self.store.cache_put(&key, &v.to_string(), ttl_secs);
        Ok(v)
    }

    /// 删掉 `cached` 存下的一项，写操作后用。
    pub fn uncache(&self, key: &str) {
        self.store.cache_delete(&format!("{}:{key}", self.uin()));
    }
}

fn mobile_write_comm(session: &Session) -> Value {
    json!({
        "ct": 11, "cv": ANDROID_VERSION, "v": ANDROID_VERSION, "chid": "10003505",
        "tmeAppID": "qqmusic", "tmeLoginType": session.login_type.to_string(),
        "qq": session.uin, "authst": session.musickey, "format": "json",
    })
}

fn musicu_result(response: Value, module: &str, method: &str) -> Result<Value> {
    for (api, code) in [("musicu".to_owned(), &response["code"]), (format!("{module}.{method}"), &response["req_0"]["code"])] {
        let code = code.as_i64().context(ApiError::bad_response(format!("{api} returned no result code")))?;
        if code != 0 {
            bail!(ApiError::ServerError { api, code: code.to_string() });
        }
    }
    Ok(response["req_0"]["data"].clone())
}

pub fn parse_jsonp(text: &str) -> Result<Value> {
    let t = text.trim();
    let t = match (t.find('('), t.rfind(')')) {
        (Some(a), Some(b)) if !t.starts_with('{') && a < b => &t[a + 1..b],
        _ => t,
    };
    serde_json::from_str(t).map_err(|e| ApiError::bad_response(format!("{e}; {}", truncate(text, 200))).into())
}

pub fn truncate(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn signed_reply_rejects_business_failure_even_when_retcode_is_zero() {
        let response = json!({"code": 0, "req_0": {"code": 80105, "data": {"retCode": 0}}});
        let error = musicu_result(response, "music.musicasset.PlaylistDetailWrite", "AddSonglist").unwrap_err();
        assert!(matches!(ApiError::from(error), ApiError::ServerError { code, .. } if code == "80105"));
        assert!(musicu_result(json!({"code": 0}), "m", "x").is_err());
        assert_eq!(musicu_result(json!({"code": 0, "req_0": {"code": 0, "data": {"retCode": 0}}}), "m", "x").unwrap()["retCode"], 0);
    }

    #[test]
    fn mobile_write_preserves_login_context_and_large_musicid() {
        let session = Session::new("1152921504606846976".into(), "test-key".into(), 1, 0);
        let comm = mobile_write_comm(&session);
        assert_eq!(comm["ct"], 11);
        assert_eq!(comm["cv"], ANDROID_VERSION);
        assert_eq!(comm["v"], ANDROID_VERSION);
        assert_eq!(comm["qq"], session.uin);
        assert_eq!(comm["authst"], session.musickey);
        assert_eq!(comm["tmeLoginType"], "1");
        assert!(comm.get("uin").is_none());
    }

    #[test]
    fn desktop_guid_persists_without_replacing_legacy_guid() {
        let store = Store::in_memory().unwrap();
        store.kv_set("guid", "1234567890").unwrap();
        let client = Core::new(store).unwrap();
        let desktop_guid = client.desktop_guid.clone();
        assert_eq!(desktop_guid.len(), 32);
        assert!(desktop_guid.bytes().all(|b| b.is_ascii_digit() || (b'A'..=b'F').contains(&b)));
        assert_eq!(client.guid, "1234567890");
        let reopened = Core::new(client.store).unwrap();
        assert_eq!(reopened.desktop_guid, desktop_guid);
        assert_eq!(reopened.guid, "1234567890");
    }

    #[test]
    fn desktop_login_uses_pc_auth_fields() {
        let client = Core::new(Store::in_memory().unwrap()).unwrap();
        let anonymous = client.desktop_comm();
        assert_eq!(anonymous["ct"], "19");
        assert_eq!(anonymous["cv"], "2276");
        assert!(anonymous.get("uin").is_none());
        assert!(anonymous.get("authst").is_none());
        client.set_session(Some(Session::new("123456".into(), "test-key".into(), 1, 0))).unwrap();
        let authenticated = client.desktop_comm();
        assert_eq!(authenticated["uin"], "123456");
        assert_eq!(authenticated["authst"], "test-key");
        assert_eq!(authenticated["tmeLoginType"], 1);
        assert!(authenticated.get("qq").is_none());
    }

    #[test]
    fn session_end_reason_follows_key_expiry() {
        let session = |expires_at| Session::new("1".into(), "k".into(), 2, expires_at);
        assert_eq!(session(0).end_reason(2_000), SessionEndReason::Unknown);
        assert_eq!(session(1_000).end_reason(2_000), SessionEndReason::Expired);
        assert_eq!(session(3_000).end_reason(2_000), SessionEndReason::Revoked);
        // 旧版本保存的登录态没有到期时间
        let old: Session = serde_json::from_str(r#"{"uin":"1","musickey":"k","login_type":2}"#).unwrap();
        assert_eq!(old.end_reason(2_000), SessionEndReason::Unknown);
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn rejected_login_is_cleared_and_reported() {
        let (tx, rx) = std::sync::mpsc::channel();
        on_session_end(move |reason| tx.send(reason).unwrap());
        core().set_session(Some(Session::new("1234567890".into(), "Q_H_L_invalid".into(), 2, 1))).unwrap();
        verify_session().await;
        assert_eq!(rx.try_recv(), Ok(SessionEndReason::Expired));
        assert!(core().session().is_none());
    }

    #[test]
    fn only_code_1000_counts_as_rejected_login() {
        let error = |code: &str| ApiError::ServerError { api: "m".into(), code: code.into() };
        assert!(error("1000").is_auth_rejected());
        assert!(error("Some(1000)").is_auth_rejected());
        assert!(!error("2000").is_auth_rejected());
        assert!(!ApiError::NotLoggedIn.is_auth_rejected());
    }
}
