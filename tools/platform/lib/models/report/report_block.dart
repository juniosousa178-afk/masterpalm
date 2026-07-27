import 'report_finding.dart';
import 'report_table.dart';

/// Discriminated union of report content blocks.
sealed class ReportBlock {
  const ReportBlock();

  String get kind;

  Map<String, dynamic> toJson();

  factory ReportBlock.fromJson(Map<String, dynamic> json) {
    switch (json['kind'] as String) {
      case 'heading':
        return HeadingBlock.fromJson(json);
      case 'text':
        return TextBlock.fromJson(json);
      case 'list':
        return ListBlock.fromJson(json);
      case 'table':
        return TableBlock.fromJson(json);
      case 'code':
        return CodeBlock.fromJson(json);
      case 'finding':
        return FindingBlock.fromJson(json);
      case 'summary':
        return SummaryBlock.fromJson(json);
      case 'decision':
        return DecisionBlock.fromJson(json);
      default:
        throw FormatException('Unknown ReportBlock kind: ${json['kind']}');
    }
  }
}

class HeadingBlock extends ReportBlock {
  const HeadingBlock({required this.level, required this.text});

  final int level;
  final String text;

  @override
  String get kind => 'heading';

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'level': level,
        'text': text,
      };

  factory HeadingBlock.fromJson(Map<String, dynamic> json) {
    return HeadingBlock(
      level: json['level'] as int,
      text: json['text'] as String,
    );
  }
}

class TextBlock extends ReportBlock {
  const TextBlock({required this.text});

  final String text;

  @override
  String get kind => 'text';

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'text': text};

  factory TextBlock.fromJson(Map<String, dynamic> json) {
    return TextBlock(text: json['text'] as String);
  }
}

class ListBlock extends ReportBlock {
  const ListBlock({required this.items, this.ordered = false});

  final List<String> items;
  final bool ordered;

  @override
  String get kind => 'list';

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'items': items,
        'ordered': ordered,
      };

  factory ListBlock.fromJson(Map<String, dynamic> json) {
    return ListBlock(
      items: (json['items'] as List<dynamic>).map((e) => e.toString()).toList(),
      ordered: json['ordered'] as bool? ?? false,
    );
  }
}

class TableBlock extends ReportBlock {
  const TableBlock({required this.table});

  final ReportTable table;

  @override
  String get kind => 'table';

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'table': table.toJson()};

  factory TableBlock.fromJson(Map<String, dynamic> json) {
    return TableBlock(
      table: ReportTable.fromJson(json['table'] as Map<String, dynamic>),
    );
  }
}

class CodeBlock extends ReportBlock {
  const CodeBlock({required this.code, this.language});

  final String code;
  final String? language;

  @override
  String get kind => 'code';

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'code': code,
        if (language != null) 'language': language,
      };

  factory CodeBlock.fromJson(Map<String, dynamic> json) {
    return CodeBlock(
      code: json['code'] as String,
      language: json['language'] as String?,
    );
  }
}

class FindingBlock extends ReportBlock {
  const FindingBlock({required this.finding});

  final ReportFinding finding;

  @override
  String get kind => 'finding';

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'finding': finding.toJson(),
      };

  factory FindingBlock.fromJson(Map<String, dynamic> json) {
    return FindingBlock(
      finding: ReportFinding.fromJson(json['finding'] as Map<String, dynamic>),
    );
  }
}

class SummaryBlock extends ReportBlock {
  const SummaryBlock({required this.text});

  final String text;

  @override
  String get kind => 'summary';

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'text': text};

  factory SummaryBlock.fromJson(Map<String, dynamic> json) {
    return SummaryBlock(text: json['text'] as String);
  }
}

class DecisionBlock extends ReportBlock {
  const DecisionBlock({
    required this.decision,
    required this.simulationOnly,
  });

  final String decision;
  final bool simulationOnly;

  @override
  String get kind => 'decision';

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'decision': decision,
        'simulationOnly': simulationOnly,
      };

  factory DecisionBlock.fromJson(Map<String, dynamic> json) {
    return DecisionBlock(
      decision: json['decision'] as String,
      simulationOnly: json['simulationOnly'] as bool? ?? true,
    );
  }
}
