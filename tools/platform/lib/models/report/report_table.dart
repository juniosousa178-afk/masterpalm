/// Column definition for a report table.
class ReportTableColumn {
  const ReportTableColumn({required this.id, required this.label});

  final String id;
  final String label;

  Map<String, dynamic> toJson() => {'id': id, 'label': label};

  factory ReportTableColumn.fromJson(Map<String, dynamic> json) {
    return ReportTableColumn(
      id: json['id'] as String,
      label: json['label'] as String,
    );
  }
}

/// Row in a report table.
class ReportTableRow {
  const ReportTableRow({required this.cells});

  final List<String> cells;

  Map<String, dynamic> toJson() => {'cells': cells};

  factory ReportTableRow.fromJson(Map<String, dynamic> json) {
    return ReportTableRow(
      cells: (json['cells'] as List<dynamic>).map((e) => e.toString()).toList(),
    );
  }
}

/// Tabular data block content.
class ReportTable {
  const ReportTable({
    required this.columns,
    required this.rows,
  });

  final List<ReportTableColumn> columns;
  final List<ReportTableRow> rows;

  Map<String, dynamic> toJson() => {
        'columns': columns.map((c) => c.toJson()).toList(),
        'rows': rows.map((r) => r.toJson()).toList(),
      };

  factory ReportTable.fromJson(Map<String, dynamic> json) {
    return ReportTable(
      columns: (json['columns'] as List<dynamic>)
          .map((e) => ReportTableColumn.fromJson(e as Map<String, dynamic>))
          .toList(),
      rows: (json['rows'] as List<dynamic>)
          .map((e) => ReportTableRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
