import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'guardian_cryptographic_adapter_paths.dart';
import 'guardian_cloud_framework_paths.dart';
import 'guardian_package_analysis_result.dart';
import 'guardian_package_context.dart';
import 'guardian_package_import_scanner.dart';
import 'guardian_package_resolver.dart';

/// Static package import analyzer for Guardian compatibility gates.
///
/// Does not execute analyzed code, load plugins, or access the network.
class GuardianPackageAnalyzer {
  const GuardianPackageAnalyzer({
    GuardianPackageImportScanner? scanner,
    GuardianPackageResolver? resolver,
  })  : _scanner = scanner ?? const GuardianPackageImportScanner(),
        _resolver = resolver ?? const GuardianPackageResolver();

  final GuardianPackageImportScanner _scanner;
  final GuardianPackageResolver _resolver;

  Future<GuardianPackageContext> loadContext(String packageRoot) {
    return GuardianPackageContext.load(packageRoot);
  }

  Future<GuardianPackageAnalysisResult> analyzePackage(
    String packageRoot, {
    List<String>? requiredAdapterRelativePaths,
    String libSubdirectory = 'lib',
  }) async {
    final context = await loadContext(packageRoot);
    return analyzeContext(
      context,
      requiredAdapterRelativePaths: requiredAdapterRelativePaths,
      libSubdirectory: libSubdirectory,
    );
  }

  Future<GuardianPackageAnalysisResult> analyzeContext(
    GuardianPackageContext context, {
    List<String>? requiredAdapterRelativePaths,
    String libSubdirectory = 'lib',
  }) async {
    final libDir = p.join(context.packageRoot, libSubdirectory);
    final dartFiles = _scanner.listDartFiles(libDir);
    final resolvedImports = <String>{};
    final unresolved = <GuardianUnresolvedImport>[];

    for (final filePath in dartFiles) {
      final content = File(filePath).readAsStringSync();
      for (final uri in _scanner.extractUris(content)) {
        if (!uri.startsWith('package:')) continue;
        final resolution = _resolver.resolve(uri, context);
        if (resolution == null) continue;
        if (resolution.isResolved) {
          resolvedImports.add(uri);
        } else {
          unresolved.add(
            GuardianUnresolvedImport(
              filePath: p.relative(filePath, from: context.packageRoot),
              uri: uri,
              packageName: resolution.packageName,
            ),
          );
        }
      }
    }

    final adapterPaths = requiredAdapterRelativePaths ?? const <String>[];
    final analyzedAdapterPaths = <String>[];
    final missingAdapterPaths = <String>[];

    for (final relative in adapterPaths) {
      final absolute = p.normalize(p.join(context.packageRoot, relative));
      if (dartFiles.contains(absolute)) {
        analyzedAdapterPaths.add(relative);
      } else {
        missingAdapterPaths.add(relative);
      }
    }

    final sortedResolved = resolvedImports.toList()..sort();
    final sortedUnresolved = List<GuardianUnresolvedImport>.from(unresolved)
      ..sort((a, b) {
        final fileCmp = a.filePath.compareTo(b.filePath);
        if (fileCmp != 0) return fileCmp;
        return a.uri.compareTo(b.uri);
      });
    final sortedAnalyzedAdapters = analyzedAdapterPaths.toList()..sort();
    final sortedMissingAdapters = missingAdapterPaths.toList()..sort();

    final fingerprint = _fingerprint({
      'packageName': context.packageName,
      'analyzedFileCount': dartFiles.length,
      'resolvedPackageImports': sortedResolved,
      'unresolvedCount': sortedUnresolved.length,
      'missingAdapterCount': sortedMissingAdapters.length,
    });

    return GuardianPackageAnalysisResult(
      packageRoot: context.packageRoot,
      packageName: context.packageName,
      packageConfigPath: context.packageConfigPath,
      analyzedFiles: dartFiles
          .map(
            (f) =>
                p.relative(f, from: context.packageRoot).replaceAll('\\', '/'),
          )
          .toList(),
      resolvedPackageImports: sortedResolved,
      unresolvedImports: sortedUnresolved,
      missingAdapterPaths: sortedMissingAdapters,
      analyzedAdapterPaths: sortedAnalyzedAdapters,
      isComplete: sortedUnresolved.isEmpty && sortedMissingAdapters.isEmpty,
      analysisFingerprint: fingerprint,
    );
  }

  Future<GuardianPackageAnalysisResult> analyzeCryptographicTrustPackage(
    String packageRoot,
  ) {
    return analyzePackage(
      packageRoot,
      requiredAdapterRelativePaths:
          GuardianCryptographicAdapterPaths.adapterRelativePaths,
    );
  }

  Future<GuardianPackageAnalysisResult> analyzeCloudFrameworkPackage(
    String packageRoot,
  ) {
    return analyzePackage(
      packageRoot,
      requiredAdapterRelativePaths:
          GuardianCloudFrameworkPaths.allRequiredPaths,
    );
  }

  Future<void> ensureCryptographicTrustResolvable(String packageRoot) async {
    final result = await analyzeCryptographicTrustPackage(packageRoot);
    result.throwIfIncomplete();
  }

  static String _fingerprint(Map<String, dynamic> comparable) {
    final keys = comparable.keys.toList()..sort();
    final normalized = <String, dynamic>{};
    for (final key in keys) {
      normalized[key] = comparable[key];
    }
    return sha256.convert(utf8.encode(jsonEncode(normalized))).toString();
  }
}
