//! 360 Reality Audio (RA04, MPEG-H 3D Audio) playback using optional platform decoders.
//! Windows renders for the default speakers with libmpegh; Android renders headphone
//! binaural stereo with QQ Music's Sony decoder.

#[cfg(all(windows, target_arch = "x86_64"))]
pub(super) use windows::{available, decode};

#[cfg(all(target_os = "android", target_arch = "aarch64"))]
pub(super) use android::{available, decode};

#[cfg(not(any(
    all(windows, target_arch = "x86_64"),
    all(target_os = "android", target_arch = "aarch64")
)))]
pub(super) fn available() -> bool {
    false
}

#[cfg(not(any(
    all(windows, target_arch = "x86_64"),
    all(target_os = "android", target_arch = "aarch64")
)))]
pub(super) fn decode(
    _: &[u8],
    _: &std::path::Path,
    _: &std::sync::atomic::AtomicBool,
    _: &dyn Fn(u64, u64),
) -> anyhow::Result<u64> {
    anyhow::bail!("360 Reality Audio decoder is unavailable on this platform")
}

#[cfg(all(windows, target_arch = "x86_64"))]
mod windows {
    use std::ffi::c_void;
    use std::os::windows::ffi::OsStrExt;
    use std::path::Path;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::mpsc::{self, SyncSender};
    use std::sync::OnceLock;

    use anyhow::{bail, ensure, Context, Result};

    use super::super::dts::write_wav;

    type OnPcm = unsafe extern "C" fn(*mut c_void, *const u8, usize) -> bool;

    struct Runtime {
        decode: unsafe extern "C" fn(*const u8, usize, i32, OnPcm, *mut c_void) -> i32,
        speaker_channels: unsafe extern "C" fn() -> i32,
    }

    fn runtime() -> Option<&'static Runtime> {
        static RUNTIME: OnceLock<Option<Runtime>> = OnceLock::new();
        RUNTIME.get_or_init(load_runtime).as_ref()
    }

    fn load_runtime() -> Option<Runtime> {
        use windows_sys::Win32::Foundation::FreeLibrary;
        use windows_sys::Win32::System::LibraryLoader::{
            GetProcAddress, LoadLibraryExW, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS,
            LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR,
        };

        let path = std::env::current_exe()
            .ok()?
            .with_file_name("kanade_ra360.dll");
        let name: Vec<_> = path.as_os_str().encode_wide().chain([0]).collect();
        unsafe {
            let library = LoadLibraryExW(
                name.as_ptr(),
                std::ptr::null_mut(),
                LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS,
            );
            if library.is_null() {
                return None;
            }
            let decode = GetProcAddress(library, c"kanade_ra360_decode".as_ptr().cast());
            let speaker_channels =
                GetProcAddress(library, c"kanade_ra360_speaker_channels".as_ptr().cast());
            let (Some(decode), Some(speaker_channels)) = (decode, speaker_channels) else {
                FreeLibrary(library);
                return None;
            };
            Some(Runtime {
                decode: std::mem::transmute(decode),
                speaker_channels: std::mem::transmute(speaker_channels),
            })
        }
    }

    pub(in crate::qq) fn available() -> bool {
        runtime().is_some()
    }

    unsafe extern "C" fn on_pcm(user: *mut c_void, pcm: *const u8, len: usize) -> bool {
        let sender = &*user.cast::<SyncSender<Vec<u8>>>();
        sender
            .send(std::slice::from_raw_parts(pcm, len).to_vec())
            .is_ok()
    }

    /// 按当前默认播放设备渲染：5.1 及以上声道的设备输出 5.1，其余输出立体声。
    pub(in crate::qq) fn decode(
        data: &[u8],
        output: &Path,
        cancelled: &AtomicBool,
        progress: &dyn Fn(u64, u64),
    ) -> Result<u64> {
        let runtime = runtime().context("360 Reality Audio decoder is unavailable")?;
        // CICP 6 is 5.1 (L R C LFE Ls Rs), the WAV channel order for six channels.
        let channels: u16 = if unsafe { (runtime.speaker_channels)() } >= 6 {
            6
        } else {
            2
        };
        let spec = hound::WavSpec {
            channels,
            sample_rate: 48_000,
            bits_per_sample: 24,
            sample_format: hound::SampleFormat::Int,
        };
        write_wav(data, output, spec, progress, |mp4, id, wav| {
            // mhm1 samples carry MHAS packets, so the samples joined form the decoder's stream.
            let mut stream = Vec::with_capacity(data.len());
            for index in 1..=mp4.sample_count(id)? {
                let sample = mp4
                    .read_sample(id, index)?
                    .context("missing 360 Reality Audio MP4 sample")?;
                stream.extend_from_slice(&sample.bytes);
            }
            let stream = &stream;
            let frame = usize::from(channels) * 3;
            std::thread::scope(|scope| {
                let (sender, receiver) = mpsc::sync_channel::<Vec<u8>>(8);
                // libmpegh keeps large buffers on the stack.
                let decoder = std::thread::Builder::new()
                    .name("ra360-decoder".into())
                    .stack_size(64 << 20)
                    .spawn_scoped(scope, move || unsafe {
                        (runtime.decode)(
                            stream.as_ptr(),
                            stream.len(),
                            i32::from(channels),
                            on_pcm,
                            (&sender as *const SyncSender<Vec<u8>>).cast_mut().cast(),
                        )
                    })?;
                // Dropping the receiver makes the next callback stop the decoder.
                for pcm in &receiver {
                    if cancelled.load(Ordering::Relaxed) {
                        break;
                    }
                    for frame in pcm.chunks_exact(frame) {
                        wav.sample(frame)?;
                    }
                    wav.flush()?;
                }
                drop(receiver);
                let status = decoder
                    .join()
                    .map_err(|_| anyhow::anyhow!("360 Reality Audio decoder panicked"))?;
                ensure!(
                    !cancelled.load(Ordering::Relaxed),
                    "360 Reality Audio decode cancelled"
                );
                if status != 0 {
                    bail!("360 Reality Audio decode failed ({status})");
                }
                Ok(())
            })
        })
    }
}

#[cfg(all(target_os = "android", target_arch = "aarch64"))]
mod android {
    use std::ffi::{c_char, c_void, CString};
    use std::os::unix::ffi::OsStrExt;
    use std::path::Path;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::OnceLock;

    use anyhow::{bail, ensure, Context, Result};

    use super::super::dts::{write_wav, Wav};

    type OnPcm = unsafe extern "C" fn(*mut c_void, *const u8, usize) -> bool;
    type Decode =
        unsafe extern "C" fn(*const c_char, *const c_char, OnPcm, *mut c_void, *mut i32) -> i32;

    fn decoder() -> Option<Decode> {
        static DECODER: OnceLock<Option<Decode>> = OnceLock::new();
        *DECODER.get_or_init(|| unsafe {
            let library = libc::dlopen(
                c"libkanade_ra360.so".as_ptr(),
                libc::RTLD_NOW | libc::RTLD_LOCAL,
            );
            if library.is_null() {
                return None;
            }
            let symbol = libc::dlsym(library, c"kanade_ra360_decode".as_ptr());
            let ready = libc::dlsym(library, c"kanade_ra360_available".as_ptr());
            // The adapter loads QQ Music's decoder libraries on first use.
            if symbol.is_null()
                || ready.is_null()
                || !std::mem::transmute::<*mut c_void, unsafe extern "C" fn() -> bool>(ready)()
            {
                libc::dlclose(library);
                return None;
            }
            Some(std::mem::transmute::<*mut c_void, Decode>(symbol))
        })
    }

    pub(in crate::qq) fn available() -> bool {
        decoder().is_some()
    }

    struct Callback<'a, 'b> {
        wav: &'a mut Wav<'b>,
        cancelled: &'a AtomicBool,
        error: Option<std::io::Error>,
    }

    unsafe extern "C" fn on_pcm(user: *mut c_void, pcm: *const u8, len: usize) -> bool {
        let callback = &mut *user.cast::<Callback>();
        let pcm = std::slice::from_raw_parts(pcm, len);
        // 48 kHz stereo 32-bit frames.
        let written = pcm
            .chunks_exact(8)
            .try_for_each(|frame| callback.wav.sample(frame))
            .and_then(|()| callback.wav.flush());
        if let Err(error) = written {
            callback.error = Some(error);
            return false;
        }
        !callback.cancelled.load(Ordering::Relaxed)
    }

    fn native_path(path: &Path) -> Result<CString> {
        Ok(CString::new(path.as_os_str().as_bytes())?)
    }

    /// 渲染成耳机双耳立体声。官方解码器只读文件，所以先把 MP4 写到 WAV 旁边，解完删除。
    pub(in crate::qq) fn decode(
        data: &[u8],
        output: &Path,
        cancelled: &AtomicBool,
        progress: &dyn Fn(u64, u64),
    ) -> Result<u64> {
        let decode = decoder().context("360 Reality Audio decoder is unavailable")?;
        // The decoder reads its HRTF coefficients from here.
        let work_dir = output.parent().context("no cache directory")?.join("ra360");
        std::fs::create_dir_all(&work_dir)?;
        let mut input = output.as_os_str().to_owned();
        input.push(".mp4");
        let input = Path::new(&input);
        std::fs::write(input, data)?;
        let spec = hound::WavSpec {
            channels: 2,
            sample_rate: 48_000,
            bits_per_sample: 32,
            sample_format: hound::SampleFormat::Int,
        };
        let result = write_wav(data, output, spec, progress, |_, _, wav| {
            let input = native_path(input)?;
            let work_dir = native_path(&work_dir)?;
            let mut callback = Callback {
                wav,
                cancelled,
                error: None,
            };
            let mut detail = 0;
            let status = unsafe {
                decode(
                    input.as_ptr(),
                    work_dir.as_ptr(),
                    on_pcm,
                    (&mut callback as *mut Callback).cast(),
                    &mut detail,
                )
            };
            if let Some(error) = callback.error {
                return Err(error.into());
            }
            ensure!(
                !cancelled.load(Ordering::Relaxed),
                "360 Reality Audio decode cancelled"
            );
            if status != 0 {
                bail!("360 Reality Audio decode failed ({status}, {detail})");
            }
            Ok(())
        });
        let _ = std::fs::remove_file(input);
        result
    }
}
