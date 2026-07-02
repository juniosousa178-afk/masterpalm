import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_canonical_json.dart';

// jsonEncode usado apenas para comparar escaping de String isolada (testes 6 e 7).

void main() {
  group('pdvV1CanonicalJsonEncode', () {
    test('1. ordena chaves de Map inseridas em ordem diferente', () {
      final a = pdvV1CanonicalJsonEncode(<String, Object>{'b': 2, 'a': 1});
      final b = pdvV1CanonicalJsonEncode(<String, Object>{'a': 1, 'b': 2});
      expect(a, '{"a":1,"b":2}');
      expect(b, a);
    });

    test('2. preserva ordem de List', () {
      final encoded = pdvV1CanonicalJsonEncode(<Object>[
        <String, Object>{'z': 1},
        <String, Object>{'a': 2},
      ]);
      expect(encoded, '[{"z":1},{"a":2}]');
    });

    test('3. vetor A literal', () {
      const canonical = '{"a":1,"b":2}';
      const expectedSha =
          '43258cff783fe7036d8a43033f830adfc60ec037382473548ac742b888292777';
      expect(
        pdvV1CanonicalJsonEncode(<String, Object>{'a': 1, 'b': 2}),
        canonical,
      );
      expect(pdvV1Sha256HexUtf8(canonical), expectedSha);
      expect(
        pdvV1CanonicalSha256(<String, Object>{'a': 1, 'b': 2}),
        expectedSha,
      );
    });

    test('4. vetor B literal', () {
      const canonical = '[{"productId":"prod-001","quantidade":2}]';
      const expectedSha =
          '54057fe86061142af70fd516bea621352587b3f611ecb969faa8b07c90584b97';
      final value = <Map<String, Object>>[
        <String, Object>{
          'productId': 'prod-001',
          'quantidade': 2,
        },
      ];
      expect(pdvV1CanonicalJsonEncode(value), canonical);
      expect(pdvV1Sha256HexUtf8(canonical), expectedSha);
      expect(pdvV1CanonicalSha256(value), expectedSha);
    });

    test('5. vetor C literal', () {
      const canonical =
          '{"lojaId":"loja-a","operationId":"op-001","origem":"pdv","protocolVersion":1,"saleId":"op-001","txItems":[{"productId":"prod-001","quantidade":2}],"txItemsHash":"54057fe86061142af70fd516bea621352587b3f611ecb969faa8b07c90584b97"}';
      const expectedSha =
          '1297da35da51a9e77d643d73b06db76be48a323bcd04612cb9d95c1d23421065';
      final value = <String, Object>{
        'protocolVersion': 1,
        'operationId': 'op-001',
        'saleId': 'op-001',
        'lojaId': 'loja-a',
        'origem': 'pdv',
        'txItemsHash':
            '54057fe86061142af70fd516bea621352587b3f611ecb969faa8b07c90584b97',
        'txItems': <Map<String, Object>>[
          <String, Object>{
            'productId': 'prod-001',
            'quantidade': 2,
          },
        ],
      };
      expect(pdvV1CanonicalJsonEncode(value), canonical);
      expect(pdvV1Sha256HexUtf8(canonical), expectedSha);
      expect(pdvV1CanonicalSha256(value), expectedSha);
    });

    test('6. String Unicode sem normalização', () {
      const original = 'ação café';
      final encoded = pdvV1CanonicalJsonEncode(original);
      expect(encoded, '"ação café"');
      expect(encoded, jsonEncode(original));
    });

    test('7. String com aspas, barra e quebra de linha', () {
      const original = '"\\/\n';
      final encoded = pdvV1CanonicalJsonEncode(original);
      expect(encoded, jsonEncode(original));
      expect(encoded, contains(r'\"'));
      expect(encoded, contains(r'\\'));
      expect(encoded, contains(r'\n'));
    });

    test('8. rejeita double 1.0', () {
      expect(
        () => pdvV1CanonicalJsonEncode(1.0),
        throwsA(isA<PdvV1CanonicalJsonError>()),
      );
    });

    test('9. rejeita DateTime', () {
      expect(
        () => pdvV1CanonicalJsonEncode(DateTime.utc(2024, 1, 1)),
        throwsA(isA<PdvV1CanonicalJsonError>()),
      );
    });

    test('10. rejeita Set', () {
      expect(
        () => pdvV1CanonicalJsonEncode(<int>{1}),
        throwsA(isA<PdvV1CanonicalJsonError>()),
      );
    });

    test('11. rejeita Map com chave não String', () {
      expect(
        () => pdvV1CanonicalJsonEncode(<Object, Object>{1: 'a'}),
        throwsA(isA<PdvV1CanonicalJsonError>()),
      );
    });

    test('12. rejeita objeto customizado', () {
      expect(
        () => pdvV1CanonicalJsonEncode(_CustomValue()),
        throwsA(isA<PdvV1CanonicalJsonError>()),
      );
    });

    test('13. Maps em ordens distintas produzem JSON e hash idênticos', () {
      final mapA = <String, Object>{
        'z': 3,
        'a': 1,
        'm': 2,
      };
      final mapB = <String, Object>{
        'a': 1,
        'm': 2,
        'z': 3,
      };
      final jsonA = pdvV1CanonicalJsonEncode(mapA);
      final jsonB = pdvV1CanonicalJsonEncode(mapB);
      expect(jsonA, jsonB);
      expect(pdvV1CanonicalSha256(mapA), pdvV1CanonicalSha256(mapB));
    });

    test('14. três execuções idênticas retornam resultado idêntico', () {
      final value = <String, Object>{'a': 1, 'b': 2};
      final results = List.generate(
        3,
        (_) => pdvV1CanonicalSha256(value),
      );
      expect(results[0], results[1]);
      expect(results[1], results[2]);
    });
  });
}

class _CustomValue {
  @override
  String toString() => 'custom';
}
