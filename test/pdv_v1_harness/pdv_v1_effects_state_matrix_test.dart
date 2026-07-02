import 'package:flutter_test/flutter_test.dart';

import 'support/pdv_v1_contract.dart';
import 'support/pdv_v1_effects_catalog.dart';

void main() {
  group('PDV V1 — efeitos pós-baixa e subestados', () {
    test('catálogo contém efeitos auditados', () {
      expect(pdvV1EffectsCatalog.length, greaterThanOrEqualTo(10));
      final criticos = pdvV1EffectsCatalog
          .where((e) => e.classe == PdvV1EffectClass.criticalInTransaction);
      expect(criticos.length, 1);
    });

    test('combo cap não é best-effort — subestado obrigatório', () {
      final combo =
          pdvV1EffectsCatalog.firstWhere((e) => e.nome.contains('Combo cap'));
      expect(combo.classe, PdvV1EffectClass.postProcessIdempotent);
      expect(combo.subestadoObrigatorio, PdvV1EffectSubstate.comboCapCompleted);
      expect(combo.recoveryPossivel, isNotEmpty);
    });

    test('fiado exige chave idempotente saleId', () {
      final fiado = pdvV1EffectsCatalog
          .firstWhere((e) => e.nome.contains('Conta receber'));
      expect(fiado.chaveIdempotencia, contains('saleId'));
      expect(
          fiado.subestadoObrigatorio, PdvV1EffectSubstate.receivableCompleted);
    });

    test('efeito crítico pendente impede sync_completed', () {
      final substates = {
        PdvV1EffectSubstate.hiveSaleCompleted: true,
        PdvV1EffectSubstate.productCacheRefreshCompleted: true,
        PdvV1EffectSubstate.comboCapPending: true,
      };
      expect(pdvV1PodeMarcarSyncCompleted(substates), isFalse);
    });

    test('todos obrigatórios completos permitem sync_completed', () {
      final substates = {
        PdvV1EffectSubstate.hiveSaleCompleted: true,
        PdvV1EffectSubstate.productCacheRefreshCompleted: true,
        PdvV1EffectSubstate.comboCapCompleted: true,
        PdvV1EffectSubstate.syncRemoteCompleted: true,
      };
      expect(pdvV1PodeMarcarSyncCompleted(substates), isTrue);
    });

    test('efeito derivado declara mecanismo de recomposição', () {
      for (final e in pdvV1EffectsCatalog
          .where((x) => x.classe == PdvV1EffectClass.derivedRecomputable)) {
        expect(e.derivavel, isTrue);
        expect(e.recoveryPossivel, isNotEmpty);
      }
    });

    test('nenhum efeito crítico fora da TX principal', () {
      final foraTx = pdvV1EffectsCatalog.where((e) =>
          e.classe == PdvV1EffectClass.criticalInTransaction &&
          !e.nome.contains('marcador'));
      expect(foraTx, isEmpty);
    });
  });
}
