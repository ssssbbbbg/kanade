> 本项目仅供个人学习和技术交流，与腾讯或 QQ 音乐没有任何关系。
> 所有音乐内容的版权归各自权利人所有；能播放哪些歌完全取决于你自己账号的权限。
> 本不会绕过会员、地区限制或歌曲权限。

<p align="center">
  <img src="docs/screenshots/desktop.png" width="90%">
</p>
<p align="center">
  <img src="docs/screenshots/desktop-player.png" width="90%">
</p>
<p align="center">
  <img src="docs/screenshots/discover.jpg" width="22%">
  <img src="docs/screenshots/playlist.jpg" width="22%">
  <img src="docs/screenshots/player.jpg" width="22%">
  <img src="docs/screenshots/lyrics.jpg" width="22%">
</p>

### 运行

需要先安装 [Flutter](https://flutter.dev) 和 [Rust](https://rustup.rs)

```bash
git clone https://github.com/LuckyLxi/kanade.git
cd kanade
flutter pub get
flutter run -d windows
```

## 许可证

本项目采用 [GNU General Public License v3.0](LICENSE)（GPL-3.0-only）。第三方代码保留各自的许可证和版权声明。

## 致谢

- [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge)
- [media_kit](https://github.com/media-kit/media-kit)
- [liquid_glass_widgets](https://pub.dev/packages/liquid_glass_widgets)
- [smtc_windows](https://pub.dev/packages/smtc_windows)
- [audio_service](https://pub.dev/packages/audio_service)
- QQ 音乐 App 授权登录流程参考了 [YAQMC/qm-api-rs](https://github.com/YAQMC/qm-api-rs)
