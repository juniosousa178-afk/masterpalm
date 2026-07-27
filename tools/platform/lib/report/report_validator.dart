import '../models/report/report_block.dart';
import '../models/report/report_document.dart';
import '../models/report/report_format.dart';
import '../models/report/report_severity.dart';
import '../models/report/report_type.dart';
import '../models/report/report_validation_result.dart';

/// Validates structural integrity of [ReportDocument].
class ReportValidator {
  const ReportValidator();

  ReportValidationResult validate(
    ReportDocument document, {
    Set<ReportFormat>? supportedFormats,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final sectionIds = <String>{};
    var blockCount = 0;
    var findingCount = 0;

    final metadata = document.metadata;
    if (metadata.reportId.isEmpty) errors.add('reportId is empty');
    if (metadata.projectId.isEmpty) errors.add('projectId is empty');
    if (metadata.reportSchemaVersion < 1) {
      errors.add('reportSchemaVersion is missing or invalid');
    }
    try {
      ReportTypeX.fromWireName(metadata.reportType.wireName);
    } catch (_) {
      errors.add('reportType is invalid');
    }

    if (supportedFormats != null) {
      for (final format in supportedFormats) {
        if (!metadata.supportedFormats.contains(format)) {
          warnings.add('Format not listed in metadata: ${format.wireName}');
        }
      }
    }

    for (final section in document.sections) {
      if (!sectionIds.add(section.id)) {
        errors.add('Duplicate section id: ${section.id}');
      }
      if (section.title.isEmpty) {
        errors.add('Section ${section.id} has empty title');
      }
      for (final block in section.blocks) {
        blockCount++;
        errors.addAll(_validateBlock(block, findingCountUpdater: () {
          findingCount++;
        }));
      }
    }

    if (metadata.missingSources.isNotEmpty) {
      warnings.addAll(
        metadata.missingSources.map((s) => 'Missing optional source: $s'),
      );
    }

    return ReportValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      sectionCount: document.sections.length,
      blockCount: blockCount,
      findingCount: findingCount,
    );
  }

  List<String> _validateBlock(
    ReportBlock block, {
    required void Function() findingCountUpdater,
  }) {
    final errors = <String>[];
    switch (block) {
      case TableBlock(:final table):
        if (table.columns.isEmpty) {
          errors.add('Table without columns');
        }
        for (final row in table.rows) {
          if (row.cells.length != table.columns.length) {
            errors.add('Table row has incompatible cell count');
          }
        }
      case FindingBlock(:final finding):
        findingCountUpdater();
        if (finding.code.isEmpty) errors.add('Finding without code');
        try {
          ReportSeverityX.fromWireName(finding.severity.wireName);
        } catch (_) {
          errors.add('Finding with invalid severity');
        }
      case HeadingBlock(:final text):
        if (text.isEmpty) errors.add('Heading with empty text');
      case TextBlock(:final text):
        if (text.isEmpty) errors.add('Text block with empty text');
      case ListBlock(:final items):
        if (items.isEmpty) {
          errors.add('List block with no items');
        }
      case CodeBlock(:final code):
        if (code.isEmpty) errors.add('Code block with empty content');
      case SummaryBlock(:final text):
        if (text.isEmpty) errors.add('Summary block with empty text');
      case DecisionBlock(:final decision):
        if (decision.isEmpty) errors.add('Decision block with empty decision');
    }
    return errors;
  }
}
