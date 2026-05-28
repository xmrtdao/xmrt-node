package io.xmrt.node

/**
 * XMRigBridge — JNI bridge to the compiled XMRig native library (.so)
 *
 * Loads xmrig.so at runtime and provides start/stop/status controls
 * called from Flutter via platform channels.
 */
object XMRigBridge {
    private var loaded = false
    private var miningPid = 0L

    // Native methods (implemented in xmrig.so via JNI)
    private external fun nativeInit(configPath: String): Long
    private external fun nativeStart(pid: Long): Boolean
    private external fun nativeStop(pid: Long): Boolean
    private external fun nativeHashrate(pid: Long): Double
    private external fun nativeShares(pid: Long): IntArray

    fun load(configPath: String): Boolean {
        return try {
            System.loadLibrary("xmrig")
            loaded = true
            miningPid = nativeInit(configPath)
            miningPid > 0
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.e("XMRigBridge", "Failed to load xmrig.so: ${e.message}")
            false
        }
    }

    fun start(): Boolean {
        if (!loaded || miningPid <= 0) return false
        return nativeStart(miningPid)
    }

    fun stop(): Boolean {
        if (!loaded || miningPid <= 0) return false
        return nativeStop(miningPid)
    }

    fun hashrate(): Double {
        if (!loaded || miningPid <= 0) return 0.0
        return nativeHashrate(miningPid)
    }

    fun shares(): Pair<Int, Int> {
        if (!loaded || miningPid <= 0) return Pair(0, 0)
        val s = nativeShares(miningPid)
        return Pair(s[0], s[1]) // good, total
    }

    fun isLoaded(): Boolean = loaded
    fun isRunning(): Boolean = miningPid > 0
}
