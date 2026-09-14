import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Confirma que o fix no-slug-flash (Cristal Pratas) permanece no baseline 9a6e35a
/// após materialização do patch Estoque (paths disjoint).
void main() {
  test('catalog loading / early shell sources still present', () {
    final required = <String>[
      'lib/core/catalog_loading_store_name.dart',
      'lib/catalog/catalog_loading_store_name_sync.dart',
      'lib/catalog/catalog_loader_name_resolution.dart',
      'lib/screens/public_catalog/widgets/catalog_early_shell_view.dart',
      'lib/screens/public_catalog/widgets/catalog_early_shell_commercial_bridge.dart',
      'test/catalog_loading_no_visible_slug_flash_test.dart',
    ];
    for (final path in required) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('no-slug-flash test still encodes Cristal Pratas regression intent', () {
    final src = File('test/catalog_loading_no_visible_slug_flash_test.dart')
        .readAsStringSync();
    expect(src.toLowerCase().contains('cristal'), isTrue);
    expect(src.contains('slug'), isTrue);
  });
}
