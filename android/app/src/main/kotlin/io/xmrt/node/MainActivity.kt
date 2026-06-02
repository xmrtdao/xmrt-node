package io.xmrt.node

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val MINING_CHANNEL = "io.xmrt.node/mining"
    private val AGENT_CHANNEL = "io.xmrt.node/agent"
    private val AGENT_STREAM_CHANNEL = "io.xmrt.node/agent.stream"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val httpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(3, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS) // long timeout for LLM streaming
            .build()
    }
    private val eventSourcesFactory by lazy { EventSources.createFactory(httpClient) }

    // Active stream cancellation handle for the EventChannel
    private var activeChatJob: Job? = null
    private var activeEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(@NonNull engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        // Existing mining channel (unchanged)
        MethodChannel(engine.dartExecutor.binaryMessenger, MINING_CHANNEL).setMethodCallHandler { call, result ->
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

        // New agent channel — install, start, stop, health, send (non-streaming)
        MethodChannel(engine.dartExecutor.binaryMessenger, AGENT_CHANNEL).setMethodCallHandler { call, result ->
            handleAgentCall(call, result)
        }

        // New agent streaming channel — SSE chat completions
        EventChannel(engine.dartExecutor.binaryMessenger, AGENT_STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    activeEventSink = events
                    val args = arguments as? Map<*, *>
                    val message = args?.get("message") as? String
                    if (message.isNullOrBlank()) {
                        events.error("INVALID_ARGS", "message is required", null)
                        return
                    }
                    startChatStream(message, args, events)
                }
                override fun onCancel(arguments: Any?) {
                    activeChatJob?.cancel()
                    activeChatJob = null
                    activeEventSink = null
                }
            })
    }

    private fun handleAgentCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "agent.install" -> {
                activityScope.launch {
                    val ok = withContext(Dispatchers.IO) { AgentBridge.extractFromAssets(applicationContext) }
                    result.success(mapOf("success" to ok))
                }
            }
            "agent.start" -> {
                val serviceIntent = Intent(this, AgentService::class.java).apply {
                    action = AgentService.ACTION_START
                }
                try {
                    startForegroundService(serviceIntent)
                    result.success(mapOf("success" to true))
                } catch (e: Exception) {
                    result.error("START_FAILED", e.message, null)
                }
            }
            "agent.stop" -> {
                val serviceIntent = Intent(this, AgentService::class.java).apply {
                    action = AgentService.ACTION_STOP
                }
                startService(serviceIntent)
                result.success(mapOf("success" to true))
            }
            "agent.status" -> {
                activityScope.launch {
                    val status = withContext(Dispatchers.IO) {
                        val installed = AgentBridge.isInstalled(applicationContext)
                        val running = installed && AgentBridge.isRunning(applicationContext)
                        mapOf(
                            "installed" to installed,
                            "running" to running,
                            "url" to AgentBridge.baseUrl()
                        )
                    }
                    result.success(status)
                }
            }
            "agent.health" -> {
                activityScope.launch {
                    try {
                        val health = withContext(Dispatchers.IO) { AgentBridge.ping(applicationContext) }
                        result.success(health)
                    } catch (e: Exception) {
                        result.error("UNREACHABLE", e.message, null)
                    }
                }
            }
            "agent.send" -> {
                // Non-streaming chat (useful for tests / quick replies)
                val message = call.argument<String>("message")
                if (message.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "message is required", null)
                    return
                }
                activityScope.launch {
                    try {
                        val reply = withContext(Dispatchers.IO) { sendChatNonStreaming(message, call.argument("sessionId")) }
                        result.success(reply)
                    } catch (e: Exception) {
                        result.error("SEND_FAILED", e.message, null)
                    }
                }
            }
            "agent.listModels" -> {
                activityScope.launch {
                    try {
                        val resp = withContext(Dispatchers.IO) {
                            httpGet("${AgentBridge.baseUrl()}/v1/models")
                        }
                        result.success(resp)
                    } catch (e: Exception) {
                        result.error("UNREACHABLE", e.message, null)
                    }
                }
            }
            "agent.readMemory" -> {
                activityScope.launch {
                    try {
                        val resp = withContext(Dispatchers.IO) { httpGet("${AgentBridge.baseUrl()}/v1/memory") }
                        result.success(resp)
                    } catch (e: Exception) { result.error("UNREACHABLE", e.message, null) }
                }
            }
            "agent.readSoul" -> {
                activityScope.launch {
                    try {
                        val resp = withContext(Dispatchers.IO) { httpGet("${AgentBridge.baseUrl()}/v1/soul") }
                        result.success(resp)
                    } catch (e: Exception) { result.error("UNREACHABLE", e.message, null) }
                }
            }
            "agent.listSessions" -> {
                activityScope.launch {
                    try {
                        val resp = withContext(Dispatchers.IO) { httpGet("${AgentBridge.baseUrl()}/v1/sessions") }
                        result.success(resp)
                    } catch (e: Exception) { result.error("UNREACHABLE", e.message, null) }
                }
            }
            "agent.getSession" -> {
                val sid = call.argument<String>("sessionId")
                if (sid.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "sessionId is required", null)
                    return
                }
                activityScope.launch {
                    try {
                        val resp = withContext(Dispatchers.IO) { httpGet("${AgentBridge.baseUrl()}/v1/sessions/$sid") }
                        result.success(resp)
                    } catch (e: Exception) { result.error("UNREACHABLE", e.message, null) }
                }
            }
            "agent.deleteSession" -> {
                val sid = call.argument<String>("sessionId")
                if (sid.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "sessionId is required", null)
                    return
                }
                activityScope.launch {
                    try {
                        val req = Request.Builder()
                            .url("${AgentBridge.baseUrl()}/v1/sessions/$sid")
                            .delete()
                            .build()
                        httpClient.newCall(req).execute().use { resp ->
                            result.success(mapOf("deleted" to resp.isSuccessful))
                        }
                    } catch (e: Exception) { result.error("UNREACHABLE", e.message, null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun startChatStream(
        message: String,
        args: Map<*, *>?,
        events: EventChannel.EventSink,
    ) {
        activeChatJob?.cancel()
        activeChatJob = activityScope.launch(Dispatchers.IO) {
            val sessionId = args?.get("sessionId") as? String
            val model = args?.get("model") as? String
            val payload = buildString {
                append("{\"model\":")
                append(if (model != null) "\"$model\"" else "\"deepseek-v4-flash:cloud\"")
                append(",\"messages\":[{\"role\":\"user\",\"content\":")
                append(jsonEscape(message))
                append("}],\"stream\":true}")
            }
            val req = Request.Builder()
                .url("${AgentBridge.baseUrl()}/v1/chat/completions")
                .header("Content-Type", "application/json")
                .header("Accept", "text/event-stream")
                .apply { if (sessionId != null) header("X-Session-Id", sessionId) }
                .post(payload.toRequestBody("application/json".toMediaType()))
                .build()

            val eventSource: EventSource = eventSourcesFactory.newEventSource(req, object : EventSourceListener() {
                override fun onEvent(eventSource: EventSource, id: String?, type: String?, data: String) {
                    if (data == "[DONE]") {
                        mainHandler.post { events.endOfStream() }
                        return
                    }
                    // Forward the raw SSE data line to Flutter. The Dart side
                    // parses it (we don't want to parse twice).
                    mainHandler.post { events.success(data) }
                }
                override fun onClosed(eventSource: EventSource) {
                    mainHandler.post { events.endOfStream() }
                }
                override fun onFailure(eventSource: EventSource, t: Throwable?, response: okhttp3.Response?) {
                    val msg = t?.message ?: "stream failed (status=${response?.code})"
                    mainHandler.post { events.error("STREAM_FAILED", msg, null) }
                }
            })
            // Block until the stream completes or is cancelled
            try {
                while (isActive) {
                    kotlinx.coroutines.delay(100)
                }
            } catch (e: Exception) {
                eventSource.cancel()
            }
        }
    }

    private fun sendChatNonStreaming(message: String, sessionId: String?): Map<String, Any> {
        val payload = buildString {
            append("{\"model\":\"deepseek-v4-flash:cloud\",\"messages\":[{\"role\":\"user\",\"content\":")
            append(jsonEscape(message))
            append("}],\"stream\":false}")
        }
        val req = Request.Builder()
            .url("${AgentBridge.baseUrl()}/v1/chat/completions")
            .header("Content-Type", "application/json")
            .apply { if (sessionId != null) header("X-Session-Id", sessionId) }
            .post(payload.toRequestBody("application/json".toMediaType()))
            .build()
        val resp = httpClient.newCall(req).execute()
        val body = resp.body?.string() ?: "{}"
        resp.close()
        @Suppress("UNCHECKED_CAST")
        return AgentBridge.SimpleJson.parseObject(body)
    }

    private fun httpGet(url: String): Map<String, Any> {
        val req = Request.Builder().url(url).build()
        val resp = httpClient.newCall(req).execute()
        val body = resp.body?.string() ?: "{}"
        resp.close()
        @Suppress("UNCHECKED_CAST")
        return AgentBridge.SimpleJson.parseObject(body)
    }

    private fun jsonEscape(s: String): String {
        val sb = StringBuilder("\"")
        for (c in s) {
            when (c) {
                '\\' -> sb.append("\\\\")
                '"' -> sb.append("\\\"")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                '\b' -> sb.append("\\b")
                else -> if (c.code < 0x20) sb.append(String.format("\\u%04x", c.code)) else sb.append(c)
            }
        }
        sb.append("\"")
        return sb.toString()
    }

    override fun onDestroy() {
        activityScope.cancel()
        super.onDestroy()
    }
}
