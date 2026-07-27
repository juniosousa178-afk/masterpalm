import 'report_block.dart';

/// Section within a [ReportDocument].
class ReportSection {
  const ReportSection({
    required this.id,
    required this.title,
    required this.blocks,
  });

  final String id;
  final String title;
  final List<ReportBlock> blocks;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory ReportSection.fromJson(Map<String, dynamic> json) {
    return ReportSection(
      id: json['id'] as String,
      title: json['title'] as String,
      blocks: (json['blocks'] as List<dynamic>)
          .map((e) => ReportBlock.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
