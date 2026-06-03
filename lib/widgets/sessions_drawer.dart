import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/xmrt_agent.dart';

/// Drawer that lists past agent sessions and lets the user load one.
///
/// Usage:
///   drawer: SessionsDrawer(agent: _agent, onSessionSelected: (id) => ...)
class SessionsDrawer extends StatefulWidget {
  final XmrtAgent agent;
  final void Function(String sessionId) onSessionSelected;
  final VoidCallback? onNewSession;

  const SessionsDrawer({
    super.key,
    required this.agent,
    required this.onSessionSelected,
    this.onNewSession,
  });

  @override
  State<SessionsDrawer> createState() => _SessionsDrawerState();
}

class _SessionsDrawerState extends State<SessionsDrawer> {
  List<AgentSession> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await widget.agent.listSessions();
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load sessions: $e';
        _loading = false;
      });
    }
  }

  String _formatTimestamp(int millis) {
    if (millis == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteSession(AgentSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12121a),
        title: const Text('Delete session?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently delete "${session.title.isEmpty ? session.id : session.title}" and all its messages.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFf87171))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.agent.deleteSession(session.id);
      setState(() {
        _sessions = _sessions.where((s) => s.id != session.id).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0C0C0C),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Color(0xFFFF6600)),
                  const SizedBox(width: 10),
                  Text(
                    AppLocalizations.of(context)!.agentSessions,
                    style: const TextStyle(
                      color: Color(0xFFFF6600),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (widget.onNewSession != null)
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.white70),
                      tooltip: 'New session',
                      onPressed: widget.onNewSession,
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    tooltip: 'Refresh',
                    onPressed: _load,
                  ),
                ],
              ),
            ),
            // List
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6600)),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFf87171), size: 32),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            AppLocalizations.of(context)!.agentSessionsEmpty,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _sessions.length,
      separatorBuilder: (_, __) => const Divider(color: Color(0x1AFFFFFF), height: 1),
      itemBuilder: (_, i) => _buildSessionTile(_sessions[i]),
    );
  }

  Widget _buildSessionTile(AgentSession s) {
    final title = s.title.isNotEmpty ? s.title : (s.preview.isNotEmpty ? s.preview : s.id);
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: const Color(0xFFf87171),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        try {
          await widget.agent.deleteSession(s.id);
          return true;
        } catch (e) {
          return false;
        }
      },
      onDismissed: (_) {
        setState(() {
          _sessions = _sessions.where((x) => x.id != s.id).toList();
        });
      },
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0x29FF6600),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.chat_bubble_outline, color: Color(0xFFFF6600), size: 18),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        subtitle: Text(
          '${s.messageCount} message${s.messageCount == 1 ? '' : 's'} · ${_formatTimestamp(s.startedAt)}',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
          onPressed: () => _deleteSession(s),
          tooltip: 'Delete',
        ),
        onTap: () => widget.onSessionSelected(s.id),
      ),
    );
  }
}
