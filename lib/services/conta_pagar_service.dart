// CRUD, parcelas de compra e resumos para Contas a Pagar.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/compra_fornecedor.dart';
import '../models/compra_fornecedor_constants.dart';
import '../models/conta_pagar.dart';
import '../models/conta_pagar_constants.dart';
import 'compra_fornecedor_hive_store.dart';
import 'conta_pagar_financeiro_exclusao_service.dart';
import 'conta_pagar_hive_store.dart';
import 'conta_pagar_pagamento_caixa_service.dart';

class ResumoContasPagar {
  final double totalAberto;
  final double totalVencido;
  final double totalPagoNoMes;
  final double fluxoProjetado;
  final int quantidadeAbertas;
  final int quantidadeVencidas;

  const ResumoContasPagar({
    this.totalAberto = 0,
    this.totalVencido = 0,
    this.totalPagoNoMes = 0,
    this.fluxoProjetado = 0,
    this.quantidadeAbertas = 0,
    this.quantidadeVencidas = 0,
  });
}

class GeracaoParcelasCompraResultado {
  GeracaoParcelasCompraResultado({
    required this.criadas,
    required this.jaExistiam,
    this.erro,
  });

  final int criadas;
  final bool jaExistiam;
  /// box_indisponivel | valor_invalido | compra_id_vazio | numero_parcelas_invalido
  final String? erro;
}

abstract final class ContaPagarService {
  ContaPagarService._();

  static List<double> parcelarValores(double total, int parcelas) =>
      ContaPagarPagamentoCaixaService.parcelarValores(total, parcelas);

  static Iterable<ContaPagar> listar(
    Box<ContaPagar> box,
    String lojaId, {
    String? filtroStatus,
    String? fornecedorNome,
    int? fornecedorId,
    String? compraId,
    DateTime? vencimentoDe,
    DateTime? vencimentoAte,
  }) {
    final id = lojaId.trim();
    final cid = compraId?.trim() ?? '';
    return box.values.where((c) {
      if (c.lojaId != id) return false;
      if (cid.isNotEmpty && c.compraId.trim() != cid) return false;
      if (fornecedorId != null &&
          fornecedorId > 0 &&
          c.fornecedorId != fornecedorId) {
        return false;
      }
      if (fornecedorNome != null &&
          fornecedorNome.trim().isNotEmpty &&
          c.fornecedorNome.toLowerCase().trim() !=
              fornecedorNome.toLowerCase().trim()) {
        return false;
      }
      if (vencimentoDe != null && c.dataVencimento.isBefore(vencimentoDe)) {
        return false;
      }
      if (vencimentoAte != null && c.dataVencimento.isAfter(vencimentoAte)) {
        return false;
      }
      if (filtroStatus == null || filtroStatus == 'todas') return true;
      final ef = c.statusEfetivo;
      if (filtroStatus == 'pendentes') {
        return ef == ContaPagarStatus.pendente;
      }
      if (filtroStatus == 'vencidas') {
        return ef == ContaPagarStatus.vencido;
      }
      if (filtroStatus == 'pagas') {
        return c.status == ContaPagarStatus.pago;
      }
      if (filtroStatus == 'canceladas') {
        return c.status == ContaPagarStatus.cancelado;
      }
      return true;
    });
  }

  static bool existeParcelasParaCompra(Box<ContaPagar> box, String compraId) {
    final cid = compraId.trim();
    if (cid.isEmpty) return false;
    return box.values.any(
      (c) =>
          c.compraId.trim() == cid &&
          c.status != ContaPagarStatus.cancelado,
    );
  }

  static int contarParcelasParaCompra(Box<ContaPagar> box, String compraId) {
    final cid = compraId.trim();
    if (cid.isEmpty) return 0;
    return box.values.where((c) => c.compraId.trim() == cid).length;
  }

  /// Gera N contas a pagar idempotente por compraId (não duplica se já existir).
  static Future<GeracaoParcelasCompraResultado> gerarParcelasCompra({
    required String lojaId,
    required CompraFornecedor compra,
    required int numeroParcelas,
    required DateTime primeiroVencimento,
    int intervaloMeses = 1,
  }) async {
    final compraId = compra.id.trim();
    if (compraId.isEmpty) {
      debugPrint('[CP_COMPRA][erro_gerar_parcelas] compraId vazio');
      return GeracaoParcelasCompraResultado(
        criadas: 0,
        jaExistiam: false,
        erro: 'compra_id_vazio',
      );
    }

    final n = numeroParcelas.clamp(1, 48);
    if (n < 1) {
      return GeracaoParcelasCompraResultado(
        criadas: 0,
        jaExistiam: false,
        erro: 'numero_parcelas_invalido',
      );
    }

    final total = compra.valorTotalFinanceiro;
    if (total <= 1e-9) {
      debugPrint('[CP_COMPRA][erro_gerar_parcelas] valorTotalFinanceiro=$total');
      return GeracaoParcelasCompraResultado(
        criadas: 0,
        jaExistiam: false,
        erro: 'valor_invalido',
      );
    }

    final box = await ContaPagarHiveStore.openBox(lojaId);
    if (box == null) {
      debugPrint('[CP_COMPRA][erro_gerar_parcelas] box Hive indisponível');
      return GeracaoParcelasCompraResultado(
        criadas: 0,
        jaExistiam: false,
        erro: 'box_indisponivel',
      );
    }

    if (existeParcelasParaCompra(box, compraId)) {
      debugPrint('[CP_COMPRA][parcelas_existentes] compraId=$compraId');
      return GeracaoParcelasCompraResultado(criadas: 0, jaExistiam: true);
    }

    debugPrint(
      '[CP_COMPRA][antes_gerar_parcelas] compraId=$compraId total=$total n=$n',
    );

    final partes = parcelarValores(total, n);
    final agora = DateTime.now();
    final ref = compra.referenciaInterna.trim();
    final descBase = ref.isNotEmpty
        ? 'Compra $ref — ${compra.fornecedorNome}'
        : 'Compra ${compra.fornecedorNome}';

    var criadas = 0;
    for (var i = 0; i < n; i++) {
      final venc = DateTime(
        primeiroVencimento.year,
        primeiroVencimento.month + i * intervaloMeses,
        primeiroVencimento.day,
      );
      final id = '${compra.id}_p${i + 1}';
      final conta = ContaPagar(
        id: id,
        lojaId: lojaId.trim(),
        fornecedorId: compra.fornecedorHiveKey,
        fornecedorNome: compra.fornecedorNome,
        compraId: compra.id,
        descricao: n > 1 ? '$descBase (${i + 1}/$n)' : descBase,
        valorTotalCompra: total,
        valorParcela: partes[i],
        parcelaNumero: i + 1,
        parcelaTotal: n,
        dataVencimento: venc,
        dataCompra: compra.dataCompra,
        observacao: compra.observacao,
        criadoEm: agora,
        atualizadoEm: agora,
      );
      await box.put(id, conta);
      criadas++;
    }

    debugPrint('[CP_COMPRA][parcelas_criadas] $criadas compraId=$compraId');
    return GeracaoParcelasCompraResultado(criadas: criadas, jaExistiam: false);
  }

  static Future<ContaPagar?> obter(Box<ContaPagar> box, String id) async {
    return box.get(id.trim());
  }

  static Future<void> salvar(Box<ContaPagar> box, ContaPagar conta) async {
    await box.put(conta.id, conta.copyWith(atualizadoEm: DateTime.now()));
  }

  static Future<bool> marcarComoPago({
    required String lojaId,
    required ContaPagar conta,
    required String formaPagamento,
    DateTime? dataPagamento,
  }) async {
    if (conta.status == ContaPagarStatus.pago) return true;
    if (conta.status == ContaPagarStatus.cancelado) return false;

    final box = await ContaPagarHiveStore.openBox(lojaId);
    if (box == null) return false;

    final quando = dataPagamento ?? DateTime.now();
    final lancId = await ContaPagarPagamentoCaixaService.registrarPagamento(
      lojaId: lojaId,
      conta: conta,
      formaPagamento: formaPagamento,
      dataPagamento: quando,
    );
    if (lancId == null) return false;

    final atualizada = conta.copyWith(
      status: ContaPagarStatus.pago,
      dataPagamento: quando,
      formaPagamento: formaPagamento.trim(),
      lancamentoFinanceiroId: lancId,
      atualizadoEm: DateTime.now(),
    );
    await box.put(atualizada.id, atualizada);
    await _sincronizarCompraPagamento(lojaId, atualizada.compraId);
    return true;
  }

  /// Cancela parcela e sincroniza compra; se paga, remove LF vinculado.
  static Future<CancelarContaPagarResultado> cancelar({
    required String lojaId,
    required ContaPagar conta,
  }) =>
      ContaPagarFinanceiroExclusaoService.cancelarContaPagar(
        lojaId: lojaId,
        conta: conta,
      );

  /// Recalcula [valorPago] / [statusPagamento] da compra pelas parcelas ativas.
  static Future<void> sincronizarCompraPagamento(
    String lojaId,
    String compraId,
  ) =>
      _sincronizarCompraPagamento(lojaId, compraId);

  static Future<void> atualizarVencimento({
    required String lojaId,
    required ContaPagar conta,
    required DateTime novaData,
  }) async {
    if (conta.status == ContaPagarStatus.pago ||
        conta.status == ContaPagarStatus.cancelado) {
      return;
    }
    final box = await ContaPagarHiveStore.openBox(lojaId);
    if (box == null) return;

    await box.put(
      conta.id,
      conta.copyWith(
        dataVencimento: novaData,
        status: ContaPagarStatus.pendente,
        atualizadoEm: DateTime.now(),
      ),
    );
  }

  /// Recalcula valorPago/statusPagamento da compra a partir das parcelas pagas.
  static Future<void> _sincronizarCompraPagamento(
    String lojaId,
    String compraId,
  ) async {
    final cid = compraId.trim();
    if (cid.isEmpty) return;

    final cpBox = await ContaPagarHiveStore.openBox(lojaId);
    final compraBox = await CompraFornecedorHiveStore.openBox(lojaId);
    if (cpBox == null || compraBox == null) return;

    final compra = compraBox.get(cid);
    if (compra == null) return;

    final parcelas =
        cpBox.values.where((c) => c.compraId.trim() == cid).toList();
    if (parcelas.isEmpty) return;

    double pago = 0;
    var abertas = 0;
    for (final p in parcelas) {
      if (p.status == ContaPagarStatus.pago) {
        pago += p.valorParcela;
      } else if (p.status != ContaPagarStatus.cancelado) {
        abertas++;
      }
    }

    String stPag;
    if (abertas == 0 && pago >= compra.valorTotalFinanceiro - 0.01) {
      stPag = CompraFornecedorStatusPagamento.pago;
    } else if (pago > 0.009) {
      stPag = CompraFornecedorStatusPagamento.parcial;
    } else {
      stPag = CompraFornecedorStatusPagamento.pendente;
    }

    await compraBox.put(
      cid,
      compra.copyWith(
        valorPago: pago.clamp(0.0, compra.valorTotalFinanceiro),
        statusPagamento: stPag,
        atualizadoEm: DateTime.now(),
      ),
    );
  }

  static ResumoContasPagar resumo({
    required Iterable<ContaPagar> contas,
    required int ano,
    required int mes,
    bool visaoCompetencia = false,
  }) {
    final inicioMes = DateTime(ano, mes, 1);
    final fimMes = DateTime(ano, mes + 1, 0, 23, 59, 59, 999);

    double aberto = 0, vencido = 0, pagoMes = 0, projetado = 0;
    var qAb = 0, qVenc = 0;

    if (visaoCompetencia) {
      final comprasContabilizadas = <String>{};
      for (final c in contas) {
        if (c.status == ContaPagarStatus.cancelado) continue;
        if (c.dataCompra.year != ano || c.dataCompra.month != mes) continue;
        if (!comprasContabilizadas.add(c.compraId.trim())) continue;
        aberto += c.valorTotalCompra;
      }
      return ResumoContasPagar(
        totalAberto: aberto,
        totalVencido: 0,
        totalPagoNoMes: 0,
        fluxoProjetado: aberto,
      );
    }

    for (final c in contas) {
      if (c.status == ContaPagarStatus.pago) {
        final dp = c.dataPagamento ?? c.atualizadoEm;
        if (!dp.isBefore(inicioMes) && !dp.isAfter(fimMes)) {
          pagoMes += c.valorParcela;
        }
        continue;
      }
      if (c.status == ContaPagarStatus.cancelado) continue;

      aberto += c.valorParcela;
      qAb++;
      projetado += c.valorParcela;

      if (c.statusEfetivo == ContaPagarStatus.vencido) {
        vencido += c.valorParcela;
        qVenc++;
      }
    }

    return ResumoContasPagar(
      totalAberto: aberto,
      totalVencido: vencido,
      totalPagoNoMes: pagoMes,
      fluxoProjetado: projetado,
      quantidadeAbertas: qAb,
      quantidadeVencidas: qVenc,
    );
  }

  static double saldoAbertoCompra(Box<ContaPagar> box, String compraId) {
    final cid = compraId.trim();
    var aberto = 0.0;
    for (final c in box.values) {
      if (c.compraId.trim() != cid) continue;
      if (!c.estaAberta) continue;
      aberto += c.valorParcela;
    }
    return aberto;
  }
}
