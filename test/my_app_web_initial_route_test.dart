import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/config/my_app_web_initial_route.dart';

void main() {
  group('myAppWebInitialRoute', () {
    test('/login → /login', () {
      expect(
        myAppWebInitialRoute(
          baseUri: Uri.parse('http://127.0.0.1/login'),
          isWebOverride: true,
        ),
        '/login',
      );
    });

    test('/login?x=1 → /login', () {
      expect(
        myAppWebInitialRoute(
          baseUri: Uri.parse('http://127.0.0.1/login?x=1'),
          isWebOverride: true,
        ),
        '/login',
      );
    });

    test('/ → /', () {
      expect(
        myAppWebInitialRoute(
          baseUri: Uri.parse('http://127.0.0.1/'),
          isWebOverride: true,
        ),
        '/',
      );
    });

    test('rota desconhecida → /', () {
      expect(
        myAppWebInitialRoute(
          baseUri: Uri.parse('http://127.0.0.1/rota-inexistente'),
          isWebOverride: true,
        ),
        '/',
      );
    });

    test('plataforma não Web retorna /', () {
      expect(
        myAppWebInitialRoute(
          baseUri: Uri.parse('http://127.0.0.1/login'),
          isWebOverride: false,
        ),
        '/',
      );
    });
  });
}
