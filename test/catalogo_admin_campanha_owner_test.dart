// M3.6.3 — ownership de campanha/sorteio no fluxo admin de pré-pedidos.
// CAMP-1…CAMP-12 (cenários aplicáveis ao Dart local).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/sorteio_numero_service.dart';

const _lojaId = 'loja-campa-owner';
const _vendaId = 'venda-admin-42';
const _vendaId2 = 'venda-admin-43';
const _campA = 'campanha-a';
const _campB = 'campanha-b';

Future<void> _seedCampanha(
  FakeFirebaseFirestore fs, {
  required String campanhaId,
  double valorMinimo = 50,
}) async {
  final now = DateTime.now();
  await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection('campanhas_sorteio')
      .doc(campanhaId)
      .set({
    'ativa': true,
    'valorMinimo': valorMinimo,
    'dataInicio': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
    'dataFim': Timestamp.fromDate(now.add(const Duration(days: 30))),
    'nome': 'Campanha $campanhaId',
  });
}

Future<void> _seedParticipacaoEngine(
  FakeFirebaseFirestore fs, {
  required String campanhaId,
  required String vendaId,
  String numero = '54321',
}) async {
  await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection('campanhas_sorteio')
      .doc(campanhaId)
      .collection('participantes')
      .add({
    'numeroSorte': numero,
    'pedidoId': vendaId,
    'vendaId': vendaId,
    'clienteNome': 'Cliente Engine',
    'valorPedido': 100.0,
    'status': 'valido',
    'origem': 'catalogo',
    'sorteado': false,
  });
}

Future<int> _countParticipantes(
  FakeFirebaseFirestore fs, {
  String? campanhaId,
}) async {
  final campanhas = campanhaId != null
      ? [
          await fs
              .collection('lojas')
              .doc(_lojaId)
              .collection('campanhas_sorteio')
              .doc(campanhaId)
              .get(),
        ]
      : (await fs
              .collection('lojas')
              .doc(_lojaId)
              .collection('campanhas_sorteio')
              .get())
          .docs;

  var total = 0;
  for (final camp in campanhas) {
    if (!camp.exists) continue;
    final parts = await camp.reference.collection('participantes').get();
    total += parts.docs.length;
  }
  return total;
}

Future<bool> _registrarSorteio({
  required String vendaId,
  double valor = 100,
  String numero = '11111',
}) {
  return SorteioNumeroService.registrarNumeroEmCampanhas(
    lojaId: _lojaId,
    clienteNome: 'Cliente Pos',
    valorCompra: valor,
    dataCompra: DateTime.now(),
    numeroSorte: numero,
    vendaIdOuPedidoId: vendaId,
  );
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    SorteioNumeroService.debugFirestoreOverride = firestore;
  });

  tearDown(() {
    SorteioNumeroService.debugFirestoreOverride = null;
  });

  group('M3.6.3 CAMP — admin CampaignEngine + SorteioNumero', () {
    test('CAMP-1: após participação do Engine, SorteioNumero não duplica', () async {
      await _seedCampanha(firestore, campanhaId: _campA);
      await _seedParticipacaoEngine(
        firestore,
        campanhaId: _campA,
        vendaId: _vendaId,
      );

      final registrou = await _registrarSorteio(vendaId: _vendaId);

      expect(registrou, isFalse);
      expect(await _countParticipantes(firestore, campanhaId: _campA), 1);
    });

    test('CAMP-2: mesma vendaId 2× em SorteioNumero gera 1 participação', () async {
      await _seedCampanha(firestore, campanhaId: _campA);

      expect(await _registrarSorteio(vendaId: _vendaId, numero: '22222'), isTrue);
      expect(await _registrarSorteio(vendaId: _vendaId, numero: '33333'), isFalse);
      expect(await _countParticipantes(firestore, campanhaId: _campA), 1);
    });

    test('CAMP-4: venda abaixo do valor mínimo não gera participação', () async {
      await _seedCampanha(firestore, campanhaId: _campA, valorMinimo: 200);

      final registrou = await _registrarSorteio(vendaId: _vendaId, valor: 50);

      expect(registrou, isFalse);
      expect(await _countParticipantes(firestore, campanhaId: _campA), 0);
    });

    test('CAMP-7: campanha A já coberta pelo Engine; B ainda elegível', () async {
      await _seedCampanha(firestore, campanhaId: _campA);
      await _seedCampanha(firestore, campanhaId: _campB);
      await _seedParticipacaoEngine(
        firestore,
        campanhaId: _campA,
        vendaId: _vendaId,
      );

      expect(await _registrarSorteio(vendaId: _vendaId), isTrue);

      expect(await _countParticipantes(firestore, campanhaId: _campA), 1);
      expect(await _countParticipantes(firestore, campanhaId: _campB), 1);
    });

    test('CAMP-12: vendas distintas geram participações independentes', () async {
      await _seedCampanha(firestore, campanhaId: _campA);

      expect(await _registrarSorteio(vendaId: _vendaId, numero: '44444'), isTrue);
      expect(await _registrarSorteio(vendaId: _vendaId2, numero: '55555'), isTrue);

      expect(await _countParticipantes(firestore, campanhaId: _campA), 2);
    });

    test('CAMP-8: retry após participação persistida não duplica', () async {
      await _seedCampanha(firestore, campanhaId: _campA);
      await _seedParticipacaoEngine(
        firestore,
        campanhaId: _campA,
        vendaId: _vendaId,
      );

      for (var i = 0; i < 3; i++) {
        await _registrarSorteio(vendaId: _vendaId, numero: '9$i$i$i$i');
      }

      expect(await _countParticipantes(firestore, campanhaId: _campA), 1);
    });
  });
}
