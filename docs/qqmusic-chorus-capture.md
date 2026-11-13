# QQ 音乐：高潮（副歌）片段

观察日期：2026-11-10（北京时间）。

## 结论

高潮片段不在播放时单独请求，而是歌曲信息里自带的两个字段，Kanade 已经在请求的 `music.trackInfo.UniformRuleCtrl.CgiGetTrackInfo` 就能拿到，不需要登录：

| 字段 | 含义（推断） | 《说好的幸福呢》 |
| --- | --- | --- |
| `track.file.try_begin` / `try_end` | 高潮片段起止，毫秒；长度不固定 | `72998` / `104743`（1:13–1:45） |
| `track.vi[4]` / `vi[5]` | 从同一起点开始的 30 秒试听窗口，毫秒 | `72998` / `102998` |

用户在官方客户端听到的副歌约在 1:11 开始，与 `try_begin` 相差约 2 秒。其余两首：

| 歌曲 | 时长 | `try_begin`–`try_end` | `vi[4]`–`vi[5]` |
| --- | --- | --- | --- |
| Call of Silence | 178 s | 103846–167219 | 103846–133846 |
| lovely | 200 s | 41877–87729 | 41877–71877 |

没有片段的歌两组字段都是 `0`；`vi` 也出现过 `[…, 0, 30000, …]`，即只有默认的前 30 秒。
「高潮」的含义是从数值吻合推断的，没有官方字段说明；本轮只核对了《说好的幸福呢》一首的听感位置。

## 证据

| 本地材料 | 字节 | 内容 |
| --- | --- | --- |
| `qqmusic-chorus-pc-20261110.saz` | 1988572 | `scripts/capture-qqmusic-fiddler.mjs --capture --player`，PC 客户端依次播放三首歌 |

由 `.gitignore` 的 `/qqmusic*.saz` 排除；含 `authst` 和设备标识，不应提交或公开。

PC 客户端播放时每首只发 `CgiGetEVkey`、`GetPlayLyricInfo`、`GetCommentCount`、`ReportPlayRecentlyInfo`、
`ListeningMusicReport`，响应里都没有高潮片段，也不含约 71 秒的时间值。歌曲信息由客户端之前缓存，本轮没有重新请求。
`GetPlayLyricInfo` 的 `data.startTs`（本首 `22792`）是第一句歌词开始的时间，不是高潮。

字段先在已有的 Android 抓包（`qqmusic-player-detail-android-20261109.saz` 等）的 `track.vi` 中发现，
再用无登录态的 `https://u.y.qq.com/cgi-bin/musicu.fcg` 调 `CgiGetTrackInfo`（`ids=[449200,202603056,213752499]`）核对上表。
