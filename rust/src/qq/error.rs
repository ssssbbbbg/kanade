//! ApiError 的 trait 实现。内部仍用 anyhow，用 `bail!(ApiError::…)` / `.context(ApiError::…)`
//! 抛出带错误码的错误，到 API 边界再统一转换。

use std::fmt;

pub use crate::api::error::ApiError;

impl ApiError {
    pub fn login(detail: impl Into<String>) -> Self {
        Self::LoginFailed { detail: detail.into() }
    }

    pub fn bad_response(detail: impl Into<String>) -> Self {
        Self::BadResponse { detail: detail.into() }
    }

    /// 接口返回 1000：登录凭证无效。部分调用处把 `Option` 直接格式化成了 `Some(1000)`。
    pub fn is_auth_rejected(&self) -> bool {
        matches!(self, Self::ServerError { code, .. } if code == "1000" || code == "Some(1000)")
    }
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotLoggedIn => write!(f, "not logged in"),
            Self::NoPlayableUrl => write!(f, "no playable url"),
            Self::UnsupportedFormat => write!(f, "unsupported format"),
            Self::UnverifiedFormat => write!(f, "format not verified for playback"),
            Self::LoginFailed { detail } => write!(f, "login failed: {detail}"),
            Self::InvalidCookie { missing } => write!(f, "cookie is missing {missing}"),
            Self::ServerError { api, code } => write!(f, "{api} returned error code {code}"),
            Self::BadResponse { detail } => write!(f, "bad response: {detail}"),
            Self::Network { detail } => write!(f, "network error: {detail}"),
            Self::Internal { detail } => write!(f, "{detail}"),
        }
    }
}

impl std::error::Error for ApiError {}

/// 纯错误转换；登录凭证复核由 API 边界显式触发。
impl From<anyhow::Error> for ApiError {
    fn from(err: anyhow::Error) -> Self {
        Self::convert(err)
    }
}

impl ApiError {
    fn convert(err: anyhow::Error) -> Self {
        if let Some(e) = err.downcast_ref::<ApiError>() {
            return e.clone();
        }
        for cause in err.chain() {
            if let Some(e) = cause.downcast_ref::<ApiError>() {
                return e.clone();
            }
            if cause.is::<reqwest::Error>() {
                return Self::Network { detail: format!("{err:#}") };
            }
            if cause.is::<serde_json::Error>() {
                return Self::BadResponse { detail: format!("{err:#}") };
            }
        }
        Self::Internal { detail: format!("{err:#}") }
    }
}

#[cfg(test)]
mod tests {
    use anyhow::{anyhow, bail, Context, Result};

    use super::*;

    #[test]
    fn conversion_does_not_check_session() {
        let before = crate::qq::client::SESSION_CHECKS.with(|count| count.get());
        let error = anyhow::Error::new(ApiError::ServerError {
            api: "test".into(),
            code: "1000".into(),
        })
        .context("request context");
        assert!(ApiError::from(error).is_auth_rejected());
        assert_eq!(
            crate::qq::client::SESSION_CHECKS.with(|count| count.get()),
            before
        );
    }

    #[test]
    fn keeps_error_codes_through_anyhow() {
        fn bailed() -> Result<()> {
            bail!(ApiError::NotLoggedIn)
        }
        assert!(matches!(ApiError::from(bailed().unwrap_err()), ApiError::NotLoggedIn));

        let missing: Result<()> = None.context(ApiError::InvalidCookie { missing: "uin".into() });
        assert!(matches!(ApiError::from(missing.unwrap_err()), ApiError::InvalidCookie { .. }));

        let wrapped = Err::<(), _>(anyhow!(ApiError::NoPlayableUrl)).context("outer");
        assert!(matches!(ApiError::from(wrapped.unwrap_err()), ApiError::NoPlayableUrl));

        let parse = serde_json::from_str::<serde_json::Value>("{").map_err(anyhow::Error::from);
        assert!(matches!(ApiError::from(parse.unwrap_err()), ApiError::BadResponse { .. }));

        assert!(matches!(ApiError::from(anyhow!("boom")), ApiError::Internal { .. }));
    }
}
