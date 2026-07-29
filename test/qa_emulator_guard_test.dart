import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/config/qa_emulator_guard.dart';

void main() {
  group('parseQaEmulatorHostPort', () {
    test('aceita localhost e 127.0.0.1', () {
      final a = parseQaEmulatorHostPort('127.0.0.1:8180', label: 'firestore');
      expect(a.host, '127.0.0.1');
      expect(a.port, 8180);
      final b = parseQaEmulatorHostPort('localhost:9199', label: 'auth');
      expect(b.host, 'localhost');
      expect(b.port, 9199);
    });

    test('bloqueia host vazio', () {
      expect(
        () => parseQaEmulatorHostPort('', label: 'auth'),
        throwsStateError,
      );
    });

    test('bloqueia host externo', () {
      expect(
        () => parseQaEmulatorHostPort('firestore.googleapis.com:443', label: 'x'),
        throwsStateError,
      );
    });

    test('bloqueia projectId produção no host string', () {
      expect(
        () => parseQaEmulatorHostPort('masterpalm-58c46:8180', label: 'x'),
        throwsStateError,
      );
    });

    test('bloqueia host.docker.internal', () {
      expect(
        () => parseQaEmulatorHostPort('host.docker.internal:8180', label: 'x'),
        throwsStateError,
      );
    });
  });

  group('sanitize / normalize', () {
    test('normalize trim e lowercase', () {
      expect(normalizeQaEmulatorHost(' LocalHost '), 'localhost');
    });
  });
}
