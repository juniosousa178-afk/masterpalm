import 'package:path/path.dart' as p;

/// Canonical path resolution for MasterPalm engineering tools.
class Paths {
  Paths({required this.repoRoot});

  final String repoRoot;

  String get root => p.normalize(repoRoot);

  String get astReportJson => p.join(
        root,
        'docs',
        'intelligence',
        'ast',
        '_data',
        'ast_report.json',
      );

  String get astReportDataDir => p.dirname(astReportJson);

  String get libDir => p.join(root, 'lib');

  String get testDir => p.join(root, 'test');

  String get guardianConfigDir => p.join(root, 'tools', 'guardian', 'config');

  String get intelligenceDir => p.join(root, 'docs', 'intelligence');

  String get knowledgeDir => p.join(root, 'docs', 'knowledge');

  String get engineeringDir => p.join(root, 'docs', 'engineering');

  String relativeToRoot(String absoluteOrRelative) {
    final normalized = p.normalize(absoluteOrRelative);
    if (p.isWithin(root, normalized)) {
      return p.relative(normalized, from: root).replaceAll('\\', '/');
    }
    return normalized.replaceAll('\\', '/');
  }
}
