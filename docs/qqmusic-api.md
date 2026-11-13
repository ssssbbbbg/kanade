# QQ 音乐接口参考（Kanade）

整理日期：2026-10-31（北京时间）。代码基线：`820b61d`，包含本轮尚未提交的接口与页面更新。

本文记录 Kanade 当前使用的 QQ 音乐上游 HTTP / MQTT 接口，并列出项目内对应的 Rust / Dart 调用入口。它是基于本仓库实现的开发参考，不是腾讯官方开放平台文档，也不代表 QQ 音乐全部接口。

本文结合源码与抓包笔记整理。本轮另执行了歌手精选、视频分页、社交信息及用户主页、收藏资产的只读联网验证；没有重放关注或创建歌单写请求。参数默认值、缓存时长和回退顺序描述的是当前代码行为；历史抓包成功不等于当前所有账号、平台和凭据均可调用成功。所有示例使用占位值或人工构造的数据，不包含真实登录凭据。

## 目录

- [请求约定与鉴权](#请求约定与鉴权)
- [搜索](#搜索)
- [歌曲详情、音质与播放](#歌曲详情音质与播放)
- [歌词](#歌词)
- [榜单与推荐](#榜单与推荐)
- [歌单读取与写入](#歌单读取与写入)
- [最近播放](#最近播放)
- [歌手与专辑](#歌手与专辑)
- [MV](#mv)
- [其他用户主页](#其他用户主页)
- [评论与回复](#评论与回复)
- [登录与用户资料](#登录与用户资料)
- [项目数据结构与调用入口](#项目数据结构与调用入口)
- [缓存与错误处理](#缓存与错误处理)
- [验证方式与已知边界](#验证方式与已知边界)
- [源码与抓包笔记](#源码与抓包笔记)

## 请求约定与鉴权

### 网关与传输封装

统一网关使用 `POST`。URL 中的 `musicu.fcg` / `musics.fcg` 是网关，真正的业务由 JSON 中的 `module` 和 `method` 决定。旧版 `c.y.qq.com` CGI 接口使用 `GET`，返回 JSON 或 JSONP。

| 本文简称 | 当前实现 / 网关 | 请求键 | Cookie 与行为 |
| --- | --- | --- | --- |
| 通用 | `Core::musicu`；先 `https://u.y.qq.com/cgi-bin/musics.fcg`，失败后 `https://u.y.qq.com/cgi-bin/musicu.fcg` | `req_0` | 有会话时带 Cookie；首个请求带 `sign=zzc…`，当前实现可能回退重发 |
| 内嵌页 | `Core::musicu_with_comm(..., webkit_comm())`；网关同通用 | `req_0` | 合并内嵌页公参；Cookie 和回退行为同通用 |
| 内嵌页写入 | `Core::musicu_write_with_comm(..., webkit_comm())`；`https://u.y.qq.com/cgi-bin/musicu.fcg` | `req_0` | 要求登录、带 Cookie；单次提交，无签名回退；关注操作使用 |
| PC 公共 | `Core::desktop_musicu`；`https://u6.y.qq.com/cgi-bin/musicu.fcg` | `module` 原文 | 不附加 Cookie；有会话时仍在 `comm` 中带登录信息 |
| PC 私有 | `Core::desktop_private`；`https://u6.y.qq.com/cgi-bin/musicu.fcg` | `module.method` | 有会话时附加 Cookie；单次业务请求，不做签名回退 |
| Android 写入 | `Core::mobile_write`；`https://u.y.qq.com/cgi-bin/musicu.fcg` | `req_0` | 要求登录并附加 Cookie；单次业务请求，用于当前红心实现 |
| 网页签名加密 | `Core::signed_web_musicu`；`https://u6.y.qq.com/cgi-bin/musics.fcg` | `req_0` | Cookie、`sign`、`encoding=ag-1`；当前保留的独立通道，红心主流程不使用它 |
| App 授权登录 | `TmeClient::call`；`https://u.y.qq.com/cgi-bin/musicu.fcg` | `req_0` | 独立 Android 会话，Cookie 显式为空，不借用当前账号 |

PC 两种封装的 `Content-Type` 都是 `application/x-www-form-urlencoded`，但请求正文直接是 JSON 字符串，不是表单字段。通用 / 内嵌页和 Android 写入发送 JSON；网页签名加密通道发送 `text/plain` 正文。不能只替换网关而忽略请求键、正文编码和客户端公参。

### 统一请求与响应

以下为 PC 公共搜索的完整结构示例。`query` 可替换，账号、设备标识和 `searchid` 应由调用方提供；此示例只是请求结构，未在本轮执行。

```json
{
  "comm": {
    "ct": "19",
    "cv": "2276",
    "_channelid": "20",
    "_os_version": "6.2.9200-2",
    "patch": "118",
    "tmeAppID": "qqmusic",
    "guid": "<PERSISTENT_32_HEX_GUID>",
    "uin": "<MUSIC_ID>",
    "authst": "<MUSIC_KEY>",
    "tmeLoginType": 2
  },
  "music.search.SearchCgiService": {
    "module": "music.search.SearchCgiService",
    "method": "DoSearchForQQMusicDesktop",
    "param": {
      "query": "钢琴",
      "search_type": 0,
      "num_per_page": 20,
      "page_num": 1,
      "remoteplace": "txt.newclient.top",
      "searchid": "<GENERATED_37_HEX_SEARCH_ID>",
      "grp": 1
    }
  }
}
```

响应外壳示意如下。`<REQUEST_KEY>` 应与请求使用的别名一致；`data` 的内容取决于业务方法。

```json
{
  "code": 0,
  "<REQUEST_KEY>": {
    "code": 0,
    "data": {}
  }
}
```

后文的“返回路径”均相对于业务请求的 `data`，除非明确说明是旧 CGI 的原始响应。例如 PC 搜索的 `body.song.list` 指 `response["music.search.SearchCgiService"].data.body.song.list`。

业务成功不能只看 HTTP 200。应核对网关 `code`、业务请求 `code`，并在存在内层结果码时继续核对。当前各封装检查力度有差异，见[缓存与错误处理](#缓存与错误处理)。

### 客户端公参

| 上下文 | 当前字段与类型 |
| --- | --- |
| 通用基础 | `ct=11`、`cv=13020508`、`v=13020508`，均为数字；`tmeAppID="qqmusic"`、`format="json"`、`inCharset/outCharset="utf-8"`、`uid=本地十位数字 GUID` |
| 通用登录态 | `qq=musicid 字符串`、`authst=musickey`、`tmeLoginType="1"` 或 `"2"`，为字符串 |
| PC | `ct="19"`、`cv="2276"`、`_channelid="20"`、`_os_version="6.2.9200-2"`、`patch="118"`、`tmeAppID="qqmusic"`、`guid=独立持久化的 32 位大写十六进制 GUID` |
| PC 登录态 | `uin=musicid 字符串`、`authst=musickey`、`tmeLoginType=1` 或 `2`，为数字 |
| 内嵌页覆盖项 | `ct=20`、`cv=2276`、`platform="wk_v17"`、`uin=musicid 字符串`、`g_tk/g_tk_new_20200303=hash33(musickey,5381)`、`needNewCode=1`、`notice=0` |
| Android 写入 | `ct=11`、`cv/v=14090008`、`chid="10003505"`、`tmeAppID="qqmusic"`、`tmeLoginType="1"/"2"`、`qq=musicid 字符串`、`authst=musickey`、`format="json"` |
| 网页签名加密 | `ct=24`、`cv=4747474`、`platform="yqq.json"`，以及 `uin/authst/g_tk/g_tk_new_20200303`、字符集、`notice=0`、`needNewCode=1` |

内嵌页字段是合并到通用基础公参上的覆盖项，基础字段中未被覆盖的 `v`、`uid`、`qq` 等仍然存在。无登录态时 `Core::uin()` 返回字符串 `"0"`，内嵌页 `g_tk` 为 `5381`。

应用会话中的 `uin` 实际保存 QQ 音乐返回的 `musicid`，不应直接假定等于 QQ 号。账号编号可能超过 JavaScript 安全整数范围，跨语言传递时保留字符串，按具体接口要求再转换类型。

### Cookie、签名与设备标识

会话包含 `uin`、`musickey`、`login_type`、昵称和头像；`login_type=2` 表示 QQ，`1` 表示微信。由会话生成的 Cookie 结构是：

```text
uin=<MUSIC_ID>; qqmusic_uin=<MUSIC_ID>; qqmusic_key=<MUSIC_KEY>; qm_keyst=<MUSIC_KEY>; tmeLoginType=<1_OR_2>
```

微信会话额外带 `wxuin=<MUSIC_ID>`。登录凭据来自用户自己的授权流程，不能把抓包中的 Cookie、`authst`、`Sign` 或 `Mask` 固定写进代码或提交到仓库。

`hash33` 在项目中按字符执行 `h = h + (h << 5) + codepoint`，使用 wrapping 运算，最终取 `h & 0x7fffffff`。QQ 二维码 `ptqrtoken` 的初值为 `0`，`g_tk` 的初值为 `5381`。

`zzc` 签名基于**实际发送的同一份 JSON 字符串**计算；修改字段顺序、空白或序列化方式后应重新签名。具体算法见 [sign.rs](../rust/src/qq/sign.rs)。网页 `ag-1` 请求使用 AES-128-GCM：随机 12 字节 nonce，加密结果带认证标签，整体按 `nonce || ciphertext || tag` 做 Base64；响应按该文件的循环 XOR 规则解码，再解析 JSON。协议常量及第三方来源见 [THIRD_PARTY_NOTICES.md](../rust/THIRD_PARTY_NOTICES.md)。

官方 PC 抓包中的原生 `Sign` / `Mask` 与网页 `zzc` 属于不同机制。当前 PC musicu 路径没有使用这两个请求头；不能将网页签名算法描述为已实现原生 PC 签名。

## 搜索

实现：[music.rs](../rust/src/qq/music.rs)。

| 功能 / 上游方法 | 通道 | `param` / 查询参数 | 返回路径与项目处理 |
| --- | --- | --- | --- |
| 分类搜索：`music.search.SearchCgiService.DoSearchForQQMusicDesktop` | PC 公共 | `query`、`search_type`、`num_per_page`、`page_num`、`remoteplace`、`searchid`、`grp=1`；分类取值见下表 | 列表见下表，总数 `meta.sum`，`meta.nextpage>0` 视为还有下一页 |
| 未登录搜歌：`https://c.y.qq.com/soso/fcgi-bin/client_search_cp` | GET | `w=关键词`、`p=页码`、`n=每页条数`、`format=json` | 原始响应 `data.song.list`、`data.song.totalnum` |
| 热搜：`tencent_musicsoso_hotkey.HotkeyService.GetHotkeyForQQMusicPC` | PC 公共 | `search_id=""`、`uin=账号编号的 i64 数值，无账号时 0` | `vec_hotkey`、`vec_reckey`；读取 `title/query/description`，过滤空 `query` |
| 联想：`music.smartboxCgi.SmartBoxCgi.GetSmartBoxResultForPc` | PC 公共 | `num_per_page=4`、`query`、`search_id=本次生成的搜索 ID` | `data.song.song_list`、`data.singer.singer_list`、`data.album.album_list`；读取 `name`、`singer` |

| 分类 `SearchKind` | `search_type` | `remoteplace` | 列表 | 项目读取 |
| --- | --- | --- | --- | --- |
| 歌曲 `Song` | 0 | `txt.newclient.top` | `body.song.list` | 统一歌曲解析 |
| 歌手 `Singer` | 1 | `sizer.newclient.singer` | `body.singer.list` | `singerMID/singerName/songNum/albumNum` |
| 专辑 `Album` | 2 | `sizer.newclient.album` | `body.album.list` | `albumMID/albumName/publicTime/singer_list` |
| 歌单 `Playlist` | 3 | `sizer.newclient.playlist` | `body.songlist.list` | `dissid/dissname/imgurl/song_count/listennum/creator.name` |
| 视频 `Video` | 4 | `sizer.newclient.mv` | `body.mv.list` | 字符串 `v_id`、`mv_name/mv_pic_url/duration/play_count`；`singer_name` 为空且有 `uploader_nick` 时视为用户上传 |
| 歌词 `Lyric` | 7 | `txt.newclient.top` | `body.song.list` | 歌曲对象；`lyric` / `lyric_hilight` 实测常为空，从 `content`（首行为“歌名 - 歌手”）取含关键词的前两行 |
| 用户 `User` | 8 | `sizer.newclient.users` | `body.user.list` | `encrypt_uin/title/pic/fans_num/diss_num/identify_title`；`iconurl` 是认证角标不是头像，结果里没有明文账号 |

页码从 `1` 开始。PC 搜索 `searchid` 是每次生成的 37 位大写十六进制字符串。联想结果映射成歌曲、歌手、专辑三类文字建议，当前返回模型不含目标 MID。

2026-10-31 补抓了官方客户端七类搜索及 MV 元数据、取流和清晰度切换，见[分类搜索与 MV 抓包](qqmusic-search-mv-capture.md)。
同日用登录态经 `musicu.fcg` 实测（`desktop_category_search_pagination`，关键词「周杰伦」，每页 10）：
七个分类第一页均有结果，第二页非空且与第一页不重复。歌单 `page_num=0` 与 `1` 返回同一页，`2` 为第二页，
因此歌单也统一从 `1` 开始。视频结果进入 [MV](#mv)，用户结果进入[用户主页](#其他用户主页)。

未登录时歌曲搜索保留旧 CGI，其他分类没有旧接口，始终走 PC 接口。README 记录旧 CGI 历史直接请求曾返回 HTTP 500，本文没有重新核实其当前可用性。PC 匿名搜索也没有作为已验证的替代路径接入。

## 歌曲详情、音质与播放

实现：[music.rs](../rust/src/qq/music.rs)、[quality.rs](../rust/src/qq/quality.rs)。

### 批量歌曲信息

`music.trackInfo.UniformRuleCtrl.CgiGetTrackInfo` 有两种当前用法：

| 用途 | 通道 | 参数 | 返回 |
| --- | --- | --- | --- |
| 推荐卡片按数字 ID 补全歌曲 | 通用 | `ids=[song_id,…]`、`types=[0,…]`，两数组等长 | `tracks[]` |
| 获取音质文件信息 | 登录时 PC 公共，否则通用 | `ctx=0`、`client=1`、`types=[0]`、`modify_stamp=[0]`、`mids=[song_mid]` | `tracks[0].file` |

`song.id` 是数字 ID，`song.mid` 是歌曲 MID，`file.media_mid` 是拼音频文件名用的媒体 MID；三者不能混用。当前解析器在 `media_mid` 缺失时使用歌曲 MID。

### 取播放链接

主接口为 `music.vkey.GetVkey.UrlGetVkey`。登录后只走 PC 公共；未登录走通用，并在主接口未拿到可用结果时尝试 `vkey.GetVkeyServer.CgiGetVkey`。

```json
{
  "guid": "<GUID_FOR_SELECTED_CONTEXT>",
  "songmid": ["<SONG_MID>"],
  "songtype": [0],
  "uin": "<MUSIC_ID_OR_0>",
  "loginflag": 1,
  "platform": "20",
  "filename": ["M800<MEDIA_MID><MEDIA_MID>.mp3"],
  "ctx": 0
}
```

PC 取链接会带 `ctx=0`；未登录的 `song_url` 调用不加这个字段。音质批量检查则两种通道都传 `ctx=0`。PC 与旧通用路径分别使用自己的持久化 GUID。

响应主要字段为 `sip[]`、`midurlinfo[]`。`song_url` 读取首个条目的 `purl`，拼接优先选取的 HTTPS `sip`；没有可选 CDN 时，该函数使用代码中的默认 CDN。音质检查会按 `filename` 匹配各授权条目，要求 `result=0`、`purl` 非空及 CDN 地址存在。

拿到 URL 不等于任何音质都能播放；链接和权限随账号及时间变化。当前 `song_url` 对扩展音质额外执行 CDN `HEAD`，基础 Low / Standard / High / Lossless 不在该函数内做此检查；音质列表查询会对所有成功授权的候选 URL 执行 `HEAD`，并发上限为 4。

### 音质文件映射

明文路径使用 `前缀 + media_mid + media_mid + "." + 扩展名`。下表保留项目的本地映射，各歌曲提供的文件以服务端响应为准。

| `Quality` | 前缀 | 扩展名 | `file` 下的大小字段 | 当前处理 |
| --- | --- | --- | --- | --- |
| Master | AI00 | flac | `size_new[0]` | 母带候选 |
| Hires | RS01 | flac | `size_hires` | Hi-Res 候选 |
| Atmos | Q000 | flac | `size_new[1]` | 扩展音质候选 |
| Atmos51 | Q001 | flac | `size_new[2]` | 扩展音质候选 |
| Atmos71 | Q003 | ogg | `size_new[6]` | 扩展音质候选 |
| Dolby | D004 | mp4 | `size_dolby` | 明文样本为 AC-4，播放走下表的 `D0M1` |
| Dts | DT03 | mp4 | `size_new[9]` | Windows x64 和 Android ARM64 可用本地 DTS:X 解码库 |
| Aicodec | TL01 | nac | `size_new[7]` | Android ARM64 和 Windows x64 可用内置模型解码加密 NAC |
| Lossless | F000 | flac | `size_flac` | 无损候选 |
| High | M800 | mp3 | `size_320mp3` | 高品质候选 |
| Standard | M500 | mp3 | `size_128mp3` | 标准候选 |
| Low | C400 | m4a | `size_96aac` | 流畅候选 |
| Ogg640 | O801 | ogg | `size_new[5]` | 格式映射保留，不单列菜单档位 |
| Ogg320 | O800 | ogg | `size_new[3]` | 同上 |
| Ogg192 | O600 | ogg | `size_192ogg` | 同上 |
| Ogg96 | O400 | ogg | `size_96ogg` | 同上 |
| Aac192 | C600 | m4a | `size_192aac` | 同上 |
| Aac48 | C200 | m4a | `size_48aac` | 同上 |

仅大小大于零的音质档位进入候选列表，再按授权和 CDN 检查计算 `available/reason`。`104003` 映射为当前账号无权限，`104013` 映射为设备受限，其他没有链接的授权结果映射为 `NoLink`；这些是项目内解释，不是完整的官方错误码定义。

登录后，明文候选不可用时，可在降档前通过 PC 公共通道调用 `music.vkey.GetEVkey.CgiGetEVkey`（`ctx=1`）。杜比全景声直接请求 `D0M1`。`musicfile[]` 使用歌曲详情的 `file.media_mid`，`filename[]` 使用下表的文件 ID，两个字段都只拼接一次 ID。队列预取的样本中，原请求的部分媒体 ID 与歌曲详情不同，实际文件名使用歌曲详情的 ID。

| 档位 | 加密文件 | `filename[]` 的 ID | 解密后的容器 |
| --- | --- | --- | --- |
| Master | `AIM0…mflac` | `track.vs[3]` | FLAC |
| Atmos | `Q0M0…mflac` | `track.vs[29]` | FLAC |
| Lossless | `F0M0…mflac` | `file.media_mid` | FLAC |
| High | `O8M0…mgg` | `file.media_mid` | Ogg |
| Dolby | `D0M1…mmp4` | `file.media_mid` | MP4，样本音轨为 E-AC-3 |
| Dts | `DTM3…mmp4` | `track.vs[30]` | MP4，音轨为 DTS-UHD Profile 2 |

加密候选须返回匹配文件的授权链接及有效 `ekey`，并能从 CDN 首段解出对应的容器头。Rust 回环中转按 CDN 的字节偏移解密，数据不写入 Kanade 的音频缓存。使用 2026-11-09 PC 抓包中的登录态重新取源，母带、全景声、SQ 和 HQ 均通过 FFmpeg 的回环读取、跳转和解码验证。

同日 Hi-Res 补抓的 `pc-hires/raw/067` 记录了《小小奇迹》的 `RSM1` 下载授权。对同一首歌，`UrlGetVkey` 按现有命名规则返回了 `RS01` 明文链接，CDN 文件头为 `fLaC`，总长 48,836,278 字节，与 `file.size_hires` 一致。Kanade 的 Hi-Res 播放沿用这个明文路径。`RSM1` 也已通过 `CgiGetEVkey` 单独验证，解密后为 96 kHz、24 bit FLAC，跳到第 7 秒后可解码出声音。

另用同一登录态重新取得以下三档的授权链接和密钥。三份完整样本均可解密，独立请求并解密的字节范围与完整样本对应位置一致。Windows 内核测试直接加载 Kanade 随包的 libmpv，使用 SQ FLAC 样本作对照。

| 档位 | 加密文件与 ID | 解密及解码结果 |
| --- | --- | --- |
| 杜比全景声 | `D0M1…mmp4`，`file.media_mid` | MP4 内为 E-AC-3（`ec-3`），FFmpeg 识别为 Dolby Digital Plus + Atmos。Windows libmpv 跳至第 7 秒后输出非静音的 48 kHz 六声道 PCM。对象渲染和设备透传待验证。 |
| DTS:X | `DTM3…mmp4`，`track.vs[30]` | MP4 音轨为 DTS-UHD Profile 2（`dtsx`）。《Mood》的解密文件与 `DT03` 明文文件逐字节相同。重新切分裸流会漏帧，Windows 解码器按 MP4 原始 sample 边界完整解出三首真实样本。 |
| NAC | `TLM1…mnac`，`track.vs[28]` | 解密后以 `NAC_` 开头。Android ARM64 和 Windows x64 的专用解码器通过 MNN 生成临时 WAV，再交给播放器。 |

两端使用同一份本地模型 `android/app/nac-local/7187332.mnn`，也可用环境变量 `KANADE_NAC_MODEL` 指定路径。执行 `flutter build apk --target-platform android-arm64` 或 `flutter build windows` 时，构建会校验模型的 SHA-256 并嵌入原生库。只有加载到该库并验证授权音源后，现有音质菜单才显示 AI 音质。Rust 下载完整首后边解码边写临时 WAV（文件头预先写好总长度），解出第一段就让播放器打开本机地址。从上次位置恢复或往后拖到还没解出的位置时，本机中转会等解码追上，所以播放这类音源时关闭 mpv 的网络超时（其他音源仍是 media_kit 默认的 5 秒）。切歌时会取消解码并回收临时 WAV。

Windows x64 使用抓包登录态实测了音质探测、重新取源、本机解码、HTTP Range 和跳转后的非静音输出。关闭音频缓存时，解码产物只供当前音源使用，切歌后回收。

Windows x64 的 DTS:X 从 `kanade.exe` 旁的 `dts-runtime\DTSXDecoder.dll` 加载。解码库及其运行时依赖由使用者提供：放入 Git 忽略的 `windows/dts-local/` 后构建，会拷贝到产物的 `dts-runtime\`；也可直接放进已构建程序的该目录。由于该接口取决于二进制布局，当前只加载 SHA-256 为 `0fb48a12aef354016992e5fc2a34ea7ef4852711a5f48a66bdff07661285c4ca` 的版本。输出为 48 kHz、24 bit、5.1 PCM。

Android ARM64 的 DTS:X 由构建者提供兼容的 DTS Playback SDK、配置和许可。将 `libDTSPlaybackSDK.so`、`dts_config.yaml` 和 `dts_hpx.lic` 放入 Git 忽略的 `android/app/dts-local/`，或用 `KANADE_DTS_ANDROID_RUNTIME` 指向该目录，再构建 APK。当前验证的 SDK SHA-256 为 `71b9872cca9e031b293eef7ec8a5762cf1069ad8762a9e17f261d20d1bff95d1`。SDK 输出 48 kHz 双声道浮点 PCM。

该 SDK 的 ELF 段按 4 KB 对齐，16 KB 页大小的 Android 环境尚未验证。

两端均在解码器初始化成功且当前歌曲有授权音源时显示 DTS:X。播放优先用明文 `DT03`，取不到时尝试 `DTM3`。与 NAC 一样边解码边写临时 WAV、解出第一段就交给播放器，切歌时回收。WAV 总长度按 MP4 的 `mdhd` 时长预先计算，解码结果超出部分丢弃、不足部分补静音。

取链接从用户指定音质开始降级。Master / Hires / Atmos 等扩展档位按 `指定档位 → Lossless → High → Standard → Low`；High 为 `High → Standard → Low`；Lossless 为 `Lossless → High → Standard → Low`。额外编码的回退规则以 `quality::playback_chain` 为准。返回 `SongUrl.quality` 是最终取得的音质，调用方不能始终显示请求值。

## 歌词

主接口：`music.musichallSong.PlayLyricInfo.GetPlayLyricInfo`，使用通用通道。

```json
{"songMID":"<SONG_MID>","songID":42,"trans":1,"roma":0,"crypt":0,"qrc":0}
```

读取 `lyric` 和 `trans`，尝试 Base64 解码为 UTF-8，失败则保留原文本。主接口失败或歌词为空时，改用：

```text
GET https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg
songmid=<SONG_MID>&format=json&nobase64=1&g_tk=5381
```

旧 CGI 读取原始响应的 `lyric/trans`。当前按 LRC 行时间轴解析并合并翻译，时间单位为毫秒；无翻译时是空字符串，翻译中的 `//` 视为无翻译。无时间轴时保留 `Lyric.plain`。当前请求明确关闭 QRC，不提供逐字歌词或罗马音。

## 榜单与推荐

| 功能 / 上游方法 | 通道 | `param` | 返回路径 / 当前行为 |
| --- | --- | --- | --- |
| 榜单目录：`musicToplist.ToplistInfoServer.GetAll` | 通用 | `{}` | `group[].toplist[]`；榜单 `topId/title/period`、封面、前三首预览 |
| 榜单详情：`musicToplist.ToplistInfoServer.GetDetail` | 通用 | `topId`、`offset=0`、`num=100`、`period` | 榜单元数据在 `data`，歌曲在 `songInfoList` |
| 推荐首页：`music.recommend.RecommendFeed.get_recommend_feed` | 内嵌页 | `direction=0`、`page=1`、`v_cache=[]`、`v_uniq=[]`、`s_num=0` | `v_shelf[].v_niche[].v_card[]` |
| 猜你喜欢：`music.radioProxy.MbTrackRadioSvr.get_radio_track` | 内嵌页 | `id=99`、`num=5`、`from=0`、`scene=0`、`song_ids=[]` | `tracks[]`；每次取新批次，不缓存 |
| 刷歌 / 雷达：`music.recommend.TrackRelationServer.GetRadarSong` | 内嵌页 | `Page`、`ReqType=0`、`FavSongs=[]`、`EntranceSongs=[song_id,…]` | `VecSongs[].Track`；批次从 1 开始，不缓存 |
| 新歌首发：`newsong.NewSongServer.get_new_song_info` | 内嵌页 | `type=5` | `songlist[]` |

推荐区块标题由 `title_template` 中的 `{String}` 替换为 `title_content`。当前保留 `type=200` 的歌曲卡、`type=500` 的歌单卡；歌曲卡的数字 ID 通过 `CgiGetTrackInfo` 补全，节目等其他卡片不进入当前模型。

雷达种子从推荐卡 `scheme` 的 `jumpToRadarMode` 跳转参数 `p.EntranceSongs` 读取，封面取卡片 `cover`，可能为空。猜你喜欢入口本身不等于完整歌曲列表；“每日30首”按推荐返回的歌单 ID 继续取歌单详情，不把首页歌曲卡当作每日30首。

推荐首页当前只请求第一页，没有暴露推荐区块的下一页接口。猜你喜欢按设计用于登录后的个性化取歌，但其函数没有本地 `NotLoggedIn` 检查，实际匿名响应由上游决定；雷达函数也没有本地登录拦截。

## 歌单读取与写入

实现：[music.rs](../rust/src/qq/music.rs)、[library.rs](../rust/src/qq/library.rs)。

### 读取

| 功能 | 接口 / 通道 | 参数 | 返回路径 |
| --- | --- | --- | --- |
| 歌单详情 | `music.srfDissInfo.aiDissInfo.uniform_get_Dissinfo`；通用 | `disstid=歌单 tid 数值`、`enc_host_uin=""`、`tag=1`、`userinfo=1`、`song_begin=0`、`song_num=1000`、`onlysonglist=0`、`orderlist=1` | `dirinfo` 元数据、`songlist[]` |
| 自建歌单，包含我喜欢 | GET `https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss` | `hostuin=musicid`、`sin=0`、`size=200`、`format=json` | 原始响应 `data.disslist[]` |
| 收藏的他人歌单 | GET `https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg` | `ct=20`、`cid=205360956`、`userid=musicid`、`reqtype=3`、`sin=0`、`ein=200`、`format=json` | 原始响应 `data.cdlist[]` |

`get_user_playlists` 合并自建与收藏歌单，要求本地已登录；收藏列表请求失败时仍返回已取得的自建列表。`get_my_playlists` 只返回自己的歌单，也要求登录，用于后续写入目标选择。

自建歌单字段映射：`dirid → dir_id`、`tid → tid`、`diss_name → name`、`diss_cover → cover_url`、`song_cnt → song_count`。收藏歌单使用 `dissid/dissname/logo/songnum/listennum/nickname`。

**`dir_id` 是当前账号下的目录编号，`tid/disstid/dissid` 是歌单标识。** 当前代码将 `201` 作为“我喜欢”目录编号，但对应 `tid` 仍须从当前账号歌单读取。普通歌单目录编号、名称和 `tid` 全部来自列表，不写死。

歌单详情当前一次最多请求 1000 首，自建 / 收藏列表各按上述固定范围读取，未实现完整分页。因此 `get_liked_song_ids` 通过歌单详情取得的红心 ID 也受当前详情读取范围限制。

### 收藏、取消收藏与歌单加删歌曲

上游模块：`music.musicasset.PlaylistDetailWrite`。添加用 `AddSonglist`，移除用 `DelSonglist`。当前一次提交一首：

```json
{
  "dirId": 123,
  "bFmtUtf8": true,
  "dirName": "<CURRENT_PLAYLIST_NAME>",
  "tid": 456,
  "v_songInfo": [{"songId":42,"songType":0}]
}
```

`dirId/tid` 为示例数字，不是真实目标。“我喜欢”走 Android 写入通道，普通歌单走 PC 私有通道；两者目前使用相同的上述参数形状。项目会先在当前账号歌单中查找目录，再提交操作。

成功要求外层结果码通过，且业务 `data.retCode` 明确为数字 `0`；缺失 `retCode` 属于响应错误。写入不自动回退重发，成功后清除目标歌单详情和自建歌单列表缓存。

### 重命名与删除整个歌单

上游模块：`music.musicasset.PlaylistBaseWrite`，使用 PC 私有通道。

| 操作 / 方法 | `param` |
| --- | --- |
| 重命名 `EditPlaylist` | `bFmtUtf8=true`、`dirId`、`dirNewName=新名称`、`dirShow=1`、`mask=1` |
| 删除 `DelPlaylist` | `bFmtUtf8=true`、`dirId`、`dirName=当前名称` |

当前封装禁止重命名或删除 `dir_id=201`，并且只允许从当前账号自建列表找到的目录。结果同样检查数字型 `retCode=0`，成功后清除相关缓存。删除所需名称可能来自 600 秒有效的歌单列表缓存，并非保证每次重新联网读取。

### 创建空歌单

`music.musicasset.PlaylistBaseWrite.AddPlaylist` 使用 PC 私有通道，参数仅为
`{"bFmtUtf8":true,"dirName":"<NEW_NAME>"}`，请求键为完整 `module.method`。
调用入口 `create_playlist(name)` 要求登录、拒绝空白名称；检查业务 `retCode=0`，并要求
`result.dirId`、`result.tid` 为正整数，返回 `MyPlaylist`。成功后清除 `my_playlists` 缓存，
由 `LibraryController` 通知“我的”与桌面侧栏刷新。

原生 PC 抓包在带 Sign / Mask 的 `musics.fcg` 成功创建。本实现复用已有 PC 私有
`musicu.fcg` 通道；本轮仅核对请求结构与失败结果处理，尚未在应用内真实提交创建。
收藏 / 取消收藏整个他人歌单仍未实现；创建空歌单与向已有歌单加歌是两个操作。

## 最近播放

实现：[history.rs](../rust/src/qq/history.rs)。两个接口均要求登录并使用 PC 私有通道。

### 读取云端记录

模块 / 方法：`music.musicasset.PlayRecentlyRead.GetPlayRecentlyInfo`。

```json
{"requestCnt":2500,"type":2,"updateTime":0}
```

返回还有额外一层结果码和 `data`，简化示意：

```json
{
  "code": 0,
  "type": 2,
  "updateTime": 1700000000,
  "data": {
    "songList": [
      {
        "track": {"id":42,"mid":"<SONG_MID>","name":"<SONG_NAME>"},
        "lastTime": 1700000000,
        "listenCnt": 1,
        "lastPlayDevice": 0
      }
    ]
  }
}
```

外壳解包后的业务 `code` 仍须为 `0`。当前提取 `data.songList[].track` 为歌曲列表，按上游顺序使用；播放时间、次数和设备字段未暴露给 Dart。

其他分类由 `recent_collections` 读取，同一接口换 `type`（字段见 [Android 最近播放分类抓包](qqmusic-recent-plays-android-capture.md)）：

| `type` | 取用 | 转成 |
| --- | --- | --- |
| 1（全部） | `data.allItems.albumList` / `geDanList` / `listenBookList` | `AlbumBrief` / `PlaylistBrief` / `RecentBook`（`episode` 为上次听的那一集） |
| 6 | `data.mvList[].mvInfo` | `VideoBrief`（无时长、播放量） |
| 5 | `data.radioList` 中 `radioType=2` 的项 | `RecentRadio`，用 `get_radio_songs(id)`（`MbTrackRadioSvr.get_radio_track`）播放 |

三个请求并发，合并缓存 300 秒。不提供 2500 条之后的翻页、增量同步或删除云端记录。

### 上报播放

模块 / 方法：`music.musicasset.PlayRecentlyWrite.ReportPlayRecentlyInfo`。

```json
{"data":[{"id":"42","lastTime":1700000000,"listenCnt":1,"type":2}]}
```

`id` 是歌曲数字 ID 的字符串形式，`lastTime` 是当前 Unix **秒**，不是毫秒。成功要求 `data.ret=0`，成功后清除最近播放缓存。此操作会改变云端记录；调用入口为 `report_play`，应在实际开始播放时调用。

## 歌手与专辑

实现：[detail.rs](../rust/src/qq/detail.rs)。以下均使用内嵌页通道。

| 功能 / 上游方法 | `param` | 返回路径 |
| --- | --- | --- |
| 歌手资料：`music.musichallSinger.SingerInfoInter.GetSingerDetail` | `singer_mids=[mid]`、`pic=1`、`group_singer=1`、`wiki_singer=1`、`ex_singer=1` | `singer_list[0].basic_info`、`pic.pic`、`ex_info.desc` |
| 歌手歌曲：`music.musichallSong.SongListInter.GetSingerSongList` | `singerMid`、`begin`、`num`、`order=1` | `songList[]`、`totalNum` |
| 歌手专辑：`music.musichallAlbum.AlbumListServer.GetAlbumList` | `singerMid`、`order=1`、`num`、`begin` | `albumList[]`、`total` |
| 精选专辑：`music.musichallAlbum.SelectedAlbumServer.SelectedAlbumList` | `singerMid` | `albumList[]`；元素 `albumMid/albumName/publishDate` |
| 视频分类：`MvService.MvInfoProServer.GetSingerMvTag` | `singermid` | `list[].id/name`；标签由接口返回 |
| 歌手视频：`MvService.MvInfoProServer.GetSingerMvList` | `singermid/tagid/start/count/order`；最新 0 / 最热 1 | `list[]/total`；读取 `vid/title/picurl/duration/playcnt` |
| 专辑资料：`music.musichallAlbum.AlbumInfoServer.GetAlbumDetail` | `albumMid` | `basicInfo`、`company.name`、`singer.singerList[]` |
| 专辑歌曲：`music.musichallAlbum.AlbumSongList.GetAlbumSongList` | `albumMid`、`begin=0`、`num=1000`、`order=2` | `songList[]` |

歌手分页的 `begin` 为从 `0` 开始的偏移量。`get_singer_detail` 并发请求资料、首批 30 首歌曲、首批 30 张专辑和精选专辑；`get_singer_songs/get_singer_albums` 支持传入偏移和条数。精选页展示首批 10 首歌曲和精选专辑；视频每页 40 条，`start` 使用已加载条数，支持最新 / 最热切换。切换分类或排序后从头加载，后续分页沿用当前分类和排序。本轮只读验证了两种排序的顺序不同及 `start=0/5` 两批没有重复。最热由上游排序，不能自行按累计播放量替代。专辑详情并发请求资料和歌曲，当前不提供专辑歌曲继续翻页的公开入口。

### 歌手粉丝与守护信息

`get_singer_social(mid)` 并发读取粉丝 CGI、守护入口与关注状态，不缓存社交结果。
`GET https://c6.y.qq.com/rsc/fcgi-bin/fcg_order_singer_getnum.fcg` 使用 `singermid/utf8=1/format=json`，
严格检查 `code/subcode=0`，读取 `num` 的原始计数。本次样本返回 `339101`。

守护入口为 `music.UnifiedHomepage.UnifiedHomepageSrv.GetHomepageIconForMedal`，
参数 `SingerMid` 与当前登录上下文的 `Uin`。读取 `NumButtonList` 中 `ButtonType=9` 的
`ButtonInfo.Title`，样本为 `38万乐迷守护`。保留服务端文案；`cnt=0` 与这个人数无关，
不反推精确人数。界面仅展示守护信息，未实现勋章详情、任务或付费行为。

### 关注歌手与用户

实现：[social.rs](../rust/src/qq/social.rs)。查询歌手状态使用内嵌页读通道：
`Concern.ConcernSystemServer.cgi_qry_concern_status`，参数
`vec_userinfo=[{usertype:1,userid:<SINGER_MID>}],opertype=5,encrypt_singerid=1`；
读取 `map_singer_status[MID]`。未登录时不查询私有关注关系。

写入统一使用 `Concern.ConcernSystemServer.cgi_concern_user_v2` 和内嵌页写通道：

| 对象 | 参数 |
| --- | --- |
| 歌手 | `opertype=关注0/取消1`、`source=0`、`encrypt_singerid=1`、`userinfo={usertype:1,userid:<SINGER_MID>}` |
| 用户 | `opertype=关注0/取消1`、`userinfo={usertype:0,userid:<encrypt_uin>}`；不带歌手专属字段 |

两者都要求网关与业务外壳 `code=0`，且业务 `data.code` 明确为数字 0。
写请求不自动回退或重试，成功后失效目标用户的主页缓存。关注按钮在请求期间禁用，
只有成功后更新状态；失败保留原状态并显示错误。本轮未从应用重放真实关注 / 取消关注。

专辑列表读取 `albumMid/albumName/publishDate/singerName`；专辑详情数字 ID 读取 `basicInfo.albumID`，评论查询需要这个 ID，不是 MID。

封面地址由本地辅助函数生成：

```text
专辑：https://y.gtimg.cn/music/photo_new/T002R300x300M000<ALBUM_MID>.jpg
歌手：https://y.gtimg.cn/music/photo_new/T001R300x300M000<SINGER_MID>.jpg
```

歌手详情优先采用响应 `pic.pic`。统一歌曲解析在没有专辑 MID 时尝试用首位歌手封面。

## MV

2026-10-31 从歌曲入口实抓确认：歌曲搜索结果的 `song.mv.vid` 直接用于 MV 详情和取流；
`mv.id=0` 时也可能有有效 VID。`Song.mv_vid` 保留该字段，播放队列持久化也一并保存。
同轮捕获了 `music.recommend.TrackRelationServer.GetSimilarSongs`（参数 `songid`，返回 `data.vecSong[].track`），
已通过 `get_similar_songs(song_id)` 接入，检查 `data.retcode=0` 后按顺序解析 `vecSong[].track`。
长按歌曲和更多按钮的共用弹窗提供「观看 MV」（VID 非空时）和「查找相似歌曲」，
分别复用 MV 播放页与歌曲列表页。参数、样本及证据见[歌曲进入 MV 与相似歌曲抓包](qqmusic-song-mv-capture.md)。

实现：[mv.rs](../rust/src/qq/mv.rs)。两项都走通用 `musicu`（带签名的 `musics.fcg`，失败回退 `musicu.fcg`）。

| 功能 / 上游方法 | `param` | 返回路径与项目处理 |
| --- | --- | --- |
| 资料：`music.video.VideoData.get_video_info_batch` | `vidlist=[VID]`、`required=[name, cover_pic, singers, playcnt, pubdate, duration, uploader_nick, desc, ...]` | `data[VID]`；`pubdate` 是 Unix 秒，按北京时间转成日期；缓存 3600 秒 |
| 播放地址：`music.stream.MvUrlProxy.GetMvUrls` | `vids=[VID]`、`request_type=10001`、`addrtype=3`、`format=264` | `data[VID].mp4[]` 中 `code=0` 的条目，取 `freeflow_url` / `url` 里第一个 https 地址；不缓存 |

官方 Windows 客户端用 `request_type=10003, format=265`，只返回相对的 `urlPath` 和 HLS 片段路径，缺 CDN 基址
（见[抓包笔记](qqmusic-search-mv-capture.md)）。2026-10-31 实测 `10001 + format=264`（H.264）直接返回完整 https MP4 地址，
官方 MV 和用户上传视频都适用。按下载到的文件头（`tkhd`）核对，`filetype` 10 / 20 / 30 / 40 分别是
640×360 / 846×476 / 1280×720 / 1920×1080，项目标成 360P / 480P / 720P / 1080P；其他 `filetype` 忽略。
地址的 `expire` 为 86400 秒，每次打开播放页都重新获取。冒烟测试 `desktop_mv_streams` 对最低档发 Range 请求，
确认返回 206 和 `ftyp`。付费 MV 和 `play_forbid_reason≠0` 的情况未验证，没有可用条目时播放页显示无法播放。

## 其他用户主页

实现：[user.rs](../rust/src/qq/user.rs)。主页资料要求登录；本轮旧 CGI 与原统一主页的匿名调用均返回 1000，当前明确返回 `NotLoggedIn`，不伪装为零条内容。从用户搜索结果传 `encrypt_uin`；自己的主页可传当前账号编号，响应仍保留 `creator.encrypt_uin` 用于后续请求。

| 功能 / 上游方法 | `param` | 返回路径 |
| --- | --- | --- |
| 资料：GET `https://c6.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg` | `userid/cid=205360838/ct=20/cv=2276/reqfrom=1/reqtype=0/format=json`，以及 `uin/g_tk/g_tk_new_20200303/platform` | `data.creator.nick/headpic/encrypt_uin/nums/isfollow/ishost/diss_lock`；`data.mydiss.num`；简介用 `creator.cfinfo.title`（认证说明） |
| 歌单：`…UnifiedHomepageSrv.GetHomepageTabDetail` | `uin`、`IsQueryTabDetail=1`、`TabID="disc"`、`PageNum`、`PageSize`、`Order=0` | `DiscTab.List[]` 的 `Dissid/Title/Picurl/Subtitle`，`HasMore` |
| 喜欢歌曲：`music.srfDissInfo.DissInfo.CgiGetDiss` | `optype=0,disstid=<目标用户喜欢歌单ID>,onlysonglist=1,song_begin=page*page_size,song_num=page_size` | `songlist[]/hasmore`；复用歌曲解析与播放组件 |
| 收藏歌单：`music.musicasset.PlaylistFavRead.GetPlaylistFavInfo_v2` | `uin=<encrypt_uin>,offset=page*page_size,size=page_size` | `v_list[].tid/name/logo/songnum/nickname`、`hasmore/hide` |
| 收藏专辑：`music.musicasset.AlbumFavRead.GetAlbumFavInfo_v2` | `euin=<encrypt_uin>,offset=page*page_size,size=page_size` | `v_list[].mid/name/logo/pubtime/v_singer`、`hasmore/hide` |
| 收藏视频：`music.musicasset.MVFavRead.getMyFavMV_v2` | `encuin=<encrypt_uin>,cid=205361447,support=1,num=page*page_size,pagesize=page_size` | `mvlist[].vid/mv_name/mv_picurl/duration/playcount/singer_name/uploader_nick`、`hasmore` |

QQ 音乐不支持用户自己写简介，PC 主页简介位置显示的就是 `cfinfo.title`，为空时显示“暂无”；统一主页 about 标签的 `AboutList[].baseInfo.desc` 在 2026-10-31 扫过约 260 个用户全为空，不再请求。

资料 CGI 严格检查 `code/subcode=0`，缓存 600 秒。`creator.nums.fansnum/follownum` 为粉丝及关注计数；
`ishost=1` 时隐藏关注按钮。非本人且 `diss_lock=1` 时展示未公开，不请求自建歌单。
自己的主页由“我的”头像进入。

若 CGI 的 `mydiss.list` 条数等于 `mydiss.num`，说明已返回完整快照，公开歌单直接对该快照分页。
本轮实测有 5 个公开歌单的旧账号，在统一主页只有 `about` 标签，强行读取 `disc` 会返回空；
使用完整快照后页面正常显示。快照不完整时保留统一主页分页；若首页仍为空但资料声明有歌单，
返回明确的响应错误，不显示“没有公开的歌单”。统一主页的 `PageNum` 从 `0` 开始。
歌曲数从副标题
“62首    1260.8万次播放 …”开头解析，播放量不单独返回。歌单 ID 可用于 `get_playlist_detail`。
收藏资产不缓存，界面按 `hasmore` 继续翻页，`hide=true` 展示未公开；不能把隐私结果当成空收藏。
收藏专辑的 `pubtime` 为 Unix 秒，复用北京时间日期转换。本轮确认了非空歌单 / 专辑和收藏歌单两页不重复。

页面分为「创建的」与「我喜欢」；后者包含歌曲、歌单、专辑、视频四个子分类。
喜欢歌曲的目录 ID 来自目标主页 `data.mymusic` 中 `type=1` 卡片的 `id`，按数字传入 `disstid`，
不复用当前登录用户的目录。`num0` 为歌曲数；没有歌曲时返回空列表，有歌曲却缺少目录 ID 则报错。
四类资产均尊重目标主页的 `fav_lock/islock`；他人未公开时显示隐私状态，本人不受该显示限制。
歌曲和视频进一步严格检查业务 `data.code/subcode=0`。

只读验证了 1400 首喜欢歌曲样本的前两页不重复，以及非空收藏视频样本的偏移 0 / 2 两批
分别返回 2 / 1 条、`hasmore` 从 1 变为 0。部分旧收藏视频 `status=0`，封面为空、时长为零；
仍保留标题与 VID，由既有封面占位图及 MV 播放页处理。视频点击复用 `MvPage`。

另有 GET `https://c6.y.qq.com/rsc/fcgi-bin/fcg_get_my_vedio.fcg`（原接口拼写为 vedio，
`userid/reqtype=1/cid=205361746/sin/pagesize`）用于上传视频，属于不同资产，本轮不混入喜欢的视频。

## 评论与回复

模块：`music.globalComment.CommentRead`，使用内嵌页通道，不在本地强制检查登录态。当前只提供读取，不提供发布、删除、点赞评论。

### 推荐 / 最热 / 最新（Android 参数）

`comment_feed(target,id,sort,cursor)` 和 `reply_feed(root_id,cursor)` 按 [Android 评论页抓包](qqmusic-comments-android-capture.md)的参数请求，
仍走内嵌页通道（2026-11-11 重放确认结果与 Android 一致），每页 15 条，回复第一页 6 条、之后 5 条。
`BizType=1` 为歌曲，`2` 为专辑；`BizId` 是相应数字 ID 的字符串。

| `sort` | 方法 | 下一页带上 |
| --- | --- | --- |
| `Recommend` | `GetRecCommentList` | `RecOffset`、`PageNum`、上一页最后一条的 `SeqNo/HotScore/RecScore`、`CommentIds` |
| `Hot` | `GetHotCommentList`，`HotType=6` | `PageNum`、上一页最后一条的 `HotScore/CmId/SeqNo` |
| `Latest` | `GetNewCommentList`，不传 `WithHot` | `PageNum`、上一页最后一条的 `CmId/SeqNo` |

三者都带 `LastTotal`、`LastTotalVer`（上一页的 `TotalVer`）和 `LastRspVer`（第一页的 `RspVer`，后续页的响应里它是空的）。
这些值由 Rust 打包成 `CommentFeed.cursor` 字符串，界面取下一页时原样传回，第一页传空字符串。

推荐列表的翻页不是按偏移取：第一页响应的 `CommentList.CommentIds` 是后续全部评论的 id（样本 285 个），
第 N 页把其中第 `(N-1)*15` 起的 15 个放进请求的 `CommentIds`，服务器返回这 15 条的正文；传别的 id 就返回别的评论。
未登录时第一页没有 `CommentIds`，推荐只有 15 条，所以 `has_more` 以 id 是否用完为准，不看 `HasMore`。

总数取顶层 `TotalCmNum`。回复的 `HasMore` 一直是 1，`has_more` 按“已取条数 < 第一页的 `Total`”判断。
字段映射：`CmId → id`、`SeqNo → seq_no`、`Nick → nick`、`Avatar → avatar_url`、`Content → content`、`PubTime → time_secs`、`PraiseNum → praise_count`、`ReplyCnt → reply_count`；被回复用户取 `RepliedComments[0].Nick`。正文会去除完整的 `[em]…[/em]` 表情代码。
带图评论读 `Pic → pic_url`、`PicSize`（`"宽x高"`）`→ pic_width/pic_height`；`Pic` 原地址不带 Cookie、不加参数可以直接下载。

抓包笔记曾记录评论 `SubCode=0`；当前 `detail.rs` 没有额外检查 `SubCode`，只使用通用网关封装的业务码检查。不得据此宣称已严格校验评论所有内层结果码。

## 登录与用户资料

实现：[login.rs](../rust/src/qq/login.rs)、[mqtt.rs](../rust/src/qq/mqtt.rs)。登录业务的最终会话字段为 `musicid` 和 `musickey`，后者也兼容响应中的 `qm_keyst` 字段。

### QQ 扫码与同机 QQ 跳转

公共配置：`appid=716027609`、`daid=383`、`pt_3rd_aid=100497308`、`u1=https://graph.qq.com/oauth2.0/login_jump`；页面 Referer 为 `https://xui.ptlogin2.qq.com/`。

| 步骤 | HTTP 接口 | 关键参数 / 结果 |
| --- | --- | --- |
| 申请图片二维码 | GET `https://ssl.ptlogin2.qq.com/ptqrshow` | 公共配置加 `e=2/l=M/s=3/d=72/v=4/t=随机值`；响应为图片，从 Cookie 取 `qrsig` |
| 申请同机跳转票据 | 同上 | 公共配置加 `s=8/e=0/type=1/t=随机值`；解析 `ptui_qrcode_CB` 中 `ec=0`、`qrcode` URL，没有图片 |
| 轮询 | GET `https://ssl.ptlogin2.qq.com/ptqrlogin` | `ptqrtoken=hash33(qrsig,0)`，Cookie 带 `qrsig`；同时带 aid、daid、pt_3rd_aid、u1 和客户端轮询字段，完整参数见 `poll_qr` |
| 建立 OAuth Cookie | GET `https://ssl.ptlogin2.graph.qq.com/check_sig` | 使用成功回调中的 `uin/ptsigx` 与客户端参数，取得 `graph.qq.com` 的 `p_skey` |
| 换 OAuth code | POST 表单 `https://graph.qq.com/oauth2.0/authorize` | `response_type=code`、`client_id=100497308`、`g_tk=hash33(p_skey,5381)` 等；不自动跟随重定向，从 Location 取 `code` |
| 换音乐会话 | 通用 `QQConnectLogin.LoginServer.QQLogin` | `param={"code":"<OAUTH_CODE>"}`，覆盖 `comm.tmeLoginType="2"` |

OAuth 表单使用 `redirect_uri=https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/`、`scope=get_user_info,get_app_friends`、`state=state`、`from_ptlogin=1`、`src=1`、`update_auth=1`、`openapi=1010_1030`、`switch=""`、毫秒级 `auth_time` 和随机 UUID `ui`。

`ptuiCB` 第一个状态值的当前映射：`66 → Waiting`、`67 → Scanned`、`65 → Expired`、`68 → Refused`、`0 → 执行后续登录交换`。同机跳转必须使用 `type=1` 取得的票据，再复用 QQ 轮询流程。

### 微信扫码

| 步骤 | 接口 | 关键参数 / 结果 |
| --- | --- | --- |
| 取得二维码 UUID | GET `https://open.weixin.qq.com/connect/qrconnect` | `appid=wx48db31d50e334801`、`response_type=code`、`scope=snsapi_login`、`state=STATE`；从页面提取 UUID |
| 下载二维码 | GET `https://open.weixin.qq.com/connect/qrcode/<UUID>` | 图片字节；项目把 UUID 放在 `QrCode.qrsig` |
| 长轮询 | GET `https://lp.open.weixin.qq.com/connect/l/qrconnect` | `uuid`、`_=当前毫秒时间`；当前 HTTP 超时 35 秒 |
| 换音乐会话 | 通用 `music.login.LoginServer.Login` | `param={"code":"<WX_CODE>","strAppid":"wx48db31d50e334801"}`，覆盖 `comm.tmeLoginType="1"` |

二维码页面使用 `redirect_uri=https://y.qq.com/portal/wx_redirect.html?login_type=2&surl=https://y.qq.com/`，以及源码中的微信弹窗样式 `href` 参数。

`wx_errcode` 映射：`408 → Waiting`、`404 → Scanned`、`403 → Refused`、`402 → Expired`、`405 且 wx_code 非空 → 执行会话交换`。

### QQ 音乐 App 授权

这个流程使用独立的 `TmeClient`，会话申请、二维码和最终凭据交换复用同一组 Android `uid/sid`。设备安装 ID 保存在 `mobile_login_device_id`，用于 `OpenUDID/OpenUDID2/udid`；不把随机值当作服务端签发的 QIMEI。

1. 初始化 Android 公参：`ct=11/cv=v=14090008/chid="10003505"/tmeAppID="qqmusic"/tmeLoginType=2/qq="0"/authst=""`，初始 `uid/sid` 为空；Android 平台另带源码读取的系统属性。
2. 调用 `music.getSession.session.GetSession`，参数 `{"uid":"","vkey":0,"caller":0}`，保存响应 `session.uid/session.sid`。
3. 调用 `music.login.LoginServer.CreateQRCode`，参数 `{"tmeAppID":"qqmusic","ct":11,"cv":14090008}`；这一步仅覆盖公参 `ct=23/cv=0`。读取 `qrcodeID` 与带 `base64,` 前缀的 `qrcode` 图片。
4. 连接 `wss://mu.y.qq.com/ws/handshake`，完成 MQTT 5 CONNECT 和 SUBSCRIBE，收到 SUBACK 后才向调用方返回二维码及授权入口 `https://y.qq.com/m/client/qr_code_login/authorize.html?qrcode_id=<QRCODE_ID>`。
5. 监听 `management.qrcode_login/<QRCODE_ID>` 的 PUBLISH。`type=cookies` 时解析临时 `cookies.qqmusic_uin.value` 和 `cookies.qqmusic_key.value`。
6. 用步骤 1/2 的同一 Android 会话调用 `music.login.LoginServer.Login`，参数 `musicid=临时账号 i64 数值`、`qrCodeID`、`token=临时 key`；覆盖 `comm.tmeLoginType=6`。取得正式会话后才替换当前登录态。

WebSocket 子协议为 `mqtt`。CONNECT 的认证方法为 `pass`，User Properties 是 `tmeAppID=qqmusic/business=management/hashTag=<QRCODE_ID>/clientTag=management.user/userID=<QRCODE_ID>`；SUBSCRIBE 的 User Properties 是 `authorization=tmelogin/pubsub=unicast`。客户端支持服务器重定向，初始 keep alive 为 45 秒，遵循服务器覆盖值并按其一半周期发送心跳。

推送 `type` 映射：`scanned → Scanned`、`canceled → Refused`、`timeout → Expired`、`loginFailed → 登录失败`。订阅等待上限 15 秒，后台授权等待上限 120 秒。`poll_login_qr(QqMusic,…)` 读取的是本地推送状态，不是轮询 `CheckQRCode`；终态读取一次后清除。

### Cookie 登录与资料

`login_with_cookie` 从 `uin → qqmusic_uin → wxuin` 取首个非空账号字段，去掉前导 `o/0`；从 `qm_keyst → qqmusic_key` 取密钥。缺失字段返回 `InvalidCookie`。当前按密钥是否以 `W_X` 开头判断微信或 QQ，不额外信任输入 Cookie 的登录类型字段。

用户资料接口为 GET `https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg`，查询参数 `format=json/cid=205360838/userid=<MUSIC_ID>/reqfrom=1`；读取原始响应 `data.creator.nick/headpic`。资料请求失败仍返回当前会话，昵称为空时使用账号编号。因此 Cookie 登录返回用户信息并不单独证明凭据可执行所有私有接口。

QQ / 微信会话交换前，当前实现会先清空旧会话；Cookie 登录会先存入传入的凭据。只有上述 QQ 音乐 App 授权流程在交换成功后才替换旧会话，不能笼统宣称所有登录失败均保留旧状态。

`current_user` 只读本地会话，`logout` 只清除本地会话；未调用上游注销或撤销授权接口。当前会话以 JSON 明文保存到本机 SQLite 的 `kv.session`，数据库与抓包都不应作为示例附件上传。

## 项目数据结构与调用入口

应用层入口定义在 [api/music.rs](../rust/src/api/music.rs)，通过 flutter_rust_bridge 生成 Dart 绑定。以下入口是应用内部函数，不是项目提供的 REST 路由。

| 功能 | 项目入口 | 返回类型 |
| --- | --- | --- |
| 搜索 / 热搜 / 联想 | `search(keyword,kind,page,page_size)` / `get_hot_search()` / `get_search_suggestions(query)` | `SearchResult` / `HotSearch` / `Vec<SearchSuggestion>` |
| 链接 / 音质 / 歌词 | `get_song_url(mid,media_mid,quality)` / `get_song_qualities(mid)` / `get_lyric(mid,id)` | `SongUrl` / `Vec<QualityOption>` / `Lyric` |
| 榜单 | `get_toplists()` / `get_toplist_detail(top_id,period)` | `Vec<TopListGroup>` / `TopListDetail` |
| 推荐 | `get_recommend_feed()` / `get_guess_you_like()` / `get_radar_songs(seed,page)` | `RecommendFeed` / 后两项为 `Vec<Song>` |
| 歌单读取 | `get_playlist_detail(id)` / `get_user_playlists()` / `get_my_playlists()` / `get_liked_song_ids()` | `PlaylistDetail` / `Vec<PlaylistBrief>` / `Vec<MyPlaylist>` / `Vec<i64>` |
| 歌单写入 | `set_song_liked(song_id,liked)` / `add_song_to_playlist(dir_id,song_id)` / `remove_song_from_playlist(dir_id,song_id)` / `rename_playlist(dir_id,name)` / `delete_playlist(dir_id)` | 成功为空，失败为 `ApiError` |
| 新建歌单 | `create_playlist(name)` | `MyPlaylist` |
| 最近播放 | `get_recent_plays()` / `report_play(song_id)` | `Vec<Song>` / 成功为空 |
| 歌手 | `get_singer_detail(mid)` / `get_singer_songs(mid,begin,num)` / `get_singer_albums(mid,begin,num)` | `SingerDetail` / `Vec<Song>` / `Vec<AlbumBrief>` |
| 歌手社交 / 视频 | `get_singer_social(mid)` / `get_singer_video_tags(mid)` / `get_singer_videos(mid,name,tag,order,begin,num)` | `SingerSocial` / `Vec<VideoTag>` / `SingerVideoPage` |
| 关注关系 | `set_singer_followed(mid,followed)` / `set_user_followed(euin,followed)` | 成功为空，失败为 `ApiError` |
| 专辑 | `get_album_detail(mid)` | `AlbumDetail` |
| MV | `get_mv_detail(vid)` | `MvDetail` |
| 相似歌曲 | `get_similar_songs(song_id)` | `Vec<Song>` |
| 其他用户 | `get_user_profile(euin)` / `get_user_public_playlists(euin,creator,page,page_size)` | `UserProfile` / `UserPlaylistPage` |
| 用户收藏 | `get_user_assets(euin,kind,page,page_size)` | `UserAssetPage`；kind 为 `Song/Playlist/Album/Video` |
| 评论 | `get_comment_feed(target,id,sort,cursor)` / `get_reply_feed(root_id,cursor)` | `CommentFeed` |
| 登录 | `create_login_qr(kind)` / `create_qq_app_login()` / `poll_login_qr(kind,qrsig)` / `login_with_cookie(cookie)` | `QrCode` / `QrCode` / `QrStatus` / `UserInfo` |
| 本地用户状态 | `current_user()` / `logout()` | `Option<UserInfo>` / 成功为空 |

核心模型见 [api/types.rs](../rust/src/api/types.rs)：

| 模型 | 关键字段 |
| --- | --- |
| `Song` | `id/mid/media_mid/name/singers/album_mid/album_name/duration_secs/cover_url/vip/has_hq/has_flac` |
| `SearchResult` | `songs/total` |
| `SongUrl` | `url/quality`，quality 为实际音质 |
| `QualityOption` | `quality/available/reason` |
| `PlaylistBrief` / `PlaylistDetail` | 列表摘要含 `id/title/cover_url/song_count/play_count/creator`；详情含描述和 `songs` |
| `MyPlaylist` | `dir_id/tid/name/cover_url/song_count` |
| `SingerDetail` | 原资料、首批歌曲与专辑，新增 `selected_albums` |
| `SingerSocial` | `fans_count/guard_title/followed` |
| `SingerVideoPage` | `videos/total`；视频复用 `VideoBrief` |
| `UserProfile` | `euin/name/avatar_url/fans_count/follow_count/playlist_count/followed/is_self/playlists_hidden` |
| `UserAssetPage` | `songs/playlists/albums/videos/has_more/hidden` |
| `RecommendFeed` | `sections/radar_seed/radar_cover`，区块含 `title/songs/playlists` |
| `CommentFeed` | `comments/total/has_more/cursor` |
| `Lyric` | `lines[{time_ms,text,trans}]/plain` |
| `QrCode` | `image/qrsig/url`；qrsig 在 QQ、微信、App 授权中分别是 qrsig、UUID、qrcodeID |
| `QrStatus` | `Waiting/Scanned/Expired/Refused/Success{user}` |
| `UserInfo` | `uin/nickname/avatar_url`，不向 Dart 用户资料模型暴露密钥 |

`Song.vip/has_hq/has_flac` 来自元数据，只作提示，不替代实时授权。`parse::songs` 兼容部分旧字段与 `songInfo/data` 包装，缺少 MID 的歌曲会被过滤，因此返回条数可能少于上游条目数。

本地音频缓存、偏好设置、初始化、`lower_quality` 等接口也在 `api/music.rs` 中，但不对应 QQ 音乐远程业务，本文不将它们计入上游接口。

## 缓存与错误处理

### 数据缓存

`Core::cached` 缓存原始 JSON，所有缓存键统一增加当前账号前缀，匿名账号使用 `0`。部分业务键还会再包含一次账号，下面只列逻辑用途。过期后重新请求，不把过期结果当作网络失败回退。

| 数据 | 当前 TTL |
| --- | --- |
| 搜索、热搜、联想、音质元数据、歌单详情、自建歌单列表 | 600 秒 |
| 推荐首页、榜单详情 | 1800 秒 |
| 榜单目录、新歌、歌手资料及其分页、专辑详情 | 3600 秒 |
| 歌词 | 7 天 |
| 最近播放 | 300 秒 |
| 用户主页资料 / 公开自建歌单分页 | 600 秒 |
| 猜你喜欢、雷达、评论、回复、播放授权 / URL、歌手社交及视频、用户收藏资产 | 无上述持久化数据缓存 |

`get_user_playlists` 的合并列表不通过 `Core::cached`；其自建列表请求与 `get_my_playlists` 的缓存封装不同。音质检查只缓存歌曲文件元数据，实时授权和 CDN 检查每次执行。

歌单写入成功后清除该歌单详情及 `my_playlists`，创建成功后清除 `my_playlists`；播放上报成功后清除 `recent_plays`；关注成功后失效目标用户资料缓存。`clear_cache` 清除接口 JSON 缓存，不等于退出登录或清除音频文件。

### 结果码与错误模型

| 封装 / 业务 | 当前检查 |
| --- | --- |
| 通用 / 内嵌页 | 必须业务请求 `code=0`；没有独立严格校验外层网关 `code`，签名请求失败可能回退一次 |
| PC 公共 / 私有 | 外层 `code` 存在且非零时失败；业务请求 `code` 必须为数字 `0`，外层缺失不单独拒绝 |
| Android 写入 / 网页签名加密 / App 授权独立客户端 | 外层与业务 `code` 都必须明确为数字 `0` |
| 内嵌页关注写入 | 外层、业务及业务 `data.code` 都必须明确为数字 `0` |
| 歌单写入 | 在传输检查后，再要求 `retCode=0` |
| 最近播放读取 / 写入 | 在传输检查后，再要求内层 `code=0` / `ret=0` |
| 旧 CGI | 通用 GET 封装只处理 HTTP 状态与 JSON / JSONP 解析，各调用点未统一严格核对业务码 |
| 本轮粉丝 / 用户资料 CGI | 调用点额外严格核对 `code/subcode=0` |

对外 `ApiError` 包括：`NotLoggedIn`、`NoPlayableUrl`、`UnsupportedFormat`、`UnverifiedFormat`、`LoginFailed{detail}`、`InvalidCookie{missing}`、`ServerError{api,code}`、`BadResponse{detail}`、`Network{detail}`、`Internal{detail}`。错误码以字符串保留给应用层，界面翻译由 Dart 处理。

### 登录失效与自动退出

登录凭证失效时，需要登录的接口返回内层 `code=1000`，不带说明（2026-11-10 用假 musickey 实测 `GetLoginUserInfo` 和 `GetPlayRecentlyInfo` 都返回 1000，公开接口忽略凭证照常返回）。服务器不区分过期、被其他设备挤下线或在登录设备管理里删除了本设备。官方 PC 客户端的 `music.login.LoginServer.Login` 响应带 `musickeyCreateTime`（Unix 秒）和 `keyExpiresIn`（抓包为 259200，即 3 天），Kanade 登录时据此记下到期时间；Cookie 登录没有这两个字段。

已登录请求转成 `ApiError` 时遇到 1000（[error.rs](../rust/src/qq/error.rs)），界面进程会在后台用 `GetPlayRecentlyInfo`（`requestCnt=1`）复核一次；仍是 1000 且期间没有换账号，就清掉登录态和接口缓存，通过 `watch_session_end` 推送原因：已过到期时间为 `Expired`，到期前被拒为 `Revoked`，不知道到期时间为 `Unknown`。启动时 `check_session` 也复核一次。Android 播放进程不订阅，登录态变化由界面进程同步。当前不使用 `refresh_key` 自动续期。

`2000`、`80105` 等数字不应被文档擅自定义为唯一原因。历史记录中同一 `80105` 与凭据所用客户端上下文有关，但不能推广为所有账号的通用结论。也不能因为 `retCode=0` 就忽略外层业务错误。

网络超时主要为 15 秒；微信长轮询、授权后台等待另有时限。写入超时可能表示结果不明确，当前专用写通道不会自动重发；应先读回状态或由用户在官方客户端核对。

## 验证方式与已知边界

本轮静态检查、Rust 单元测试与关注按钮控件测试通过。只读联网测试 `desktop_singer_social_and_user_assets`
将显式指定的本地 HAR 登录态放入测试进程的内存数据库，验证精选专辑、粉丝 / 守护、视频两批、
本人 / 他人主页和收藏歌单分页及非空收藏专辑。没有执行真实关注、创建、删除、改名或播放上报。

`desktop_user_liked_songs_and_videos` 单独验证“我喜欢”的歌曲与视频：歌曲两页及第 1200 首之后的分页、
非空视频两页及最后一页的 `hasmore`。视频用户从本次既有搜索结果中只读选取；其加密标识只保存在
本地 `QQMUSIC_TEST_ASSET_TARGETS` 指向的 JSON 文件中（格式 `{"video_user":"<ENCRYPT_UIN>"}`），不写入测试源码。

已有笔记记录过歌手 / 专辑读取、评论及回复后续页验证，也记录过指定歌曲红心的受控写入与恢复。原始笔记保留当时的请求、结果和限制；它们不能替代今天的在线验证。部分笔记中的旧函数名 `desktop_write`、未接入描述或早期红心通道已落后于源码，应以本文对应的当前函数为准。

仓库提供默认忽略的联网测试。需要重新验证时，先逐项选择只读测试；以下为 PowerShell 示例，必须从项目根目录开始执行，且凭据文件只保留本地：

```powershell
Set-Location rust
$env:QQMUSIC_TEST_HAR = 'D:\private\qqmusic.har'
cargo test --test live desktop_search_pagination -- --ignored --test-threads=1
cargo test --test live desktop_my_playlists_include_liked -- --ignored --test-threads=1
cargo test --test live desktop_recent_plays -- --ignored --test-threads=1
cargo test --test live desktop_singer_social_and_user_assets -- --ignored --exact --test-threads=1
```

HAR 凭据辅助函数依赖该文件内存在可解析的 `comm.uin/authst/tmeLoginType`；不是任意抓包都能用。联网测试共享进程级会话，按串行执行。只运行上面指定的测试不会包含红心恢复测试；不要在文档验证时笼统运行所有 ignored 测试。

`desktop_like_iris_and_restore` 会真实更改固定歌曲的收藏状态，需要另外明确授权，并显式设置 `QQMUSIC_TEST_SESSION_DB` 和 `QQMUSIC_TEST_ALLOW_LIKE_IRIS=1`。本次编写未执行该测试，也未执行任何其他账号写入。

本轮新建歌单及关注操作已实现，真实应用写入尚待用户触发验证；原生签名与当前应用通道的差异没有被抓包成功替代。其余未提供或未完整验证的能力包括：收藏整个歌单、歌单及专辑完整大列表分页、最近播放增量同步与删除、推荐区块持续翻页、上传视频列表、评论写入、QRC 逐字歌词、Android NAC 真机播放，以及全账号 / 全平台兼容性。

## 源码与抓包笔记

| 来源 | 用途 |
| --- | --- |
| [client.rs](../rust/src/qq/client.rs) | 网关、会话、公参、Cookie、缓存、结果码 |
| [music.rs](../rust/src/qq/music.rs) / [quality.rs](../rust/src/qq/quality.rs) | 搜索、授权、歌词、推荐、榜单、歌单读取、音质映射 |
| [library.rs](../rust/src/qq/library.rs) / [history.rs](../rust/src/qq/history.rs) | 歌单写入、红心、最近播放 |
| [detail.rs](../rust/src/qq/detail.rs) | 歌手、专辑、评论与回复 |
| [social.rs](../rust/src/qq/social.rs) / [user.rs](../rust/src/qq/user.rs) | 关注关系、用户主页及收藏资产 |
| [login.rs](../rust/src/qq/login.rs) / [mqtt.rs](../rust/src/qq/mqtt.rs) / [sign.rs](../rust/src/qq/sign.rs) | 登录、推送、签名编码 |
| [parse.rs](../rust/src/qq/parse.rs) / [lyric.rs](../rust/src/qq/lyric.rs) | 上游数据与歌词解析 |
| [api/music.rs](../rust/src/api/music.rs) / [api/types.rs](../rust/src/api/types.rs) / [api/error.rs](../rust/src/api/error.rs) | 应用层入口、模型、错误枚举 |
| [真实接口测试](../rust/tests/live.rs) | 手动联网验证入口及其前置条件 |
| [分类搜索与 MV 抓包](qqmusic-search-mv-capture.md) | 七类搜索参数、MV 元数据、取流与清晰度切换及未验证边界 |
| [歌手、关注与用户主页抓包](qqmusic-singer-user-create-capture.md) | 精选、视频、计数、关注、新建歌单与用户主页原始证据 |
| [播放器关联操作抓包](qqmusic-player-actions-capture.md) | 歌手、专辑、评论、红心、加歌、80105 排查 |
| [歌单管理抓包](qqmusic-playlist-management-capture.md) | 改名与删除的官方请求样本 |
| [最近播放抓包](qqmusic-recent-plays-capture.md) | 云端记录读取、播放上报 |
| [Android 最近播放分类抓包](qqmusic-recent-plays-android-capture.md) | 专辑、歌单、电台、有声、视频各 `type`，增量同步与计数接口 |
| [Android 排行榜抓包](qqmusic-toplist-android-capture.md) | 目录分组、往期、分页、排名变化 `rankType`、歌曲标签，及与 PC 模块的对照 |
| [Android 评论页抓包](qqmusic-comments-android-capture.md) | 推荐 / 最热 / 最新 / 语音 / 时刻 / 表白各 tab、翻页游标、回复分页，及与 PC 内嵌页的差异 |
| [Android 播放页歌曲信息页抓包](qqmusic-player-detail-android-capture.md) | 右滑信息页的合并请求、栏目顺序、标签、相关歌单换一批、精选视频 |
| [推荐页抓包](qqmusic-recommendations-capture.md) / [推荐封面抓包](qqmusic-recommendation-covers-capture.md) | 推荐结构、取歌与图片来源 |

原始 HAR / SAZ / PCAPNG 是本地诊断材料，不是运行依赖，也不是本文的必需附件。项目忽略规则保留它们在本机；发布本文不需要上传这些文件。
