// lib/services/gasto_fixo_lancamento_service.dart
// Gera lançamentos sugeridos (tipo gasto_fixo, pendentes) a partir do cadastro de gastos fixos.
// Idempotência por [referenciaExterna] — um par gasto fixo + mês civil.

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../financeiro/financeiro_constants.dart';
import '../models/gasto_fixo_mensal.dart';
import '../models/lancamento_financeiro.dart';
import 'financeiro_firestore_service.dart';

class GeracaoGastoFixoResultado {
  GeracaoGastoFixoResultado({
    required this.criados,
    required this.puladosJaExistiam,
    required this.ignoradosInativosOuValorZero,
  });

  final int criados;
  final int puladosJaExistiam;
  final int ignoradosInativosOuValorZero;
}

class QuitarGastoFixoLoteResultado {
  QuitarGastoFixoLoteResultado({required this.afetados});

  final int afetados;
}

abstract final class GastoFixoLancamentoService {
  GastoFixoLancamentoService._();

  /// Chave única por gasto fixo + ano/mês (competência).
  static String referenciaGastoFixoMes(String gastoFixoId, int ano, int mes) {
    final m = mes.clamp(1, 12);
    return 'gf_gen:${gastoFixoId.trim()}:$ano:${m.toString().padLeft(2, '0')}';
  }

  static bool existeLancamentoComReferencia(
    Box<LancamentoFinanceiro> box,
    String lojaId,
    String referencia,
  ) {
    final id = lojaId.trim();
    final r = referencia.trim();
    for (final l in box.values) {
      if (l.lojaId != id) continue;
      if (l.referenciaExterna.trim() == r) return true;
    }
    return false;
  }

  /// Cria lançamentos **pendentes** (tipo [gasto_fixo]) para o mês, sem duplicar.
  static Future<GeracaoGastoFixoResultado> gerarSugestoesMes({
    required Box<GastoFixoMensal> gastosBox,
    required Box<LancamentoFinanceiro> lancBox,
    required String lojaId,
    required int ano,
    required int mes,
    required String usuarioId,
    required String usuarioNome,
  }) async {
    final idLoja = lojaId.trim();
    var criados = 0, pulados = 0, ignorados = 0;
    final ultimoDia = DateTime(ano, mes + 1, 0).day;

    for (final g in gastosBox.values) {
      if (g.lojaId != idLoja) continue;
      if (!g.ativo) {
        ignorados++;
        continue;
      }
      if (g.valorPadrao <= 1e-9) {
        ignorados++;
        continue;
      }

      final ref = referenciaGastoFixoMes(g.id, ano, mes);
      if (existeLancamentoComReferencia(lancBox, idLoja, ref)) {
        pulados++;
        continue;
      }

      final dia = g.diaVencimento.clamp(1, ultimoDia);
      final dataLan = DateTime(ano, mes, dia);
      final desc = g.descricao.trim().isEmpty
          ? 'Gasto fixo'
          : g.descricao.trim();

      final l = LancamentoFinanceiro(
        id: const Uuid().v4(),
        lojaId: idLoja,
        descricao: '$desc · $mes/$ano',
        valor: g.valorPadrao,
        tipo: FinanceiroTipoLancamento.gastoFixo,
        categoria: g.categoria.isNotEmpty
            ? g.categoria
            : financeiroCategoriaOuPadrao(''),
        subcategoria: g.subcategoria,
        status: FinanceiroStatusLancamento.pendente,
        formaPagamento: g.formaPagamentoPadrao,
        fornecedor: g.fornecedor,
        observacao: g.observacao.isNotEmpty
            ? 'Sugerido do cadastro de gastos fixos.\n${g.observacao}'
            : 'Sugerido do cadastro de gastos fixos.',
        dataLancamento: dataLan,
        dataPagamento: null,
        competenciaMes: mes,
        competenciaAno: ano,
        recorrente: false,
        origem: FinanceiroOrigemLancamento.geradoGastoFixo,
        usuarioId: usuarioId,
        usuarioNome: usuarioNome,
        centroCusto: g.centroCusto,
        referenciaExterna: ref,
      );

      await lancBox.put(l.id, l);
      await FinanceiroFirestoreService.upsertLancamento(l);
      criados++;
    }

    return GeracaoGastoFixoResultado(
      criados: criados,
      puladosJaExistiam: pulados,
      ignoradosInativosOuValorZero: ignorados,
    );
  }

  /// Quantos lançamentos seriam quitados (mesmo critério de [quitarGeradosPendentesCompetencia]).
  static int contarGeradosPendentesCompetencia({
    required Box<LancamentoFinanceiro> lancBox,
    required String lojaId,
    required int competenciaAno,
    required int competenciaMes,
  }) {
    final id = lojaId.trim();
    var n = 0;
    for (final l in lancBox.values) {
      if (l.lojaId != id) continue;
      if (l.origem != FinanceiroOrigemLancamento.geradoGastoFixo) continue;
      if (l.tipo != FinanceiroTipoLancamento.gastoFixo) continue;
      if (l.status != FinanceiroStatusLancamento.pendente) continue;
      if (l.competenciaAno != competenciaAno ||
          l.competenciaMes != competenciaMes) {
        continue;
      }
      if (!l.referenciaExterna.trim().startsWith('gf_gen:')) continue;
      n++;
    }
    return n;
  }

  /// Marca como **pagos** lançamentos gerados pelo cadastro de gastos fixos, pendentes,
  /// da competência informada. Não cria linhas novas; não altera origem manual.
  static Future<QuitarGastoFixoLoteResultado> quitarGeradosPendentesCompetencia({
    required Box<LancamentoFinanceiro> lancBox,
    required String lojaId,
    required int competenciaAno,
    required int competenciaMes,
    required DateTime dataPagamento,
  }) async {
    final id = lojaId.trim();
    var n = 0;
    final dp = DateTime(
      dataPagamento.year,
      dataPagamento.month,
      dataPagamento.day,
    );

    for (final l in lancBox.values.toList()) {
      if (l.lojaId != id) continue;
      if (l.origem != FinanceiroOrigemLancamento.geradoGastoFixo) continue;
      if (l.tipo != FinanceiroTipoLancamento.gastoFixo) continue;
      if (l.status != FinanceiroStatusLancamento.pendente) continue;
      if (l.competenciaAno != competenciaAno ||
          l.competenciaMes != competenciaMes) {
        continue;
      }
      if (!l.referenciaExterna.trim().startsWith('gf_gen:')) continue;

      l.status = FinanceiroStatusLancamento.pago;
      l.dataPagamento = dp;
      await l.save();
      await FinanceiroFirestoreService.upsertLancamento(l);
      n++;
    }

    return QuitarGastoFixoLoteResultado(afetados: n);
  }
}
