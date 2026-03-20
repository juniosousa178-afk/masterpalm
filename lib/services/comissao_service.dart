// lib/services/comissao_service.dart
// Serviço para calcular e registrar comissões de vendas

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/venda.dart';
import '../models/venda_tracking.dart';
import 'comissao_config_service.dart';
import 'tracking_service.dart';

/// Serviço para cálculo e registro de comissões
class ComissaoService {
  ComissaoService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ============================================================
  // CÁLCULO DE COMISSÃO
  // ============================================================

  /// Calcula a comissão de uma venda
  ///
  /// [lojaId] - ID da loja
  /// [vendedorUid] - UID do vendedor
  /// [subtotalProdutos] - Subtotal dos produtos (sem frete)
  /// [frete] - Valor do frete
  /// [desconto] - Valor do desconto aplicado
  /// [percentualMetaAtingida] - % da meta atingida (para bônus)
  ///
  /// Retorna o resultado do cálculo com base, percentual e valor
  static Future<ComissaoCalculo> calcularComissao({
    required String lojaId,
    required String vendedorUid,
    required double subtotalProdutos,
    required double frete,
    required double desconto,
    double? percentualMetaAtingida,
  }) async {
    try {
      // Buscar configuração
      final config = await ComissaoConfigService.getConfig(lojaId);
      if (config == null) {
        debugPrint('⚠️ [COMISSAO] Sem configuração, usando padrões');
      }

      // Calcular base de comissão
      double baseComissao = subtotalProdutos;

      // Excluir frete da base (padrão: sim)
      // Frete não entra na base por padrão
      final excluirFrete = config?.excluirFreteDaBase ?? true;
      // Não somamos frete na base

      // Desconto reduz a base (padrão: sim)
      final descontoReduzBase = config?.descontoReduzBase ?? true;
      if (descontoReduzBase) {
        baseComissao -= desconto;
      }

      // Garantir base não negativa
      if (baseComissao < 0) baseComissao = 0;

      // Calcular percentual efetivo
      final percentual = await ComissaoConfigService.calcularPercentualEfetivo(
        lojaId: lojaId,
        vendedorUid: vendedorUid,
        percentualMetaAtingida: percentualMetaAtingida,
      );

      // Calcular valor da comissão
      double comissaoValor = baseComissao * (percentual / 100);

      // Aplicar limites mínimo e máximo
      final minimo = config?.comissaoMinimaValor ?? 0.0;
      final maximo = config?.comissaoMaximaValor ?? 0.0;

      if (minimo > 0 && comissaoValor < minimo) {
        comissaoValor = minimo;
        debugPrint('📌 [COMISSAO] Aplicado mínimo: R\$ $minimo');
      }

      if (maximo > 0 && comissaoValor > maximo) {
        comissaoValor = maximo;
        debugPrint('📌 [COMISSAO] Aplicado máximo: R\$ $maximo');
      }

      debugPrint('💰 [COMISSAO] Cálculo:');
      debugPrint('   Subtotal: R\$ ${subtotalProdutos.toStringAsFixed(2)}');
      debugPrint('   Desconto: R\$ ${desconto.toStringAsFixed(2)}');
      debugPrint('   Base: R\$ ${baseComissao.toStringAsFixed(2)}');
      debugPrint('   Percentual: $percentual%');
      debugPrint('   Comissão: R\$ ${comissaoValor.toStringAsFixed(2)}');

      return ComissaoCalculo(
        baseComissao: baseComissao,
        percentual: percentual,
        valor: comissaoValor,
        excluiuFrete: excluirFrete,
        descontoReduziuBase: descontoReduzBase,
      );
    } catch (e) {
      debugPrint('❌ [COMISSAO] Erro ao calcular (type=${e.runtimeType})');
      return ComissaoCalculo(
        baseComissao: 0,
        percentual: 0,
        valor: 0,
        excluiuFrete: true,
        descontoReduziuBase: true,
      );
    }
  }

  // ============================================================
  // REGISTRO DE COMISSÃO
  // ============================================================

  /// Registra a comissão de uma venda
  ///
  /// Deve ser chamado após a venda ser confirmada (pagamento OK)
  static Future<ComissaoVenda?> registrarComissao({
    required String lojaId,
    required String vendaId,
    required String vendedorUid,
    required String vendedorEmail,
    required String vendedorNome,
    String? trackingId,
    required double subtotalProdutos,
    required double frete,
    required double desconto,
    required double totalVenda,
    required String origem,
    String statusPagamentoVenda = 'pago',
    double? percentualMetaAtingida,
  }) async {
    try {
      // Calcular comissão
      final calculo = await calcularComissao(
        lojaId: lojaId,
        vendedorUid: vendedorUid,
        subtotalProdutos: subtotalProdutos,
        frete: frete,
        desconto: desconto,
        percentualMetaAtingida: percentualMetaAtingida,
      );

      // Verificar configuração
      final config = await ComissaoConfigService.getConfig(lojaId);
      final apenasAposPagamento = config?.apenasAposPagamentoConfirmado ?? true;

      // Determinar status inicial
      String status;
      if (apenasAposPagamento) {
        status = statusPagamentoVenda == 'pago' ? 'confirmado' : 'pendente';
      } else {
        status = 'confirmado';
      }

      // Criar registro
      final comissaoId = 'com_${DateTime.now().millisecondsSinceEpoch}';
      final comissao = ComissaoVenda(
        comissaoId: comissaoId,
        lojaId: lojaId,
        vendaId: vendaId,
        vendedorUid: vendedorUid,
        vendedorEmail: vendedorEmail,
        vendedorNome: vendedorNome,
        trackingId: trackingId,
        subtotalProdutos: subtotalProdutos,
        frete: frete,
        desconto: desconto,
        totalVenda: totalVenda,
        baseComissao: calculo.baseComissao,
        comissaoPercentual: calculo.percentual,
        comissaoValor: calculo.valor,
        status: status,
        origem: origem,
        statusPagamentoVenda: statusPagamentoVenda,
        dataVenda: DateTime.now(),
        dataConfirmacao: status == 'confirmado' ? DateTime.now() : null,
      );

      // Salvar no Firestore
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes')
          .doc(comissaoId)
          .set(comissao.toMap());

      // Se tem tracking, marcar como utilizado
      if (trackingId != null && trackingId.isNotEmpty) {
        await TrackingService.marcarTrackingUtilizado(
          lojaId: lojaId,
          trackingId: trackingId,
          vendaId: vendaId,
        );
      }

      debugPrint('✅ [COMISSAO] Comissão registrada: $comissaoId');
      debugPrint('   Valor: R\$ ${calculo.valor.toStringAsFixed(2)}');
      debugPrint('   Status: $status');

      return comissao;
    } catch (e) {
      debugPrint('❌ [COMISSAO] Erro ao registrar (type=${e.runtimeType})');
      return null;
    }
  }

  /// Registra comissão a partir de uma venda do Hive
  static Future<ComissaoVenda?> registrarComissaoDeVenda({
    required String lojaId,
    required Venda venda,
    required String vendaId,
    required String vendedorUid,
    required String vendedorEmail,
    required String vendedorNome,
    String? trackingId,
    String origem = 'catalogo',
    double? percentualMetaAtingida,
  }) async {
    // Calcular subtotal (preco já é o subtotal sem frete)
    final subtotal = venda.preco;
    final desconto = venda.descontoValor;
    final frete = venda.frete;
    final total = venda.total;

    return registrarComissao(
      lojaId: lojaId,
      vendaId: vendaId,
      vendedorUid: vendedorUid,
      vendedorEmail: vendedorEmail,
      vendedorNome: vendedorNome,
      trackingId: trackingId,
      subtotalProdutos: subtotal,
      frete: frete,
      desconto: desconto,
      totalVenda: total,
      origem: origem,
      statusPagamentoVenda: 'pago',
      percentualMetaAtingida: percentualMetaAtingida,
    );
  }

  // ============================================================
  // CONFIRMAÇÃO E ESTORNO
  // ============================================================

  /// Confirma a comissão após pagamento ser confirmado
  static Future<bool> confirmarComissao({
    required String lojaId,
    required String comissaoId,
  }) async {
    try {
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes')
          .doc(comissaoId)
          .update({
        'status': 'confirmado',
        'statusPagamentoVenda': 'pago',
        'dataConfirmacao': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ [COMISSAO] Comissão $comissaoId confirmada');
      return true;
    } catch (e) {
      debugPrint('❌ [COMISSAO] Erro ao confirmar (type=${e.runtimeType})');
      return false;
    }
  }

  /// Estorna a comissão (venda cancelada)
  static Future<bool> estornarComissao({
    required String lojaId,
    required String comissaoId,
    required String motivo,
  }) async {
    try {
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes')
          .doc(comissaoId)
          .update({
        'status': 'estornado',
        'statusPagamentoVenda': 'cancelado',
        'dataEstorno': DateTime.now().toIso8601String(),
        'motivoEstorno': motivo,
      });

      debugPrint('✅ [COMISSAO] Comissão $comissaoId estornada: $motivo');
      return true;
    } catch (e) {
      debugPrint('❌ [COMISSAO] Erro ao estornar (type=${e.runtimeType})');
      return false;
    }
  }

  /// Estorna comissões de uma venda (quando venda é cancelada)
  static Future<void> estornarComissoesDaVenda({
    required String lojaId,
    required String vendaId,
    required String motivo,
  }) async {
    try {
      // Buscar configuração
      final config = await ComissaoConfigService.getConfig(lojaId);
      if (config?.estornoAutomaticoEmCancelamento != true) {
        debugPrint('ℹ️ [COMISSAO] Estorno automático desabilitado');
        return;
      }

      // Buscar comissões da venda
      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes')
          .where('vendaId', isEqualTo: vendaId)
          .where('status', whereIn: ['pendente', 'confirmado'])
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.update({
          'status': 'estornado',
          'statusPagamentoVenda': 'cancelado',
          'dataEstorno': DateTime.now().toIso8601String(),
          'motivoEstorno': motivo,
        });
      }

      debugPrint('✅ [COMISSAO] ${snapshot.docs.length} comissões estornadas da venda $vendaId');
    } catch (e) {
      debugPrint('❌ [COMISSAO] Erro ao estornar comissões da venda (type=${e.runtimeType})');
    }
  }

  /// Marca comissão como paga ao vendedor
  static Future<bool> marcarComoPago({
    required String lojaId,
    required String comissaoId,
  }) async {
    try {
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes')
          .doc(comissaoId)
          .update({
        'status': 'pago',
        'dataPagamento': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ [COMISSAO] Comissão $comissaoId marcada como paga');
      return true;
    } catch (e) {
      debugPrint('❌ [COMISSAO] Erro ao marcar como pago (type=${e.runtimeType})');
      return false;
    }
  }

  // ============================================================
  // CONSULTAS
  // ============================================================

  /// Lista comissões de um vendedor
  static Future<List<ComissaoVenda>> listarComissoesVendedor({
    required String lojaId,
    required String vendedorUid,
    DateTime? inicio,
    DateTime? fim,
    String? status,
    int limite = 100,
  }) async {
    try {
      Query query = _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes')
          .where('vendedorUid', isEqualTo: vendedorUid);

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }

      query = query.orderBy('dataVenda', descending: true).limit(limite);

      final snapshot = await query.get();

      final comissoes = snapshot.docs
          .map((doc) => ComissaoVenda.fromMap(doc.data() as Map<String, dynamic>, docId: doc.id))
          .toList();

      // Filtrar por data se necessário
      if (inicio != null || fim != null) {
        return comissoes.where((c) {
          if (inicio != null && c.dataVenda.isBefore(inicio)) return false;
          if (fim != null && c.dataVenda.isAfter(fim)) return false;
          return true;
        }).toList();
      }

      return comissoes;
    } catch (e) {
      debugPrint('❌ [COMISSAO] Erro ao listar comissões (type=${e.runtimeType})');
      return [];
    }
  }

  /// Lista todas as comissões da loja (admin)
  static Future<List<ComissaoVenda>> listarTodasComissoes({
    required String lojaId,
    DateTime? inicio,
    DateTime? fim,
    String? status,
    int limite = 200,
  }) async {
    try {
      Query query = _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes');

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }

      query = query.orderBy('dataVenda', descending: true).limit(limite);

      final snapshot = await query.get();

      final comissoes = snapshot.docs
          .map((doc) => ComissaoVenda.fromMap(doc.data() as Map<String, dynamic>, docId: doc.id))
          .toList();

      // Filtrar por data se necessário
      if (inicio != null || fim != null) {
        return comissoes.where((c) {
          if (inicio != null && c.dataVenda.isBefore(inicio)) return false;
          if (fim != null && c.dataVenda.isAfter(fim)) return false;
          return true;
        }).toList();
      }

      return comissoes;
    } catch (e) {
      debugPrint('❌ [COMISSAO] Erro ao listar todas comissões (type=${e.runtimeType})');
      return [];
    }
  }

  // ============================================================
  // RESUMOS E TOTAIS
  // ============================================================

  /// Calcula o total de comissões de um vendedor no período
  static Future<ResumoComissaoVendedor> calcularResumoVendedor({
    required String lojaId,
    required String vendedorUid,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    try {
      final comissoes = await listarComissoesVendedor(
        lojaId: lojaId,
        vendedorUid: vendedorUid,
        inicio: inicio,
        fim: fim,
      );

      double totalVendas = 0;
      double totalComissoesConfirmadas = 0;
      double totalComissoesPendentes = 0;
      double totalComissoesPagas = 0;
      int qtdVendas = 0;
      int qtdVendasCatalogo = 0;

      for (final c in comissoes) {
        if (c.status != 'estornado') {
          totalVendas += c.totalVenda;
          qtdVendas++;

          if (c.origem == 'catalogo') {
            qtdVendasCatalogo++;
          }

          switch (c.status) {
            case 'confirmado':
              totalComissoesConfirmadas += c.comissaoValor;
              break;
            case 'pendente':
              totalComissoesPendentes += c.comissaoValor;
              break;
            case 'pago':
              totalComissoesPagas += c.comissaoValor;
              break;
          }
        }
      }

      return ResumoComissaoVendedor(
        vendedorUid: vendedorUid,
        periodo: '${inicio.day}/${inicio.month} - ${fim.day}/${fim.month}',
        totalVendas: totalVendas,
        totalComissoesConfirmadas: totalComissoesConfirmadas,
        totalComissoesPendentes: totalComissoesPendentes,
        totalComissoesPagas: totalComissoesPagas,
        qtdVendas: qtdVendas,
        qtdVendasCatalogo: qtdVendasCatalogo,
      );
    } catch (e) {
      debugPrint('❌ [COMISSAO] Erro ao calcular resumo (type=${e.runtimeType})');
      return ResumoComissaoVendedor(
        vendedorUid: vendedorUid,
        periodo: '',
        totalVendas: 0,
        totalComissoesConfirmadas: 0,
        totalComissoesPendentes: 0,
        totalComissoesPagas: 0,
        qtdVendas: 0,
        qtdVendasCatalogo: 0,
      );
    }
  }

  /// Calcula resumo de comissões de todos os vendedores (para admin)
  static Future<List<ResumoComissaoVendedor>> calcularResumoTodosVendedores({
    required String lojaId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    try {
      // Buscar todos os vendedores com comissão configurada
      final vendedores = await ComissaoConfigService.listarVendedoresComissao(lojaId);

      final resumos = <ResumoComissaoVendedor>[];

      for (final vendedor in vendedores) {
        if (vendedor.ativo) {
          final resumo = await calcularResumoVendedor(
            lojaId: lojaId,
            vendedorUid: vendedor.vendedorUid,
            inicio: inicio,
            fim: fim,
          );

          // Adicionar info do vendedor
          resumos.add(ResumoComissaoVendedor(
            vendedorUid: vendedor.vendedorUid,
            vendedorNome: vendedor.vendedorNome,
            vendedorEmail: vendedor.vendedorEmail,
            percentualComissao: vendedor.comissaoPercentual,
            periodo: resumo.periodo,
            totalVendas: resumo.totalVendas,
            totalComissoesConfirmadas: resumo.totalComissoesConfirmadas,
            totalComissoesPendentes: resumo.totalComissoesPendentes,
            totalComissoesPagas: resumo.totalComissoesPagas,
            qtdVendas: resumo.qtdVendas,
            qtdVendasCatalogo: resumo.qtdVendasCatalogo,
          ));
        }
      }

      return resumos;
    } catch (e) {
      debugPrint('❌ [COMISSAO] Erro ao calcular resumo geral (type=${e.runtimeType})');
      return [];
    }
  }
}

/// Resultado do cálculo de comissão
class ComissaoCalculo {
  final double baseComissao;
  final double percentual;
  final double valor;
  final bool excluiuFrete;
  final bool descontoReduziuBase;

  ComissaoCalculo({
    required this.baseComissao,
    required this.percentual,
    required this.valor,
    required this.excluiuFrete,
    required this.descontoReduziuBase,
  });
}

/// Resumo de comissões de um vendedor
class ResumoComissaoVendedor {
  final String vendedorUid;
  final String? vendedorNome;
  final String? vendedorEmail;
  final double? percentualComissao;
  final String periodo;
  final double totalVendas;
  final double totalComissoesConfirmadas;
  final double totalComissoesPendentes;
  final double totalComissoesPagas;
  final int qtdVendas;
  final int qtdVendasCatalogo;

  ResumoComissaoVendedor({
    required this.vendedorUid,
    this.vendedorNome,
    this.vendedorEmail,
    this.percentualComissao,
    required this.periodo,
    required this.totalVendas,
    required this.totalComissoesConfirmadas,
    required this.totalComissoesPendentes,
    required this.totalComissoesPagas,
    required this.qtdVendas,
    required this.qtdVendasCatalogo,
  });

  double get totalComissoes =>
      totalComissoesConfirmadas + totalComissoesPendentes + totalComissoesPagas;

  double get comissaoAAReceber => totalComissoesConfirmadas;
}
