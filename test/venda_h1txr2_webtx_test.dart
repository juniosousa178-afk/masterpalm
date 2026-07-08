// H1TX-R2 — anel sem-cor/_sem_extra + marker + quantidade string (WEBTX).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/firestore_dynamic_map.dart';

void assertMarkerCompat({required Map<String, dynamic> data}) {
  final _ = data['baixaAplicada'];
}

Map<String, dynamic> variacoesAnelWebLike(int qtd) {
  return firestoreStringDynamicMapDeepOrEmpty(<String, Object?>{
    '15': <String, Object?>{
      'sem-cor': <String, Object?>{'_sem_extra': qtd},
    },
  });
}

int expressaoLegadaQuantidadeLinha1390(Map<String, dynamic> data) =>
    (data['quantidade'] as num?)?.toInt() ?? 0;

int expressaoCorrigidaQuantidade(Map<String, dynamic> data) =>
    firestoreIntFieldOrZero(data['quantidade']);

void main() {
  group('H1TXR2 — VM', () {
    test('WEBTX-ANEL deep normalize 3 niveis', () {
      final v = variacoesAnelWebLike(3);
      expect(v['15'], isA<Map<String, dynamic>>());
      final cor = v['15'] as Map<String, dynamic>;
      expect(cor['sem-cor'], isA<Map<String, dynamic>>());
    });

    test('WEBTX-RED marker implicit cast falha sem normalizar', () {
      final raw = Map<dynamic, dynamic>.from({'baixaAplicada': true});
      expect(
        () => assertMarkerCompat(data: raw as Map<String, dynamic>),
        throwsA(isA<TypeError>()),
      );
    });

    test('WEBTX-GREEN marker normalizado nao lanca', () {
      final raw = Map<dynamic, dynamic>.from({'baixaAplicada': true});
      expect(
        () => assertMarkerCompat(
          data: firestoreStringDynamicMapOrEmpty(raw),
        ),
        returnsNormally,
      );
    });

    test('WEBTX-RED quantidade string legado linha 1390', () {
      final data = <String, dynamic>{'quantidade': '19'};
      expect(
        () => expressaoLegadaQuantidadeLinha1390(data),
        throwsA(isA<TypeError>()),
      );
    });

    test('WEBTX-GREEN quantidade string coercao segura', () {
      final data = <String, dynamic>{'quantidade': '19'};
      expect(expressaoCorrigidaQuantidade(data), 19);
    });
  });

  group('H1TXR2 — dart2js probe', () {
    test('WEBTX dart2js probe R2 disponivel', () async {
      final result = await Process.run(
        'node',
        ['tools/h1txr2_probe.js'],
        runInShell: true,
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, 0);
      final out = '${result.stdout}';
      expect(out, contains('WEBTX-12 assertMarker param implicit cast: ERR'));
      expect(out, contains('WEBTX-RED linha1390 quantidade string: ERR'));
    });
  });
}
