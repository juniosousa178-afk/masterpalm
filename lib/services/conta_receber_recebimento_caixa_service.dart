// Registra recebimento de contas a receber no módulo financeiro (entrada no fluxo de caixa).

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/conta_receber_identity.dart';
import '../core/conta_receber_lancamento_vinculo.dart';
import '../core/financeiro_lancamento_duplicidade_resolver.dart';
import '../financeiro/financeiro_constants.dart';
import '../models/conta_receber.dart';
import '../models/lancamento_financeiro.dart';
import 'financeiro_firestore_service.dart';
import 'financeiro_hive_store.dart';

class ContaReceberRecebimentoCaixaService {
  ContaReceberRecebimentoCaixaService._();

  static List<double> parcelarValores(double total, int parcelas) {
    final qtd = parcelas.clamp(1, 48);
    final totalCentavos = (total * 100).round();
    final base = totalCentavos ~/ qtd;
    final resto = totalCentavos % qtd;
    return List<double>.generate(
      qtd,
      (i) => (base + (i < resto ? 1 : 0)) / 100.0,
    );
  }

  /// Grava [entrada_extra] paga na [dataRecebimento]. Retorna id do LF ou null se falhou.
  /// Idempotente: mesmo recebimento (conta estável ou Hive key, parcela, valor, dia) não duplica.
  static Future<String?> registrarRecebimento({
    required String lojaId,
    required double valor,
    required String formaPagamento,
    required String clienteNome,
    String observacaoConta = '',
    required ContaReceber conta,
    required int contaHiveKey,
    int parcelaNumero = 1,
    DateTime? dataRecebimento,
    String? contaReceberDocId,
    String? baixaId,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty || valor <= 1e-9) return null;

    final box = await FinanceiroHiveStore.openLancamentosBox(loja);
    if (box == null) {
      debugPrint('[CR-CAIXA] Box lançamentos indisponível (loja=$loja)');
      return null;
    }

    final quando = dataRecebimento ?? DateTime.now();
    final parcela = parcelaNumero.clamp(1, 999);

    final docIdConta = (contaReceberDocId ?? resolveContaReceberDocId(conta)).trim();
    final bx = (baixaId ?? '').trim();

    final ids = idsRecebimentoContaReceber(
      conta: conta,
      contaHiveKey: contaHiveKey,
      parcelaNumero: parcela,
      valor: valor,
      dataRecebimento: quando,
      contaReceberDocId: docIdConta.isNotEmpty ? docIdConta : null,
      baixaId: bx.isNotEmpty ? bx : null,
    );
    var docId = ids.docId;
    var ref = ids.ref;

    if (docId == 'mp_cr_invalido' || ref.isEmpty) {
      debugPrint(
        '[CR-CAIXA] Conta sem id estável nem Hive key — recebimento sem idempotência forte.',
      );
      final ms = DateTime.now().millisecondsSinceEpoch;
      docId = 'mp_cr_orfao_$ms';
      ref = 'cr_receb:orfao:$ms';
    }

    final existente = box.get(docId);
    if (existente != null &&
        existente.status == FinanceiroStatusLancamento.pago &&
        valoresParecidosRecebimento(existente.valor, valor)) {
      debugPrint('[CR-CAIXA] Recebimento já registrado docId=$docId — idempotente.');
      return docId;
    }

    for (final l in box.values) {
      if (l.lojaId != loja) continue;
      if (ref.isNotEmpty &&
          l.referenciaExterna.trim() == ref &&
          l.status == FinanceiroStatusLancamento.pago) {
        debugPrint('[CR-CAIXA] Ref $ref já recebida — idempotente.');
        return l.id;
      }
      // Cross-device: mesmo recebimento estável com docId legado diferente.
      if (contaReceberStableId(conta).isNotEmpty) {
        final parsed = recebimentoRefFromLancamento(l);
        final alvo = parseReferenciaExternaContaReceber(ref);
        if (parsed != null &&
            alvo != null &&
            parsed.isStable &&
            alvo.isStable &&
            parsed.stableId == alvo.stableId &&
            parsed.parcelaNumero == alvo.parcelaNumero &&
            parsed.centavos == alvo.centavos &&
            parsed.dia == alvo.dia &&
            l.status == FinanceiroStatusLancamento.pago) {
          debugPrint('[CR-CAIXA] Recebimento estável já existe id=${l.id} — idempotente.');
          return l.id;
        }
      }
    }

    String usuarioNome = '';
    String usuarioId = '';
    try {
      final sessao = await Hive.openBox('sessao');
      usuarioNome = (sessao.get('usuario_logado') ?? '').toString().trim();
      usuarioId = usuarioNome;
    } catch (_) {}

    final obsConta = observacaoConta.trim();
    final l = LancamentoFinanceiro(
      id: docId,
      lojaId: loja,
      descricao: 'Recebimento — $clienteNome',
      valor: valor,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      categoria: 'recebimentos_fiado',
      subcategoria: '',
      status: FinanceiroStatusLancamento.pago,
      formaPagamento: formaPagamento.trim(),
      fornecedor: '',
      observacao: obsConta.isEmpty
          ? 'Conta a receber'
          : 'Conta a receber · $obsConta',
      dataLancamento: quando,
      dataPagamento: quando,
      competenciaMes: quando.month,
      competenciaAno: quando.year,
      recorrente: false,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      usuarioId: usuarioId,
      usuarioNome: usuarioNome,
      referenciaExterna: ref,
    );

    final dupExistente = FinanceiroLancamentoDuplicidadeResolver
        .encontrarDuplicataExistente(
      candidato: l,
      lancamentos: box.values,
      lojaId: loja,
    );
    if (dupExistente != null && dupExistente.id.trim() != docId) {
      debugPrint(
        '[FIN-DUP][ANTI-DUP-BAIXA-CR] mantém id=${dupExistente.id} '
        'ignorando docId=$docId ref=$ref',
      );
      return dupExistente.id;
    }

    await box.put(docId, l);
    try {
      await FinanceiroFirestoreService.upsertLancamento(l);
    } catch (e) {
      debugPrint(
        '[CR-CAIXA] Sync Firestore falhou (type=${e.runtimeType})',
      );
    }
    return docId;
  }

  static bool valoresParecidosRecebimento(double a, double b) =>
      (a - b).abs() < 0.02;
}
