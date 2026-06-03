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
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader

/**
 * AgentService — Android Foreground Service
 *
 * Owns the XMRT Python agent subprocess. Mirrors MiningService.kt's
 * structure (foreground service + wake lock + persistent notification),
 * but spawns a Python process via Runtime.exec() instead of JNI.
 *
 * Architecture:
 *   Kotlin (this) -> Runtime.exec("python3 .../xmrt-agent") -> subprocess
 *                                                         -> log file
 *
 * Lifecycle:
 *   ACTION_START  -> spawn subprocess, acquire wake lock, go foreground
 *   ACTION_STOP   -> kill subprocess, release wake lock, stop foreground
 *   ACTION_STATUS -> report running PID (read from pid file)
 *
 * The agent itself listens on 127.0.0.1:8642. The Flutter side talks
 * to it via OkHttp through MainActivity's MethodChannel handler.
 */
class AgentService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var agentProcess: Process? = null
    private var isRunning = false

    companion object {
        const val CHANNEL_ID = "xmrt_agent"
        const val NOTIFICATION_ID = 19091
        const val ACTION_START = "io.xmrt.node.START_AGENT"
        const val ACTION_STOP = "io.xmrt.node.STOP_AGENT"
        const val ACTION_STATUS = "io.xmrt.node.AGENT_STATUS"

        // Paths — all on internal storage, scoped to the app's UID.
        // The Python agent is extracted from APK assets into <filesDir>/xmrt-agent/
        // on first launch by MainActivity. The python3 binary comes from Termux.
        private const val TERMUX_PYTHON = "/data/data/com.termux/files/usr/bin/python3"
        private const val AGENT_DIR_NAME = "xmrt-agent"
        private const val AGENT_ENTRYPOINT = "main.py"
        private const val PID_FILE_NAME = "agent.pid"
        private const val LOG_FILE_NAME = "agent.log"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startAgent()
            ACTION_STOP -> stopAgent()
            ACTION_STATUS -> { /* status read on-demand via file, no-op here */ }
        }
        return START_STICKY
    }

    /**
     * Spawn the Python agent subprocess. Steps:
     *  1. Verify <filesDir>/xmrt-agent/main.py exists (extracted on first run)
     *  2. Open log file for append
     *  3. Build the command: python3 -m xmrt_agent (uses __main__.py)
     *  4. ProcessBuilder with redirected stderr -> log
     *  5. Acquire wake lock, go foreground
     *  6. Write PID file
     *  7. Start a watcher thread that reaps the process and stops the service when it exits
     */
    private fun startAgent() {
        if (isRunning) return
        val agentDir = File(filesDir, AGENT_DIR_NAME)
        val entry = File(agentDir, AGENT_ENTRYPOINT)
        if (!entry.exists()) {
            android.util.Log.e("AgentService", "Agent not extracted at ${entry.absolutePath} — run install first")
            return
        }
        if (!File(TERMUX_PYTHON).exists()) {
            android.util.Log.e("AgentService", "Termux python3 not found at $TERMUX_PYTHON — install Termux + python")
            return
        }

        isRunning = true
        val logFile = File(agentDir, LOG_FILE_NAME)
        val pidFile = File(agentDir, PID_FILE_NAME)

        try {
            // Command: cd into agent dir, then run as module
            // Using `python3 -m xmrt_agent` so it finds the package properly
            val processBuilder = ProcessBuilder(
                TERMUX_PYTHON,
                "-m", "xmrt_agent"
            )
            processBuilder.directory(agentDir)
            processBuilder.redirectErrorStream(true)
            // Add agent dir to PYTHONPATH so xmrt_agent package is importable
            val env = processBuilder.environment()
            env["PYTHONPATH"] = agentDir.absolutePath
            env["PYTHONUNBUFFERED"] = "1"
            env["HOME"] = "/data/data/com.termux/files/home"

            agentProcess = processBuilder.start()

            // Write PID file
            pidFile.writeText(agentProcess!!.pid().toString())

            // Drain stdout -> log file (in a background thread)
            Thread({
                try {
                    BufferedReader(InputStreamReader(agentProcess!!.inputStream)).use { reader ->
                        FileOutputStream(logFile, true).use { out ->
                            val buf = CharArray(4096)
                            while (true) {
                                val n = reader.read(buf)
                                if (n <= 0) break
                                out.write(String(buf, 0, n).toByteArray())
                                out.flush()
                            }
                        }
                    }
                } catch (e: Exception) {
                    // process closed, expected
                }
            }, "AgentLogDrain").start()

            acquireWakeLock()
            startForeground(NOTIFICATION_ID, buildNotification())
            android.util.Log.i("AgentService", "XMRT agent started, pid=${agentProcess!!.pid()}")

            // Watcher: when the process exits, stop the service
            Thread({
                try {
                    val exitCode = agentProcess!!.waitFor()
                    android.util.Log.i("AgentService", "Agent exited with code $exitCode")
                } catch (e: InterruptedException) {
                    // expected on stop
                } finally {
                    isRunning = false
                    if (pidFile.exists()) pidFile.delete()
                    releaseWakeLock()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }, "AgentWatcher").start()

        } catch (e: Exception) {
            android.util.Log.e("AgentService", "Failed to start agent: ${e.message}", e)
            isRunning = false
        }
    }

    private fun stopAgent() {
        if (!isRunning) return
        try {
            agentProcess?.destroy()
            // Give it 3 seconds to die gracefully, then SIGKILL
            Thread({
                try {
                    Thread.sleep(3000)
                    if (agentProcess?.isAlive == true) {
                        agentProcess?.destroyForcibly()
                    }
                } catch (_: InterruptedException) {}
            }, "AgentForceStop").start()
        } catch (e: Exception) {
            android.util.Log.e("AgentService", "Error stopping agent: ${e.message}")
        }
        // The watcher thread will fire the cleanup
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val port = AgentBridge.DEFAULT_PORT
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("XMRT Agent")
            .setContentText("Listening on http://127.0.0.1:$port")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "XMRT Agent",
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            (getSystemService(NotificationManager::class.java)).createNotificationChannel(channel)
        }
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "xmrt:agent")
        wakeLock?.acquire(8 * 60 * 60 * 1000L) // 8 hours max
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopAgent()
        super.onDestroy()
    }
}
