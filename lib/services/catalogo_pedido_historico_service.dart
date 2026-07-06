// Documento `lojas/{lojaId}/pedidos` para pós-pagamento (WhatsApp, status, roleta).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/logger.dart';
import '../repositories/pedido_repository.dart';
import 'catalogo_venda_helpers.dart';
import 'pedido_collection_resolver.dart';

/// Garante o doc em `pedidos` usado por PosPagamentoService (WhatsApp rico,
/// `atualizarStatusPedido`, `_ativarPremioRoleta`).
class CatalogoPedidoHistoricoService {
  CatalogoPedidoHistoricoService({PedidoRepository? pedidoRepository})
      : _pedidoRepository = pedidoRepository ?? PedidoRepository();

  static PedidoRepository? debugPedidoRepositoryOverride;

  PedidoRepository get _repo => debugPedidoRepositoryOverride ?? _pedidoRepository;

  final PedidoRepository _pedidoRepository;

  /// Idempotente por [vendaId]: retorna o id do doc existente ou recém-criado.
  Future<String?> garantirDocumentoPedidosHistorico({
    required String lojaId,
    required String vendaId,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> entrega,
    required String pagamento,
    required double subtotal,
    required double total,
    String observacao = '',
    Map<String, dynamic>? cupom,
    String? cupomFreteCodigo,
    Map<String, dynamic>? premioRoletaRaw,
  }) async {
    try {
      final existente = await _repo.findFirstRefByField(
        flowType: PedidoFlowType.pedidos,
        lojaId: lojaId,
        field: 'vendaId',
        value: vendaId,
      );
      if (existente != null) {
        return existente.id;
      }

      final data = _montarPayloadPedidosHistorico(
        lojaId: lojaId,
        vendaId: vendaId,
        customer: customer,
        items: items,
        entrega: entrega,
        pagamento: pagamento,
        subtotal: subtotal,
        total: total,
        observacao: observacao,
        cupom: cupom,
        cupomFreteCodigo: cupomFreteCodigo,
        premioRoletaRaw: premioRoletaRaw,
      );

      final ref = await _repo.createPedido(
        flowType: PedidoFlowType.pedidos,
        lojaId: lojaId,
        data: data,
      );
      return ref.id;
    } catch (e, st) {
      logE(
        '⚠️ [PEDIDO_HISTORICO] Falha ao garantir doc pedidos (type=${e.runtimeType})',
        error: e,
        st: st,
      );
      return null;
    }
  }

  static Map<String, dynamic> _montarPayloadPedidosHistorico({
    required String lojaId,
    required String vendaId,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> entrega,
    required String pagamento,
    required double subtotal,
    required double total,
    String observacao = '',
    Map<String, dynamic>? cupom,
    String? cupomFreteCodigo,
    Map<String, dynamic>? premioRoletaRaw,
  }) {
    final isPix = pagamento.toUpperCase() == 'PIX';
    final freteGratis = entrega['freteGratis'] == true;
    final freteValor = (entrega['valor'] as num?)?.toDouble() ?? 0.0;
    final desconto = (cupom?['desconto'] as num?)?.toDouble() ?? 0.0;
    final cupomCodigo = cupom?['codigo']?.toString();

    final cupomRoletaCodigo = premioRoletaRaw?['codigo']?.toString();
    final cupomRoletaDesconto =
        (premioRoletaRaw?['valor'] as num?)?.toDouble();
    final premioRoletaDescricao = premioRoletaRaw?['descricao']?.toString();

    final clientePayload = <String, dynamic>{
      'nome': customer['nome'],
      'email': customer['email'],
      'telefone': customer['telefone'] ?? customer['tel'],
      'endereco': customer['endereco'],
    };
    final enderecoFmt = (customer['enderecoFormatado'] ?? '').toString().trim();
    if (enderecoFmt.isNotEmpty) {
      clientePayload['enderecoFormatado'] = enderecoFmt;
    }

    return {
      'tipo': 'catalogo_web',
      'lojaId': lojaId,
      'vendaId': vendaId,
      'cliente': clientePayload,
      'itens': items
          .map((item) {
            final price =
                (item['preco'] ?? item['price'] ?? item['precoUnitario'] ?? 0.0)
                    as num;
            final qty = (item['quantidade'] as int?) ??
                (item['qty'] as int?) ??
                1;
            final pctPix =
                (item['percentualDescontoPix'] as num?)?.toDouble() ?? 0.0;
            final precoEfetivo = (isPix && pctPix > 0)
                ? (price.toDouble() * (1 - pctPix / 100))
                : price.toDouble();
            return {
              'nome': item['nome'] ?? item['name'] ?? '',
              'quantidade': qty,
              'precoUnitario': precoEfetivo,
              'tamanho': item['tamanho'] ?? item['size'] ?? '',
              'cor': item['cor'] ?? item['color'] ?? '',
              'imageUrl': item['imageUrl'] ?? item['url_foto'] ?? '',
              'total': precoEfetivo * qty,
              if (item['itensComboComSelecao'] is List &&
                  (item['itensComboComSelecao'] as List).isNotEmpty)
                'itensComboComSelecao': item['itensComboComSelecao'],
              if ((item['comboConfiguravelResumo'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty)
                'comboConfiguravelResumo':
                    (item['comboConfiguravelResumo'] ?? '').toString().trim(),
            };
          })
          .toList(),
      'subtotal': subtotal,
      'frete': {
        'nome': entrega['nome'],
        'valor': freteValor,
        'gratis': freteGratis,
        'tipo': entrega['tipo'],
      },
      'cupom': cupomCodigo != null && cupomCodigo.isNotEmpty
          ? {
              'codigo': cupomCodigo,
              'desconto': desconto,
            }
          : null,
      'cupomFrete': cupomFreteCodigo != null && cupomFreteCodigo.isNotEmpty
          ? {'codigo': cupomFreteCodigo}
          : null,
      'cupomRoleta': cupomRoletaCodigo != null && cupomRoletaCodigo.isNotEmpty
          ? {
              'codigo': cupomRoletaCodigo,
              'desconto': cupomRoletaDesconto,
            }
          : null,
      'premioRoleta': premioRoletaDescricao != null ||
              (cupomRoletaCodigo != null && cupomRoletaCodigo.isNotEmpty)
          ? {
              'descricao': premioRoletaDescricao ?? '',
              'tipo': determinarTipoPremio(
                premioRoletaDescricao,
                cupomRoletaCodigo,
                cupomRoletaDesconto,
              ),
              'valor': cupomRoletaDesconto ?? 0.0,
              'codigo': cupomRoletaCodigo,
              'status': 'pendente',
              'dataGanho': FieldValue.serverTimestamp(),
              'dataAtivacao': null,
              'valido': false,
            }
          : null,
      'total': total,
      'pagamento': pagamento,
      'observacao': observacao,
      'dataHora': FieldValue.serverTimestamp(),
      'status': 'concluido',
      'origem': 'catalogo',
    };
  }
}
