// Baixa parcial/total de contas a receber com validação e histórico.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/conta_receber_dedup.dart';
import '../core/conta_receber_identity.dart';
import '../core/conta_receber_lancamento_vinculo.dart';
import '../core/conta_receber_venda_vinculo.dart';
import '../core/hive_box_names.dart';
import '../models/conta_receber.dart';
import 'conta_receber_firestore_service.dart';
import 'conta_receber_recebimento_caixa_service.dart';
import 'conta_receber_venda_backfill.dart';

class ResultadoBaixaContaReceber {
  final bool sucesso;
  final String? mensagemErro;
  final String? mensagemSucesso;
  final bool quitado;
  final double saldoRestante;

  const ResultadoBaixaContaReceber({
    required this.sucesso,
    this.mensagemErro,
    this.mensagemSucesso,
    this.quitado = false,
    this.saldoRestante = 0,
  });
}

class ContaReceberService {
  ContaReceberService._();

  /// Abre a box tipada da loja (obrigatório no Web para leitura correta).
  static Future<Box<ContaReceber>> openBoxLoja(String lojaId) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) {
      throw ArgumentError('lojaId vazio ao abrir contas a receber.');
    }
    if (!Hive.isAdapterRegistered(29)) {
      throw StateError(
        'ContaReceberAdapter (typeId 29) não registrado. Reinicie o app.',
      );
    }
    final name = HiveBoxNames.contasReceber(loja);

    if (Hive.isBoxOpen(name)) {
      try {
        return Hive.box<ContaReceber>(name);
      } catch (e, st) {
        debugPrint(
          '[CONTA_RECEBER_HIVE_FAIL] box=$name aberta com tipo incorreto '
          'type=${e.runtimeType} err=$e',
        );
        debugPrint('$st');
        try {
          await Hive.box(name).close();
        } catch (_) {}
      }
    }

    try {
      return await Hive.openBox<ContaReceber>(name);
    } catch (e, st) {
      debugPrint(
        '[CONTA_RECEBER_HIVE_FAIL] open box=$name type=${e.runtimeType} err=$e',
      );
      debugPrint('$st');
      if (kIsWeb) {
        await _repairBoxWeb(name);
        return Hive.openBox<ContaReceber>(name);
      }
      rethrow;
    }
  }

  /// Repara box corrompida no IndexedDB (mesmo padrão de Vendas/Clientes no Web).
  static Future<void> _repairBoxWeb(String boxName) async {
    if (!kIsWeb) return;
    try {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).close();
      }
      await Hive.deleteBoxFromDisk(boxName);
      debugPrint('[CONTA_RECEBER] repair web ok box=$boxName');
    } catch (e) {
      debugPrint(
        '[CONTA_RECEBER_HIVE_FAIL] repair web falhou box=$boxName type=${e.runtimeType} err=$e',
      );
    }
  }

  /// Conta pertence à loja (trim + legado sem lojaId na box por loja).
  static bool contaPertenceALoja(ContaReceber conta, String lojaId) {
    final loja = lojaId.trim();
    if (loja.isEmpty) return false;
    final cl = conta.lojaId.trim();
    return cl == loja || cl.isEmpty;
  }

  /// Listagem usada pela tela de contas a receber e resumos financeiros.
  /// [filtro]: pendentes | pagas | vencidas | todas
  static List<ContaReceber> listar({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    String filtro = 'todas',
  }) {
    final hoje = DateTime.now();
    var list = contas.where((c) => contaPertenceALoja(c, lojaId)).toList();
    list = list
        .where(
          (c) =>
              c.status.trim().toLowerCase() != ContaReceberStatus.cancelada,
        )
        .toList();
    list = deduplicarContasReceber(list);
    list.sort((a, b) => b.dataVencimento.compareTo(a.dataVencimento));
    switch (filtro) {
      case 'pendentes':
        list = list.where((c) => !c.pago && c.valor >= 0.01).toList();
        break;
      case 'vencidas':
        list = list
            .where(
              (c) =>
                  !c.pago &&
                  c.valor >= 0.01 &&
                  c.dataVencimento.isBefore(hoje),
            )
            .toList();
        break;
      case 'pagas':
        list = list.where((c) => c.pago).toList();
        break;
    }
    return list;
  }

  /// Cancela contas vinculadas à venda no Firestore e remove do Hive local (idempotente).
  static Future<int> cancelarContasReceberDaVenda({
    required String lojaId,
    int? vendaKey,
    String? vendaIdFirebase,
    String motivo = 'venda_excluida',
  }) async {
    final loja = lojaId.trim();
    final idV = (vendaIdFirebase ?? '').trim();
    final vk = vendaKey;
    if (loja.isEmpty) return 0;
    if (idV.isEmpty && (vk == null || vk < 0)) return 0;

    debugPrint(
      '[CR-CANCEL][INICIO] vendaId=$idV lojaId=$loja vendaKey=$vk',
    );

    if (idV.isNotEmpty) {
      await ContaReceberFirestoreService.cancelarContasReceberDaVenda(
        lojaId: loja,
        vendaIdFirebase: idV,
        motivo: motivo,
      );
    }

    final crBox = await openBoxLoja(loja);
    final keysToDelete = <dynamic>[];
    final idsLocais = <String>[];
    for (final k in crBox.keys) {
      final c = crBox.get(k);
      if (c == null) continue;
      if (!contaReceberVinculadaAVenda(
        conta: c,
        lojaId: loja,
        vendaKey: vk,
        vendaIdFirebase: idV,
      )) {
        continue;
      }
      final docId = resolveContaReceberDocId(c);
      if (docId.isNotEmpty && idV.isNotEmpty) {
        await ContaReceberFirestoreService.marcarCanceladaRemota(
          lojaId: loja,
          contaReceberDocId: docId,
          motivo: motivo,
        );
      }
      idsLocais.add(docId.isNotEmpty ? docId : 'hive:$k');
      keysToDelete.add(k);
    }

    debugPrint('[CR-CANCEL][LOCAL] ids=$idsLocais');
    for (final k in keysToDelete) {
      await crBox.delete(k);
    }

    debugPrint(
      '[CR-CANCEL][OK] vendaId=$idV removidas_local=${keysToDelete.length}',
    );
    return keysToDelete.length;
  }

  static void validarValorBaixa({
    required double valorRecebido,
    required double saldoRestante,
  }) {
    if (valorRecebido <= 1e-9) {
      throw ArgumentError('Informe um valor recebido maior que zero.');
    }
    if (valorRecebido > saldoRestante + 0.01) {
      throw ArgumentError('Valor recebido maior que o saldo em aberto.');
    }
  }

  /// Aplica baixa na conta (memória). Não grava Hive nem caixa.
  static void aplicarBaixaNaConta({
    required ContaReceber conta,
    required double valorRecebido,
    required String formaPagamento,
    required DateTime dataRecebimento,
    String? baixaId,
    String? referenciaFinanceira,
  }) {
    conta.normalizarCamposFinanceiros();
    validarValorBaixa(
      valorRecebido: valorRecebido,
      saldoRestante: conta.saldoRestante,
    );

    conta.valorPago += valorRecebido;
    conta.valor = (conta.saldoRestante - valorRecebido).clamp(0.0, double.infinity);
    if (conta.valor < 0.01) {
      conta.valor = 0;
    }
    conta.adicionarPagamentoHistorico(
      valorRecebido: valorRecebido,
      data: dataRecebimento,
      formaPagamento: formaPagamento,
      baixaId: baixaId,
      referenciaFinanceira: referenciaFinanceira,
    );
    conta.recalcularStatus();
  }

  /// Firestore como fonte remota: pull → backfill → publish conservador → pull final.
  static Future<ContaReceberPullResultado> sincronizarRemoto(String lojaId) async {
    final loja = lojaId.trim();
    debugPrint('[CR-SYNC][INICIO] lojaId=$loja');

    Box<ContaReceber>? boxAntes;
    try {
      boxAntes = await openBoxLoja(loja);
      final total = boxAntes.length;
      final maio = boxAntes.values.where((c) {
        final v = c.dataVencimento;
        return v.year == 2026 && v.month == 5;
      }).length;
      debugPrint('[CR-SYNC][HIVE-COUNT] total=$total maio=$maio');
    } catch (_) {}

    var pull = await _pullComRetry(loja);
    var totalImp = pull.importados;
    var totalAtt = pull.atualizados;
    var totalPul = pull.pulados;
    var totalErr = pull.erros;
    debugPrint(
      '[CR-PULL][REMOTE-COUNT] fase=pull_inicial importados=${pull.importados} '
      'atualizados=${pull.atualizados} pulados=${pull.pulados}',
    );

    final backfill =
        await ContaReceberVendaBackfillService.backfillFromVendasFiadas(loja);
    debugPrint(
      '[CR-BACKFILL][RESUMO] criadas=${backfill.criadas} existiam=${backfill.jaExistiam} '
      'ignoradas=${backfill.ignoradas} importadas_hive=${backfill.importadasHive}',
    );

    final pub =
        await ContaReceberFirestoreService.publicarContasHivePendentes(loja);
    debugPrint(
      '[CR-SYNC][PUBLICAR-PENDENTES] enviados=${pub.enviados} pulados=${pub.pulados}',
    );

    pull = await _pullComRetry(loja);
    totalImp += pull.importados;
    totalAtt += pull.atualizados;
    totalPul += pull.pulados;
    totalErr += pull.erros;
    debugPrint(
      '[CR-PULL][REMOTE-COUNT] fase=pull_final importados=${pull.importados} '
      'atualizados=${pull.atualizados} pulados=${pull.pulados}',
    );

    if (boxAntes != null && boxAntes.isOpen) {
      final deduped = deduplicarContasReceber(boxAntes.values.toList());
      if (deduped.length < boxAntes.length) {
        debugPrint(
          '[CR-SYNC][DUP-DETECTADO] hiveAntes=${boxAntes.length} '
          'aposDedupeSemantico=${deduped.length}',
        );
      }
    }

    return ContaReceberPullResultado(
      importados: totalImp,
      atualizados: totalAtt,
      pulados: totalPul,
      erros: totalErr,
    );
  }

  static Future<ContaReceberPullResultado> _pullComRetry(String loja) async {
    var pull = await ContaReceberFirestoreService.pullContasReceberRemotas(loja);
    for (var tentativa = 0;
        pull.ignoradoJaEmExecucao && tentativa < 8;
        tentativa++) {
      await Future.delayed(const Duration(milliseconds: 150));
      pull = await ContaReceberFirestoreService.pullContasReceberRemotas(loja);
    }
    return pull;
  }

  /// Registra recebimento no caixa e persiste a conta (Hive + Firestore).
  static Future<ResultadoBaixaContaReceber> registrarBaixa({    required ContaReceber conta,
    required double valorRecebido,
    required String formaPagamento,
    required String lojaId,
    required int contaHiveKey,
    int parcelaNumero = 1,
    DateTime? dataRecebimento,
  }) async {
    final quando = dataRecebimento ?? DateTime.now();

    await sincronizarRemoto(lojaId);

    if (conta.saldoRestante <= 1e-9) {
      return ResultadoBaixaContaReceber(
        sucesso: false,
        mensagemErro:
            'Esta conta já foi recebida (sincronizado de outro dispositivo).',
      );
    }

    try {
      validarValorBaixa(
        valorRecebido: valorRecebido,
        saldoRestante: conta.saldoRestante,
      );
    } on ArgumentError catch (e) {
      return ResultadoBaixaContaReceber(
        sucesso: false,
        mensagemErro: e.message?.toString() ?? e.toString(),
      );
    }

    final docId = resolveContaReceberDocId(conta);
    conta.garantirDocIdFirestore(docId);
    final publicado = await ContaReceberFirestoreService.publicarContaSeRemotoAusente(conta);
    if (!publicado) {
      return const ResultadoBaixaContaReceber(
        sucesso: false,
        mensagemErro:
            'Não foi possível sincronizar a conta com o servidor. Tente novamente.',
      );
    }

    final baixaId = baixaIdDeterministico(
      contaReceberId: docId,
      valor: valorRecebido,
      dataRecebimento: quando,
      formaPagamento: formaPagamento,
    );

    final remoto = await ContaReceberFirestoreService.registrarBaixaRemota(
      lojaId: lojaId,
      conta: conta,
      valorRecebido: valorRecebido,
      formaPagamento: formaPagamento,
      dataRecebimento: quando,
      referenciaFinanceira: referenciaExternaContaReceberFirestore(
        contaReceberDocId: docId,
        baixaId: baixaId,
      ),
    );
    if (!remoto.sucesso) {
      return ResultadoBaixaContaReceber(
        sucesso: false,
        mensagemErro: remoto.mensagemErro ??
            'Não foi possível registrar a baixa no servidor.',
      );
    }

    if (remoto.idempotente) {
      await sincronizarRemoto(lojaId);
      return ResultadoBaixaContaReceber(
        sucesso: false,
        mensagemErro:
            'Esta baixa já foi registrada (sincronizado de outro dispositivo).',
      );
    }

    final docIdFin = await ContaReceberRecebimentoCaixaService.registrarRecebimento(
      lojaId: lojaId,
      valor: valorRecebido,
      formaPagamento: formaPagamento,
      clienteNome: conta.clienteNome,
      observacaoConta: conta.observacao,
      conta: conta,
      contaHiveKey: contaHiveKey,
      parcelaNumero: parcelaNumero,
      dataRecebimento: quando,
      contaReceberDocId: docId,
      baixaId: baixaId,
    );
    if (docIdFin == null) {
      return const ResultadoBaixaContaReceber(
        sucesso: false,
        mensagemErro: 'Não foi possível registrar o recebimento no caixa.',
      );
    }

    aplicarBaixaNaConta(
      conta: conta,
      valorRecebido: valorRecebido,
      formaPagamento: formaPagamento,
      dataRecebimento: quando,
      baixaId: baixaId,
      referenciaFinanceira: docIdFin,
    );
    await conta.save();
    await ContaReceberFirestoreService.upsertContaReceber(
      conta,
      lastWriteOrigin: 'baixa_local',
    );
    final quitado = conta.pago;
    final saldo = conta.saldoRestante;
    final msg = quitado
        ? 'Recebimento registrado. Conta quitada.'
        : 'Pagamento parcial registrado. Saldo restante: R\$ ${saldo.toStringAsFixed(2).replaceAll('.', ',')}.';

    return ResultadoBaixaContaReceber(
      sucesso: true,
      mensagemSucesso: msg,
      quitado: quitado,
      saldoRestante: saldo,
    );
  }
}
