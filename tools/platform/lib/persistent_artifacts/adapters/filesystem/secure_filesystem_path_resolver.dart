import 'dart:io';

import 'package:path/path.dart' as p;

import 'secure_filesystem_backend_config.dart';

class SecureFilesystemPathResolver {
  SecureFilesystemPathResolver({
    required SecureFilesystemBackendConfig config,
  })  : _config = config,
        _root = Directory(config.rootDirectory).absolute;

  final SecureFilesystemBackendConfig _config;
  final Directory _root;

  Directory get rootDirectory => _root;

  String publicLocationForRelativePath(String relativePath) {
    return '${_config.backendId}://${p.url.normalize(relativePath.replaceAll('\\', '/'))}';
  }

  File resolveFile(List<String> segments) {
    final sanitized = _sanitizeSegments(segments);
    final fullPath = p.normalize(p.joinAll([_root.path, ...sanitized]));
    _assertRootConfined(fullPath);
    _assertNoSymlinkInPath(fullPath, expectLeafDirectory: false);
    return File(fullPath);
  }

  Directory resolveDirectory(List<String> segments) {
    final sanitized = _sanitizeSegments(segments);
    final fullPath = p.normalize(p.joinAll([_root.path, ...sanitized]));
    _assertRootConfined(fullPath);
    _assertNoSymlinkInPath(fullPath, expectLeafDirectory: true);
    return Directory(fullPath);
  }

  void ensureWithinRoot(String fullPath) {
    _assertRootConfined(fullPath);
    _assertNoSymlinkInPath(fullPath, expectLeafDirectory: false);
  }

  List<String> _sanitizeSegments(List<String> segments) {
    if (segments.isEmpty) {
      throw const FormatException('Path segments must not be empty');
    }
    return segments.map((segment) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) {
        throw const FormatException('Path segment must not be empty');
      }
      _rejectDangerousSegment(trimmed);
      return trimmed;
    }).toList(growable: false);
  }

  void _rejectDangerousSegment(String segment) {
    final lower = segment.toLowerCase();
    final decoded = Uri.decodeComponent(segment).toLowerCase();
    final hasTraversal = lower == '..' ||
        lower.contains('../') ||
        lower.contains('..\\') ||
        decoded.contains('..');
    final hasAbsolute = p.isAbsolute(segment) ||
        segment.startsWith('/') ||
        segment.startsWith('\\') ||
        segment.startsWith('~') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(segment) ||
        segment.startsWith(r'\\');
    final hasControl =
        segment.codeUnits.any((unit) => unit < 32 || unit == 127);
    final hasNullByte = segment.contains('\x00');
    if (hasTraversal || hasAbsolute || hasControl || hasNullByte) {
      throw const FormatException('Unsafe path segment rejected');
    }
  }

  void _assertRootConfined(String fullPath) {
    final absoluteRoot = p.normalize(_root.absolute.path);
    final absoluteTarget = p.normalize(File(fullPath).absolute.path);
    final rootWithSep = absoluteRoot.endsWith(p.separator)
        ? absoluteRoot
        : '$absoluteRoot${p.separator}';
    if (absoluteTarget != absoluteRoot &&
        !absoluteTarget.startsWith(rootWithSep)) {
      throw const FileSystemException('Path escapes configured root');
    }
  }

  void _assertNoSymlinkInPath(String targetPath,
      {required bool expectLeafDirectory}) {
    final relative = p.relative(targetPath, from: _root.path);
    final segments =
        relative.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
    var currentPath = _root.path;
    for (final segment in segments) {
      currentPath = p.join(currentPath, segment);
      final type = FileSystemEntity.typeSync(
        currentPath,
        followLinks: false,
      );
      if (type == FileSystemEntityType.link) {
        throw const FileSystemException('Symbolic link path is rejected');
      }
      if (type == FileSystemEntityType.notFound) {
        // Once path does not exist there cannot be link traversal deeper.
        break;
      }
    }

    final leafType = FileSystemEntity.typeSync(targetPath, followLinks: false);
    if (leafType == FileSystemEntityType.link) {
      throw const FileSystemException('Symbolic link leaf is rejected');
    }
    if (expectLeafDirectory && leafType == FileSystemEntityType.file) {
      throw const FileSystemException('Expected directory, got file');
    }
  }
}
