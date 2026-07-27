import 'package:package_config/package_config.dart';

import 'guardian_package_context.dart';
import 'guardian_package_exceptions.dart';

/// Resolves `package:` imports using the target package [PackageConfig].
class GuardianPackageResolver {
  const GuardianPackageResolver();

  /// Returns true when [uri] is a resolvable `package:` import in [context].
  bool canResolve(String uri, GuardianPackageContext context) {
    return resolve(uri, context) != null;
  }

  /// Resolves [uri] to an absolute file path, or null when not a package import.
  ///
  /// Throws [GuardianPackageResolutionException] when the package import cannot
  /// be resolved in [context.packageConfig].
  String? resolveOrThrow(
    String uri,
    GuardianPackageContext context, {
    required String sourceFilePath,
  }) {
    final resolved = resolve(uri, context);
    if (resolved == null) {
      return null;
    }
    if (!resolved.isResolved) {
      throw GuardianPackageResolutionException(
        uri: uri,
        packageRoot: context.packageRoot,
        filePath: sourceFilePath,
      );
    }
    return resolved.resolvedPath;
  }

  GuardianResolvedImport? resolve(String uri, GuardianPackageContext context) {
    if (!uri.startsWith('package:')) {
      return null;
    }
    final withoutScheme = uri.substring('package:'.length);
    final slash = withoutScheme.indexOf('/');
    final packageName =
        slash == -1 ? withoutScheme : withoutScheme.substring(0, slash);

    final package = context.packageConfig[packageName];
    if (package == null) {
      return GuardianResolvedImport(
        uri: uri,
        packageName: packageName,
        isResolved: false,
      );
    }

    final resolvedUri = context.packageConfig.resolve(Uri.parse(uri));
    if (resolvedUri == null) {
      return GuardianResolvedImport(
        uri: uri,
        packageName: packageName,
        isResolved: false,
      );
    }

    if (resolvedUri.scheme != 'file') {
      return GuardianResolvedImport(
        uri: uri,
        packageName: packageName,
        isResolved: false,
      );
    }

    return GuardianResolvedImport(
      uri: uri,
      packageName: packageName,
      isResolved: true,
      resolvedPath: resolvedUri.toFilePath(windows: _isWindows),
    );
  }

  bool hasPackage(String packageName, GuardianPackageContext context) {
    return context.packageConfig[packageName] != null;
  }

  List<String> listPackageNames(GuardianPackageContext context) {
    return context.packageConfig.packages.map((p) => p.name).toList()..sort();
  }

  static bool get _isWindows =>
      Uri.base.scheme == 'file' && Uri.base.path.contains(':');
}

class GuardianResolvedImport {
  const GuardianResolvedImport({
    required this.uri,
    required this.packageName,
    required this.isResolved,
    this.resolvedPath,
  });

  final String uri;
  final String packageName;
  final bool isResolved;
  final String? resolvedPath;
}
