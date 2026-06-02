import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/xmrt_agent.dart';

/// Chat screen — talks to the local XMRT Python agent via MethodChannel + EventChannel.
///
/// Flow:
///  1. On first build, check if agent is installed + running
///  2. If not installed, show "Install" button
///  3. If installed but not running, show "Start" button
///  4. Once running, show the chat UI
///  5. User types a message -> we stream from `agent.chat(message)` and accumulate chunks
///
/// SSE parsing is minimal: we just split on `\n\n` and look for `data: ` lines.
class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final _agent = XmrtAgent();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Msg> _messages = [];
  final _statusMessages = <String>[];

  AgentStatus? _status;
  bool _busy = false;
  String? _sessionId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _messages.add(_Msg(
      'XMRT Agent',
      'Ready when you are. Ask me about mining, fleet, DAO, or Monero.',
      isAgent: true,
    ));
    _refreshStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    try {
      final s = await _agent.status();
      setState(() {
        _status = s;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'status check failed: $e');
    }
  }

  Future<void> _install() async {
    setState(() => _busy = true);
    try {
      final ok = await _agent.install();
      _addStatus(ok ? 'agent installed' : 'install failed');
      await _refreshStatus();
    } catch (e) {
      _addStatus('install error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await _agent.start();
      // Give the service a sec to bind the port, then check
      await Future.delayed(const Duration(seconds: 2));
      await _refreshStatus();
    } catch (e) {
      _addStatus('start error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await _agent.stop();
      await _refreshStatus();
    } catch (e) {
      _addStatus('stop error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _addStatus(String msg) {
    setState(() {
      _statusMessages.add(msg);
      if (_statusMessages.length > 50) _statusMessages.removeAt(0);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    if (_status?.state != 'running') {
      _addStatus('agent not running — start it first');
      return;
    }

    setState(() {
      _messages.add(_Msg('You', text, isAgent: false));
      _messages.add(_Msg('XMRT Agent', '', isAgent: true, streaming: true));
      _busy = true;
    });
    _controller.clear();
    _scrollToBottom();

    final userMsgCount = _messages.length;
    String accumulated = '';

    try {
      final stream = _agent.chat(text, sessionId: _sessionId);
      await for (final sseChunk in stream) {
        // sseChunk is one or more "data: {...}\n\n" lines
        for (final line in sseChunk.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data == '[DONE]') {
            _sessionId = _sessionId; // sessionId already set in URL header
            continue;
          }
          // Try to extract content from OpenAI-compat delta
          try {
            final cleaned = data.startsWith('{') ? data : '{}';
            final json = _safeJsonDecode(cleaned);
            if (json == null) continue;
            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;
            final first = choices.first as Map;
            final delta = first['delta'] as Map?;
            if (delta == null) continue;
            // Content (text) or reasoning_content (thinking)
            final content = delta['content'] as String?;
            if (content != null && content.isNotEmpty) {
              accumulated += content;
              _updateLastAgentMessage(accumulated);
            }
            final reasoning = delta['reasoning_content'] as String?;
            if (reasoning != null && reasoning.isNotEmpty) {
              // Could surface in a separate bubble, for now append with marker
              accumulated += reasoning;
              _updateLastAgentMessage(accumulated);
            }
            // Tool calls (mark with bullet)
            final toolCalls = delta['tool_calls'] as List?;
            if (toolCalls != null) {
              for (final tc in toolCalls) {
                final fn = (tc as Map)['function'] as Map?;
                if (fn == null) continue;
                final name = fn['name'] as String? ?? '';
                if (name.isNotEmpty && !accumulated.contains('[$name]')) {
                  accumulated += '\n\n[$name]\n';
                  _updateLastAgentMessage(accumulated);
                }
              }
            }
            // Custom tool_result event from our agent
            final toolResult = json['xmrt_tool_result'] as Map?;
            if (toolResult != null) {
              final name = toolResult['name'] as String? ?? '';
              final result = toolResult['result'];
              accumulated += '\n_$name → ${result.toString().substring(0, result.toString().length.clamp(0, 200))}_\n';
              _updateLastAgentMessage(accumulated);
            }
          } catch (_) {
            // skip malformed
          }
        }
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        _updateLastAgentMessage(accumulated.isEmpty ? '[error: $e]' : '$accumulated\n\n[error: $e]');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Suppress unused warning when userMsgCount isn't needed
    userMsgCount.toString();
  }

  Map? _safeJsonDecode(String s) {
    // Light decoder — we know the agent emits standard JSON. Avoid pulling
    // in dart:convert explicitly here; the channel marshals it as String.
    try {
      // ignore: avoid_dynamic_calls
      return _jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  void _updateLastAgentMessage(String text) {
    if (_messages.isEmpty) return;
    setState(() {
      _messages[_messages.length - 1] = _Msg(
        _messages.last.sender,
        text,
        isAgent: true,
        streaming: _busy,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _statusBar(),
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text('No messages yet.', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _MessageBubble(msg: _messages[i]),
                ),
        ),
        if (_statusMessages.isNotEmpty) _statusLog(),
        _inputBar(),
      ],
    );
  }

  Widget _statusBar() {
    final state = _status?.state ?? 'checking';
    final color = switch (state) {
      'running' => const Color(0xFF22c55e),
      'installed_not_running' => const Color(0xFFfbbf24),
      'not_installed' => const Color(0xFFf87171),
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Agent: $state',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          if (_status?.state == 'not_installed')
            TextButton(onPressed: _busy ? null : _install, child: const Text('Install'))
          else if (_status?.state == 'installed_not_running')
            TextButton(onPressed: _busy ? null : _start, child: const Text('Start'))
          else if (_status?.state == 'running')
            TextButton(onPressed: _busy ? null : _stop, child: const Text('Stop'))
          else
            TextButton(onPressed: _busy ? null : _refreshStatus, child: const Text('Refresh')),
        ],
      ),
    );
  }

  Widget _statusLog() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: ListView(
        scrollDirection: Axis.vertical,
        children: _statusMessages.reversed.take(3).map((m) => Text(
          '· $m',
          style: const TextStyle(fontSize: 11, color: Color(0xFF8b8ba0), fontFamily: 'monospace'),
        )).toList(),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: _status?.state == 'running'
                    ? 'Message XMRT Agent...'
                    : 'Agent not running',
                filled: true,
                fillColor: const Color(0xFF0C0C0C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x29FF6600)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(fontSize: 14),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _busy ? null : _send,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded, color: Color(0xFFFF6600)),
            style: IconButton.styleFrom(backgroundColor: const Color(0x29FF6600)),
          ),
        ],
      ),
    );
  }
}

class _Msg {
  final String sender;
  final String text;
  final bool isAgent;
  final bool streaming;
  _Msg(this.sender, this.text, {required this.isAgent, this.streaming = false});
}

class _MessageBubble extends StatelessWidget {
  final _Msg msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: msg.isAgent ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (msg.isAgent) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0x29FF6600), shape: BoxShape.circle),
              child: const Text('X', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.black)),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: msg.isAgent ? const Color(0xFF0C0C0C) : const Color(0x29FF6600),
                borderRadius: BorderRadius.circular(12),
                border: msg.streaming ? Border.all(color: const Color(0xFFFF6600), width: 1) : null,
              ),
              child: Text(
                msg.text.isEmpty
                    ? (msg.streaming ? '...' : '')
                    : msg.text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: msg.isAgent ? Colors.white : Colors.black,
                  fontStyle: msg.streaming ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
          if (!msg.isAgent) const SizedBox(width: 10),
        ],
      ),
    );
  }
}

// Tiny JSON decoder for SSE payload parsing
Map? _jsonDecode(String s) {
  try {
    return jsonDecode(s) as Map?;
  } catch (_) {
    return null;
  }
}
