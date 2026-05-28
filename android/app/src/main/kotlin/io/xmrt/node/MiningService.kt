package io.xmrt.node

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * MiningService — Android Foreground Service
 *
 * Keeps XMRig running in the background with a persistent notification.
 * Android kills background processes without a foreground service.
 * This is the standard pattern for long-running background work.
 */
class MiningService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var isMining = false

    companion object {
        const val CHANNEL_ID = "xmrt_mining"
        const val NOTIFICATION_ID = 19090
        const val ACTION_START = "io.xmrt.node.START_MINING"
        const val ACTION_STOP = "io.xmrt.node.STOP_MINING"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startMining()
            ACTION_STOP -> stopMining()
        }
        return START_STICKY
    }

    private fun startMining() {
        if (isMining) return
        isMining = true

        val configPath = "${filesDir.absolutePath}/config.json"
        XMRigBridge.load(configPath)
        XMRigBridge.start()

        startForeground(NOTIFICATION_ID, buildNotification())
        android.util.Log.i("MiningService", "XMRig started")
    }

    private fun stopMining() {
        if (!isMining) return
        XMRigBridge.stop()
        isMining = false
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        android.util.Log.i("MiningService", "XMRig stopped")
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("XMRT Node")
            .setContentText("Mining to fleet pool — ${XMRigBridge.hashrate().toInt()} H/s")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "XMRT Mining",
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            (getSystemService(NotificationManager::class.java)).createNotificationChannel(channel)
        }
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "xmrt:mining")
        wakeLock?.acquire(8 * 60 * 60 * 1000L) // 8 hours max
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopMining()
        super.onDestroy()
    }
}
