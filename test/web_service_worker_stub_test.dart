import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WEB_SERVICE_WORKER_STUB_REPRODUCIBLE', () {
    test('web/flutter_service_worker.js existe e não é vazio', () {
      final f = File('web/flutter_service_worker.js');
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(100));
      final text = f.readAsStringSync();
      expect(text, contains('fetch'));
      expect(text, isNot(contains('caches.open')));
    });
  });
}
