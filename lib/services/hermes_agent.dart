import 'dart:convert';
import 'package:http/http.dart' as http;

class HermesAgent {
  String _model = 'kimi-k2.6:cloud';

  Future<String> chat(String message) async {
    try {
      final res = await http.post(
        Uri.parse('https://ollama.com/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': 'You are Hermes, fleet agent for XMRT-DAO. You coordinate mining operations.'},
            {'role': 'user', 'content': message},
          ],
          'stream': false,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['message']['content'] ?? 'No response';
      }
      return 'Agent error (${res.statusCode})';
    } catch (e) {
      return 'Connection error. Make sure Ollama is running.';
    }
  }
}
