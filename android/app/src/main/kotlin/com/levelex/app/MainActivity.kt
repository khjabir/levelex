package com.levelex.app

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "levelex/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "memoryInfo" -> {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val info = ActivityManager.MemoryInfo()
                        am.getMemoryInfo(info)
                        result.success(
                            mapOf(
                                "totalMb" to (info.totalMem / (1024L * 1024L)).toInt(),
                                "lowRamDevice" to am.isLowRamDevice,
                                "memoryClassMb" to am.memoryClass,
                            ),
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
