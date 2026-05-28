import 'package:flutter/material.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final _messages = [
    _Msg('Hermes', 'Ahoy Captain! I am your fleet agent. Ask me about mining status, pool stats, or fleet operations.', true),
  ];
  final _controller = TextEditingController();

  void _send() {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _messages.add(_Msg('You', _controller.text, false));
      _messages.add(_Msg('Hermes', '⚡ Checking fleet systems...\n\nMining Status: Idle\nPool: supportxmr.com:3333\nWorker: web-preview\nDashboard: relay.mobilemonero.com\n\nSay "start mining" to begin!', true));
    });
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (_, i) {
              final m = _messages[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: m.isAgent ? MainAxisAlignment.start : MainAxisAlignment.end,
                  children: [
                    if (m.isAgent) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: Color(0x29FF6600), shape: BoxShape.circle),
                        child: const Text('🤖', style: TextStyle(fontSize: 16)),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: m.isAgent ? const Color(0xFF0C0C0C) : const Color(0x29FF6600),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(m.text, style: const TextStyle(fontSize: 13, height: 1.5)),
                      ),
                    ),
                    if (!m.isAgent) const SizedBox(width: 10),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
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
                    hintText: 'Message Hermes...',
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
                onPressed: _send,
                icon: const Icon(Icons.send_rounded, color: Color(0xFFFF6600)),
                style: IconButton.styleFrom(backgroundColor: const Color(0x29FF6600)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Msg {
  final String sender;
  final String text;
  final bool isAgent;
  _Msg(this.sender, this.text, this.isAgent);
}
