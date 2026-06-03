package io.xmrt.node

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * AgentBridge — helpers for talking to the XMRT Python agent on the device.
 *
 * Three responsibilities:
 *  1. **Lifecycle status** — is the agent installed, is it running, is the HTTP
 *     server reachable on 127.0.0.1:8642?
 *  2. **Asset extraction** — copy the Python agent source from APK assets to
 *     <filesDir>/xmrt-agent/ on first launch, so it's editable + persistent.
 *  3. **HTTP helper** — short helper for hitting the agent's OpenAI-compat
 *     endpoints. Streaming uses OkHttp at the MainActivity layer; this is
 *     for non-streaming JSON calls (health, model list, memory read).
 *
 * The agent listens on 127.0.0.1:8642. From Kotlin we use HttpURLConnection
 * (no extra dependency). Streaming is done by MainActivity with OkHttp because
 * the Android system already pulls it in.
 */
object AgentBridge {
    const val TAG = "AgentBridge"
    const val DEFAULT_PORT = 8642
    const val AGENT_DIR_NAME = "xmrt-agent"
    const val PID_FILE_NAME = "agent.pid"
    const val LOG_FILE_NAME = "agent.log"

    // Path of the bundled agent source inside APK assets. We point the
    // AssetManager at <assetsDir>/agent-source/ for the python package + skills.
    // The Python package xmrt_agent is in <assetsDir>/agent-source/xmrt_agent/
    // and the skills live in <assetsDir>/agent-source/skills/.
    private const val ASSET_AGENT_DIR = "agent-source"

    fun agentDir(ctx: Context): File = File(ctx.filesDir, AGENT_DIR_NAME)
    fun pidFile(ctx: Context): File = File(agentDir(ctx), PID_FILE_NAME)
    fun logFile(ctx: Context): File = File(agentDir(ctx), LOG_FILE_NAME)

    fun baseUrl(): String = "http://127.0.0.1:$DEFAULT_PORT"

    /**
     * Check if the Python agent source has been extracted to internal storage.
     * First-run detection: if <filesDir>/xmrt-agent/xmrt_agent/__main__.py
     * is missing, the agent hasn't been installed yet.
     */
    fun isInstalled(ctx: Context): Boolean {
        val entry = File(agentDir(ctx), "xmrt_agent/__main__.py")
        return entry.exists()
    }

    /**
     * Is the agent process running? Reads the PID file and checks if the PID
     * is alive. We can't use Process.kill(pid, 0) from the app's UID because
     * the agent runs as the termux UID. Instead, we just check the PID file
     * exists AND the port is reachable. Simpler and more reliable.
     */
    fun isRunning(ctx: Context): Boolean {
        val pid = pidFile(ctx).takeIf { it.exists() }?.readText()?.trim()?.toLongOrNull()
            ?: return false
        // Check the port — if we can hit /health, it's alive
        return try {
            ping(ctx)["status"] == "ok"
        } catch (e: Exception) {
            Log.w(TAG, "Agent PID $pid but port unreachable: ${e.message}")
            false
        }
    }

    /**
     * Hit GET /health on the agent. Returns the parsed JSON map.
     * Throws on connection failure.
     */
    fun ping(ctx: Context): Map<String, Any> {
        val conn = (URL("${baseUrl()}/health").openConnection() as HttpURLConnection).apply {
            connectTimeout = 2000
            readTimeout = 3000
            requestMethod = "GET"
        }
        try {
            val code = conn.responseCode
            if (code != 200) {
                throw RuntimeException("health returned $code")
            }
            val body = conn.inputStream.bufferedReader().readText()
            @Suppress("UNCHECKED_CAST")
            return SimpleJson.parseObject(body)
        } finally {
            conn.disconnect()
        }
    }

    /**
     * Extract the Python agent source from APK assets to <filesDir>/xmrt-agent/.
     * Copies every file under <assets>/agent-source/ recursively, preserving
     * relative paths. Skips files that already exist (no clobber on update).
     *
     * This is called from MainActivity on first launch (and on update).
     */
    fun extractFromAssets(ctx: Context): Boolean {
        val dest = agentDir(ctx)
        dest.mkdirs()
        return try {
            copyAssetDir(ctx, ASSET_AGENT_DIR, dest)
            Log.i(TAG, "Extracted agent to ${dest.absolutePath}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Asset extraction failed: ${e.message}", e)
            false
        }
    }

    private fun copyAssetDir(ctx: Context, path: String, dest: File) {
        val assets = ctx.assets
        val items = assets.list(path) ?: emptyArray()
        for (name in items) {
            val assetPath = "$path/$name"
            val destFile = File(dest, name)
            val isDir = try {
                assets.list(assetPath)?.isNotEmpty() == true
            } catch (e: Exception) { false }

            if (isDir) {
                destFile.mkdirs()
                copyAssetDir(ctx, assetPath, destFile)
            } else {
                if (!destFile.exists() || destFile.length() == 0L) {
                    assets.open(assetPath).use { input ->
                        FileOutputStream(destFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                }
            }
        }
    }

    /**
     * Tiny JSON parser for the simple response shapes we need.
     * We only parse flat top-level objects with string/number/boolean values.
     * For streaming, we don't parse — OkHttp streams raw bytes.
     */
    object SimpleJson {
        fun parseObject(s: String): Map<String, Any> {
            val map = mutableMapOf<String, Any>()
            // Naive parser — strips braces, splits on commas at depth 0, then
            // splits each on the first colon. Sufficient for the /health response
            // shape, not a general JSON parser. We avoid pulling in Gson.
            val trimmed = s.trim().removePrefix("{").removeSuffix("}")
            if (trimmed.isEmpty()) return map
            val pairs = splitTopLevel(trimmed, ',')
            for (pair in pairs) {
                val colonIdx = findUnquotedColon(pair)
                if (colonIdx < 0) continue
                val key = pair.substring(0, colonIdx).trim().removeSurrounding("\"")
                val rawVal = pair.substring(colonIdx + 1).trim()
                val value: Any = when {
                    rawVal == "null" -> "null"
                    rawVal == "true" -> true
                    rawVal == "false" -> false
                    rawVal.startsWith("\"") && rawVal.endsWith("\"") ->
                        rawVal.substring(1, rawVal.length - 1)
                    rawVal.startsWith("[") -> rawVal // keep raw
                    rawVal.startsWith("{") -> rawVal // keep raw
                    else -> rawVal.toDoubleOrNull() ?: rawVal
                }
                map[key] = value
            }
            return map
        }

        private fun splitTopLevel(s: String, sep: Char): List<String> {
            val out = mutableListOf<String>()
            var depth = 0
            var inStr = false
            var escape = false
            val buf = StringBuilder()
            for (c in s) {
                if (escape) { buf.append(c); escape = false; continue }
                if (c == '\\') { buf.append(c); escape = true; continue }
                if (c == '"') inStr = !inStr
                if (!inStr) {
                    if (c == '{' || c == '[') depth++
                    else if (c == '}' || c == ']') depth--
                    else if (c == sep && depth == 0) {
                        out.add(buf.toString())
                        buf.clear()
                        continue
                    }
                }
                buf.append(c)
            }
            if (buf.isNotEmpty()) out.add(buf.toString())
            return out
        }

        private fun findUnquotedColon(s: String): Int {
            var inStr = false
            var escape = false
            for ((i, c) in s.withIndex()) {
                if (escape) { escape = false; continue }
                if (c == '\\') { escape = true; continue }
                if (c == '"') inStr = !inStr
                if (c == ':' && !inStr) return i
            }
            return -1
        }
    }
}
