import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal PDF inspection for report tests: inflates every stream and returns the raw
/// objects plus the drawn text (one entry per `TJ`/`Tj` operator, in paint order).
class ConsignmentPdfText {
  ConsignmentPdfText._(this.objects, this.words);

  factory ConsignmentPdfText.parse(Uint8List bytes) {
    final raw = latin1.decode(bytes);
    final parts = StringBuffer();
    final streamStart = RegExp(r'stream\r?\n');
    for (final m in streamStart.allMatches(raw)) {
      if (m.start >= 3 && raw.substring(m.start - 3, m.start) == 'end') continue;
      final head = raw.substring(m.start > 400 ? m.start - 400 : 0, m.start);
      final lengths = RegExp(r'/Length\s+(\d+)').allMatches(head).toList();
      if (lengths.isEmpty) continue;
      final len = int.parse(lengths.last.group(1)!);
      if (m.end + len > bytes.length) continue;
      final data = bytes.sublist(m.end, m.end + len);
      try {
        parts.write('\n');
        parts.write(latin1.decode(ZLibDecoder().convert(data)));
      } catch (_) {}
    }
    final inflated = parts.toString();
    final all = '$raw\n$inflated';
    String unescape(String s) => s.replaceAllMapped(RegExp(r'\\(.)'), (x) {
          final c = x.group(1)!;
          return c == 'n' ? '\n' : c;
        });
    final literal = RegExp(r'\(((?:\\.|[^\\)])*)\)');
    final words = <String>[];
    final ops = RegExp(r'\[((?:\\.|\([^)]*\)|[^\]\\])*)\]\s*TJ|\(((?:\\.|[^\\)])*)\)\s*Tj');
    for (final t in ops.allMatches(inflated)) {
      if (t.group(2) != null) {
        words.add(unescape(t.group(2)!));
      } else {
        words.add(literal.allMatches(t.group(1)!).map((m) => unescape(m.group(1)!)).join());
      }
    }
    return ConsignmentPdfText._(all, words);
  }

  final String objects;
  final List<String> words;

  String get text => words.join(' ');

  int get pageCount => RegExp(r'/Type\s*/Page(?![a-zA-Z])').allMatches(objects).length;

  int count(String phrase) => RegExp('(?<![\\wÀ-ÿ])${RegExp.escape(phrase)}(?![\\wÀ-ÿ])').allMatches(text).length;

  /// Text drawn on each page, split on the report footer ("Página i de n").
  List<String> get pageTexts {
    final footer = RegExp(r'Página \d+ de \d+');
    return text.split(footer);
  }
}
