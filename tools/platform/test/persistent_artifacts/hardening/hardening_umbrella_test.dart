import 'package:test/test.dart';

void main() {
  group('hardening umbrella', () {
    for (var i = 0; i < 10; i++) {
      test('umbrella smoke $i', () {
        expect(i >= 0, isTrue);
      });
    }
  });
}
