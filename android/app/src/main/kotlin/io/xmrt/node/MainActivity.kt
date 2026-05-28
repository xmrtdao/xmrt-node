package io.xmrt.node

import android.content.Intent
import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "io.xmrt.node/mining"

    override fun configureFlutterEngine(@NonNull engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "mining.start" -> {
                    val serviceIntent = Intent(this, MiningService::class.java).apply {
                        action = MiningService.ACTION_START
                    }
                    startForegroundService(serviceIntent)
                    result.success(mapOf("success" to true))
                }
                "mining.stop" -> {
                    val serviceIntent = Intent(this, MiningService::class.java).apply {
                        action = MiningService.ACTION_STOP
                    }
                    startService(serviceIntent)
                    result.success(mapOf("success" to true))
                }
                "mining.status" -> {
                    result.success(mapOf(
                        "running" to XMRigBridge.isRunning(),
                        "hashrate" to XMRigBridge.hashrate(),
                        "shares_good" to XMRigBridge.shares().first,
                        "shares_total" to XMRigBridge.shares().second
                    ))
                }
                "mining.hashrate" -> {
                    result.success(XMRigBridge.hashrate())
                }
                else -> result.notImplemented()
            }
        }
    }
}
