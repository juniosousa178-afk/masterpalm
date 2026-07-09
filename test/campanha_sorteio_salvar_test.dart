// M3.7 — campanha não salva: guard de campanha ativa + status sorteada.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/campanhas_sorteio_service.dart';

const _lojaId = 'loja-campanha-salvar-test';

Future<void> _seedCampanha(
  FakeFirebaseFirestore fs, {
  required String id,
  bool ativa = true,
  String status = 'aberta',
  DateTime? inicio,
  DateTime? fim,
}) async {
  final now = DateTime.now();
  await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection('campanhas_sorteio')
      .doc(id)
      .set({
    'nome': 'Campanha $id',
    'ativa': ativa,
    'status': status,
    'dataInicio': Timestamp.fromDate(inicio ?? now.subtract(const Duration(days: 1))),
    'dataFim': Timestamp.fromDate(fim ?? now.add(const Duration(days: 30))),
  });
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    CampanhasSorteioService.debugFirestoreOverride = firestore;
  });

  tearDown(() {
    CampanhasSorteioService.debugFirestoreOverride = null;
  });

  group('M3.7 campanha salvar — listarCampanhasAtivas', () {
    test('RED legado: sorteada+ativa=true não deve bloquear nova campanha', () async {
      await _seedCampanha(
        firestore,
        id: 'camp-sorteada',
        ativa: true,
        status: 'sorteada',
      );

      final ativas = await CampanhasSorteioService.listarCampanhasAtivas(
        lojaId: _lojaId,
      );

      expect(ativas, isEmpty);
    });

    test('GREEN: campanha aberta no período continua bloqueando', () async {
      await _seedCampanha(
        firestore,
        id: 'camp-aberta',
        ativa: true,
        status: 'aberta',
      );

      final ativas = await CampanhasSorteioService.listarCampanhasAtivas(
        lojaId: _lojaId,
      );

      expect(ativas, hasLength(1));
      expect(ativas.first['id'], 'camp-aberta');
    });

    test('pausada e finalizada não entram na lista de bloqueio', () async {
      await _seedCampanha(
        firestore,
        id: 'camp-pausada',
        ativa: false,
        status: 'pausada',
      );
      await _seedCampanha(
        firestore,
        id: 'camp-finalizada',
        ativa: true,
        status: 'finalizada',
      );

      final ativas = await CampanhasSorteioService.listarCampanhasAtivas(
        lojaId: _lojaId,
      );

      expect(ativas, isEmpty);
    });
  });

  group('M3.7 campanha salvar — payload Firestore', () {
    test('salvarCampanha create grava path e campos esperados', () async {
      final inicio = DateTime(2026, 7, 1);
      final fim = DateTime(2026, 7, 31);
      final sorteio = DateTime(2026, 8, 1);

      await CampanhasSorteioService.salvarCampanha(
        lojaId: _lojaId,
        nome: 'Campanha Homolog',
        descricao: 'Teste H8',
        dataInicio: inicio,
        dataFim: fim,
        dataSorteio: sorteio,
        premioDescricao: 'Brinde',
        valorMinimo: 100,
        valorXPorNumero: 50,
        ativa: true,
      );

      final snap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('campanhas_sorteio')
          .get();

      expect(snap.docs, hasLength(1));
      final data = snap.docs.first.data();
      expect(data['nome'], 'Campanha Homolog');
      expect(data['status'], 'aberta');
      expect(data['ativa'], isTrue);
      expect(data['valorX'], 50.0);
      expect(data['valorMinimo'], 100.0);
    });
  });
}
