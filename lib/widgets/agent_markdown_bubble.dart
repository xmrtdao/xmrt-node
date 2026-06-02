import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Renders agent responses as formatted Markdown, themed to match
/// the dark/orange XMRT dashboard.
///
/// The agent emits standard CommonMark + GFM. We don't sanitize
/// (flutter_markdown_plus already escapes HTML), and we use a
/// Material-themed MarkdownStyleSheet so it inherits from the app theme.
///
/// Usage:
///   AgentMarkdownBubble(text: response)
class AgentMarkdownBubble extends StatelessWidget {
  final String text;
  final Color textColor;
  final Color accentColor;

  const AgentMarkdownBubble({
    super.key,
    required this.text,
    this.textColor = Colors.white,
    this.accentColor = const Color(0xFFFF6600),
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: text,
      shrinkWrap: true,
      fitContent: false,
      styleSheet: _buildStyleSheet(textColor, accentColor),
      onTapLink: (text, href, title) {
        // TODO: launch the URL in a browser (need url_launcher)
        // For now, just log it.
        debugPrint('AgentMarkdownBubble link tap: $href');
      },
    );
  }

  MarkdownStyleSheet _buildStyleSheet(Color textColor, Color accent) {
    return MarkdownStyleSheet(
      p: TextStyle(
        color: textColor,
        fontSize: 13,
        height: 1.5,
      ),
      h1: TextStyle(
        color: accent,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        height: 1.4,
      ),
      h2: TextStyle(
        color: accent,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      h3: TextStyle(
        color: accent,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      h4: TextStyle(
        color: accent,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      h5: TextStyle(
        color: textColor,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      h6: TextStyle(
        color: textColor.withOpacity(0.7),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      strong: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w700,
      ),
      em: TextStyle(
        color: textColor,
        fontStyle: FontStyle.italic,
      ),
      del: TextStyle(
        color: textColor.withOpacity(0.6),
        decoration: TextDecoration.lineThrough,
      ),
      a: TextStyle(
        color: accent,
        decoration: TextDecoration.underline,
      ),
      code: TextStyle(
        color: const Color(0xFFfbbf24),
        backgroundColor: const Color(0xFF0d0d15),
        fontFamily: 'monospace',
        fontSize: 12,
      ),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF0d0d15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      blockquote: TextStyle(
        color: textColor.withOpacity(0.85),
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        border: Border(
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      tableHead: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w700,
      ),
      tableBody: TextStyle(
        color: textColor.withOpacity(0.9),
        fontSize: 12,
      ),
      tableBorder: TableBorder.all(
        color: const Color(0xFF2a2a3a),
        width: 1,
      ),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      listBullet: TextStyle(
        color: accent,
        fontSize: 14,
      ),
      h1Padding: const EdgeInsets.only(top: 12, bottom: 6),
      h2Padding: const EdgeInsets.only(top: 10, bottom: 4),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 4),
      h4Padding: const EdgeInsets.only(top: 6, bottom: 4),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: const Color(0xFF2a2a3a),
            width: 1,
          ),
        ),
      ),
    );
  }
}
