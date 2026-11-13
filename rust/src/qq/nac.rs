#[cfg(any(
    all(target_os = "android", target_arch = "aarch64"),
    all(windows, target_arch = "x86_64")
))]
pub(super) use native::{available, decode};

#[cfg(not(any(
    all(target_os = "android", target_arch = "aarch64"),
    all(windows, target_arch = "x86_64")
)))]
pub(super) use unsupported::{available, decode};

#[cfg(any(
    test,
    all(target_os = "android", target_arch = "aarch64"),
    all(windows, target_arch = "x86_64")
))]
const SEGMENT_SIZE: usize = 1764;

#[cfg(any(
    test,
    all(target_os = "android", target_arch = "aarch64"),
    all(windows, target_arch = "x86_64")
))]
fn payload(data: &[u8]) -> anyhow::Result<(&[u8], i32)> {
    use anyhow::bail;
    if data.len() < 15 || !data.starts_with(b"NAC_") {
        bail!("invalid NAC header");
    }
    let end = 15 + u16::from_be_bytes([data[13], data[14]]) as usize;
    if end >= data.len() || !(data.len() - end).is_multiple_of(SEGMENT_SIZE) {
        bail!("incomplete NAC segments");
    }
    let header: serde_json::Value = serde_json::from_slice(&data[15..end])?;
    for (name, expected) in [
        ("nf", 32),
        ("cn", 22),
        ("cb", 10),
        ("fft", 512),
        ("hop", 256),
    ] {
        if header[name].as_i64() != Some(expected) {
            bail!("unsupported NAC {name}");
        }
    }
    let segments = (data.len() - end) / SEGMENT_SIZE;
    if let Some(frames) = header["tf"].as_u64() {
        if frames <= ((segments - 1) * 32) as u64 || frames > (segments * 32) as u64 {
            bail!("NAC frame count does not match the payload");
        }
    }
    let rate = header["sr"].as_i64().unwrap_or(44_100);
    if !matches!(rate, 44_100 | 48_000) || header["ch"].as_i64().unwrap_or(2) != 2 {
        bail!("unsupported NAC sample rate or channel count");
    }
    Ok((&data[end..], rate as i32))
}

#[cfg(not(any(
    all(target_os = "android", target_arch = "aarch64"),
    all(windows, target_arch = "x86_64")
)))]
mod unsupported {
    use std::path::Path;
    use std::sync::atomic::AtomicBool;

    pub(in crate::qq) fn available() -> bool {
        false
    }

    pub(in crate::qq) fn decode(
        _: &[u8],
        _: &Path,
        _: &AtomicBool,
        _: &dyn Fn(u64, u64),
    ) -> anyhow::Result<u64> {
        anyhow::bail!("NAC decoder is unavailable on this platform");
    }
}

#[cfg(any(
    all(target_os = "android", target_arch = "aarch64"),
    all(windows, target_arch = "x86_64")
))]
mod native {
    use super::{payload, SEGMENT_SIZE};
    use anyhow::{bail, Context, Result};
    use std::ffi::c_void;
    use std::path::Path;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::OnceLock;

    #[cfg(target_os = "android")]
    type PathUnit = u8;
    #[cfg(windows)]
    type PathUnit = u16;

    type Decode = unsafe extern "C" fn(
        *const u8,
        usize,
        i32,
        *const PathUnit,
        unsafe extern "C" fn(*const c_void, u64) -> bool,
        *const c_void,
    ) -> i32;

    struct Callback<'a> {
        cancelled: &'a AtomicBool,
        progress: &'a dyn Fn(u64),
    }

    fn decoder() -> Option<Decode> {
        static DECODER: OnceLock<Option<Decode>> = OnceLock::new();
        *DECODER.get_or_init(load_decoder)
    }

    #[cfg(target_os = "android")]
    fn load_decoder() -> Option<Decode> {
        unsafe {
            let library = libc::dlopen(
                c"libkanade_nac.so".as_ptr(),
                libc::RTLD_NOW | libc::RTLD_LOCAL,
            );
            if library.is_null() {
                return None;
            }
            let symbol = libc::dlsym(library, c"kanade_nac_decode".as_ptr());
            if symbol.is_null() {
                libc::dlclose(library);
                return None;
            }
            Some(std::mem::transmute::<*mut c_void, Decode>(symbol))
        }
    }

    #[cfg(windows)]
    fn load_decoder() -> Option<Decode> {
        use windows_sys::Win32::Foundation::FreeLibrary;
        use windows_sys::Win32::System::LibraryLoader::{
            GetProcAddress, LoadLibraryExW, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS,
            LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR,
        };

        let library_path = std::env::current_exe()
            .ok()?
            .with_file_name("kanade_nac.dll");
        let path = native_path(&library_path).ok()?;
        unsafe {
            let library = LoadLibraryExW(
                path.as_ptr(),
                std::ptr::null_mut(),
                LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS,
            );
            if library.is_null() {
                return None;
            }
            let Some(symbol) = GetProcAddress(library, c"kanade_nac_decode".as_ptr().cast()) else {
                FreeLibrary(library);
                return None;
            };
            Some(std::mem::transmute::<
                unsafe extern "system" fn() -> isize,
                Decode,
            >(symbol))
        }
    }

    #[cfg(target_os = "android")]
    fn native_path(path: &Path) -> Result<Vec<PathUnit>> {
        use std::ffi::CString;
        use std::os::unix::ffi::OsStrExt;

        Ok(CString::new(path.as_os_str().as_bytes())?.into_bytes_with_nul())
    }

    #[cfg(windows)]
    fn native_path(path: &Path) -> Result<Vec<PathUnit>> {
        use std::os::windows::ffi::OsStrExt;

        Ok(path
            .as_os_str()
            .encode_wide()
            .chain(std::iter::once(0))
            .collect())
    }

    pub(in crate::qq) fn available() -> bool {
        decoder().is_some()
    }

    unsafe extern "C" fn on_progress(user: *const c_void, written: u64) -> bool {
        let callback = &*(user.cast::<Callback>());
        (callback.progress)(written);
        !callback.cancelled.load(Ordering::Relaxed)
    }

    /// 解码成 16 位双声道 WAV。每解完一段调用 `progress(已写入字节, 文件总大小)`。
    pub(in crate::qq) fn decode(
        data: &[u8],
        path: &Path,
        cancelled: &AtomicBool,
        progress: &dyn Fn(u64, u64),
    ) -> Result<u64> {
        let decode = decoder().context("NAC decoder is unavailable")?;
        let (data, rate) = payload(data)?;
        let segments = data.len() / SEGMENT_SIZE;
        // 与 nac_decoder.cpp 的 WaveWriter 一致：44 字节头 + 每段 32×256 帧 + 结尾 256 帧，每帧 4 字节。
        let total = 44 + (segments as u64 * 32 * 256 + 256) * 4;
        let output = native_path(path)?;
        let callback = Callback {
            cancelled,
            progress: &|written| progress(written, total),
        };
        let status = unsafe {
            decode(
                data.as_ptr(),
                segments,
                rate,
                output.as_ptr(),
                on_progress,
                (&callback as *const Callback).cast(),
            )
        };
        if status != 0 {
            bail!("NAC decoder failed ({status})");
        }
        Ok(std::fs::metadata(path)?.len())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_big_endian_header_length_and_validates_segments() {
        let json = br#"{"nf":32,"cn":22,"cb":10,"fft":512,"hop":256}"#;
        let mut file = b"NAC_".to_vec();
        file.resize(13, 0);
        file.extend((json.len() as u16).to_be_bytes());
        file.extend(json);
        file.resize(file.len() + SEGMENT_SIZE, 0);
        assert_eq!(payload(&file).unwrap().0.len(), SEGMENT_SIZE);
        assert_eq!(payload(&file).unwrap().1, 44_100);
        assert!(payload(&file[..file.len() - 1]).is_err());
    }
}
