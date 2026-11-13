# QQ 音乐：音质档位与文件名

观察日期：2026-11-09（北京时间）。目的是让 Kanade 设置里的「默认音质」和官方档位对齐。
在官方 Android QQ 音乐 20.09（MuMu 15，`scripts/capture-qqmusic-android.mjs --prepare`）和 Windows 版 QQ 音乐
（`scripts/capture-qqmusic-fiddler.mjs --capture --player`）里切换音质并播放歌曲，经 Fiddler 抓取取链接请求。
账号为超级会员。Android 版由 adb 驱动；Windows 版由用户手动切换音质并播放。

## 证据

| 本地材料 | 字节 | SHA-256 |
| --- | --- | --- |
| `qqmusic-quality-pc-20261109.saz` | 865623 | `bc6e48b75a6c2398f533aa41fdb063b4534e48e8c60a5faab82e5454d1bbc205` |
| `qqmusic-quality-pc-hires-20261109.saz` | 662493 | `6a6746fab398999ac1a830ff54e5b105388e2ea137d49401a8ec8820f545cd32` |
| `qqmusic-quality-android-360ra-20261109.saz` | 30557919 | `ad5a81bd60a6ae5acffed23c7d1dd0923450109006d55be5e2f3b37fa7d82238` |
| `qqmusic-quality-android-dts-20261109.saz` | 598716 | `3275627a1e1777ddaeaa2985fa2733e45224b3cd72a47a4cca027a1590277831` |
| `qqmusic-quality-android-atmos-20261109.saz` | 92064 | `65c8f456566210eddea1632f0f6fc00c8898fb14a5b19a6fbd7121cea46a34e7` |

均由 `.gitignore` 的 `/qqmusic*.saz` 排除。请求含 `authst`、vkey、Cookie 和设备标识，不应提交或公开；本文不复制这些值。

| 文件 / 会话 | 操作 |
| --- | --- |
| pc `raw/075` | SQ 无损（含预取的队列歌曲） |
| pc `raw/093` | 杜比全景声，第57次取消发送 |
| pc `raw/125` | NAC |
| pc `raw/170` | 臻品全景声 |
| pc `raw/209`、`231` | 臻品母带（`231` 含 Mood） |
| pc-hires `raw/067` | 以 Hi-Res 下载小小奇迹 `003sxA7H1XqCEH`（17:57:56） |
| pc-hires 全部 | 以臻品音质播放，没有取链接请求 |
| android-360ra `raw/017` | 360 Reality Audio，Mood (Explicit) |
| android-dts `raw/008`、`013` | DTS:X，Mood (Remix\|Explicit) 等 |
| android-atmos `raw/08` | 臻品全景声3.0，Mood (Explicit) |

## 官方档位

Android「Wi-Fi / 移动网络播放音质」页（可「调序」，下表是本账号 Wi-Fi 页的顺序）：

| 分组 | 档位 | 页面副标题 |
| --- | --- | --- |
| 超级会员独家尊享 | 杜比全景声 | 沉浸式音频体验全新升级 |
| | 360 Reality Audio | 360度球形空间音频 |
| | DTS:X | 多维沉浸 声动随心 |
| | 臻品母带4.0 | 还原声音细节，150-220M/首 |
| | 臻品全景声3.0 | 影院级空间声场 |
| | 臻品音质2.0 | 音乐品质增强 |
| 普通 | Hi-Res无损品质 | 40-150M/首，flac，最高 24-bit/192 kHz |
| | SQ无损品质 | 20-40M/首，flac，最高 24-bit/48 kHz |
| | HQ高品质 | 9-15M/首，ogg，最高 320kbps |
| | NAC品质 | 2-5M/首，自研 AICodec 编码 |
| | 标准品质 | 3-6M/首 |

没有「流畅」档。页面说明：歌曲没有所选档位时自动切到能播的最高档，顺序为「超级会员音质权益 > Hi-Res > 无损 > HQ > 标准」。
用户确认 Windows 版没有 360 Reality Audio。

## 取链接

两端都用 `POST https://u6.y.qq.com/cgi-bin/musics.fcg` 的 `music.vkey.GetEVkey.CgiGetEVkey`，取的是**加密**文件
（`mflac` / `mmp4` / `mnac` / `mgg`）。Android 响应是 JCE；Windows 请求和响应都是 JSON。Kanade 现在用的
`music.vkey.GetVkey.UrlGetVkey` 和下文的明文文件名在这两次抓包里都没有出现。

Windows 请求参数（每次 5 首，当前歌曲加队列预取）：`ctx=1`、`checklimit=0`、`downloadfrom=0`、`filename[]`、`musicfile[]`，
以及 `guid/uin/songmid/songtype` 等。`musicfile[]` 总是「前缀 + 歌曲 `media_mid` + 扩展名」；
`filename[]` 是实际取到的文件，高级档位里换成了**各档独立的文件 ID**。响应 `midurlinfo[].filename` 与 `filename[]` 一致。

文件名只拼一次 ID：`前缀 + ID + "." + 扩展名`，不像 Kanade 现有映射那样拼两次 `media_mid`。

## 档位映射

| 官方档位 | 前缀 / 扩展名 | ID 来源 | 证据 |
| --- | --- | --- | --- |
| 臻品母带 | `AIM0` / mflac | `track.vs[3]` | pc 209、231 |
| 臻品全景声 | `Q0M0` / mflac | `track.vs[29]` | pc 170、android-atmos |
| DTS:X | `DTM3` / mmp4 | `track.vs[30]`（Mood 的 `vs[30]` 与 Android 一致） | android-dts |
| NAC | `TLM1` / mnac | `track.vs[28]` | pc 125 |
| 杜比全景声 | `D0M1` / mmp4 | `file.media_mid` | pc 093 |
| 360 Reality Audio | `RA04` / mp4（未加密扩展名） | `file.media_mid` | android-360ra |
| SQ 无损 | `F0M0` / mflac | `file.media_mid` | pc 075 |
| HQ（ogg） | `O8M0` / mgg | `file.media_mid` | pc 075 |
| Hi-Res | `RSM1` / mflac | `file.media_mid` | pc-hires 067（下载，`music.vkey.GetEDownUrl.CgiGetEDownUrl`） |
| 臻品音质（Android 叫「臻品音质2.0」） | 没有单独文件 | — | 见下 |
| 标准 | 未抓到 | — | |

明文文件同样存在：用 pc-hires 抓包里的登录态，经 `musicu.fcg` 的 `music.vkey.GetVkey.UrlGetVkey` 请求小小奇迹的
`RS01` / `AI00` / `F000` / `M500` 明文名（`media_mid` 拼两次），四个都返回 `result=0` 和链接；CDN 首段分别是
`fLaC` / `fLaC` / `fLaC` / `ID3`，`RS01` 的总长 48836278 与 `file.size_hires` 一致。官方客户端只是选用加密文件。

Kanade 现有的全景声明文名也都能取到（同一登录态、`UrlGetVkey`，四首歌结果一致）：

| 文件名 | 大小对应 | CDN 首段 |
| --- | --- | --- |
| `Q000` + `media_mid`×2 + `.flac` | `size_new[1]` | FLAC，2 声道，16-bit/44.1 kHz |
| `Q001` + `media_mid`×2 + `.flac` | `size_new[2]` | FLAC，6 声道（5.1） |
| `Q003` + `media_mid`×2 + `.ogg` | `size_new[6]` | Vorbis，12 声道（7.1.4） |
| `Q000` + `vs[29]` + `.flac` | `size_new[8]` | FLAC，2 声道；部分歌曲 24-bit/48 kHz |
| `Q0M0` + `vs[29]` + `.mflac` | `size_new[8]` | 加密，与上一行同长 |

官方「臻品全景声」请求的 `Q0M0`+`vs[29]` 有同长的明文 `Q000`+`vs[29]`.flac，是双声道文件。`Q001`+`vs[29]` 返回 404。
Kanade 的 `Q000`×2（标为「臻品音质」）是另一份双声道文件，官方客户端在两次抓包里都没请求过它。

Mood 的对比（2026-11-10，均重采样到 8 kHz、左右相加后按最佳对齐算相关系数）：`Q000`×2 与普通无损 `F000` 为 0.92，
`Q001` 和 `Q003` 缩混成立体声后与 `Q000`×2 为 0.89、0.87，与 `F000` 为 0.85、0.94；官方臻品全景声 `Q000`+`vs[29]` 与其余各文件只有 0.61–0.70。
所以 `Q000`×2 / `Q001` / `Q003` 是一组，接近普通立体声母版（推测是由它升混而来）；5.1 和 7.1.4 不是从官方臻品全景声拆出来的，后者是另一份混音。

其余明文名（第57次取消发送、Mood）：

| 文件名 | 结果 |
| --- | --- |
| `D004` + `media_mid`×2 + `.mp4` | 第57次取消发送取到，`ftyp mp42`，音轨 `ac-4`（Dolby AC-4）；Mood 返回 `104003`（无杜比） |
| `DT03` + `media_mid`×2 或 `vs[30]` + `.mp4` | 都取到同一文件（`size_new[9]`），`ftyp isom`，音轨 `dtsx`（DTS:X） |
| `TL01` + `media_mid`×2 或 `vs[28]` + `.nac` | 都取到同一文件（`size_new[7]`），首段 `NAC_`，自研编码 |
| `V0M0` + `media_mid`×2 + `.mflac` | 两首都返回 `104003`；官方两端都没有黑胶档，这个映射来自 QQMusicApi，不是官方档位 |

能否在 media_kit / libmpv 里解码 `ac-4`、`dtsx` 未验证。

官方客户端的「臻品音质」大概率是在 SQ 文件上做的音效，不是单独的音频文件：

- Android 选中后只请求了 `F0M0…mflac`（SQ）。
- Windows 选中后播放，抓包里没有任何取链接请求（pc-hires）。
- Windows 版不能以臻品音质下载（用户操作确认）。
- 同一首歌 Windows 显示「臻品音质」，Android 显示「臻品音质2.0」，是同一档。

`vs` 来自 `music.trackInfo.UniformRuleCtrl.CgiGetTrackInfo` 的 `tracks[].vs`（不是 `file` 里的字段），匿名公共通道也能拿到。
下标对照来自三首歌（第57次取消发送 `001P6YOB0eXLlj`、Jealous `002xcJil1I20IC`、Mood `003XetF81E5l6j`），三首的 `vs[3]`、`vs[28]`、`vs[29]`
都和抓到的 `filename` 一致；只是样本推断，不是官方定义。

哪些歌有哪一档：

- `vs` 对应下标为空字符串时，该档位大概率不存在（Mood 的 `vs[28]` 为空，抓包时 NAC 预取里也没有 Mood）。未逐档验证。
- 匿名 `CgiGetTrackInfo` 里 Mood 的 `file.size_360ra` 是空数组，但 Android 能取到 `RA04` 文件，所以不能用它判断 360RA。
- 第57次取消发送的 `file.size_dolby` > 0 且能取到杜比文件；Mood 为 0。

## 与 Kanade 现状的差异

现有映射见 [qqmusic-api.md](qqmusic-api.md#音质文件映射) 和 `rust/src/qq/quality.rs`：

- 母带 `AI00`、全景声 `Q000/Q001/Q003`、杜比 `D004`、DTS `DT03`、NAC `TL01`，都用 `media_mid` 拼两次；官方客户端没有请求过这些名字。
- 官方只有一个「臻品全景声」，Kanade 拆成「臻品音质 / 全景声 5.1 / 全景声 7.1」三档，对应关系不明。
- 明文名是否仍能通过 `UrlGetVkey` 取到、加密文件能否播放，本次都没验证。

## 未完成

- 用 Kanade 当前的 `UrlGetVkey` 分别试 `vs` ID + 明文前缀、`vs` ID + 加密前缀，确认哪种能拿到链接、能否播放。
- 标准档的请求没抓到。臻品音质是否只是音效，是从「没有文件请求、不能下载」推断的，没有直接证据。
- 360RA 是独立文件，不是音效：android-360ra `raw/017` 的链接（抓包当天仍有效）首段为 `ftyp mp42/isom`、`moov/trak`，
  音轨编码 `mhm1`（MPEG-H 3D Audio），总长 28217972，未加密。用 Windows 登录态经 `UrlGetVkey` 请求同名文件（`media_mid` 拼一次或两次）
  都返回 `104003`，与 Windows 版没有该档一致。本机 FFmpeg 没有 MPEG-H 解码器，media_kit / libmpv 大概率也解不了 `mhm1`，未验证。
- 360RA 链接能用 JSON 拿到，不需要 JCE：用 Kanade 自己的微信扫码登录（超级会员），`musicu.fcg` 的 `music.vkey.GetVkey.UrlGetVkey`，
  comm 为 `ct=11` 且 `cv`/`v` = `14090008` 时，`RA04` + `media_mid`（拼一次或两次）+ `.mp4` 都返回链接，文件与 Android 抓包同长（28217972）、
  `ftyp mp42`、含 `mhm1`。同一登录用 Kanade 现在 `comm()` 的 `cv=13020508` 返回 `104003`，加不加 `chid` 都一样，所以关键是 `cv`。
  `GetSession` 的 uid/sid 和设备字段不影响结果。`music.vkey.GetEVkey.CgiGetEVkey` 对 `RA04` 返回 `104005`。
  `RA01`–`RA03` 只在旧 `cv` 下试过（都是 `104003`），没在 `14090008` 下复测。
- Kanade 已接入 360RA：`CgiGetTrackInfo` 用同一 `cv` 时 `file.size_360ra` 有 4 个大小，第 4 个对应 `RA04`；Mood 的链接只给了 http 的 `sip`。
  `mhm1` 的各 sample 首尾相接就是 MHAS 流。Windows 用 libmpegh（`LC_LEVEL_4`）按默认播放设备渲染成立体声或 5.1；
  Android 用官方 `libqm_native_decoder_360ra.so` 渲染成耳机双耳立体声（`native/ra360/`）。缓存的 WAV 保留解码当时的声道布局。

## 抓包注意

- MuMu 里的官方 App 打开完整播放页会在 `MediaCodec_loop` 崩溃，只能从底部小播放条或列表播放。
- `adb shell input text` 在搜索框里丢了首字符，搜错了歌；以截图确认。音质页的档位是可点的文本节点，顺序会变，按文字点。
- App 会缓存 vkey（响应里有 `fnameHitCache`），重复播放同一首可能不再发请求。
- `D:/Fiddler/ExecAction.exe cls` / `dump` 用来清空和导出会话。
- Kanade 设置页 `lib/ui/settings_page.dart` 的 `_qualities` 在本次排查前临时加了 `atmos/atmos51/atmos71`，尚未提交。
