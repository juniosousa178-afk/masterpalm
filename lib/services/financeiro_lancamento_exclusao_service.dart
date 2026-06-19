// Exclusão manual e estorno de baixa de Contas a Receber no módulo financeiro.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/conta_pagar_lancamento_vinculo.dart';
import '../core/conta_receber_identity.dart';
import '../core/conta_receber_lancamento_vinculo.dart';
import '../core/financeiro_lancamento_acao.dart';
import '../core/financeiro_lancamento_legacy_resolver.dart';
import '../financeiro/financeiro_constants.dart';
import '../models/conta_receber.dart';
import '../models/lancamento_financeiro.dart';
import 'conta_receber_financeiro_sync_service.dart';
import 'conta_receber_service.dart';
import 'financeiro_firestore_service.dart';
import 'financeiro_hive_store.dart';
import 'financeiro_service.dart';

class FinanceiroLancamentoExclusaoResultado {
  const FinanceiroLancamentoExclusaoResultado({
    required this.sucesso,
    this.idempotente = false,
    this.bloqueado = false,
    this.mensagemErro,
    this.contaReceberAtualizada = false,
    this.legado = false,
    this.apenasLocal = false,
  });

  final bool sucesso;
  final bool idempotente;
  final bool bloqueado;
  final String? mensagemErro;
  final bool contaReceberAtualizada;
  final bool legado;
  /// Exclusão aplicada só no Hive (sem doc remoto ou Firestore indisponível).
  final bool apenasLocal;
}

abstract final class FinanceiroLancamentoExclusaoService {
  FinanceiroLancamentoExclusaoService._();

  static const _msgSemVinculo =
      'Não foi possível estornar automaticamente porque o vínculo com a parcela não foi encontrado com segurança.';

  static const msgEstornoSemVinculoComOpcaoExclusao =
      'Não foi possível estornar automaticamente porque o vínculo com a parcela não foi encontrado com segurança.\n'
      'Você pode excluir somente o lançamento financeiro, se deseja apenas remover este registro dos relatórios.';

  static const msgModalExcluirSomenteFinanceiroCr =
      'Este lançamento antigo foi gerado por Conta a Receber, mas não possui vínculo seguro com a parcela.\n\n'
      'Você pode excluir somente o lançamento financeiro. Essa ação removerá o valor dos relatórios financeiros, '
      'mas não vai reabrir a parcela em Contas a Receber.\n\n'
      'Deseja continuar?';

  static const msgModalGestaoExcluirSomenteFinanceiroCr = msgModalExcluirSomenteFinanceiroCr;

  static const msgSucessoExcluirSomenteFinanceiro =
      'Lançamento financeiro excluído com segurança. A parcela em Contas a Receber não foi alterada.';

  static bool lancamentoExcluivelNaUi(LancamentoFinanceiro l) {
    if (!FinanceiroStatusLancamento.statusLiquidado(l.status)) return false;
    if (lancamentoVinculadoAContaPagar(l)) return false;
    return true;
  }

  static FinanceiroLancamentoAcaoInfo acaoParaUi(
    LancamentoFinanceiro l, {
    Iterable<ContaReceber> contas = const [],
    String lojaId = '',
  }) =>
      FinanceiroLancamentoAcaoResolver.resolver(
        l,
        contas: contas,
        lojaId: lojaId,
      );

  static bool lancamentoEhBaixaContaReceber(LancamentoFinanceiro l) =>
      FinanceiroLancamentoLegacyResolver.pareceBaixaContaReceber(l);

  static FinanceiroLancamentoLegadoInfo infoLegado(
    LancamentoFinanceiro l, {
    Iterable<ContaReceber> contas = const [],
    String lojaId = '',
  }) =>
      FinanceiroLancamentoLegacyResolver.classificar(
        l,
        contas: contas,
        lojaId: lojaId,
      );

  static Future<Iterable<ContaReceber>> _contasReceberLoja(String lojaId) async {
    try {
      final box = await ContaReceberService.openBoxLoja(lojaId);
      return box.values;
    } catch (e) {
      debugPrint('[FIN-LEGACY] CR box indisponível (type=${e.runtimeType})');
      return const [];
    }
  }

  static Future<String> _usuarioAtual() async {
    try {
      final sessao = await Hive.openBox('sessao');
      return (sessao.get('usuario_logado') ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  static LancamentoFinanceiro? _buscarNoHive(
    Box<LancamentoFinanceiro> box,
    LancamentoFinanceiro alvo,
  ) {
    if (alvo.key != null && box.containsKey(alvo.key)) {
      final porChave = box.get(alvo.key);
      if (porChave != null) return porChave;
    }
    final id = alvo.id.trim();
    if (id.isNotEmpty) {
      final direto = box.get(id);
      if (direto != null) return direto;
    }
    return FinanceiroLancamentoLegacyResolver.buscarNoHive(box.values, alvo);
  }

  static bool _aindaNoHive(
    Box<LancamentoFinanceiro> box,
    LancamentoFinanceiro alvo,
  ) {
    if (alvo.key != null && box.containsKey(alvo.key)) return true;
    final id = alvo.id.trim();
    if (id.isNotEmpty && box.containsKey(id)) return true;
    for (final v in box.values) {
      if (identical(v, alvo)) return true;
      if (alvo.key != null && v.key == alvo.key) return true;
      if (id.isNotEmpty && v.id.trim() == id) return true;
    }
    return false;
  }

  static Future<bool> _removerDoHive(
    Box<LancamentoFinanceiro> box,
    LancamentoFinanceiro l,
  ) async {
    if (l.key != null && box.containsKey(l.key)) {
      await box.delete(l.key);
      return true;
    }
    final id = l.id.trim();
    if (id.isNotEmpty && box.containsKey(id)) {
      await box.delete(id);
      return true;
    }
    for (final key in box.keys.toList()) {
      final v = box.get(key);
      if (v != null && id.isNotEmpty && v.id.trim() == id) {
        await box.delete(key);
        return true;
      }
      if (v != null && l.key != null && v.key == l.key) {
        await box.delete(key);
        return true;
      }
    }
    return false;
  }

  /// Mesma regra da seção Lançamentos financeiros do Relatório Financeiro.
  static List<LancamentoFinanceiro> lancamentosRelatorioMesAtual({
    required Box<LancamentoFinanceiro> box,
    required String lojaId,
    required DateTime referencia,
  }) {
    final inicio = DateTime(referencia.year, referencia.month, 1);
    final fim = DateTime(referencia.year, referencia.month + 1, 0, 23, 59, 59, 999);
    return FinanceiroService.lancamentosPagosNoPeriodo(box, lojaId, inicio, fim)
        .where(lancamentoExcluivelNaUi)
        .toList();
  }

  static Future<FinanceiroLancamentoExclusaoResultado> excluirLancamentoManual({
    required String lojaId,
    required LancamentoFinanceiro lancamento,
    String motivoExclusao = '',
  }) async {
    debugPrint('[FIN-DELETE][INICIO] id=${lancamento.id} loja=$lojaId');

    final lid = lojaId.trim();
    if (lid.isEmpty) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Loja inválida.',
      );
    }

    if (lancamentoEhBaixaContaReceber(lancamento)) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro:
            'Este lançamento veio de Contas a Receber. Use Estornar baixa.',
      );
    }

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lid);
    if (finBox == null) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Armazenamento financeiro indisponível.',
      );
    }

    final existente = _buscarNoHive(finBox, lancamento);
    if (existente == null) {
      if (!_aindaNoHive(finBox, lancamento)) {
        debugPrint(
          '[FIN-DELETE][OK] idempotente id=${lancamento.id} key=${lancamento.key}',
        );
        return const FinanceiroLancamentoExclusaoResultado(
          sucesso: true,
          idempotente: true,
        );
      }
      debugPrint(
        '[FIN-DELETE][LEGACY-ERRO] não localizado id=${lancamento.id} '
        'key=${lancamento.key}',
      );
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro:
            'Não foi possível localizar o lançamento para exclusão.',
      );
    }

    final legado = FinanceiroLancamentoLegacyResolver.pareceManualLegado(existente);
    if (legado) debugPrint('[FIN-LEGACY][MANUAL] id=${existente.id}');

    final usuario = await _usuarioAtual();
    final fsOk = await FinanceiroFirestoreService.softDeleteLancamentoManual(
      lojaId: lid,
      id: existente.id,
      deletedBy: usuario,
      motivoExclusao: motivoExclusao.trim(),
      origem: existente.origem,
      referenciaExterna: existente.referenciaExterna,
    );
    if (!fsOk) {
      debugPrint(
        '[FIN-DELETE][LEGACY-LOCAL-ONLY] id=${existente.id} key=${existente.key}',
      );
    }

    final removido = await _removerDoHive(finBox, existente);
    if (!removido) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Não foi possível remover o lançamento localmente.',
      );
    }

    debugPrint(
      legado
          ? (fsOk
              ? '[FIN-DELETE][LEGACY-OK] id=${existente.id}'
              : '[FIN-DELETE][LEGACY-OK] id=${existente.id} (local)')
          : FinanceiroStatusLancamento.statusEhFinalizadoLegado(existente.status)
              ? '[FIN-DELETE][FINALIZADO-OK] id=${existente.id}'
              : '[FIN-DELETE][OK] id=${existente.id}',
    );
    return FinanceiroLancamentoExclusaoResultado(
      sucesso: true,
      legado: legado,
      apenasLocal: !fsOk,
    );
  }

  /// Remove apenas o lançamento financeiro de baixa CR antiga sem vínculo seguro.
  /// Não reabre parcela, não altera venda/estoque/MP.
  static Future<FinanceiroLancamentoExclusaoResultado>
      excluirSomenteLancamentoFinanceiroLegado({
    required String lojaId,
    required LancamentoFinanceiro lancamento,
    String motivoExclusao = '',
  }) async {
    debugPrint(
      '[FIN-DELETE][FINANCEIRO-ONLY-INICIO] id=${lancamento.id} '
      'key=${lancamento.key} loja=$lojaId',
    );

    final lid = lojaId.trim();
    if (lid.isEmpty) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Loja inválida.',
      );
    }

    if (!lancamentoEhBaixaContaReceber(lancamento)) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Lançamento não é uma baixa de Contas a Receber.',
      );
    }

    final contasCr = await _contasReceberLoja(lid);
    final info = FinanceiroLancamentoLegacyResolver.classificar(
      lancamento,
      contas: contasCr,
      lojaId: lid,
    );

    if (info.vinculoCrSeguro) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Este lançamento possui vínculo seguro. Use Estornar baixa.',
      );
    }

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lid);
    if (finBox == null) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Armazenamento financeiro indisponível.',
      );
    }

    final existente = _buscarNoHive(finBox, lancamento);
    if (existente == null) {
      if (!_aindaNoHive(finBox, lancamento)) {
        debugPrint(
          '[FIN-DELETE][FINANCEIRO-ONLY-OK] idempotente id=${lancamento.id}',
        );
        return FinanceiroLancamentoExclusaoResultado(
          sucesso: true,
          idempotente: true,
          legado: info.legado,
        );
      }
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Não foi possível localizar o lançamento para exclusão.',
      );
    }

    final usuario = await _usuarioAtual();
    final motivo = motivoExclusao.trim().isEmpty
        ? 'exclusao_somente_financeiro_cr_sem_vinculo'
        : motivoExclusao.trim();
    final idFs = existente.id.trim();
    var fsOk = false;
    if (idFs.isNotEmpty) {
      fsOk = await FinanceiroFirestoreService.softDeleteLancamentoManual(
        lojaId: lid,
        id: idFs,
        deletedBy: usuario,
        motivoExclusao: motivo,
        origem: existente.origem,
        referenciaExterna: existente.referenciaExterna,
      );
      if (fsOk) {
        debugPrint('[FIN-DELETE][FINANCEIRO-ONLY-FS-OK] id=$idFs');
      } else {
        debugPrint('[FIN-DELETE][FINANCEIRO-ONLY-FS-ERRO] id=$idFs');
      }
    } else {
      debugPrint(
        '[FIN-DELETE][FINANCEIRO-ONLY-LOCAL] id vazio key=${existente.key}',
      );
    }

    final removido = await _removerDoHive(finBox, existente);
    if (!removido) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Não foi possível remover o lançamento localmente.',
      );
    }

    debugPrint('[FIN-DELETE][FINANCEIRO-ONLY-OK] id=${existente.id}');
    return FinanceiroLancamentoExclusaoResultado(
      sucesso: true,
      legado: info.legado,
      apenasLocal: idFs.isEmpty || !fsOk,
    );
  }

  static Future<FinanceiroLancamentoExclusaoResultado> estornarBaixaContaReceber({
    required String lojaId,
    required LancamentoFinanceiro lancamento,
    String motivoEstorno = '',
  }) async {
    debugPrint(
      '[FIN-ESTORNO-BAIXA][INICIO] id=${lancamento.id} loja=$lojaId',
    );

    final lid = lojaId.trim();
    if (lid.isEmpty) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Loja inválida.',
      );
    }

    if (!lancamentoEhBaixaContaReceber(lancamento)) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Lançamento não é uma baixa de Contas a Receber.',
      );
    }

    final contasCr = await _contasReceberLoja(lid);
    final info = FinanceiroLancamentoLegacyResolver.classificar(
      lancamento,
      contas: contasCr,
      lojaId: lid,
    );

    if (!info.vinculoCrSeguro) {
      debugPrint(
        FinanceiroStatusLancamento.statusEhFinalizadoLegado(lancamento.status)
            ? '[FIN-ESTORNO-BAIXA][FINALIZADO-BLOQUEADO] id=${lancamento.id}'
            : '[FIN-ESTORNO-BAIXA][LEGACY-BLOQUEADO] id=${lancamento.id}',
      );
      return FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        bloqueado: true,
        mensagemErro: info.motivoBloqueioEstorno ?? _msgSemVinculo,
        legado: info.legado,
      );
    }

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lid);
    if (finBox == null) {
      return const FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Armazenamento financeiro indisponível.',
      );
    }

    final existente = _buscarNoHive(finBox, lancamento);
    if (existente == null) {
      await FinanceiroFirestoreService.sincronizarTombstonesLancamentos(lid);
      debugPrint('[FIN-ESTORNO-BAIXA][OK] idempotente id=${lancamento.id}');
      return FinanceiroLancamentoExclusaoResultado(
        sucesso: true,
        idempotente: true,
        legado: info.legado,
      );
    }

    final bloqueio = await _validarEstornoContaReceber(
      lojaId: lid,
      lancamento: existente,
      contas: contasCr,
    );
    if (bloqueio != null) {
      debugPrint('[FIN-ESTORNO-BAIXA][ERRO] $bloqueio');
      return FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: bloqueio,
        legado: info.legado,
      );
    }

    debugPrint('[FIN-ESTORNO-BAIXA][VALOR] ${existente.valor}');

    final usuario = await _usuarioAtual();
    final ref = recebimentoRefFromLancamento(existente);
    String contaReceberDocId = ref?.contaReceberDocId ?? '';
    String vendaIdFirebase = '';

    debugPrint(
      '[CR-ESTORNO-BAIXA][INICIO] ref=${ref?.stableId.isNotEmpty == true ? ref!.stableId : ref?.contaReceberDocId ?? "heuristica"}',
    );

    final conta = ContaReceberFinanceiroSyncService.resolverContaParaEstorno(
      contas: contasCr,
      lojaId: lid,
      lancamento: existente,
    );

    if (conta != null) {
      contaReceberDocId = resolveContaReceberDocId(conta);
      vendaIdFirebase = conta.vendaIdFirebase.trim();
      debugPrint(
        '[CR-ESTORNO-BAIXA][SALDO-ANTES] pago=${conta.valorPago} saldo=${conta.saldoRestante}',
      );
    } else {
      debugPrint('[CR-ESTORNO-BAIXA][ERRO] conta local ausente');
      return FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: info.legado
            ? FinanceiroLancamentoLegacyResolver.msgEstornoLegadoSemVinculo
            : _msgSemVinculo,
        legado: info.legado,
      );
    }

    final estornoCr =
        await ContaReceberFinanceiroSyncService.reverterBaixaPorLancamento(
      lojaId: lid,
      lancamento: existente,
      permitirResolucaoLegada: true,
    );

    if (!estornoCr.sucesso) {
      return FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: estornoCr.mensagem ?? _msgSemVinculo,
        legado: info.legado,
      );
    }

    if (estornoCr.jaEstavaEstornada) {
      await _removerDoHive(finBox, existente);
      await FinanceiroFirestoreService.softDeleteLancamentoEstorno(
        lojaId: lid,
        id: existente.id,
        estornadoPor: usuario,
        motivoEstorno: motivoEstorno.trim(),
        origem: existente.origem,
        referenciaExterna: existente.referenciaExterna,
        contaReceberId: contaReceberDocId,
        vendaIdFirebase: vendaIdFirebase,
        valorEstornado: existente.valor,
      );
      return FinanceiroLancamentoExclusaoResultado(
        sucesso: true,
        idempotente: true,
        legado: info.legado,
      );
    }

    debugPrint(
      '[CR-ESTORNO-BAIXA][SALDO-DEPOIS] pago=${conta.valorPago} saldo=${conta.saldoRestante}',
    );
    debugPrint('[CR-ESTORNO-BAIXA][OK] conta=$contaReceberDocId');

    final fsOk = await FinanceiroFirestoreService.softDeleteLancamentoEstorno(
      lojaId: lid,
      id: existente.id,
      estornadoPor: usuario,
      motivoEstorno: motivoEstorno.trim(),
      origem: existente.origem,
      referenciaExterna: existente.referenciaExterna,
      contaReceberId: contaReceberDocId,
      vendaIdFirebase: vendaIdFirebase,
      valorEstornado: existente.valor,
    );
    if (fsOk) {
      debugPrint('[FIN-ESTORNO-BAIXA][FS-OK] id=${existente.id}');
    } else {
      debugPrint('[FIN-ESTORNO-BAIXA][FS-ERRO] id=${existente.id}');
    }

    await _removerDoHive(finBox, existente);
    debugPrint(
      info.legado
          ? '[FIN-ESTORNO-BAIXA][LEGACY-OK] id=${existente.id}'
          : FinanceiroStatusLancamento.statusEhFinalizadoLegado(existente.status)
              ? '[FIN-ESTORNO-BAIXA][FINALIZADO-OK] id=${existente.id}'
              : '[FIN-ESTORNO-BAIXA][OK] id=${existente.id}',
    );
    return FinanceiroLancamentoExclusaoResultado(
      sucesso: true,
      contaReceberAtualizada: estornoCr.contaAtualizada,
      legado: info.legado,
    );
  }

  static Future<String?> _validarEstornoContaReceber({
    required String lojaId,
    required LancamentoFinanceiro lancamento,
    required Iterable<ContaReceber> contas,
  }) async {
    final info = FinanceiroLancamentoLegacyResolver.classificar(
      lancamento,
      contas: contas,
      lojaId: lojaId,
    );
    if (!info.vinculoCrSeguro) {
      return info.motivoBloqueioEstorno ?? _msgSemVinculo;
    }

    final conta = ContaReceberFinanceiroSyncService.resolverContaParaEstorno(
      contas: contas,
      lojaId: lojaId,
      lancamento: lancamento,
    );
    if (conta == null) {
      return info.legado
          ? FinanceiroLancamentoLegacyResolver.msgEstornoLegadoSemVinculo
          : _msgSemVinculo;
    }

    if (conta.status == ContaReceberStatus.cancelada) {
      return 'Não é possível estornar: a parcela foi cancelada (ex.: venda excluída).';
    }

    if (lancamento.valor > conta.valorPago + 0.01) {
      return 'Não é possível estornar: valor da baixa maior que o total pago na parcela.';
    }

    return null;
  }
}
