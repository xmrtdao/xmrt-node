import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/xmrt_agent.dart';
import '../widgets/agent_markdown_bubble.dart';

/// Base class for the Memory / Soul / Skills editor screens.
///
/// All three follow the same pattern: fetch initial content from
/// the agent, let the user edit, save back. For Skills, it's
/// read-only browsing with a detail view.
abstract class _AgentFileEditor extends StatefulWidget {
  final XmrtAgent agent;
  final String title;
  const _AgentFileEditor({required this.agent, required this.title});

  @override
  State<_AgentFileEditor> createState();
}

class _MemoryEditor extends _AgentFileEditor {
  const _MemoryEditor({required super.agent}) : super(title: 'Memory');

  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _SoulEditor extends _AgentFileEditor {
  const _SoulEditor({required super.agent}) : super(title: 'Soul');

  @override
  State<_SoulEditor> createState() => _SoulEditorState();
}

/// Stateful shell that handles the load/edit/save flow.
abstract class _AgentEditorState extends State<_AgentFileEditor> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _preview = true; // start in preview mode
  String? _error;
  String? _lastSavedContent;

  /// Subclass hook: how to fetch initial content.
  Future<String> _loadContent();

  /// Subclass hook: how to save content.
  Future<void> _saveContent(String content);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final content = await _loadContent();
      _controller.text = content;
      _lastSavedContent = content;
    } catch (e) {
      _error = 'Failed to load: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _saveContent(_controller.text);
      _lastSavedContent = _controller.text;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved'),
            duration: Duration(seconds: 1),
            backgroundColor: Color(0xFF22c55e),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: const Color(0xFFf87171),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _dirty => _controller.text != _lastSavedContent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030303),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0C0C),
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(color: Color(0xFFFF6600), fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (!_loading) ...[
            IconButton(
              icon: Icon(_preview ? Icons.edit : Icons.visibility, color: Colors.white70),
              tooltip: _preview ? 'Edit' : 'Preview',
              onPressed: () => setState(() => _preview = !_preview),
            ),
            TextButton.icon(
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6600)))
                  : const Icon(Icons.save, color: Color(0xFFFF6600)),
              label: Text(
                _dirty ? 'Save' : 'Saved',
                style: TextStyle(
                  color: _dirty ? const Color(0xFFFF6600) : Colors.white38,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: (_saving || !_dirty) ? null : _save,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6600)),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFf87171), size: 32),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            TextButton(onPressed: _bootstrap, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_preview) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AgentMarkdownBubble(text: _controller.text),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          height: 1.5,
          fontFamily: 'monospace',
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Start writing...',
          hintStyle: TextStyle(color: Colors.white24),
        ),
        onChanged: (_) => setState(() {}), // re-evaluate _dirty
      ),
    );
  }
}

class _MemoryEditorState extends _AgentEditorState {
  @override
  Future<String> _loadContent() => widget.agent.readMemory();
  @override
  Future<void> _saveContent(String content) async {
    // Append-mode is the usual flow (matches the agent's POST /v1/memory
    // body). For now we always do a full-write via the agent's
    // append entry handler — extend the client later if needed.
    throw UnimplementedError('Use the + Add button to append entries.');
  }
  // Override the build to add a "Add" FAB that appends an entry.
  @override
  Widget build(BuildContext context) {
    final base = super.build(context);
    return Stack(children: [
      base,
      Positioned(
        right: 16, bottom: 16,
        child: FloatingActionButton.extended(
          backgroundColor: const Color(0xFFFF6600),
          icon: const Icon(Icons.add, color: Colors.black),
          label: const Text('Add entry', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
          onPressed: _showAddDialog,
        ),
      ),
    ]);
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF12121a),
          title: const Text('Add memory entry', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 5,
            minLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'What should the agent remember?',
              hintStyle: TextStyle(color: Colors.white38),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Add', style: TextStyle(color: Color(0xFFFF6600))),
            ),
          ],
        );
      },
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      // Use the agent's append-entry endpoint. We don't have it on the
      // Dart client yet, so we hit the channel directly.
      // (Simpler than extending the client right now.)
      const channel = MethodChannel('io.xmrt.node/agent');
      await channel.invokeMethod('agent.appendMemory', {'entry': result});
      await _bootstrap();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Append failed: $e'), backgroundColor: const Color(0xFFf87171)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SoulEditorState extends _AgentEditorState {
  @override
  Future<String> _loadContent() => widget.agent.readSoul();
  @override
  Future<void> _saveContent(String content) async {
    const channel = MethodChannel('io.xmrt.node/agent');
    await channel.invokeMethod('agent.writeSoul', {'content': content});
  }
}

/// Public editors exposed for the chat screen's overflow menu.
class AgentMemoryEditor extends _MemoryEditor {
  const AgentMemoryEditor({required super.agent});
}
class AgentSoulEditor extends _SoulEditor {
  const AgentSoulEditor({required super.agent});
}
class AgentSkillsBrowser extends _SkillsBrowser {
  const AgentSkillsBrowser({required super.agent});
}
class _SkillsBrowser extends StatefulWidget {
  final XmrtAgent agent;
  const _SkillsBrowser({required this.agent});

  @override
  State<_SkillsBrowser> createState() => _SkillsBrowserState();
}

class _SkillsBrowserState extends State<_SkillsBrowser> {
  List<String> _skills = [];
  String? _selected;
  String? _content;
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
      // Use MethodChannel directly to hit listSkills; we don't have a
      // typed wrapper yet.
      const channel = MethodChannel('io.xmrt.node/agent');
      final res = await channel.invokeMethod<Map>('agent.listSkills');
      final skills = res?['skills'] as List? ?? [];
      _skills = skills.map((s) => (s as Map)['name'] as String? ?? '').where((n) => n.isNotEmpty).toList();
    } catch (e) {
      _error = 'Failed to load skills: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(String name) async {
    setState(() {
      _selected = name;
      _content = null;
    });
    try {
      const channel = MethodChannel('io.xmrt.node/agent');
      final res = await channel.invokeMethod<Map>('agent.getSkill', {'name': name});
      _content = (res?['body'] as String?) ?? '';
    } catch (e) {
      _content = 'Failed to load: $e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030303),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0C0C),
        elevation: 0,
        title: const Text('Skills', style: TextStyle(color: Color(0xFFFF6600), fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6600)))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
              : Row(
                  children: [
                    // List
                    SizedBox(
                      width: 140,
                      child: _skills.isEmpty
                          ? const Center(child: Text('No skills', style: TextStyle(color: Colors.white60, fontSize: 12)))
                          : ListView.builder(
                              itemCount: _skills.length,
                              itemBuilder: (_, i) {
                                final name = _skills[i];
                                final selected = name == _selected;
                                return Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: selected ? const Color(0xFFFF6600) : Colors.transparent,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    title: Text(
                                      name,
                                      style: TextStyle(
                                        color: selected ? const Color(0xFFFF6600) : Colors.white,
                                        fontSize: 12,
                                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                                      ),
                                    ),
                                    onTap: () => _select(name),
                                  ),
                                );
                              },
                            ),
                    ),
                    VerticalDivider(color: Colors.white.withOpacity(0.1), width: 1),
                    // Detail
                    Expanded(
                      child: _selected == null
                          ? const Center(
                              child: Text('Pick a skill to view', style: TextStyle(color: Colors.white60)),
                            )
                          : _content == null
                              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6600)))
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selected!,
                                        style: const TextStyle(
                                          color: Color(0xFFFF6600),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      AgentMarkdownBubble(text: _content!),
                                    ],
                                  ),
                                ),
                    ),
                  ],
                ),
    );
  }
}
