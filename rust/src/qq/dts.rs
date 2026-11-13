//! DTS-UHD Profile 2 playback using optional platform decoders.

#[cfg(all(windows, target_arch = "x86_64"))]
pub(super) use windows::{available, decode};

#[cfg(all(target_os = "android", target_arch = "aarch64"))]
mod android;
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
    anyhow::bail!("DTS:X decoder is unavailable on this platform")
}

/// 按 MP4 时长预先写好头的 WAV，播放器可以边解边读。
/// 解码结果超出时长的部分丢弃，不足的部分补静音，保证文件大小和头一致。
#[cfg(any(
    all(windows, target_arch = "x86_64"),
    all(target_os = "android", target_arch = "aarch64")
))]
pub(super) struct Wav<'a> {
    file: std::io::BufWriter<std::fs::File>,
    written: u64,
    total: u64,
    progress: &'a dyn Fn(u64, u64),
}

#[cfg(any(
    all(windows, target_arch = "x86_64"),
    all(target_os = "android", target_arch = "aarch64")
))]
impl Wav<'_> {
    pub(super) fn sample(&mut self, bytes: &[u8]) -> std::io::Result<()> {
        use std::io::Write;

        if self.written + bytes.len() as u64 > self.total {
            return Ok(());
        }
        self.written += bytes.len() as u64;
        self.file.write_all(bytes)
    }

    /// 写到文件后才报告进度，播放器只读已经落盘的部分。
    pub(super) fn flush(&mut self) -> std::io::Result<()> {
        use std::io::Write;

        self.file.flush()?;
        (self.progress)(self.written, self.total);
        Ok(())
    }
}

/// 借 hound 生成同格式的空 WAV 头，再填入 `frames` 帧对应的大小。返回头和文件总大小。
#[cfg(any(
    test,
    all(windows, target_arch = "x86_64"),
    all(target_os = "android", target_arch = "aarch64")
))]
fn wav_header(spec: hound::WavSpec, frames: u64) -> anyhow::Result<(Vec<u8>, u64)> {
    let mut header = Vec::new();
    hound::WavWriter::new(std::io::Cursor::new(&mut header), spec)?.finalize()?;
    let data_bytes = frames * u64::from(spec.channels) * u64::from(spec.bits_per_sample) / 8;
    let total = header.len() as u64 + data_bytes;
    anyhow::ensure!(
        header.ends_with(b"data\0\0\0\0") && total <= u64::from(u32::MAX),
        "unsupported decoded WAV size"
    );
    let data_offset = header.len() - 4;
    header[4..8].copy_from_slice(&(total as u32 - 8).to_le_bytes());
    header[data_offset..].copy_from_slice(&(data_bytes as u32).to_le_bytes());
    Ok((header, total))
}

#[cfg(any(
    all(windows, target_arch = "x86_64"),
    all(target_os = "android", target_arch = "aarch64")
))]
pub(super) type Mp4<'a> = mp4::Mp4Reader<std::io::Cursor<&'a [u8]>>;

/// 按 MP4 音轨时长写好 WAV 头，`decode` 拿到读取器和音轨 ID 后写入 PCM。返回文件总大小。
#[cfg(any(
    all(windows, target_arch = "x86_64"),
    all(target_os = "android", target_arch = "aarch64")
))]
pub(super) fn write_wav(
    data: &[u8],
    output: &std::path::Path,
    spec: hound::WavSpec,
    progress: &dyn Fn(u64, u64),
    decode: impl FnOnce(&mut Mp4, u32, &mut Wav) -> anyhow::Result<()>,
) -> anyhow::Result<u64> {
    use anyhow::{ensure, Context};
    use std::io::{Cursor, Read, Write};

    let mut mp4 = mp4::Mp4Reader::read_header(Cursor::new(data), data.len() as u64)?;
    let track = mp4
        .tracks()
        .values()
        .find(|track| matches!(track.track_type(), Ok(mp4::TrackType::Audio)))
        .context("MP4 has no audio track")?;
    let id = track.track_id();
    let mdhd = &track.trak.mdia.mdhd;
    ensure!(mdhd.timescale > 0, "MP4 has no timescale");
    let frames = mdhd.duration * u64::from(spec.sample_rate) / u64::from(mdhd.timescale);
    ensure!(mp4.sample_count(id)? > 0, "MP4 has no samples");

    let (header, total) = wav_header(spec, frames)?;
    let mut wav = Wav {
        file: std::io::BufWriter::new(std::fs::File::create(output)?),
        written: header.len() as u64,
        total,
        progress,
    };
    wav.file.write_all(&header)?;
    decode(&mut mp4, id, &mut wav)?;
    let silence = total - wav.written;
    std::io::copy(&mut std::io::repeat(0).take(silence), &mut wav.file)?;
    wav.file.flush()?;
    Ok(total)
}

/// 解码成 WAV。每解完一个 MP4 sample 调用 `progress(已写入字节, 文件总大小)`。
#[cfg(any(
    all(windows, target_arch = "x86_64"),
    all(target_os = "android", target_arch = "aarch64")
))]
fn decode_wav(
    data: &[u8],
    output: &std::path::Path,
    spec: hound::WavSpec,
    cancelled: &std::sync::atomic::AtomicBool,
    progress: &dyn Fn(u64, u64),
    mut decode: impl FnMut(&[u8], &mut Wav) -> anyhow::Result<()>,
) -> anyhow::Result<u64> {
    use anyhow::{ensure, Context};
    use std::sync::atomic::Ordering;

    write_wav(data, output, spec, progress, |mp4, id, wav| {
        for index in 1..=mp4.sample_count(id)? {
            ensure!(!cancelled.load(Ordering::Relaxed), "DTS:X decode cancelled");
            // Keep the MP4 sample boundaries, including continuation frames.
            let sample = mp4
                .read_sample(id, index)?
                .context("missing DTS:X MP4 sample")?;
            ensure!(
                sample.bytes.starts_with(b"\x40\x41\x1b\xf2")
                    || sample.bytes.starts_with(b"\x71\xc4\x42\xe8"),
                "invalid DTS-UHD sample sync"
            );
            decode(&sample.bytes, wav)?;
            wav.flush()?;
        }
        Ok(())
    })
}

#[cfg(all(windows, target_arch = "x86_64"))]
mod windows {
    use std::ffi::c_void;
    use std::os::windows::ffi::OsStrExt;
    use std::path::Path;
    use std::ptr::{self, NonNull};
    use std::sync::atomic::AtomicBool;
    use std::sync::OnceLock;

    use anyhow::{ensure, Context, Result};
    use ring::digest::{digest, SHA256};
    use windows_sys::Win32::System::LibraryLoader::{
        LoadLibraryExW, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR, LOAD_LIBRARY_SEARCH_SYSTEM32,
    };

    // The decoder exposes no stable C exports for this interface. Only this
    // exact Windows x64 image has the entry points and layouts below.
    const RUNTIME_SHA256: [u8; 32] = [
        0x0f, 0xb4, 0x8a, 0x12, 0xae, 0xf3, 0x54, 0x01, 0x69, 0x92, 0xe5, 0xfc, 0x2a, 0x34, 0xea,
        0x7e, 0xf4, 0x85, 0x27, 0x11, 0xa5, 0xf4, 0x8a, 0x66, 0xbd, 0xff, 0x07, 0x66, 0x12, 0x85,
        0xc4, 0xca,
    ];
    const SAMPLE_RATE: u32 = 48_000;
    const SPEAKER_SLOTS: [usize; 6] = [1, 2, 0, 5, 3, 4]; // WAV order: FL FR FC LFE BL BR.

    #[repr(C)]
    struct Packet {
        data: *const u8,
        len: u32,
        flags: u32,
        reserved: usize,
    }

    #[repr(C)]
    struct PacketList {
        packet: *const Packet,
        len: usize,
    }

    #[repr(C)]
    struct Pcm {
        bits: u32,
        sample_rate: u32,
        speaker_mask: u32,
        channel_count: u32,
        sample_count: u32,
        reserved: u32,
        channels: [*const i32; 32],
    }

    struct Runtime {
        memory_size: unsafe extern "C" fn(i32) -> u32,
        create: unsafe extern "C" fn(*mut *mut c_void, i32, *mut c_void) -> i32,
        decode:
            unsafe extern "C" fn(*mut c_void, *const PacketList, *mut *mut Pcm, *mut u32) -> i32,
        set: unsafe extern "C" fn(*mut c_void, i32, *const u32, u32) -> i32,
        destroy: unsafe extern "C" fn(*mut c_void) -> i32,
    }

    fn runtime() -> Option<&'static Runtime> {
        static RUNTIME: OnceLock<Option<Runtime>> = OnceLock::new();
        RUNTIME.get_or_init(load_runtime).as_ref()
    }

    fn load_runtime() -> Option<Runtime> {
        let exe = std::env::current_exe().ok()?;
        let path = exe
            .parent()?
            .join("dts-runtime")
            .join("DTSXDecoder.dll")
            .canonicalize()
            .ok()?;
        let data = std::fs::read(&path).ok()?;
        if digest(&SHA256, &data).as_ref() != RUNTIME_SHA256 {
            return None;
        }
        let name: Vec<_> = path.as_os_str().encode_wide().chain([0]).collect();
        // Keep the verified module loaded for the lifetime of its function pointers.
        unsafe {
            let module = LoadLibraryExW(
                name.as_ptr(),
                ptr::null_mut(),
                LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32,
            );
            if module.is_null() {
                return None;
            }
            let base = module as usize;
            Some(Runtime {
                memory_size: std::mem::transmute(base + 0x1A7D0),
                create: std::mem::transmute(base + 0x1A870),
                decode: std::mem::transmute(base + 0x1A3F0),
                set: std::mem::transmute(base + 0x1AB30),
                destroy: std::mem::transmute(base + 0x1A780),
            })
        }
    }

    pub(in crate::qq) fn available() -> bool {
        runtime().is_some()
    }

    struct Decoder<'a> {
        runtime: &'a Runtime,
        handle: NonNull<c_void>,
        _memory: Vec<u128>,
    }

    impl<'a> Decoder<'a> {
        fn new(runtime: &'a Runtime) -> Result<Self> {
            const PROFILE: i32 = 5;
            let bytes = unsafe { (runtime.memory_size)(PROFILE) } as usize;
            let mut memory = vec![0_u128; (bytes + 8).div_ceil(16)];
            let mut handle = ptr::null_mut();
            let code =
                unsafe { (runtime.create)(&mut handle, PROFILE, memory.as_mut_ptr().cast()) };
            ensure!(code >= 0, "DTS:X decoder initialization failed ({code})");
            let decoder = Self {
                runtime,
                handle: NonNull::new(handle).context("DTS:X decoder returned no handle")?,
                _memory: memory,
            };
            // Speaker activity mask for 5.1 and the runtime's PCM output modes.
            for (param, value) in [(102, 0x0f), (100, 0), (106, 0)] {
                decoder.set(param, value)?;
            }
            Ok(decoder)
        }

        fn set(&self, param: i32, value: u32) -> Result<()> {
            let code = unsafe { (self.runtime.set)(self.handle.as_ptr(), param, &value, 4) };
            ensure!(code >= 0, "DTS:X decoder option {param} failed ({code})");
            Ok(())
        }

        fn decode_sample(&mut self, data: &[u8], wave: &mut super::Wav) -> Result<()> {
            let packet = Packet {
                data: data.as_ptr(),
                len: data.len().try_into()?,
                flags: 16,
                reserved: 0,
            };
            let list = PacketList {
                packet: &packet,
                len: 1,
            };
            let mut storage = [0_u128; 32];
            let mut status = [0_u32; 40];
            let mut out = storage.as_mut_ptr().cast::<Pcm>();
            let mut code = unsafe {
                (self.runtime.decode)(self.handle.as_ptr(), &list, &mut out, status.as_mut_ptr())
            };
            if code == -1022 {
                self.set(200, 0)?;
                out = storage.as_mut_ptr().cast();
                status.fill(0);
                code = unsafe {
                    (self.runtime.decode)(
                        self.handle.as_ptr(),
                        &list,
                        &mut out,
                        status.as_mut_ptr(),
                    )
                };
            }
            ensure!(
                code >= 0 && !out.is_null(),
                "DTS:X frame decode failed ({code})"
            );
            // The returned planar samples remain valid until the next decode call.
            let pcm = unsafe { &*out };
            ensure!(
                pcm.bits == 24
                    && pcm.sample_rate == SAMPLE_RATE
                    && (1..=8192).contains(&pcm.sample_count),
                "unsupported DTS:X PCM format"
            );
            let count = pcm.sample_count as usize;
            let channels = SPEAKER_SLOTS.map(|slot| {
                let samples = pcm.channels[slot];
                if samples.is_null() || pcm.speaker_mask & (1 << slot) == 0 {
                    &[][..]
                } else {
                    unsafe { std::slice::from_raw_parts(samples, count) }
                }
            });
            for index in 0..count {
                for channel in &channels {
                    let sample = channel.get(index).copied().unwrap_or(0);
                    wave.sample(&sample.to_le_bytes()[..3])?;
                }
            }
            Ok(())
        }
    }

    impl Drop for Decoder<'_> {
        fn drop(&mut self) {
            unsafe { (self.runtime.destroy)(self.handle.as_ptr()) };
        }
    }

    pub(in crate::qq) fn decode(
        data: &[u8],
        output: &Path,
        cancelled: &AtomicBool,
        progress: &dyn Fn(u64, u64),
    ) -> Result<u64> {
        let runtime = runtime().context("DTS:X decoder is unavailable")?;
        let mut decoder = Decoder::new(runtime)?;
        let spec = hound::WavSpec {
            channels: 6,
            sample_rate: SAMPLE_RATE,
            bits_per_sample: 24,
            sample_format: hound::SampleFormat::Int,
        };
        super::decode_wav(data, output, spec, cancelled, progress, |sample, wave| {
            decoder.decode_sample(sample, wave)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::wav_header;

    #[test]
    fn precomputed_header_matches_a_finished_hound_file() {
        let specs = [
            (6, 24, hound::SampleFormat::Int),
            (2, 32, hound::SampleFormat::Float),
        ];
        for (channels, bits_per_sample, sample_format) in specs {
            let spec = hound::WavSpec {
                channels,
                sample_rate: 48_000,
                bits_per_sample,
                sample_format,
            };
            let frames = 1_000;
            let mut file = Vec::new();
            let mut writer = hound::WavWriter::new(std::io::Cursor::new(&mut file), spec).unwrap();
            for _ in 0..frames * u64::from(channels) {
                match sample_format {
                    hound::SampleFormat::Int => writer.write_sample(0_i32).unwrap(),
                    hound::SampleFormat::Float => writer.write_sample(0_f32).unwrap(),
                }
            }
            writer.finalize().unwrap();
            let (header, total) = wav_header(spec, frames).unwrap();
            assert_eq!(total, file.len() as u64);
            assert_eq!(header, file[..header.len()]);
        }
    }
}
