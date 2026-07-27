import 'package:path/path.dart' as p;

import '../config/analysis_options.dart';
import '../config/platform_config.dart';
import '../exceptions/analysis_exception.dart';
import '../interfaces/ast_provider.dart';
import '../utils/file_helpers.dart';
import '../utils/json_helpers.dart';

/// Reads and writes AST intelligence from the canonical report path via [PlatformConfig].
class FileSystemAstProvider implements AstProvider {
  FileSystemAstProvider({
    required PlatformConfig config,
    FileHelpers? fileHelpers,
    AnalysisOptions? options,
  })  : _config = config,
        _files = fileHelpers ?? const FileHelpers(),
        _options = options ?? config.analysis;

  final PlatformConfig _config;
  final FileHelpers _files;
  final AnalysisOptions _options;

  Map<String, dynamic>? _cache;

  @override
  String get reportPath => _config.paths.astReportJson;

  @override
  Map<String, dynamic> loadReport() {
    if (_options.cacheAstReport && _cache != null) return _cache!;

    final path = _config.paths.astReportJson;
    if (!_files.exists(path)) {
      _cache = {};
      return _cache!;
    }

    try {
      _cache = _files.readJsonMap(path);
      return _cache!;
    } catch (e) {
      throw AnalysisException(
        'Failed to load AST report',
        cause: e,
        context: path,
      );
    }
  }

  @override
  void saveReport(Map<String, dynamic> report) {
    final path = reportPath;
    _files.ensureDirectory(p.dirname(path));
    _files.writeText(path, JsonHelpers.encode(report, pretty: true));
    _cache = Map<String, dynamic>.from(report);
  }

  @override
  int? complexityForMethod(String methodKey) {
    final methods = loadReport()['methods'] as Map<String, dynamic>?;
    if (methods == null) return null;
    final m = methods[methodKey];
    if (m is Map<String, dynamic>) {
      return m['complexity'] as int?;
    }
    return null;
  }

  @override
  int? complexityForFile(String relPath) {
    final normalized = relPath.replaceAll('\\', '/');
    final methods = loadReport()['methods'] as Map<String, dynamic>?;
    if (methods == null) return null;
    int? max;
    for (final entry in methods.entries) {
      final m = entry.value as Map<String, dynamic>;
      if ((m['file'] as String?) == normalized) {
        final c = m['complexity'] as int? ?? 0;
        if (max == null || c > max) max = c;
      }
    }
    return max;
  }

  @override
  int? linesForFile(String relPath) {
    final normalized = relPath.replaceAll('\\', '/');
    final files = loadReport()['top_critical_files'] as List<dynamic>?;
    if (files != null) {
      for (final f in files) {
        if (f is Map && f['file'] == normalized) {
          return f['lines'] as int?;
        }
      }
    }
    return null;
  }

  @override
  List<String> callersForFile(String relPath) {
    final normalized = relPath.replaceAll('\\', '/');
    final methods = loadReport()['methods'] as Map<String, dynamic>?;
    if (methods == null) return [];
    final callers = <String>{};
    for (final entry in methods.entries) {
      final m = entry.value as Map<String, dynamic>;
      if ((m['file'] as String?) != normalized) continue;
      for (final c in (m['callers'] as List<dynamic>? ?? [])) {
        callers.add(c.toString());
      }
    }
    return callers.toList()..sort();
  }

  @override
  bool hasImportCycle(List<String> changedFiles) {
    final cycles = loadReport()['cyclic_imports'] as List<dynamic>? ?? [];
    final set = changedFiles.map((f) => f.replaceAll('\\', '/')).toSet();
    for (final cycle in cycles) {
      if (cycle is List) {
        for (final node in cycle) {
          if (set.contains(node.toString())) return true;
        }
      }
    }
    return false;
  }
}
