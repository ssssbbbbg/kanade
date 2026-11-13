package com.lxi.kanade

import android.app.ActivityManager
import android.app.Application
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import com.ryanheise.audioservice.AudioServicePlugin

class KanadeApplication : Application() {
    @Suppress("DEPRECATION")
    val separateAndroidPlayback: Boolean by lazy {
        packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            .metaData?.getBoolean("kanade.separateAndroidPlayback") == true
    }

    override fun onCreate() {
        super.onCreate()
        if (!separateAndroidPlayback) return
        val process = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            getProcessName()
        } else {
            getSystemService(ActivityManager::class.java).runningAppProcesses
                ?.firstOrNull { it.pid == Process.myPid() }?.processName
        }
        // 界面进程不随播放保活：后台播放时系统可以单独回收它，播放进程不受影响。
        AudioServicePlugin.configurePlaybackProcess(
            process != "$packageName:playback",
            "androidPlaybackMain",
            MainActivity::class.java.name,
            null,
        )
    }
}
