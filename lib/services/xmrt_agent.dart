// XMRT Agent — Dart client for the local Python agent on 127.0.0.1:8642.
//
// Mirrors the OpenAI Python SDK shape so the UI can stay clean.
// Talks to the agent via the MethodChannel + EventChannel set up in
// MainActivity.kt. All HTTP work happens in Kotlin; Dart just sends
// the request and gets back events.
//
// Public API:
//   final agent = XmrtAgent();
//   await agent.health();                 // -> Map
//   await agent.status();                 // -> {installed, running, url}
//   agent.chat('hello').listen((chunk) { // -> Stream<String> (raw SSE data lines)
//     print(chunk);
//   });
//   await agent.listModels();             // -> List<String>
//   await agent.readMemory();             // -> String
//   await agent.readSoul();               // -> String
//   await agent.listSessions();           // -> List<Session>
//
// The EventChannel is used for streaming. MethodChannel is used for
// everything else (single request/response).

import 'dart:async';
import 'package:flutter/services.dart';

class XmrtAgent {
  static const _methodChannel = MethodChannel('io.xmrt.node/agent');
  static const _eventChannel = EventChannel('io.xmrt.node/agent.stream');

  /// Hit the agent's /health endpoint. Throws on failure.
  Future<Map> health() async {
    final res = await _methodChannel.invokeMethod<Map>('agent.health');
    return res ?? {};
  }

  /// Returns install + running state of the local agent.
  Future<AgentStatus> status() async {
    final res = await _methodChannel.invokeMethod<Map>('agent.status');
    return AgentStatus.fromMap(res ?? {});
  }

  /// Install the agent from APK assets to internal storage.
  /// Idempotent — safe to call on every launch.
  Future<bool> install() async {
    final res = await _methodChannel.invokeMethod<Map>('agent.install');
    return res?['success'] == true;
  }

  /// Start the agent foreground service. Throws on failure.
  Future<bool> start() async {
    final res = await _methodChannel.invokeMethod<Map>('agent.start');
    return res?['success'] == true;
  }

  /// Stop the agent foreground service.
  Future<bool> stop() async {
    final res = await _methodChannel.invokeMethod<Map>('agent.stop');
    return res?['success'] == true;
  }

  /// Stream a chat completion. Yields raw SSE `data: {...}` strings.
  /// Caller is responsible for parsing the SSE chunks.
  Stream<String> chat(
    String message, {
    String? model,
    String? sessionId,
  }) {
    return _eventChannel.receiveBroadcastStream({
      'message': message,
      if (model != null) 'model': model,
      if (sessionId != null) 'sessionId': sessionId,
    }).map((event) {
      if (event is String) return event;
      if (event is Map && event['error'] != null) {
        throw Exception(event['error']);
      }
      return event.toString();
    }).where((s) => s.isNotEmpty);
  }

  /// Non-streaming chat. Returns the assistant content string.
  Future<String> send(String message, {String? sessionId}) async {
    final res = await _methodChannel.invokeMethod<Map>('agent.send', {
      'message': message,
      if (sessionId != null) 'sessionId': sessionId,
    });
    // Response shape: {id, choices: [{message: {content: "..."}}]}
    final choices = res?['choices'] as List?;
    if (choices == null || choices.isEmpty) return '';
    final first = choices.first as Map;
    final message = first['message'] as Map?;
    return message?['content'] as String? ?? '';
  }

  Future<List<String>> listModels() async {
    final res = await _methodChannel.invokeMethod<Map>('agent.listModels');
    final data = res?['data'] as List?;
    if (data == null) return [];
    return data
        .map((m) => (m as Map)['id'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<String> readMemory() async {
    final res = await _methodChannel.invokeMethod<Map>('agent.readMemory');
    return res?['content'] as String? ?? '';
  }

  Future<String> readSoul() async {
    final res = await _methodChannel.invokeMethod<Map>('agent.readSoul');
    return res?['content'] as String? ?? '';
  }

  Future<List<AgentSession>> listSessions() async {
    final res = await _methodChannel.invokeMethod<Map>('agent.listSessions');
    final sessions = res?['sessions'] as List?;
    if (sessions == null) return [];
    return sessions
        .map((s) => AgentSession.fromMap(s as Map))
        .toList();
  }

  /// Load all messages for a single session.
  Future<AgentSessionDetail> getSession(String sessionId) async {
    final res = await _methodChannel.invokeMethod<Map>('agent.getSession', {
      'sessionId': sessionId,
    });
    return AgentSessionDetail.fromMap(res ?? {});
  }

  /// Delete a session and all its messages.
  Future<bool> deleteSession(String sessionId) async {
    final res = await _methodChannel.invokeMethod<Map>('agent.deleteSession', {
      'sessionId': sessionId,
    });
    return res?['deleted'] == true;
  }
}

class AgentStatus {
  final bool installed;
  final bool running;
  final String url;
  AgentStatus({required this.installed, required this.running, required this.url});

  factory AgentStatus.fromMap(Map m) => AgentStatus(
        installed: m['installed'] == true,
        running: m['running'] == true,
        url: m['url'] as String? ?? 'http://127.0.0.1:8642',
      );

  String get state {
    if (!installed) return 'not_installed';
    if (running) return 'running';
    return 'installed_not_running';
  }
}

class AgentSession {
  final String id;
  final String title;
  final String model;
  final int messageCount;
  final int startedAt;
  final String preview;

  AgentSession({
    required this.id,
    required this.title,
    required this.model,
    required this.messageCount,
    required this.startedAt,
    required this.preview,
  });

  factory AgentSession.fromMap(Map m) => AgentSession(
        id: m['id'] as String? ?? '',
        title: m['title'] as String? ?? '',
        model: m['model'] as String? ?? '',
        messageCount: (m['message_count'] as int?) ?? 0,
        startedAt: (m['started_at'] as int?) ?? 0,
        preview: m['preview'] as String? ?? '',
      );
}

/// A single session with all its messages loaded. Returned by
/// [XmrtAgent.getSession].
class AgentSessionDetail {
  final AgentSession session;
  final List<AgentMessage> messages;

  AgentSessionDetail({required this.session, required this.messages});

  factory AgentSessionDetail.fromMap(Map m) {
    final rawMessages = m['messages'] as List? ?? [];
    return AgentSessionDetail(
      session: AgentSession.fromMap(m),
      messages: rawMessages
          .map((x) => AgentMessage.fromMap(x as Map))
          .toList(),
    );
  }
}

class AgentMessage {
  final int id;
  final String role;
  final String content;
  final int timestamp;
  final String? thinking;

  AgentMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.thinking,
  });

  factory AgentMessage.fromMap(Map m) => AgentMessage(
        id: (m['id'] as int?) ?? 0,
        role: m['role'] as String? ?? '',
        content: m['content'] as String? ?? '',
        timestamp: (m['timestamp'] as int?) ?? 0,
        thinking: m['thinking'] as String?,
      );

  bool get isUser => role == 'user';
  bool get isAgent => role == 'assistant';
}
