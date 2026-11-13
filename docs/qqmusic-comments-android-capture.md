# QQ 音乐：Android 端评论页

观察日期：2026-11-11（北京时间）。在 MuMu 15 中运行官方 Android QQ 音乐 20.9.8.8（`cv=20090808`，已登录），
用 `scripts/capture-qqmusic-android.mjs --prepare` 经 Fiddler 抓包。入口是「我的 → 最近播放 → 歌曲 → 某首歌的 ⋮ → 评论」
（MuMu 里打开完整播放页会崩溃，所以没走播放页的评论按钮）。样本歌曲是 Tim King「River Flows in You」，`songid=121345659`，页面标题「评论 (2071)」。

操作由 adb 驱动，本轮只读：没有点赞、发评论、回复、表白或分享。

## 证据

| 本地材料 | 字节 | SHA-256 |
| --- | --- | --- |
| `qqmusic-comments-android-20261111.saz` | 3758118 | `a4014fda43f72051c12d98450dac1589f6b081774bb71018c7ed0ce4076676b3` |

文件由现有 `.gitignore` 排除。请求公参含 `authst`、`wxrefresh_token`、Cookie 和设备标识，不应提交或公开；本文不复制这些值，也不复制评论正文和昵称。

| 会话 | 时间 | 操作 |
| --- | --- | --- |
| `011` | 17:11:56 | 打开歌曲 ⋮ 菜单：`CommentCountSrv.GetCmCount`（菜单上「评论 999+」角标） |
| `017` | 17:12:10 | 进入评论页，默认「推荐」tab：一个合并请求，含 `GetRecCommentList` 第 0 页 |
| `109` | 17:12:34 | 展开推荐第一条的回复（116 条）：`GetReplyCommentList` 第 0 页 |
| `143`、`177`、`206` | 17:12:41–17:13:07 | 推荐列表下滑，第 1～3 页 |
| `266` | 17:13:24 | 仍在「推荐」tab、列表底部「正在加载」时发出 `GetHotCommentList` `PageNum=5`（见下文） |
| `280`、`308` | 17:13:26–17:13:33 | 「最新」tab 第 0、1 页 |
| `335` | 17:13:38 | 「语音」tab：`SongTsComment.GetSongTsCmList` `AudioType=1`，本歌为空 |
| `346` | 17:13:50 | 「时刻」tab：`SongTsComment.GetSongTsCmList` `SeekTs=-1`，1 条 |
| `351`、`352` | 17:14:02 | 「表白」tab：`LoveLetterSvr.GetSongLetters` / `GetSingerLetters`，本歌为空 |
| `375`、`385`、`393` | 17:14:39–17:14:53 | 「最热」tab 第 0～2 页 |
| `403`、`418` | 17:15:11–17:15:27 | 展开一条热评的回复（18 条），再点「展开更多评论」：第 0、1 页 |

## 传输

与[Android 排行榜](qqmusic-toplist-android-capture.md)相同：`POST /cgi-bin/musics.fcg`，`M-Encoding: m1`，带 `sign` / `mask`，
请求体是 5 字节前缀加压缩 JSON，响应是压缩 JSON。评论相关请求全部是 JSON，没有 JCE。
进评论页前的计数和首屏走 `u6.y.qq.com`，评论页里的翻页、切 tab、回复走 `szu6.y.qq.com`。
公参 `ct=11`、`cv=20090808`，不是 Kanade 目前用的内嵌页 `ct=20`。

同时段还有几条 JCE 的 `music.vkey.GetEVkey.CgiGetEVkey`、`MembershipCardSvr.GetActionSheet` 等，与评论无关。

## 接口

请求键以样本为准；方法都在 `music.globalComment` 下，除另有注明。

### 计数：`CommentCountSrv.GetCmCount`

```json
{"request": {"biz_id": "121345659", "biz_type": 1, "biz_sub_type": 2}}
```

返回 `response.count=2071`、`count_view="999+"`、`count_ver`，另有 `cmTabType=0`。注意这里是 snake_case，评论列表接口是 PascalCase。

### 首屏合并请求（会话 017）

一次 `musics.fcg` 里有 9 个请求键，参数都带 `"prefetch": "yes"`：

| 请求键 | module.method | 本样本结果 |
| --- | --- | --- |
| `req` | `CommentRead.GetRecCommentList` | 推荐评论第 0 页 |
| `recommend` | `CommentRead.GetRecItemList`（`PageNum=1`） | 1 个插入卡片，内容为空 |
| `songReq` | `music.trackInfo.UniformRuleCtrl.CgiGetTrackInfo` | 页头歌曲信息 |
| `notice` | `CommentRead.GetBanners` | 一条推广横幅（页头「关注…小红书」那条） |
| `marquee` | `CmBizRate.GetVerticalMarquee` | 「34人在听」 |
| `moduleListReq` | `CommentRecommendSrv.GetModuleList` | 1 个模块，`JsonContent` 是字符串 |
| `topicListReq` | `HashTag.GetRelatedHashTagList` | 空 |
| `topic` | `CommentTopic.GetTopicEasterEgg` | 空彩蛋 |
| `feed` | `music.magzine.CmMomentSvr.GetRecentMomentInfoForCm` | 空 |

页面打开后还另外调了 `CommentAISrv.GetPanelTip`、`CommentRead.GetCommentAchievement`、`CommentEmo.GetEmoPkgList`、
`CommentTopic.IsInAirbPeriod`、`CommentTopic.GetTopicOpts`，都是输入框、表情和装饰用的，本文不展开。

### 推荐：`CommentRead.GetRecCommentList`

第 0 页：

```json
{"BizType": 1, "BizId": "121345659", "LastCommentSeqNo": "", "PageSize": 15, "RecOffset": 0,
 "LastHotScore": "", "LastRecScore": "", "FromParentCmId": "", "FromCommentId": "", "Flag": 1,
 "PicEnable": 1, "LastTotal": 0, "LastTotalVer": "0", "LastRspVer": "", "CmListUIVer": 1, "AudioEnable": 1}
```

后续页多了 `PageNum`（1、2、3）和 `HashTagID: ""`，`Flag` 变成 0，并带上一页的：

- `RecOffset`：上一页返回的 `CommentList.NextOffset`（15、30、45）；
- `LastCommentSeqNo` / `LastHotScore` / `LastRecScore`：上一页最后一条的 `SeqNo` / `HotScore` / `RecScore`；
- `LastTotal=2071`；`LastTotalVer`、`LastRspVer`：响应里的 `TotalVer` / `RspVer`；
- `CommentIds`：**要取的** 15 条的 `CmId`，来自第 0 页响应的 `CommentList.CommentIds`（285 个，后续页没有这个数组）。
  第 N 页取其中第 `(N-1)*15` 起的 15 个，响应正好是这 15 条；第 0 页的 15 条不在这 285 个里。
  `LastRspVer` 每一页都是第 0 页的 `RspVer`（后续页响应的 `RspVer` 为空）。

返回 `CommentList.ListType=7`，`HasMore=1`，`Total=0`（推荐列表不给总数，总数在顶层 `TotalCmNum=2071`）。
`CommentList2`（`ListType=2`）和 `CommentList3`（`ListType=4`）都是空的。

推荐每翻一页，客户端会把 `GetRecItemList`（`PageNum` 跟着 +1）、`GetTopicEasterEgg`、`GetRecentMomentInfoForCm` 放在同一个请求里一起发。

**会话 266**：推荐第 3 页之后，列表底部「正在加载」时发出的是 `GetHotCommentList` `PageNum=5`，
`LastHotScore`、`LastCommentSeqNo`、`LastCommentId` 都有值。当时 tab 仍是「推荐」（截图确认），推测推荐列表到一定深度后改为按热度续拉；只看到这一次，没有核实。

### 最热：`CommentRead.GetHotCommentList`

```json
{"BizType": 1, "BizId": "121345659", "PageSize": 15, "PageNum": 0, "HotType": 6, "WithTop": 0,
 "LastHotScore": "", "LastCommentId": "", "LastCommentSeqNo": "", "HashTagID": "", "PicEnable": 1,
 "LastTotal": 2071, "LastTotalVer": "<TotalVer>", "LastRspVer": "", "CmListUIVer": 1, "AudioEnable": 1}
```

后续页 `PageNum` +1，带上一页最后一条的 `HotScore` / `CmId` / `SeqNo`，以及上一页的 `RspVer`。
返回 `CommentList.ListType=6`，`HasMore=1`，`Total=0`。

`HotType=6` 与 PC 内嵌页之前观察到的 `HotType=2` 不同。第 0 页同一请求里还有 `CommentList.GetRecentPubCm`（`newSend`，本账号没发过，`CmList=null`）。

### 最新：`CommentRead.GetNewCommentList`

```json
{"BizType": 1, "BizId": "121345659", "PageSize": 15, "PageNum": 0, "LastCommentId": "", "LastCommentSeqNo": "",
 "SelfSeeEnable": 1, "HashTagID": "", "PicEnable": 1, "LastTotal": 2071, "LastTotalVer": "<TotalVer>",
 "LastRspVer": "", "CmListUIVer": 1, "AudioEnable": 1}
```

后续页 `PageNum` +1，带上一页最后一条的 `CmId` / `SeqNo` 和 `RspVer`。返回 `CommentList.ListType=3`、`Total=2071`、`HasMore=1`。
Android **没有**用 `WithHot`，热评由「最热」tab 单独请求；`CommentList2` / `CommentList3` 为空（`ListType=1`）。

### 回复：`CommentRead.GetReplyCommentList`

```json
{"RootCmId": "<CmId>", "PageNum": 0, "PageSize": 6, "LastCommentSeqNo": "", "LastRankScore": "",
 "RankType": 1, "LastRspVer": "", "SelfSeeEnable": 1, "PicEnable": 1, "AudioEnable": 1}
```

第 1 页（「展开更多评论」）`PageSize=5`，`LastRankScore` 和 `LastCommentSeqNo` 取上一页最后一条的 `RankScore` / `SeqNo`。
返回 `ListType=5`。第 0 页 `Total` 是回复数（116、18），第 1 页 `Total=0`；两次 `HasMore` 都是 1。
回复的 `RepliedComments[0]` 有 `Nick`、`CmId`、`Content` 等字段，与现有解析一致。

### 语音、时刻：`SongTsComment.GetSongTsCmList`

| tab | 参数 | 本样本 |
| --- | --- | --- |
| 语音 | `{"BizType":1,"BizId":"…","Size":15,"LastPos":"","HashTagID":"","AudioType":1}` | `CmList=null`，页面「暂无语音评论」 |
| 时刻 | `{"BizType":1,"BizId":"…","Size":15,"LastPos":"","HashTagID":"","SeekTs":-1}` | 1 条 |

分页字段是 `HasMore` / `NextPos`，不是 `PageNum`。时刻评论的 `SongTsElems[]` 形如 `{"S":0,"E":4,"Ts":68}`：
正文第 S～E 个字符是时间戳文本，`Ts` 是对应的歌曲秒数。

### 表白：`music.loveletter.LoveLetterSvr`

请求键 `req_0`，各一个请求：

- `GetSongLetters`：`{"songID":121345659,"singerID":"<singer mid>","passThrough":""}`；
- `GetSingerLetters`：`{"songID":…,"singerID":…,"size":10,"last":"","sortType":3,"letterID":"","cReq":{…}}`。

本样本都没有表白信（`letters=null`）。刚进页面时 tab 栏只有前五个，几秒后才多出「表白」；是哪个响应控制它出现，没有确认。

## 评论条目字段

三种列表的条目结构相同。Kanade 现在读的 `CmId`、`SeqNo`、`Nick`、`Avatar`、`Content`、`PubTime`、`PraiseNum`、`ReplyCnt`、
`RepliedComments[0].Nick` 都在，可以直接复用解析。Android 额外有 `HotScore`、`RecScore`、`RankScore`（翻页游标）、
`Location`（IP 属地，部分条目有）、`VipUI` / `IconList` / `Medal`（昵称后的徽章）、`Audio`（语音评论）、`SongTsElems`、`Pic` 等。

### 带图评论

183 条样本评论里只有 1 条带图（会话 280，「最新」第 0 页第 12 条），同时也有文字：

- `Pic`：`https://music-file.y.qq.com/comment/u/<用户目录>/<短目录>/<哈希>_<短串>.jpg`；
- `PicSize`：`"700x1050"`，宽 x 高的字符串。

App 实际下载（会话 306）时，域名换成 `music-file6.y.qq.com`，路径不变，末尾加 `?hippycomment=1`；
请求不带 Cookie，返回 `image/webp`（88822 字节）、`Cache-Control: max-age=2592000`。
原始 `music-file` 地址不加参数能否直接下载没有试；回复里的图片和表情图（`EmoPic`，本样本全空）都没有样本。

## 与 Kanade 改动前的差异

下表是抓包时的状态；Kanade 之后已改用右栏的参数（仍走内嵌页通道，见下文重放）。

| 项目 | Kanade（PC 内嵌页） | Android |
| --- | --- | --- |
| 公参 | `ct=20` | `ct=11`，原生签名 |
| 默认列表 | `GetNewCommentList` `WithHot=1`，第一页同时带热评 | 推荐 `GetRecCommentList`；最热、最新各自是一个 tab |
| 每页 | 25 | 15（回复 6，之后 5） |
| 热评 | `CommentList2` | `GetHotCommentList` `HotType=6`，可翻页 |
| 翻页游标 | `PageNum` + `LastCommentSeqNo` | 另带 `LastCommentId`、`LastHotScore` / `LastRecScore` / `RecOffset`、`LastRspVer`、`LastTotalVer` |

## 通用通道重放（2026-11-11）

用 Kanade 现有的内嵌页通道（`ct=20`，`musics.fcg` 带签名，明文 JSON）发上面的参数，样本歌曲不变。

| 列表 | 结果 |
| --- | --- |
| 最热 | 未登录可用，翻 4 页每页 15 条不重复，`ListType=6` |
| 最新 | 未登录可用，翻 3 页不重复，`Total=2071` |
| 回复 | 未登录可用，6 + 5 + 5 + … 不重复；`HasMore` 一直是 1，按第 0 页的 `Total` 能正好取完（18 条） |
| 推荐 | 第 0 页未登录也有 15 条，但 `CommentIds` 为空，无法翻页；登录后有 285 个 id，按上文方式翻满 20 页共 300 条不重复，最后一页 `HasMore=0` |
| 带图评论 | `Pic` 原地址不带 Cookie、不加参数返回 200 `image/jpeg`（311352 字节）；换成 `music-file6` 加 `?hippycomment=1` 结果相同 |

公参换成 `ct=11`（`cv` 13020508 或 20090808）结果一样，所以没有换通道。推荐翻页时如果把上一页的 `CmId` 放进 `CommentIds`，服务器会原样返回上一页。
专辑（`BizType=2`，样本专辑共 39 条）的最热、最新同样可用。

## 边界

- 只抓了一首歌（`BizType=1`）；专辑评论只做了重放，歌单评论没有试。
- 推荐列表在第 3 页后转为 `GetHotCommentList` `PageNum=5` 只是推测（会话 266）。重放时推荐列表自己能翻到 300 条，Kanade 没有照做这次切换。
- 所有写操作（点赞、发表、回复、删除、表白）都没有触发。
