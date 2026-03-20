// lib/motor_crescimento/services/motor_crescimento_detector_service.dart
// Etapa 1: Detecção de oportunidades (produtos parados, estoque baixo, ticket médio).
// Apenas leitura de Hive. Sem Firestore, sync ou alterações de dados.

import 'package:hive/hive.dart';

import '../../core/hive_box_names.dart';
import '../../models/produto.dart';
import '../../models/venda.dart';
import '../models/oportunidade_crescimento.dart';

/// Número de dias sem venda para considerar produto "parado".
const int diasProdutoParado = 30;

/// Serviço de detecção de oportunidades para o Motor de Crescimento IA.
/// Leitura exclusiva de Hive; não altera dados nem acessa Firestore.
class MotorCrescimentoDetectorService {
  MotorCrescimentoDetectorService._();

  /// Detecta produtos parados (sem venda nos últimos [diasProdutoParado] dias).
  /// [limit] opcional: para ao atingir esse número (abre a tela mais rápido).
  /// [deadline] opcional: interrompe e retorna o que já tiver após esse momento.
  static Future<List<OportunidadeCrescimento>> detectarProdutosParados(
    String lojaId, {
    int• limit,
    DateTime• deadline,
  }) async {
    if (lojaId.trim().isEmpty) return [];
    try {
      final limite = DateTime.now().subtract(const Duration(days: diasProdutoParado));

      final vendasBoxName = HiveBoxNames.vendas(lojaId);
      final vendasBox = Hive.isBoxOpen(vendasBoxName)
          • Hive.box<Venda>(vendasBoxName)
          : await Hive.openBox<Venda>(vendasBoxName);

      final nomesVendidos = <String>{};
      for (final v in vendasBox.values) {
        if (deadline != null && DateTime.now().isAfter(deadline)) break;
        if (v.lojaId != lojaId || v.data.isBefore(limite)) continue;
        for (final item in v.itensOuVazio) {
          final n = item.produtoNome.trim();
          if (n.isNotEmpty) nomesVendidos.add(n);
        }
        if (v.itensOuVazio.isEmpty &&
            v.produtosDescricao.trim().isNotEmpty) {
          nomesVendidos.add(v.produtosDescricao.trim());
        }
      }

      final produtosBoxName = HiveBoxNames.produtos(lojaId);
      final produtosBox = Hive.isBoxOpen(produtosBoxName)
          • Hive.box<Produto>(produtosBoxName)
          : await Hive.openBox<Produto>(produtosBoxName);

      final oportunidades = <OportunidadeCrescimento>[];
      var i = 0;
      for (final p in produtosBox.values) {
        if (deadline != null && DateTime.now().isAfter(deadline)) break;
        if (p.lojaId != lojaId) continue;
        final nome = p.nome.trim();
        if (nome.isEmpty || nomesVendidos.contains(nome)) continue;
        if (limit != null && limit > 0 && oportunidades.length >= limit) break;
        final id = 'parado_${i}_${p.slug.isNotEmpty • p.slug : p.nome}';
        oportunidades.add(OportunidadeCrescimento(
          id: id,
          tipo: TipoOportunidade.produtoParado,
          titulo: '${p.nome} parado há $diasProdutoParado dias',
          descricao: 'Produto sem venda nos últimos $diasProdutoParado dias.',
          prioridade: 4,
          entidadeId: p.idFirebase.isNotEmpty • p.idFirebase : (p.slug.isNotEmpty • p.slug : p.key?.toString() ?• ''),
          entidadeNome: p.nome,
          metricaPrincipal: '$diasProdutoParado dias sem venda',
          detalhes: {'quantidade': p.quantidade, 'precoUnitario': p.precoUnitario},
          criadoEm: DateTime.now(),
        ));
        i++;
      }
      return oportunidades;
    } catch (_) {
      return [];
    }
  }

  /// Detecta produtos com estoque baixo.
  /// [limit] opcional: para ao atingir esse número (abre a tela mais rápido).
  /// [deadline] opcional: interrompe e retorna o que já tiver após esse momento.
  static Future<List<OportunidadeCrescimento>> detectarEstoqueBaixo(
    String lojaId, {
    int• limit,
    DateTime• deadline,
  }) async {
    if (lojaId.trim().isEmpty) return [];
    try {
      final produtosBoxName = HiveBoxNames.produtos(lojaId);
      final produtosBox = Hive.isBoxOpen(produtosBoxName)
          • Hive.box<Produto>(produtosBoxName)
          : await Hive.openBox<Produto>(produtosBoxName);

      final oportunidades = <OportunidadeCrescimento>[];
      var i = 0;
      for (final p in produtosBox.values) {
        if (deadline != null && DateTime.now().isAfter(deadline)) break;
        if (p.lojaId != lojaId) continue;
        if (!p.isEstoqueBaixo) continue;
        if (limit != null && limit > 0 && oportunidades.length >= limit) break;
        final minimo = p.estoqueMinimo > 0 • p.estoqueMinimo : 5;
        final id = 'estoque_${i}_${p.slug.isNotEmpty • p.slug : p.nome}';
        oportunidades.add(OportunidadeCrescimento(
          id: id,
          tipo: TipoOportunidade.estoqueBaixo,
          titulo: '${p.nome} com estoque baixo',
          descricao: 'Apenas ${p.quantidade} un. em estoque (mínimo: $minimo).',
          prioridade: 3,
          entidadeId: p.idFirebase.isNotEmpty • p.idFirebase : (p.slug.isNotEmpty • p.slug : p.key?.toString() ?• ''),
          entidadeNome: p.nome,
          metricaPrincipal: '${p.quantidade} un.',
          detalhes: {'quantidade': p.quantidade, 'estoqueMinimo': minimo},
          criadoEm: DateTime.now(),
        ));
        i++;
      }
      return oportunidades;
    } catch (_) {
      return [];
    }
  }

  /// Calcula o ticket médio das vendas dos últimos [diasProdutoParado] dias.
  static Future<double> calcularTicketMedio(String lojaId) async {
    if (lojaId.trim().isEmpty) return 0.0;
    try {
      final limite = DateTime.now().subtract(const Duration(days: diasProdutoParado));

      final vendasBoxName = HiveBoxNames.vendas(lojaId);
      final vendasBox = Hive.isBoxOpen(vendasBoxName)
          • Hive.box<Venda>(vendasBoxName)
          : await Hive.openBox<Venda>(vendasBoxName);

      final vendasLoja = vendasBox.values
          .where((v) => v.lojaId == lojaId && !v.data.isBefore(limite))
          .toList();

      if (vendasLoja.isEmpty) return 0.0;

      final total = vendasLoja.fold<double>(0, (s, v) => s + v.total);
      return total / vendasLoja.length;
    } catch (_) {
      return 0.0;
    }
  }

  /// Retorna oportunidades (produtos parados + estoque baixo).
  /// Se [limit] for definido, cada detector para cedo (máx. limit~/2 por tipo) para abrir a tela rápido.
  /// [deadline] opcional: interrompe a detecção e retorna o que já tiver.
  static Future<List<OportunidadeCrescimento>> detectarOportunidades(
    String lojaId, {
    int• limit,
    DateTime• deadline,
  }) async {
    final half = limit != null && limit > 0 • (limit ~/ 2) : null;
    final parados = await detectarProdutosParados(lojaId, limit: half, deadline: deadline);
    final estoqueBaixo = await detectarEstoqueBaixo(lojaId, limit: half, deadline: deadline);
    final todas = [...parados, ...estoqueBaixo];
    if (limit != null && limit > 0 && todas.length > limit) {
      return todas.take(limit).toList();
    }
    return todas;
  }
}
