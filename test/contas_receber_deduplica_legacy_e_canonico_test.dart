// Legado + canônico da mesma parcela não duplicam na listagem.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/conta_receber_dedup.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_service.dart';

void main() {
  const lojaId = 'loja-dedup-legacy-canon';
  const vendaId = 'venda-dedup-uuid-maio';

  test('dedupe mantém canônico cr_{vendaId}_p1 e oculta cr_legacy', () {
    final legacy = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Maria',
      valor: 50,
      valorOriginal: 50,
      dataVencimento: DateTime(2026, 5, 20),
      dataVenda: DateTime(2026, 5, 10),
      parcelaNumero: 1,
      parcelaTotal: 1,
    );
    normalizarContaReceberId(legacy);
    expect((legacy.idFirebase ?? '').startsWith('cr_legacy_'), isTrue);

    final canon = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Maria',
      valor: 50,
      valorOriginal: 50,
      dataVencimento: DateTime(2026, 5, 20),
      dataVenda: DateTime(2026, 5, 10),
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
      parcelaTotal: 1,
    );
    normalizarContaReceberId(canon);
    expect(canon.idFirebase, 'cr_${vendaId}_p1');

    final list = ContaReceberService.listar(
      contas: [legacy, canon],
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(list.length, 1);
    expect(list.first.vendaIdFirebase, vendaId);
    expect(list.first.idFirebase, 'cr_${vendaId}_p1');
  });
}
