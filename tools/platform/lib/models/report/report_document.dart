import 'report_metadata.dart';
import 'report_section.dart';

/// Immutable structured report document.
class ReportDocument {
  const ReportDocument({
    required this.metadata,
    required this.sections,
  });

  final ReportMetadata metadata;
  final List<ReportSection> sections;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  factory ReportDocument.fromJson(Map<String, dynamic> json) {
    return ReportDocument(
      metadata: ReportMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      sections: (json['sections'] as List<dynamic>)
          .map((e) => ReportSection.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toComparableJson() {
    return {
      'metadata': metadata.toComparableJson(),
      'sections': sections.map((s) => s.toJson()).toList(),
    };
  }
}
