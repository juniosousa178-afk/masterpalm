/// Deterministic ID factory for graph nodes.
class GraphNodeIdFactory {
  const GraphNodeIdFactory();

  static String normalizePath(String path) =>
      path.replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');

  String project(String projectName) => 'project:$projectName';

  String package(String packageName) => 'package:$packageName';

  String file(String path) => 'file:${normalizePath(path)}';

  String library(String path) => 'library:${normalizePath(path)}';

  String classId(String file, String className) =>
      'class:${normalizePath(file)}::$className';

  String mixin(String file, String name) =>
      'mixin:${normalizePath(file)}::$name';

  String enumType(String file, String name) =>
      'enum:${normalizePath(file)}::$name';

  String extension(String file, String name) =>
      'extension:${normalizePath(file)}::$name';

  String method(String file, String name, {String? className}) {
    final normalized = normalizePath(file);
    if (className != null && className.isNotEmpty) {
      return 'method:$normalized::$className::$name';
    }
    return 'method:$normalized::$name';
  }

  String constructor(String file, String className) =>
      'constructor:${normalizePath(file)}::$className';

  String function(String file, String name) => method(file, name);

  String firestoreCollection(String name) => 'firestore_collection:$name';

  String hiveBox(String name) => 'hive_box:$name';

  String externalType(String name) => 'external_type:$name';
}
