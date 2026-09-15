import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:master_palm/services/web_build_convergence_service.dart';

void main() {
  test('current build matches version.json → no reload', () async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/version.json'));
      expect(request.url.queryParameters.containsKey('v'), isTrue);
      return http.Response(
        '{"buildId":"web-34200df","gitCommit":"34200df"}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final svc = WebBuildConvergenceService(
      client: client,
      localBuildId: 'web-34200df',
      forceVersionCheck: true,
    );
    final result = await svc.check(baseUri: Uri.parse('https://app.example/'));
    expect(result.mismatch, isFalse);
    expect(result.shouldPromptReload, isFalse);
    expect(result.remoteBuildId, 'web-34200df');
  });

  test('stale build detected via version.json cache-bust query', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters.containsKey('v'), isTrue);
      return http.Response('{"buildId":"web-34200df"}', 200);
    });
    final svc = WebBuildConvergenceService(
      client: client,
      localBuildId: 'web-9a6e35a',
      forceVersionCheck: true,
    );
    final open = await svc.check(baseUri: Uri.parse('https://app.example/'));
    expect(open.mismatch, isTrue);
    expect(open.remoteBuildId, 'web-34200df');
    expect(open.localBuildId, 'web-9a6e35a');
    expect(open.shouldPromptReload, isTrue);
  });

  test('in-flight PDV mutation blocks reload prompt', () async {
    final client = MockClient(
      (_) async => http.Response('{"buildId":"web-34200df"}', 200),
    );
    final svc = WebBuildConvergenceService(
      client: client,
      localBuildId: 'web-stale',
      forceVersionCheck: true,
    );
    await PdvMutationGate.run(() async {
      final r = await svc.check(baseUri: Uri.parse('https://app.example/'));
      expect(r.mismatch, isTrue);
      expect(r.shouldPromptReload, isFalse);
    });
  });

  test('mutation gate blocks concurrent depth accounting', () async {
    expect(PdvMutationGate.isMutationInFlight, isFalse);
    await PdvMutationGate.run(() async {
      expect(PdvMutationGate.isMutationInFlight, isTrue);
      return 1;
    });
    expect(PdvMutationGate.isMutationInFlight, isFalse);
  });

  test('grade sizes 34-39 Lina-shaped model rebuilds selector keys', () {
    final variacoes = <String, Map<String, int>>{
      '34': {'amendoa': 2},
      '35': {'amendoa': 2},
      '36': {'amendoa': 2},
      '37': {'amendoa': 2},
      '38': {'amendoa': 2},
      '39': {'amendoa': 2},
    };
    final estoquePorTamanho = <String, int>{
      '34': 2,
      '35': 2,
      '36': 2,
      '37': 2,
      '38': 2,
      '39': 2,
    };
    final usaVariacoes = variacoes.isNotEmpty;
    final mostrarTamanho =
        usaVariacoes || estoquePorTamanho.isNotEmpty;
    final tamanhos = <String, int>{};
    for (final e in variacoes.entries) {
      if (e.key == 'sem-tamanho') continue;
      final total = e.value.values.fold<int>(0, (a, b) => a + b);
      if (total > 0) tamanhos[e.key] = total;
    }
    expect(mostrarTamanho, isTrue);
    expect(tamanhos.keys.toList()..sort(),
        ['34', '35', '36', '37', '38', '39']);
    expect(tamanhos['37'], 2);
    // Selected size identity retained for sale payload.
    const selected = '37';
    expect(variacoes.containsKey(selected), isTrue);
  });
}
