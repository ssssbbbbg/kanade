use std::ffi::c_void;
use std::path::Path;
use std::ptr::{self, NonNull};
use std::sync::atomic::AtomicBool;
use std::sync::OnceLock;

use anyhow::{ensure, Context, Result};

#[repr(C)]
struct PcmFrame {
    left: *const f32,
    right: *const f32,
    frames: i32,
}

struct Runtime {
    create: unsafe extern "C" fn() -> *mut c_void,
    frame: unsafe extern "C" fn(*mut c_void, *const u8, i32, *mut PcmFrame) -> i32,
    destroy: unsafe extern "C" fn(*mut c_void),
}

fn runtime() -> Option<&'static Runtime> {
    static RUNTIME: OnceLock<Option<Runtime>> = OnceLock::new();
    RUNTIME
        .get_or_init(|| unsafe {
            let library = libc::dlopen(
                c"libkanade_dts.so".as_ptr(),
                libc::RTLD_NOW | libc::RTLD_LOCAL,
            );
            if library.is_null() {
                return None;
            }
            let create = libc::dlsym(library, c"kanade_dts_create".as_ptr());
            let frame = libc::dlsym(library, c"kanade_dts_frame".as_ptr());
            let destroy = libc::dlsym(library, c"kanade_dts_destroy".as_ptr());
            if create.is_null() || frame.is_null() || destroy.is_null() {
                libc::dlclose(library);
                return None;
            }
            Some(Runtime {
                create: std::mem::transmute(create),
                frame: std::mem::transmute(frame),
                destroy: std::mem::transmute(destroy),
            })
        })
        .as_ref()
}

struct Decoder {
    runtime: &'static Runtime,
    handle: NonNull<c_void>,
}

impl Decoder {
    fn new() -> Result<Self> {
        let runtime = runtime().context("DTS:X decoder is unavailable")?;
        let handle = NonNull::new(unsafe { (runtime.create)() })
            .context("DTS Playback SDK configuration or license was rejected")?;
        Ok(Self { runtime, handle })
    }

    fn frame(&mut self, data: &[u8]) -> Result<(&[f32], &[f32])> {
        let mut pcm = PcmFrame {
            left: ptr::null(),
            right: ptr::null(),
            frames: 0,
        };
        let status = unsafe {
            (self.runtime.frame)(
                self.handle.as_ptr(),
                data.as_ptr(),
                data.len().try_into()?,
                &mut pcm,
            )
        };
        ensure!(status == 0, "DTS:X frame decode failed ({status})");
        // The adapter checks both planes and the frame count. The SDK owns
        // these samples until the next call on this decoder.
        unsafe {
            Ok((
                std::slice::from_raw_parts(pcm.left, pcm.frames as usize),
                std::slice::from_raw_parts(pcm.right, pcm.frames as usize),
            ))
        }
    }
}

impl Drop for Decoder {
    fn drop(&mut self) {
        unsafe { (self.runtime.destroy)(self.handle.as_ptr()) };
    }
}

pub(in crate::qq) fn available() -> bool {
    static AVAILABLE: OnceLock<bool> = OnceLock::new();
    *AVAILABLE.get_or_init(|| Decoder::new().is_ok())
}

pub(in crate::qq) fn decode(
    data: &[u8],
    output: &Path,
    cancelled: &AtomicBool,
    progress: &dyn Fn(u64, u64),
) -> Result<u64> {
    let mut decoder = Decoder::new()?;
    let spec = hound::WavSpec {
        channels: 2,
        sample_rate: 48_000,
        bits_per_sample: 32,
        sample_format: hound::SampleFormat::Float,
    };
    super::decode_wav(data, output, spec, cancelled, progress, |sample, wave| {
        let (left, right) = decoder.frame(sample)?;
        for (&left, &right) in left.iter().zip(right) {
            wave.sample(&left.to_le_bytes())?;
            wave.sample(&right.to_le_bytes())?;
        }
        Ok(())
    })
}
