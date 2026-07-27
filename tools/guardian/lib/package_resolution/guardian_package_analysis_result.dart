import 'guardian_package_exceptions.dart';

class GuardianUnresolvedImport {
  const GuardianUnresolvedImport({
    required this.filePath,
    required this.uri,
    required this.packageName,
  });

  final String filePath;
  final String uri;
  final String packageName;

  Map<String, dynamic> toComparableJson() => {
        'filePath': filePath,
        'uri': uri,
        'packageName': packageName,
      };
}

class GuardianPackageAnalysisResult {
  const GuardianPackageAnalysisResult({
    required this.packageRoot,
    required this.packageName,
    required this.packageConfigPath,
    required this.analyzedFiles,
    required this.resolvedPackageImports,
    required this.unresolvedImports,
    required this.missingAdapterPaths,
    required this.analyzedAdapterPaths,
    required this.isComplete,
    required this.analysisFingerprint,
  });

  final String packageRoot;
  final String packageName;
  final String packageConfigPath;
  final List<String> analyzedFiles;
  final List<String> resolvedPackageImports;
  final List<GuardianUnresolvedImport> unresolvedImports;
  final List<String> missingAdapterPaths;
  final List<String> analyzedAdapterPaths;
  final bool isComplete;
  final String analysisFingerprint;

  bool get hasUnresolvedImports => unresolvedImports.isNotEmpty;

  bool get hasMissingAdapters => missingAdapterPaths.isNotEmpty;

  Map<String, dynamic> toComparableJson() => {
        'packageRoot': packageRoot,
        'packageName': packageName,
        'packageConfigPath': packageConfigPath,
        'analyzedFiles': analyzedFiles,
        'resolvedPackageImports': resolvedPackageImports,
        'unresolvedImports':
            unresolvedImports.map((e) => e.toComparableJson()).toList(),
        'missingAdapterPaths': missingAdapterPaths,
        'analyzedAdapterPaths': analyzedAdapterPaths,
        'isComplete': isComplete,
        'analysisFingerprint': analysisFingerprint,
      };

  void throwIfIncomplete() {
    if (isComplete) return;
    if (hasUnresolvedImports) {
      final first = unresolvedImports.first;
      throw GuardianPackageResolutionException(
        uri: first.uri,
        packageRoot: packageRoot,
        filePath: first.filePath,
      );
    }
    if (hasMissingAdapters) {
      throw GuardianPackageException(
        'expected adapter files missing from analysis: '
        '${missingAdapterPaths.join(', ')}',
        packageRoot: packageRoot,
      );
    }
    throw GuardianPackageException(
      'package analysis incomplete',
      packageRoot: packageRoot,
    );
  }
}
