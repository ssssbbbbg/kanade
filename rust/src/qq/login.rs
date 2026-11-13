//! 扫码登录。QQ：ptlogin 二维码 → graph.qq.com OAuth code → QQ 音乐 musickey；
//! 微信：open.weixin.qq.com 二维码 → wx_code → QQ 音乐 musickey。

use std::sync::Arc;

use anyhow::{bail, Context, Result};
use reqwest::cookie::{CookieStore, Jar};
use reqwest::redirect::Policy;
use serde_json::{json, Value};
use url::Url;

use super::client::{core, now_ms, Session, UA, ANDROID_VERSION};
use super::error::ApiError;
use super::parse::{first_s, n, s};
use super::sign::hash33;
use crate::api::types::{QrCode, QrStatus, UserInfo};

const APPID: &str = "716027609";
const DAID: &str = "383";
const THIRD_AID: &str = "100497308";
const U1: &str = "https://graph.qq.com/oauth2.0/login_jump";
const XUI: &str = "https://xui.ptlogin2.qq.com/";

fn login_client(jar: Arc<Jar>) -> Result<reqwest::Client> {
    Ok(reqwest::Client::builder()
        .user_agent(UA)
        .cookie_provider(jar)
        .redirect(Policy::none())
        .timeout(std::time::Duration::from_secs(15))
        .build()?)
}

fn cookie_value(jar: &Jar, url: &str, name: &str) -> Option<String> {
    let header = jar.cookies(&Url::parse(url).ok()?)?;
    header
        .to_str()
        .ok()?
        .split(';')
        .filter_map(|kv| kv.trim().split_once('='))
        .find(|(k, v)| *k == name && !v.is_empty())
        .map(|(_, v)| v.to_string())
}

pub async fn create_qr() -> Result<QrCode> {
    let jar = Arc::new(Jar::default());
    let client = login_client(jar.clone())?;
    let resp = client
        .get("https://ssl.ptlogin2.qq.com/ptqrshow")
        .query(&[
            ("appid", APPID),
            ("e", "2"),
            ("l", "M"),
            ("s", "3"),
            ("d", "72"),
            ("v", "4"),
            ("t", &format!("0.{}", rand::random::<u32>())),
            ("daid", DAID),
            ("pt_3rd_aid", THIRD_AID),
            ("u1", U1),
        ])
        .header("Referer", XUI)
        .send()
        .await?
        .error_for_status()?;
    let image = resp.bytes().await?.to_vec();
    let qrsig = cookie_value(&jar, "https://ssl.ptlogin2.qq.com/", "qrsig").context(ApiError::login("missing qrsig cookie"))?;
    Ok(QrCode { image, qrsig, url: String::new() })
}

/// 同一台手机跳转 QQ 登录用的票据（H5 登录页 `pt.qrcode.get(1)` 的做法）。
/// 与扫码用的票据不同，必须带 `type=1`，否则 QQ 会报“登录失败(73)”；没有图片，轮询方式与扫码相同。
pub async fn create_app_qr() -> Result<QrCode> {
    let jar = Arc::new(Jar::default());
    let client = login_client(jar.clone())?;
    let text = client
        .get("https://ssl.ptlogin2.qq.com/ptqrshow")
        .query(&[
            ("s", "8"),
            ("e", "0"),
            ("appid", APPID),
            ("type", "1"),
            ("t", &format!("0.{}", rand::random::<u32>())),
            ("u1", U1),
            ("daid", DAID),
            ("pt_3rd_aid", THIRD_AID),
        ])
        .header("Referer", XUI)
        .send()
        .await?
        .error_for_status()?
        .text()
        .await?;
    let qrsig = cookie_value(&jar, "https://ssl.ptlogin2.qq.com/", "qrsig").context(ApiError::login("missing qrsig cookie"))?;
    let url = parse_qrcode_cb(&text).with_context(|| ApiError::bad_response(format!("unexpected ptqrshow response: {text}")))?;
    Ok(QrCode { image: Vec::new(), qrsig, url })
}

/// 解析 `ptui_qrcode_CB({"ec":0,"qrcode":"http://txz.qq.com/p?k=...","em":"..."})`。
fn parse_qrcode_cb(text: &str) -> Option<String> {
    let json: serde_json::Value = serde_json::from_str(text.get(text.find('{')?..=text.rfind('}')?)?).ok()?;
    let url = s(&json["qrcode"]);
    (json["ec"].as_i64() == Some(0) && !url.is_empty()).then_some(url)
}

/// 解析 `ptuiCB('66','0','url','0','msg', 'nick')`。
fn parse_ptuicb(text: &str) -> Result<Vec<String>> {
    let start = text.find("ptuiCB(").with_context(|| ApiError::bad_response(format!("unexpected ptlogin response: {text}")))? + 7;
    let end = text.rfind(')').unwrap_or(text.len());
    Ok(text[start..end].split(',').map(|p| p.trim().trim_matches('\'').to_string()).collect())
}

fn query_param(url: &str, key: &str) -> Option<String> {
    Url::parse(url).ok()?.query_pairs().find(|(k, _)| k == key).map(|(_, v)| v.into_owned())
}

pub async fn poll_qr(qrsig: &str) -> Result<QrStatus> {
    let client = login_client(Arc::new(Jar::default()))?;
    let text = client
        .get("https://ssl.ptlogin2.qq.com/ptqrlogin")
        .query(&[
            ("u1", U1.to_string()),
            ("ptqrtoken", hash33(qrsig, 0).to_string()),
            ("ptredirect", "0".into()),
            ("h", "1".into()),
            ("t", "1".into()),
            ("g", "1".into()),
            ("from_ui", "1".into()),
            ("ptlang", "2052".into()),
            ("action", format!("0-0-{}", now_ms())),
            ("js_ver", "20102616".into()),
            ("js_type", "1".into()),
            ("pt_uistyle", "40".into()),
            ("aid", APPID.into()),
            ("daid", DAID.into()),
            ("pt_3rd_aid", THIRD_AID.into()),
            ("has_onekey", "1".into()),
        ])
        .header("Referer", XUI)
        .header("Cookie", format!("qrsig={qrsig}"))
        .send()
        .await?
        .text()
        .await?;
    let parts = parse_ptuicb(&text)?;
    match parts.first().map(String::as_str) {
        Some("66") => Ok(QrStatus::Waiting),
        Some("67") => Ok(QrStatus::Scanned),
        Some("65") => Ok(QrStatus::Expired),
        Some("68") => Ok(QrStatus::Refused),
        Some("0") => {
            let url = parts.get(2).cloned().unwrap_or_default();
            let user = finish_login(&url).await?;
            Ok(QrStatus::Success { user })
        }
        _ => bail!(ApiError::login(parts.get(4).cloned().unwrap_or(text))),
    }
}

async fn finish_login(check_sig_url: &str) -> Result<UserInfo> {
    let uin = query_param(check_sig_url, "uin").context(ApiError::login("login callback is missing uin"))?;
    let sigx = query_param(check_sig_url, "ptsigx").context(ApiError::login("login callback is missing ptsigx"))?;

    let jar = Arc::new(Jar::default());
    let client = login_client(jar.clone())?;
    client
        .get("https://ssl.ptlogin2.graph.qq.com/check_sig")
        .query(&[
            ("uin", uin.as_str()),
            ("pttype", "1"),
            ("service", "ptqrlogin"),
            ("nodirect", "0"),
            ("ptsigx", sigx.as_str()),
            ("s_url", U1),
            ("ptlang", "2052"),
            ("ptredirect", "100"),
            ("aid", APPID),
            ("daid", DAID),
            ("j_later", "0"),
            ("low_login_hour", "0"),
            ("regmaster", "0"),
            ("pt_login_type", "3"),
            ("pt_aid", "0"),
            ("pt_aaid", "16"),
            ("pt_light", "0"),
            ("pt_3rd_aid", THIRD_AID),
        ])
        .header("Referer", XUI)
        .send()
        .await?;
    let p_skey = cookie_value(&jar, "https://graph.qq.com/", "p_skey").context(ApiError::login("missing p_skey cookie"))?;

    let resp = client
        .post("https://graph.qq.com/oauth2.0/authorize")
        .form(&[
            ("response_type", "code".to_string()),
            ("client_id", THIRD_AID.into()),
            ("redirect_uri", "https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/".into()),
            ("scope", "get_user_info,get_app_friends".into()),
            ("state", "state".into()),
            ("switch", "".into()),
            ("from_ptlogin", "1".into()),
            ("src", "1".into()),
            ("update_auth", "1".into()),
            ("openapi", "1010_1030".into()),
            ("g_tk", hash33(&p_skey, 5381).to_string()),
            ("auth_time", now_ms().to_string()),
            ("ui", uuid::Uuid::new_v4().to_string()),
        ])
        .header("Referer", "https://graph.qq.com/")
        .send()
        .await?;
    let location = resp.headers().get("Location").and_then(|v| v.to_str().ok()).unwrap_or_default().to_string();
    let code = query_param(&location, "code").with_context(|| ApiError::login(format!("OAuth authorization failed: {location}")))?;

    let c = core();
    c.set_session(None)?;
    let data = c.musicu_with_comm("QQConnectLogin.LoginServer", "QQLogin", json!({ "code": code }), json!({ "tmeLoginType": "2" })).await?;
    let musicid = s(&data["musicid"]);
    let musickey = first_s(&data, &["musickey", "qm_keyst"]);
    if musicid.is_empty() || musickey.is_empty() {
        bail!(ApiError::login("QQ Music login returned no musickey"));
    }
    c.set_session(Some(Session::new(musicid, musickey, 2, key_expires_at(&data))))?;
    refresh_user_info().await
}

/// 手动粘贴 y.qq.com 的 Cookie 登录（备用方案）。
pub async fn login_with_cookie(cookie: &str) -> Result<UserInfo> {
    let get = |name: &str| {
        cookie
            .split(';')
            .filter_map(|kv| kv.trim().split_once('='))
            .find(|(k, v)| *k == name && !v.is_empty())
            .map(|(_, v)| v.trim().to_string())
    };
    let uin = get("uin")
        .or_else(|| get("qqmusic_uin"))
        .or_else(|| get("wxuin"))
        .map(|u| u.trim_start_matches(['o', '0']).to_string())
        .context(ApiError::InvalidCookie { missing: "uin".into() })?;
    let musickey =
        get("qm_keyst").or_else(|| get("qqmusic_key")).context(ApiError::InvalidCookie { missing: "qm_keyst / qqmusic_key".into() })?;
    let login_type = if musickey.starts_with("W_X") { 1 } else { 2 };
    core().set_session(Some(Session::new(uin, musickey, login_type, 0)))?;
    refresh_user_info().await
}

/// 登录响应给出的 musickey 到期时间（Unix 秒），没有有效期字段时为 0。
/// 官方 PC 客户端的登录响应里 `keyExpiresIn` 为 259200（3 天）。
fn key_expires_at(data: &Value) -> i64 {
    let ttl = n(&data["keyExpiresIn"]);
    if ttl <= 0 {
        return 0;
    }
    let created = n(&data["musickeyCreateTime"]);
    if created > 0 { created + ttl } else { (now_ms() / 1000) as i64 + ttl }
}

pub async fn refresh_user_info() -> Result<UserInfo> {
    let c = core();
    let Some(mut sess) = c.session() else { bail!(ApiError::NotLoggedIn) };
    let data = c
        .get_json(
            "https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg",
            &[("format", "json".into()), ("cid", "205360838".into()), ("userid", sess.uin.clone()), ("reqfrom", "1".into())],
        )
        .await;
    if let Ok(d) = data {
        let creator = &d["data"]["creator"];
        let nick = s(&creator["nick"]);
        if !nick.is_empty() {
            sess.nickname = nick;
            sess.avatar_url = s(&creator["headpic"]);
            c.set_session(Some(sess.clone()))?;
        }
    }
    Ok(user_of(&sess))
}

pub fn user_of(s: &Session) -> UserInfo {
    UserInfo {
        uin: s.uin.clone(),
        nickname: if s.nickname.is_empty() { s.uin.clone() } else { s.nickname.clone() },
        avatar_url: s.avatar_url.clone(),
    }
}

// ---------------- 微信扫码登录 ----------------
// open.weixin.qq.com 网页扫码 → wx_code → QQ 音乐 musickey（以 W_X 开头）。

const WX_APPID: &str = "wx48db31d50e334801";

pub async fn create_wx_qr() -> Result<QrCode> {
    let client = login_client(Arc::new(Jar::default()))?;
    let html = client
        .get("https://open.weixin.qq.com/connect/qrconnect")
        .query(&[
            ("appid", WX_APPID),
            ("redirect_uri", "https://y.qq.com/portal/wx_redirect.html?login_type=2&surl=https://y.qq.com/"),
            ("response_type", "code"),
            ("scope", "snsapi_login"),
            ("state", "STATE"),
            ("href", "https://y.qq.com/mediastyle/music_v17/src/css/popup_wechat.css#wechat_redirect"),
        ])
        .send()
        .await?
        .error_for_status()?
        .text()
        .await?;
    // 页面里形如 <img class="qrcode" src="/connect/qrcode/UUID"> 或 uuid=UUID"
    let uuid = ["/connect/qrcode/", "uuid="]
        .iter()
        .find_map(|marker| {
            let start = html.find(marker)? + marker.len();
            let rest = &html[start..];
            let end = rest.find(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '-'))?;
            (end > 0).then(|| rest[..end].to_string())
        })
        .context(ApiError::bad_response("QR code not found on WeChat login page"))?;
    let image = client
        .get(format!("https://open.weixin.qq.com/connect/qrcode/{uuid}"))
        .header("Referer", "https://open.weixin.qq.com/")
        .send()
        .await?
        .error_for_status()?
        .bytes()
        .await?
        .to_vec();
    Ok(QrCode { image, qrsig: uuid, url: String::new() })
}

/// 解析 `window.wx_errcode=408;window.wx_code='';`
fn parse_wx_poll(text: &str) -> (i64, String) {
    let field = |name: &str| {
        let start = text.find(name)? + name.len();
        let rest = text[start..].trim_start_matches(['=', ' ']);
        let end = rest.find(';').unwrap_or(rest.len());
        Some(rest[..end].trim().trim_matches('\'').to_string())
    };
    let code = field("wx_errcode").and_then(|c| c.parse().ok()).unwrap_or(-1);
    (code, field("wx_code").unwrap_or_default())
}

pub async fn poll_wx_qr(uuid: &str) -> Result<QrStatus> {
    // 微信这边是长轮询，服务端最长挂起约 25 秒
    let client = reqwest::Client::builder().user_agent(UA).timeout(std::time::Duration::from_secs(35)).build()?;
    let text = client
        .get("https://lp.open.weixin.qq.com/connect/l/qrconnect")
        .query(&[("uuid", uuid.to_string()), ("_", now_ms().to_string())])
        .header("Referer", "https://open.weixin.qq.com/")
        .send()
        .await?
        .text()
        .await?;
    match parse_wx_poll(&text) {
        (408, _) => Ok(QrStatus::Waiting),
        (404, _) => Ok(QrStatus::Scanned),
        (403, _) => Ok(QrStatus::Refused),
        (402, _) => Ok(QrStatus::Expired),
        (405, code) if !code.is_empty() => Ok(QrStatus::Success { user: finish_wx_login(&code).await? }),
        _ => bail!(ApiError::login(super::client::truncate(&text, 100))),
    }
}

async fn finish_wx_login(wx_code: &str) -> Result<UserInfo> {
    let c = core();
    c.set_session(None)?;
    let data = c
        .musicu_with_comm(
            "music.login.LoginServer",
            "Login",
            json!({ "code": wx_code, "strAppid": WX_APPID }),
            json!({ "tmeLoginType": "1" }),
        )
        .await?;
    let musicid = s(&data["musicid"]);
    let musickey = first_s(&data, &["musickey", "qm_keyst"]);
    if musicid.is_empty() || musickey.is_empty() {
        bail!(ApiError::login("QQ Music login returned no musickey"));
    }
    c.set_session(Some(Session::new(musicid, musickey, 1, key_expires_at(&data))))?;
    refresh_user_info().await
}

// ---------------- QQ 音乐 App 授权登录 ----------------
// music.login.LoginServer.CreateQRCode → 二维码指向 y.qq.com/m/client/qr_code_login/authorize.html，
// 在 QQ 音乐里打开该页并点“登录”。结果不能靠 CheckQRCode 轮询（授权后它仍返回 40000），
// 而是由 mu.y.qq.com 的 MQTT 推送到 `management.qrcode_login/{qrcodeID}`；收到 cookies 消息后
// 再用 LoginServer.Login 换正式 musickey。账号类型随 QQ 音乐 App 当前登录方式（QQ 或微信）。

const TME_LIFETIME: std::time::Duration = std::time::Duration::from_secs(120);

enum TmeState {
    Waiting,
    Scanned,
    Refused,
    Expired,
    Done(UserInfo),
    Failed(String),
}

/// 后台推送连接写入、`poll_tme_qr` 读取的登录状态，以 qrcodeID 为键。
fn tme_states() -> &'static std::sync::Mutex<std::collections::HashMap<String, TmeState>> {
    static STATES: std::sync::OnceLock<std::sync::Mutex<std::collections::HashMap<String, TmeState>>> = std::sync::OnceLock::new();
    STATES.get_or_init(Default::default)
}

fn set_tme_state(qrcode_id: &str, state: TmeState) {
    tme_states().lock().unwrap().insert(qrcode_id.to_string(), state);
}

const TME_LOGIN_MODULE: &str = "music.login.LoginServer";

/// 一次授权始终使用同一 Android 会话，不借用当前账号或通用接口的公参。
struct TmeClient {
    comm: serde_json::Value,
    user_agent: String,
}

impl TmeClient {
    async fn new() -> Result<Self> {
        let store = &core().store;
        let device_id = match store.kv_get("mobile_login_device_id") {
            Some(id) => id,
            None => {
                let id = uuid::Uuid::new_v4().simple().to_string();
                store.kv_set("mobile_login_device_id", &id)?;
                id
            }
        };
        let comm = json!({
            "ct": 11, "cv": ANDROID_VERSION, "v": ANDROID_VERSION,
            "chid": "10003505", "tmeAppID": "qqmusic", "tmeLoginType": 2,
            "qq": "0", "authst": "", "uid": "", "sid": "",
            "OpenUDID": device_id, "OpenUDID2": device_id, "udid": device_id,
        });
        let mut client = Self { comm, user_agent: String::new() };
        // 使用本机公开的系统属性，不把随机字符串当作服务端签发的 QIMEI。
        #[cfg(target_os = "android")]
        for (field, property) in [
            ("os_ver", "ro.build.version.release"),
            ("phonetype", "ro.product.model"),
            ("devicelevel", "ro.build.version.sdk"),
            ("newdevicelevel", "ro.build.version.sdk"),
            ("rom", "ro.build.fingerprint"),
        ] {
            let output = std::process::Command::new("/system/bin/getprop").arg(property).output()?;
            let value = String::from_utf8(output.stdout)?.trim().to_owned();
            if !output.status.success() || value.is_empty() {
                bail!(ApiError::login(format!("cannot read Android property {property}")));
            }
            client.comm[field] = json!(value);
        }
        client.user_agent = format!("QQMusic {ANDROID_VERSION}(android {})", client.comm["os_ver"].as_str().unwrap_or("10"));
        let data = client.call("music.getSession.session", "GetSession", json!({"uid": "", "vkey": 0, "caller": 0}), json!({})).await?;
        let uid = s(&data["session"]["uid"]);
        let sid = s(&data["session"]["sid"]);
        if uid.is_empty() || sid.is_empty() {
            bail!(ApiError::bad_response("GetSession returned no uid/sid"));
        }
        client.comm["uid"] = json!(uid);
        client.comm["sid"] = json!(sid);
        Ok(client)
    }

    fn body(&self, module: &str, method: &str, param: serde_json::Value, extra_comm: serde_json::Value) -> serde_json::Value {
        let mut comm = self.comm.clone();
        comm.as_object_mut().unwrap().extend(extra_comm.as_object().unwrap().clone());
        json!({"comm": comm, "req_0": {"module": module, "method": method, "param": param}})
    }

    async fn call(&self, module: &str, method: &str, param: serde_json::Value, extra_comm: serde_json::Value) -> Result<serde_json::Value> {
        let body = self.body(module, method, param, extra_comm);
        let resp = core()
            .http
            .post("https://u.y.qq.com/cgi-bin/musicu.fcg")
            .header("User-Agent", &self.user_agent)
            .header("Referer", "https://y.qq.com/")
            .header("Origin", "https://y.qq.com")
            .header("Cookie", "")
            .json(&body)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await
            .context(ApiError::bad_response("failed to parse Android musicu response"))?;
        tme_response(resp, module, method)
    }
}

fn tme_response(resp: serde_json::Value, module: &str, method: &str) -> Result<serde_json::Value> {
    for (api, code) in [("musicu".to_owned(), &resp["code"]), (format!("{module}.{method}"), &resp["req_0"]["code"])] {
        match code.as_i64() {
            Some(0) => {}
            Some(code) => bail!(ApiError::ServerError { api, code: code.to_string() }),
            None => bail!(ApiError::bad_response(format!("{api} returned no result code"))),
        }
    }
    Ok(resp["req_0"]["data"].clone())
}

pub async fn create_tme_qr() -> Result<QrCode> {
    let client = TmeClient::new().await?;
    // 手机授权入口专用 ct/cv；param 中保留 Android 客户端版本。
    let data = client
        .call(
            TME_LOGIN_MODULE,
            "CreateQRCode",
            json!({"tmeAppID": "qqmusic", "ct": 11, "cv": ANDROID_VERSION}),
            json!({"ct": 23, "cv": 0}),
        )
        .await?;
    let qrcode_id = s(&data["qrcodeID"]);
    let image = s(&data["qrcode"])
        .split_once("base64,")
        .and_then(|(_, b64)| base64::Engine::decode(&base64::engine::general_purpose::STANDARD, b64).ok());
    let (false, Some(image)) = (qrcode_id.is_empty(), image) else {
        bail!(ApiError::bad_response("CreateQRCode returned no QR code"));
    };
    let mut url = Url::parse("https://y.qq.com/m/client/qr_code_login/authorize.html")?;
    url.query_pairs_mut().append_pair("qrcode_id", &qrcode_id);
    // 先收到 SUBACK 再开放授权入口，防止用户确认时尚未订阅推送。
    let mqtt = tokio::time::timeout(std::time::Duration::from_secs(15), connect_tme(&qrcode_id))
        .await
        .context(ApiError::login("QQ Music push subscription timed out"))??;
    set_tme_state(&qrcode_id, TmeState::Waiting);
    let id = qrcode_id.clone();
    tokio::spawn(async move {
        let state = match tokio::time::timeout(TME_LIFETIME, watch_tme(&id, mqtt, client)).await {
            Ok(Ok(state)) => state,
            Ok(Err(e)) => TmeState::Failed(format!("{e:#}")),
            Err(_) => TmeState::Expired,
        };
        set_tme_state(&id, state);
    });
    Ok(QrCode { image, qrsig: qrcode_id, url: url.into() })
}

pub async fn poll_tme_qr(qrcode_id: &str) -> Result<QrStatus> {
    let mut states = tme_states().lock().unwrap();
    let status = match states.get(qrcode_id) {
        Some(TmeState::Waiting) => return Ok(QrStatus::Waiting),
        Some(TmeState::Scanned) => return Ok(QrStatus::Scanned),
        // 终态读一次就清掉；找不到（比如 App 重启过）按过期处理
        _ => states.remove(qrcode_id),
    };
    match status {
        Some(TmeState::Done(user)) => Ok(QrStatus::Success { user }),
        Some(TmeState::Refused) => Ok(QrStatus::Refused),
        Some(TmeState::Failed(msg)) => bail!(ApiError::login(msg)),
        _ => Ok(QrStatus::Expired),
    }
}

async fn connect_tme(qrcode_id: &str) -> Result<super::mqtt::MqttWs> {
    use super::mqtt::MqttWs;

    let client_id = format!("{}{}", now_ms(), rand::random::<u16>() % 9000 + 1000);
    let mut mqtt = MqttWs::connect(
        "mu.y.qq.com",
        "/ws/handshake",
        &client_id,
        45,
        "pass",
        &[
            ("tmeAppID", "qqmusic"),
            ("business", "management"),
            ("hashTag", qrcode_id),
            ("clientTag", "management.user"),
            ("userID", qrcode_id),
        ],
    )
    .await?;
    let topic = format!("management.qrcode_login/{qrcode_id}");
    mqtt.subscribe(&topic, &[("authorization", "tmelogin"), ("pubsub", "unicast")]).await?;
    Ok(mqtt)
}

/// 订阅推送直到终态；返回值写回状态表。
async fn watch_tme(qrcode_id: &str, mut mqtt: super::mqtt::MqttWs, client: TmeClient) -> Result<TmeState> {
    let topic = format!("management.qrcode_login/{qrcode_id}");
    let period = std::time::Duration::from_secs((mqtt.keep_alive / 2).max(1) as u64);
    let mut ping = tokio::time::interval_at(tokio::time::Instant::now() + period, period);
    loop {
        let publish = tokio::select! {
            p = mqtt.next_publish() => p?,
            _ = ping.tick(), if mqtt.keep_alive != 0 => {
                mqtt.ping().await?;
                continue;
            }
        };
        if publish.topic != topic {
            continue;
        }
        match publish.user_prop("type") {
            Some("scanned") => set_tme_state(qrcode_id, TmeState::Scanned),
            Some("canceled") => return Ok(TmeState::Refused),
            Some("timeout") => return Ok(TmeState::Expired),
            Some("loginFailed") => return Ok(TmeState::Failed("QQ Music reported login failure".into())),
            Some("cookies") => return Ok(TmeState::Done(finish_tme_login(&client, qrcode_id, &publish.payload).await?)),
            _ => {}
        }
    }
}

/// 推送里的 cookies 只是临时凭证，需要再调一次 Login（tmeLoginType 6）换正式 musickey。
async fn finish_tme_login(client: &TmeClient, qrcode_id: &str, payload: &[u8]) -> Result<UserInfo> {
    let msg: serde_json::Value = serde_json::from_slice(payload).context(ApiError::bad_response("invalid MQTT cookies message"))?;
    let cookies = &msg["cookies"];
    let uin: i64 = s(&cookies["qqmusic_uin"]["value"]).parse().unwrap_or(0);
    let token = s(&cookies["qqmusic_key"]["value"]);
    if uin <= 0 || token.is_empty() {
        bail!(ApiError::login("MQTT cookies message is missing credentials"));
    }
    let c = core();
    let data = client
        .call(
            "music.login.LoginServer",
            "Login",
            json!({ "musicid": uin, "qrCodeID": qrcode_id, "token": token }),
            json!({ "tmeLoginType": 6 }),
        )
        .await?;
    let musicid = s(&data["musicid"]);
    let musickey = first_s(&data, &["musickey", "qm_keyst"]);
    if musicid.is_empty() || musickey.is_empty() {
        bail!(ApiError::login("QQ Music login returned no musickey"));
    }
    // 微信账号的 musickey 以 W_X 开头
    let login_type = if musickey.starts_with("W_X") { 1 } else { 2 };
    c.set_session(Some(Session::new(musicid, musickey, login_type, key_expires_at(&data))))?;
    refresh_user_info().await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_wx_poll() {
        assert_eq!(parse_wx_poll("window.wx_errcode=408;window.wx_code='';"), (408, String::new()));
        assert_eq!(parse_wx_poll("window.wx_errcode=405;window.wx_code='abc123';"), (405, "abc123".into()));
    }

    #[test]
    fn parses_qrcode_cb() {
        let url = parse_qrcode_cb(r#"ptui_qrcode_CB({"em":"x","qrcode":"http://txz.qq.com/p?k=abc&f=716027609","ec":0})"#);
        assert_eq!(url.as_deref(), Some("http://txz.qq.com/p?k=abc&f=716027609"));
        assert_eq!(parse_qrcode_cb(r#"ptui_qrcode_CB({"ec":1,"qrcode":""})"#), None);
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn creates_tme_qr_and_subscribes() {
        let qr = create_tme_qr().await.unwrap();
        assert!(!qr.image.is_empty());
        // create 返回前已完成连接/订阅；无需等待后台连接。
        assert!(matches!(poll_tme_qr(&qr.qrsig).await.unwrap(), QrStatus::Waiting));
    }

    #[test]
    fn tme_login_reuses_session_after_qr_overrides() {
        let client = TmeClient {
            comm: json!({"ct": 11, "cv": ANDROID_VERSION, "v": ANDROID_VERSION,
                "uid": "server-uid", "sid": "server-sid", "OpenUDID": "install-id", "qq": "0", "authst": ""}),
            user_agent: String::new(),
        };
        let qr = client.body(TME_LOGIN_MODULE, "CreateQRCode", json!({"ct": 11, "cv": ANDROID_VERSION}), json!({"ct": 23, "cv": 0}));
        let login = client.body(
            TME_LOGIN_MODULE,
            "Login",
            json!({"musicid": 123, "qrCodeID": "qr", "token": "temporary"}),
            json!({"tmeLoginType": 6}),
        );
        assert_eq!(qr["comm"]["ct"], 23);
        assert_eq!(qr["comm"]["cv"], 0);
        assert_eq!(login["comm"]["ct"], 11);
        assert_eq!(login["comm"]["cv"], ANDROID_VERSION);
        assert_eq!(login["comm"]["tmeLoginType"], 6);
        for field in ["uid", "sid", "OpenUDID", "qq", "authst"] {
            assert_eq!(qr["comm"][field], login["comm"][field]);
        }
        assert_eq!(login["req_0"]["param"]["musicid"], 123);
        assert_eq!(login["req_0"]["param"]["token"], "temporary");
    }

    #[test]
    fn tme_response_keeps_server_error_codes_without_credentials() {
        for response in
            [json!({"code": 50006, "req_0": {"code": 0}}), json!({"code": 0, "req_0": {"code": 50006, "data": {"token": "secret"}}})]
        {
            let err = tme_response(response, TME_LOGIN_MODULE, "Login").unwrap_err();
            assert!(matches!(ApiError::from(err), ApiError::ServerError { code, .. } if code == "50006"));
        }
        assert!(tme_response(json!({"code": 0}), TME_LOGIN_MODULE, "Login").is_err());
        assert_eq!(
            tme_response(json!({"code": 0, "req_0": {"code": 0, "data": {"musicid": 123}}}), TME_LOGIN_MODULE, "Login").unwrap()["musicid"],
            123
        );
    }

    #[tokio::test]
    #[ignore = "需要联网"]
    async fn creates_app_qr() {
        let qr = create_app_qr().await.unwrap();
        assert!(qr.url.contains("://txz.qq.com/p?k="), "{}", qr.url);
    }

    #[test]
    fn key_expiry_comes_from_login_response() {
        assert_eq!(key_expires_at(&json!({"musickeyCreateTime": 1793279876, "keyExpiresIn": 259200})), 1793539076);
        assert_eq!(key_expires_at(&json!({"musickey": "k"})), 0);
        let now = (now_ms() / 1000) as i64;
        assert!((now + 259200..=now + 259201).contains(&key_expires_at(&json!({"keyExpiresIn": 259200}))));
    }

    #[test]
    fn parses_ptuicb() {
        let p = parse_ptuicb("ptuiCB('66','0','','0','二维码未失效。', '')").unwrap();
        assert_eq!(p[0], "66");
    }
}
