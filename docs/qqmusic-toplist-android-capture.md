# QQ 音乐：Android 端排行榜

观察日期：2026-11-09（北京时间）。在 MuMu 15 中运行官方 Android QQ 音乐 20.09（`QQMusic 20090808`，已登录），
用 `scripts/capture-qqmusic-android.mjs --prepare` 经 Fiddler 抓包。入口是「首页 → 乐馆 → 排行」，页面标题为 Charts。
操作由 adb 驱动，本轮只读：没有播放、收藏或分享。

## 证据

| 本地材料 | 字节 | SHA-256 |
| --- | --- | --- |
| `qqmusic-toplist-android-20261109-a.saz` | 5321293 | `3233a29ee8482175293d9dc152b11a4f00abedd766917512218f1ba0be4aa500` |
| `qqmusic-toplist-android-20261109-b.saz` | 454229 | `d5f5012d5afd8e6ce6600f993615640869cf508a43d2cc7cfe0c6633300f09ca` |

两个文件都由现有 `.gitignore` 排除。请求公参含 `authst`、`wxrefresh_token`、Cookie 和设备标识，不应提交或公开；本文不复制这些值。
分两段抓包、分别导出，是因为同一 Fiddler 会话里第二次导出时前面的会话已不在列表中。

| 文件 / 会话 | 时间 | 操作 |
| --- | --- | --- |
| a `raw/521` | 12:48:26.551 | 冷启动后进入排行页：`music.ranking.Recommend.get_list` + `music.musicToplist.Toplist.GetAll` |
| a `raw/634` | 12:49:16.456 | 打开欧美榜（`topId=3`，当期 2026 第 45 周） |
| a `raw/653` | 12:49:38.759 | 欧美榜期数选择器切到第 44 周 |
| b `raw/019` | 12:50:11.637 | 打开飙升榜（`topId=62`，日榜） |
| b `raw/038`、`044`、`049` | 12:50:35–12:50:51 | 打开热歌榜（`topId=26`，300 首）并滑到第 300 名，三次分页 |

## 传输

与[Android 最近播放](qqmusic-recent-plays-android-capture.md)相同：`POST https://u6.y.qq.com/cgi-bin/musics.fcg`，
`M-Encoding: m1`，带 `sign` / `mask`；请求体是 5 字节前缀加 zlib 压缩的 JSON，请求键等于 `module.method`。
排行榜相关的请求和响应都是 JSON，没有 JCE。

## 接口

Android 用的模块是 `music.musicToplist.Toplist`，Kanade 现在用的是 PC 的 `musicToplist.ToplistInfoServer`。
`GetAll`、`GetDetail` 两个模块逐字段一致；`GetQuickListenInfo` 只有 Android 模块有；
`music.ranking.Recommend.get_list` 是另一个模块。见下文[重放](#通用通道重放2026-11-09)。

### 目录：`GetAll`

参数 `{}`。返回 `data.group[]`，本样本 5 组 46 个榜：

| `groupId` | `groupName` | `type` | 榜数 | UI |
| --- | --- | --- | --- | --- |
| 0 | 巅峰榜 | 0 | 18 | 纵向列表，左封面、右前三名 |
| 2 | 特色榜 | 1 | 13 | 三列卡片 |
| 1 | 地区榜 | 1 | 6 | 三列卡片 |
| 3 | 全球榜 | 1 | 7 | 三列卡片 |
| 4 | 网络榜 | 1 | 2 | 三列卡片 |

`group.type` 与布局的对应是从这一个样本推断的。`data` 里另有 `location.province`（本样本 `provinceID=19`、广东省）和 `refreshInterval=1`。

每个 `toplist[]` 项的主要字段：

| 字段 | 内容 |
| --- | --- |
| `topId`、`title`、`intro` | 榜单 ID、名称、简介（目录里 `intro` 多为空，详情里才有） |
| `updateType` | 0：周榜，`period` 形如 `2026_45`；1：日榜，`period` 形如 `2026-11-09` 或空；2：日内更新（巅峰潮流榜、新歌榜 `period=2026110912`、音乐指数榜「每分钟更新」） |
| `topType` | 1 出现在美国公告牌、英国 UK、韩国 Melon、日本公信、JOOX、TVB、KKBOX 这些外部榜，其余为 0 |
| `period`、`updateTime` | 当期标识和日期；周榜的 `updateTime` 是发布日（如 `2026-11-05`） |
| `history` | 周榜的往期目录：`year[]` 与 `subPeriod[][]` 按下标对应，周数降序，个别周缺失。日榜和日内榜为空数组 |
| `totalNum` | 榜单总歌曲数（热歌榜、巅峰潮流榜、音乐指数榜 300，多数 100，部分 20～55） |
| `song[]` | 目录里是前三名预览：`rank`、`rankType`、`rankValue`、`songId`、`title`、`singerName`、`cover` |
| `listenNum` | 收听数 |
| `updateTips` | 卡片副标题，如「每周更新」「21首歌新上榜」「12:00 更新」「QQ音乐 x 微博」 |
| `headPicUrl`、`frontPicUrl`、`mbFrontPicUrl`、`mbHeadPicUrl`、`topAlbumURL` | 封面；`magicColor{r,g,b}` 在详情里给出主题色 |
| `specialScheme`、`h5JumpUrl` | 非空时 App 不进普通详情页，见下 |
| `subTopIds` | 新歌榜（427）为 `[27]`，其余为空；用途未验证 |

带跳转的榜单（`specialScheme` 解码后）：

| `topId` | 榜单 | 跳转 |
| --- | --- | --- |
| 135 | 巅峰潮流榜 | RN 页 `PopToplist` |
| 506 | Global-K Chart | RN 页 `melontoplist_index` |
| 607 | 分享热度榜 | RN 页 `SongShareToplist` |
| 505 / 136 / 501 | 铃声榜 / 收藏人气榜 / 评论人气榜 | RN 页 `RingToplist` / `FavToplist` / `CmtToplist` |
| 201 | MV 榜 | RN 页 `MvToplist`，`h5JumpUrl` 为 `y.qq.com/m/client/video_rank_list/` |
| 75 | 有声榜 | `qqmusic://qq.com/ui/longAudioToplist` |
| 137 | Vemus 未音 AI 原创榜 | H5 |
| 23 / 134 / 502 / 301 / 138 | 畅销专辑 / 畅销实体专辑 / 腾讯音乐人新势力榜 / 腾讯音乐榜 / 中国原创榜 | 只有 `h5JumpUrl`（H5 页） |

中国原创榜（138）`totalNum=0`、没有预览歌曲。这些榜单本轮都没有点开。

### 顶部推荐：`music.ranking.Recommend.get_list`

和 `GetAll` 合在同一个请求里，参数 `{}`。返回 `data.group[0]`（`groupId=101`，「推荐」），`toplist[]` 结构同上，本样本 12 项：
腾讯音乐榜、巅峰潮流榜、Global-K Chart、Vemus 未音 AI 原创榜、欧美榜、日本榜、香港地区榜、台湾 KKBOX 榜、综艺新歌榜、香港 TVB 劲歌金榜、美国公告牌榜、英国 UK 榜。
对应 Charts 页顶部横向滑动的大卡片。

### 详情：`GetDetail`

| 场景 | `param` |
| --- | --- |
| 打开周榜（当期） | `{"topId":3,"offset":0,"num":100,"withTags":true,"provinceID":19,"period":"2026_45"}` |
| 期数选择器切往期 | `{"topId":3,"offset":0,"num":100,"withTags":true,"provinceID":-1,"period":"2026_44"}` |
| 打开日榜 | `{"topId":62,"offset":0,"num":100,"withTags":true,"provinceID":19}`（不带 `period`） |
| 分页 | 同上，`offset` 依次为 100、200 |

- `provinceID` 取自 `GetAll` 的 `location`，切往期时变为 `-1`；对结果的影响未验证（国乐榜 `provId=19`，可能和地区有关）。
- 每页 100 首。热歌榜滑到第 100 名附近时请求 `offset=100`，再往下请求 `offset=200`，每页都带完整的 `data` 元数据。
- App 只给周榜显示期数选择器（「最近更新 11月05日 ▼」，年份 + 第几周两列滚轮）；日榜只显示日期，没有选择器。

返回 `data` 下：

| 字段 | 内容 |
| --- | --- |
| `data` | 榜单元数据，字段同目录项；`song[]` 为本页的排名信息，`titleDetail` 为「欧美榜 第45周」「飙升榜 第313天」，`intro` 为完整说明（含 `<br>`） |
| `songInfoList[]` | 与 `song[]` 一一对应的完整歌曲对象（`mid`、`singer[]`、`album`、`file`、`pay` 等，与其他接口的歌曲结构相同） |
| `songTagInfoList[]` | `withTags=true` 时返回，每项 `{id, tag, link, tagid, from_type}`，`id` 是歌曲数字 ID；本样本每页 16～36 项 |
| `extInfoList` | 本样本为空数组 |
| `indexInfoList` | 本样本为 `null` |

#### 排名变化

`song[].rankType` / `rankValue`，已对照截图：

| `rankType` | 含义 | `rankValue` | UI |
| --- | --- | --- | --- |
| 1 | 上升 | 名次差 | 绿色 ▲ 和数字 |
| 2 | 下降 | 名次差 | 蓝色 ▼ 和数字 |
| 3 | 持平 | `0` | 横线 |
| 4 | 新上榜 | `0` | `NEW` |
| 5 | 重新上榜 | `0` | `RE` |
| 6 | 涨幅 | 百分比字符串，如 `347%` | ▲ 和百分比（飙升榜、流行指数榜） |

目录预览里的 `rankType` 同样适用；巅峰潮流榜等预览为 `0` 和空字符串。

#### 歌曲标签

`songTagInfoList[].from_type` 对应歌名后面的绿色小标签：

| `from_type` | 例子 | `link` |
| --- | --- | --- |
| 1 | Pop、Electropop、R&B、EDM | 相似歌曲 / 分类搜索 / 歌单 scheme |
| 5 | 英雄联盟 | 无 |
| 6 | 格莱美提名、QQ音乐巅峰榜获奖 | H5 |
| 9 | 昨日热播、本周热播、收藏1w+、评论1w+ | 相似歌曲 scheme |
| 13 | 银河计划 | 无 |
| 18 | 已关注歌手 | 无；依赖登录态 |
| 22 | 温柔舒缓旋律、来一曲能量补给 | 无 |
| 28 | 带引号的短评，如 "回忆中的青春旋律" | 部分为 RN scheme |

一首歌最多一个标签，没有标签的歌不出现在列表里。

### `GetQuickListenInfo`

每次打开详情或切期都会和 `GetDetail` 合并发出，参数 `{"topID": <topId>}`（注意大写 `ID`）。
返回 `{"enableQuick": false, "songIDList": [...]}`：

- `songIDList` 是**当期**整榜的歌曲数字 ID：热歌榜一次给出 300 个，与三页 `GetDetail` 拼起来的顺序完全一致。
- 切到第 44 周时它仍返回第 45 周的列表，没有 `period` 参数。
- 本样本 `enableQuick` 都是 `false`，UI 中没有看到对应的「快听」入口。

### 同屏的其他请求

打开详情时还有 `music.playlist.CommonBanner.BusinessGetBanner`（歌曲列表上方的横幅：VIP 提示、「巅峰榜2026第三季度榜单揭晓」、AI 深度解读）
和 `music.musicasset.CgiSongFavRead.GetSongFansNumber`（每首歌右侧的收藏数）。榜单说明 (i) 打开的是 H5 页
`https://y.qq.com/m/client/v5detail/toplist.html?id=<topId>`。这些本轮没有展开分析。

## 通用通道重放（2026-11-09）

用 Kanade 通用通道的公参（`ct=11`、`cv=13020508`），匿名、无签名，直接 POST `https://u.y.qq.com/cgi-bin/musicu.fcg`：

| 请求 | 结果 |
| --- | --- |
| `music.musicToplist.Toplist.GetAll` / `musicToplist.ToplistInfoServer.GetAll` | 都是 `code=0`，5 组 18/13/6/7/2，欧美榜 `history.year` 9 年 |
| `music.ranking.Recommend.get_list` | `code=0`，但 `group=null`；登录态或 Android 公参是否必需未验证 |
| 欧美榜 `period=2026_44`，两个模块 | 结果一致；PC 模块不带 `withTags` 时 `songTagInfoList=null`，带上后返回标签 |
| 飙升榜 `period=2026-11-08` | 返回 11-08 的榜单，所以日榜也能按日期取往期，只是 App 没有入口 |
| 热歌榜 `offset=100` | 返回第 101～200 名 |
| `GetQuickListenInfo` | Android 模块 `code=0`，与抓包相同；PC 模块返回 `code=500005`，没有这个方法 |

两个模块的逐字段对比（同一请求里各发一份，忽略 `songTagInfoList`）：`GetAll` 响应字节数相同，只有畅销专辑（每 5 分钟更新）的 `listenNum`
和 `mbFrontLogoUrl` 两处不同，属于两次读取间的数据变化；`GetDetail` 的周榜当期、周榜往期、日榜、热歌榜 `offset=200` 四种情况都没有差异。

标签不是固定的：同一期欧美榜，匿名重放和登录抓包各有 4 项标签不同。抓包里有 `from_type=18`（已关注歌手），匿名没有；
其余差异是同一首歌换了标签（`本周热播` ↔ `已关注歌手`）或别的歌拿到风格标签，像是每次请求都重新挑选。

## 与 Kanade 现状的差异

[music.rs](../rust/src/qq/music.rs) 的 `toplists()` / `toplist_detail()` 只读 `topId`、`title`、封面、`period`、前三名预览和 `songInfoList`，
且固定 `offset=0`、`num=100`。对照抓包，目前没有用到：

- 300 首的榜单（热歌榜、巅峰潮流榜、音乐指数榜）只拿到前 100 首；
- `history` 往期、`rankType` / `rankValue` 排名变化、`withTags` 标签、`updateTips`、`updateType`；
- `specialScheme` / `h5JumpUrl` 榜单在 Kanade 里按普通榜单打开，实际内容是否完整未验证。

## 未验证

- `provinceID` 的作用，`subTopIds`、`topType`、`extInfoList`、`indexInfoList` 的含义。
- 日内榜（新歌榜 `period=2026110912`）的往期格式。
- 带跳转的特殊榜单（RN / H5 页）内部用的接口。
