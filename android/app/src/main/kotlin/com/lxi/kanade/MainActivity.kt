package com.lxi.kanade

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private var bubble: RecognizeBubble? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        if ((application as KanadeApplication).separateAndroidPlayback) null
        else super.provideFlutterEngine(context)

    override fun onDestroy() {
        bubble?.hide()
        stopService(Intent(this, RecognizeService::class.java))
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val recognize = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kanade/recognize")
        val bubble = RecognizeBubble(applicationContext) { action ->
            if (action == "open") {
                // 有悬浮窗权限，系统允许从后台把自己切回前台
                startActivity(
                    Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                )
            } else {
                recognize.invokeMethod("action", action)
            }
        }
        this.bubble = bubble
        recognize.setMethodCallHandler { call, result ->
            when (call.method) {
                "canOverlay" -> result.success(Settings.canDrawOverlays(this))
                "openOverlaySettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")),
                    )
                    result.success(null)
                }
                "startService" -> result.success(
                    try {
                        startForegroundService(
                            Intent(this, RecognizeService::class.java)
                                .putExtra(RecognizeService.EXTRA_TITLE, call.argument<String>("title")),
                        )
                        true
                    } catch (_: Exception) {
                        // 系统不让起前台服务时只是切走后录不了音，界面里照常识曲
                        false
                    },
                )
                "stopService" -> {
                    stopService(Intent(this, RecognizeService::class.java))
                    result.success(null)
                }
                "show" -> {
                    bubble.show()
                    result.success(null)
                }
                "hide" -> {
                    bubble.hide()
                    result.success(null)
                }
                "update" -> {
                    bubble.update(call.arguments<Map<String, Any?>>()!!)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kanade/app_login").setMethodCallHandler { call, result ->
            when (call.method) {
                // 必须指定包名：QQ 音乐也注册了 wtloginmqq://，不指定可能被它接走
                "open" -> result.success(
                    try {
                        startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")))
                                .addCategory(Intent.CATEGORY_BROWSABLE)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                .setPackage(call.argument<String>("package")),
                        )
                        true
                    } catch (_: Exception) {
                        false
                    },
                )
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kanade/update").setMethodCallHandler { call, result ->
            when (call.method) {
                // 没开「安装未知应用」权限时，系统安装器会自己引导去打开
                "install" -> result.success(
                    try {
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.update",
                            File(call.argument<String>("path")!!),
                        )
                        startActivity(
                            Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        true
                    } catch (_: Exception) {
                        false
                    },
                )
                else -> result.notImplemented()
            }
        }
    }
}
