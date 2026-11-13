import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 退到后台后仍要继续放歌、并在当前歌放完时自动切下一首：
    // 只有声明了 UIBackgroundModes = audio，且 AVAudioSession 的类别是 playback，
    // 系统才会在锁屏/切后台后继续给我们 CPU 时间。audio_service 的 Darwin 实现
    // 只会在开始播放时创建 sharedInstance，不会设置类别，所以这里先设好。
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [])
    } catch {
      NSLog("AVAudioSession setCategory failed: \(error)")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
