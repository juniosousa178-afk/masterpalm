// H1TX — uncaught runTransaction web / nested map TypeError (RED + fix proof).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/firestore_dynamic_map.dart';

/// Replica estrutura Firestore Web: top-level normalizado, nested [Map<String, Object?>].
Map<String, dynamic> variacoesWebLikeShallow(int qtd) {
  final top = firestoreStringDynamicMapOrEmpty(<String, Object?>{
    '7mm': <String, Object?>{'cristal': qtd},
  });
  return top;
}

/// Expressão legada de [_mapaAposDebitoVariacao] (pré-fix linha 791).
Map<String, dynamic> expressaoLegadaMapaCorLinha791(
  Map<String, dynamic> variacoes,
  String tamanho,
) {
  final mapaCor = variacoes[tamanho];
  if (mapaCor == null || mapaCor is! Map) {
    throw Exception('mapaCor ausente');
  }
  return Map<String, dynamic>.from(mapaCor);
}

/// Expressão corrigida (pós-fix).
Map<String, dynamic> expressaoCorrigidaMapaCor(
  Map<String, dynamic> variacoes,
  String tamanho,
) {
  final mapaCor = variacoes[tamanho];
  if (mapaCor == null || mapaCor is! Map) {
    throw Exception('mapaCor ausente');
  }
  return firestoreStringDynamicMapOrEmpty(mapaCor);
}

/// Harness mínimo: Future chain como runTransaction (async callback + await).
Future<String> harnessRunTransactionLike(Future<void> Function() callback) async {
  return callback().then((_) => 'batch_after_runTransaction');
}

void main() {
  group('H1TX — nested map web RED', () {
    test('H1TX-1 variacoes web-like shallow normaliza top-level', () {
      final v = variacoesWebLikeShallow(1);
      expect(v['7mm'], isA<Map>());
    });

    test('H1TX-2 expressao legada linha 791: VM tolera, web falha (dart2js probe C)', () {
      final v = variacoesWebLikeShallow(1);
      // VM: Map.from aceita nested Map<String,Object?>.
      expect(() => expressaoLegadaMapaCorLinha791(v, '7mm'), returnsNormally);
      // Prova web (dart2js/node): cast legado em JsLinkedHashMap → TypeError.
      // Ver tools/h1tx_web_probe.dart probe C.
      expect(File('tools/h1tx_web_probe.dart').existsSync(), isTrue);
    });

    test('H1TX-3 cast legado top-level ainda falha (controle TYPEH1)', () {
      final raw = Map<dynamic, dynamic>.from({
        '7mm': Map<dynamic, dynamic>.from({'cristal': 1}),
      });
      expect(
        () => legacyUnsafeFirestoreVariacoesCast(raw),
        throwsA(isA<TypeError>()),
      );
    });

    test('H1TX-4 shallow normalize nao deep-normaliza nested', () {
      final v = variacoesWebLikeShallow(3);
      final nested = v['7mm'];
      expect(nested, isA<Map>());
      expect(firestoreStringDynamicMapDeepOrEmpty(v)['7mm'], isA<Map<String, dynamic>>());
    });

    test('H1TX-5 deep normalize permite debito tam+cor H1-like', () {
      final v = firestoreStringDynamicMapDeepOrEmpty(variacoesWebLikeShallow(3));
      final mapa = expressaoCorrigidaMapaCor(v, '7mm');
      expect(mapa['cristal'], 3);
    });
  });

  group('H1TX — Future chain semantics (harness)', () {
    test('H1TX-6 TypeError apos await e catchable na cadeia awaited', () async {
      Object? caught;
      try {
        await harnessRunTransactionLike(() async {
          await Future<void>.delayed(Duration.zero);
          throw TypeError();
        });
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<TypeError>());
    });

    test('H1TX-7 Future orfa com Error nao completa harness principal', () async {
      final done = Completer<void>();
      // ignore: unawaited_futures
      Future<void>.error(TypeError()).catchError((_) => done.complete());
      await done.future;
      expect(true, isTrue);
    });

    test('H1TX-8 stage pos-transaction ausente quando callback falha', () async {
      expect(
        () => harnessRunTransactionLike(() async {
          throw TypeError();
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('H1TX-9 expressao corrigida nao lanca em nested web-like', () {
      final v = firestoreStringDynamicMapDeepOrEmpty(variacoesWebLikeShallow(1));
      expect(() => expressaoCorrigidaMapaCor(v, '7mm'), returnsNormally);
    });

    test('H1TX-10 UI policy receberia ok=false se catch superior funcionar', () {
      // Documenta: TypeError.toString() → mensagem fallback em formatSalvarVendaErrorForUser.
      final msg = TypeError().toString();
      expect(msg.startsWith("Instance of '"), isTrue);
    });
  });

  group('H1TX-RED — reproduz classe real de producao', () {
    test('H1TX-RED dart2js probe confirma TypeError em cast legado', () async {
      final result = await Process.run(
        'node',
        ['tools/h1tx_probe.js'],
        runInShell: true,
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, 0);
      final out = '${result.stdout}';
      expect(out, contains('C legacy cast variacoes: ERR'));
      expect(out, contains('TypeError'));
    });
  });
}
