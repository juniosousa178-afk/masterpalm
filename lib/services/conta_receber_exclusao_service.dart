// Exclusão segura de contas a receber recuperadas/manuais (soft delete + tombstone).

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/conta_receber_identity.dart';
import '../core/conta_receber_recuperada_manual.dart';
import '../core/hive_box_names.dart';
import '../models/conta_receber.dart';
import '../models/venda.dart';
import 'conta_receber_firestore_service.dart';
import 'conta_receber_service.dart';

class ContaReceberExclusaoDiagnostico {
  final bool ehRecuperadaOuManual;
  final bool marcadorForteRecuperacao;
  final bool temVendaAtiva;
  final bool podeExcluir;
  final String? motivoBloqueio;
  final String decisao;

  const ContaReceberExclusaoDiagnostico({
    required this.ehRecuperadaOuManual,
    required this.marcadorForteRecuperacao,
    required this.temVendaAtiva,
    required this.podeExcluir,
    required this.decisao,
    this.motivoBloqueio,
  });
}

class ResultadoExclusaoContaReceber {
  final bool sucesso;
  final String? mensagemErro;
  final String? mensagemSucesso;

  const ResultadoExclusaoContaReceber({
    required this.sucesso,
    this.mensagemErro,
    this.mensagemSucesso,
  });
}

abstract final class ContaReceberExclusaoService {
  ContaReceberExclusaoService._();

  static const _motivoExclusao = 'exclusao_recuperada_manual';

  static const tituloModalRecuperada = 'Excluir conta recuperada?';
  static const corpoModalRecuperada =
      'Esta conta foi identificada como recuperada/manual.\n\n'
      'A exclusão remove somente esta conta da tela Contas a Receber. '
      'Nenhuma venda, estoque ou Mercado Pago será alterado.\n\n'
      'Deseja continuar?';
  static const msgSucessoRecuperada =
      'Conta recuperada excluída com segurança.';

  /// Verifica se há venda ativa (não cancelada/estornada) vinculada à conta.
  @visibleForTesting
  static Future<bool> temVendaAtivaVinculada({
    required String lojaId,
    required ContaReceber conta,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return false;

    final idV = conta.vendaIdFirebase.trim();
    final vk = conta.vendaKey;
    if (idV.isEmpty && vk <= 0) return false;

    try {
      final vendasName = HiveBoxNames.vendas(loja);
      if (!Hive.isBoxOpen(vendasName)) {
        await Hive.openBox<Venda>(vendasName);
      }
      final vendaBox = Hive.box<Venda>(vendasName);

      if (idV.isNotEmpty) {
        for (final v in vendaBox.values) {
          if ((v.idFirebase ?? '').trim() != idV) continue;
          if (v.cancelada || v.estornada) continue;
          if (v.lojaId != null &&
              v.lojaId!.trim().isNotEmpty &&
              v.lojaId!.trim() != loja) {
            continue;
          }
          return true;
        }
      }

      if (vk >= 0) {
        final v = vendaBox.get(vk);
        if (v != null && !v.cancelada && !v.estornada) {
          if (v.lojaId == null ||
              v.lojaId!.trim().isEmpty ||
              v.lojaId!.trim() == loja) {
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('[CR-DELETE][DIAGNOSTICO] venda lookup err=${e.runtimeType}');
    }

    return false;
  }

  static void _logDiagnosticoDetalhado({
    required ContaReceber conta,
    required bool recuperadaManual,
    required bool marcadorForteRecuperacao,
    required bool vendaAtivaEncontrada,
    required String decisao,
  }) {
    debugPrint(
      '[CR-DELETE][DIAGNOSTICO-DETALHADO] '
      'cliente=${conta.clienteNome} '
      'valor=${conta.valor} '
      'observacao=${conta.observacao} '
      'vendaIdFirebase=${conta.vendaIdFirebase} '
      'vendaKey=${conta.vendaKey} '
      'idFirebase=${conta.idFirebase ?? ''} '
      'hiveKey=${conta.key} '
      'status=${conta.status} '
      'recuperadaManual=$recuperadaManual '
      'marcadorForteRecuperacao=$marcadorForteRecuperacao '
      'vendaAtivaEncontrada=$vendaAtivaEncontrada '
      'decisao=$decisao',
    );
  }

  static Future<ContaReceberExclusaoDiagnostico> diagnosticar({
    required String lojaId,
    required ContaReceber conta,
  }) async {
    final ehRec = contaReceberEhRecuperadaOuManual(conta);
    final marcadorForte = contaReceberTemMarcadorForteRecuperacao(conta);

    if (!ehRec) {
      _logDiagnosticoDetalhado(
        conta: conta,
        recuperadaManual: false,
        marcadorForteRecuperacao: false,
        vendaAtivaEncontrada: false,
        decisao: 'bloqueado-nao-recuperada',
      );
      debugPrint(
        '[CR-DELETE][BLOQUEADO-NAO-RECUPERADA] cliente=${conta.clienteNome} '
        'obs=${conta.observacao}',
      );
      return const ContaReceberExclusaoDiagnostico(
        ehRecuperadaOuManual: false,
        marcadorForteRecuperacao: false,
        temVendaAtiva: false,
        podeExcluir: false,
        decisao: 'bloqueado-nao-recuperada',
        motivoBloqueio:
            'Esta conta não parece ter sido criada por recuperação ou cadastro manual.',
      );
    }

    final temVenda = await temVendaAtivaVinculada(lojaId: lojaId, conta: conta);

    if (marcadorForte) {
      _logDiagnosticoDetalhado(
        conta: conta,
        recuperadaManual: true,
        marcadorForteRecuperacao: true,
        vendaAtivaEncontrada: temVenda,
        decisao: 'permitir-somente-conta-recuperada',
      );
      debugPrint(
        '[CR-DELETE][RECUPERADA-MANUAL] cliente=${conta.clienteNome} '
        'ignoraVendaAtiva=$temVenda',
      );
      return ContaReceberExclusaoDiagnostico(
        ehRecuperadaOuManual: true,
        marcadorForteRecuperacao: true,
        temVendaAtiva: temVenda,
        podeExcluir: true,
        decisao: 'permitir-somente-conta-recuperada',
      );
    }

    if (temVenda) {
      _logDiagnosticoDetalhado(
        conta: conta,
        recuperadaManual: true,
        marcadorForteRecuperacao: false,
        vendaAtivaEncontrada: true,
        decisao: 'bloqueado-venda-ativa',
      );
      debugPrint(
        '[CR-DELETE][BLOQUEADO-VENDA-ATIVA] cliente=${conta.clienteNome} '
        'vendaId=${conta.vendaIdFirebase} vendaKey=${conta.vendaKey}',
      );
      return const ContaReceberExclusaoDiagnostico(
        ehRecuperadaOuManual: true,
        marcadorForteRecuperacao: false,
        temVendaAtiva: true,
        podeExcluir: false,
        decisao: 'bloqueado-venda-ativa',
        motivoBloqueio:
            'Esta conta está vinculada a uma venda ativa. Para evitar inconsistência, '
            'exclua/cancele a venda pelo fluxo correto ou confirme uma regra específica '
            'antes de remover apenas a conta.',
      );
    }

    _logDiagnosticoDetalhado(
      conta: conta,
      recuperadaManual: true,
      marcadorForteRecuperacao: false,
      vendaAtivaEncontrada: false,
      decisao: 'permitir-manual-sem-venda-ativa',
    );
    debugPrint(
      '[CR-DELETE][DIAGNOSTICO] cliente=${conta.clienteNome} '
      'valor=${conta.valor} doc=${resolveContaReceberDocId(conta)} '
      'manualSemVenda=${contaReceberEhManualSemVenda(conta)}',
    );

    return const ContaReceberExclusaoDiagnostico(
      ehRecuperadaOuManual: true,
      marcadorForteRecuperacao: false,
      temVendaAtiva: false,
      podeExcluir: true,
      decisao: 'permitir-manual-sem-venda-ativa',
    );
  }

  /// Remove conta recuperada/manual do Hive e publica tombstone no Firestore.
  static Future<ResultadoExclusaoContaReceber>
      excluirContaReceberManualOuRecuperada({
    required String lojaId,
    required ContaReceber conta,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) {
      return const ResultadoExclusaoContaReceber(
        sucesso: false,
        mensagemErro: 'Loja não identificada.',
      );
    }

    debugPrint(
      '[CR-DELETE][CLICK] cliente=${conta.clienteNome} valor=${conta.valor}',
    );

    final diag = await diagnosticar(lojaId: loja, conta: conta);
    if (!diag.podeExcluir) {
      return ResultadoExclusaoContaReceber(
        sucesso: false,
        mensagemErro: diag.motivoBloqueio ??
            'Não foi possível excluir esta conta a receber.',
      );
    }

    debugPrint('[CR-DELETE][CONFIRMOU] cliente=${conta.clienteNome}');

    final msgSucesso = diag.marcadorForteRecuperacao
        ? msgSucessoRecuperada
        : 'Conta a receber excluída com segurança.';

    try {
      final crBox = await ContaReceberService.openBoxLoja(loja);
      final docId = resolveContaReceberDocId(conta);
      final hiveKey = conta.key;

      if (hiveKey != null) {
        await crBox.delete(hiveKey);
      } else {
        ContaReceber? alvo;
        dynamic keyAlvo;
        for (final k in crBox.keys) {
          final c = crBox.get(k);
          if (c == null) continue;
          if (!ContaReceberService.contaPertenceALoja(c, loja)) continue;
          if (c == conta ||
              (c.clienteNome == conta.clienteNome &&
                  c.valor == conta.valor &&
                  c.observacao == conta.observacao)) {
            alvo = c;
            keyAlvo = k;
            break;
          }
        }
        if (keyAlvo != null) {
          await crBox.delete(keyAlvo);
        } else if (alvo != null) {
          await alvo.delete();
        }
      }

      debugPrint(
        '[CR-DELETE][LOCAL-OK] cliente=${conta.clienteNome} hiveKey=$hiveKey',
      );

      if (docId.isNotEmpty) {
        final fsOk = await ContaReceberFirestoreService.marcarCanceladaRemota(
          lojaId: loja,
          contaReceberDocId: docId,
          motivo: _motivoExclusao,
        );
        if (fsOk) {
          debugPrint('[CR-DELETE][FS-OK] docId=$docId');
          debugPrint('[CR-DELETE][TOMBSTONE-OK] docId=$docId');
        } else {
          debugPrint('[CR-DELETE][FS-AVISO] docId=$docId falhou (local removido)');
        }
      }

      debugPrint('[CR-DELETE][REFRESH-LISTA] cliente=${conta.clienteNome}');

      return ResultadoExclusaoContaReceber(
        sucesso: true,
        mensagemSucesso: msgSucesso,
      );
    } catch (e, st) {
      debugPrint('[CR-DELETE][ERRO] type=${e.runtimeType} err=$e');
      debugPrint('$st');
      return const ResultadoExclusaoContaReceber(
        sucesso: false,
        mensagemErro: 'Erro ao excluir conta a receber.',
      );
    }
  }
}
