// lib/utils/fs_paths.dart
import 'pedido_collection_resolver.dart';

class FSPaths {
  /// Documento principal da loja
  static String lojaDoc(String lojaId) => 'lojas/$lojaId';

  /// Coleção de produtos
  static String produtosCol(String lojaId) => 'lojas/$lojaId/produtos';

  /// Coleções de estoque/sync (admin) — use com .collection(lojas).doc(lojaId).collection(...)
  static const String estoqueProdutosCol = 'estoque_produtos';
  static const String estoqueClientesCol = 'estoque_clientes'; // DOMÍNIO ADMIN: sync/histórico, não é perfil catálogo
  static const String estoqueVendasCol = 'estoque_vendas';
  static const String draftProdutosCol = 'draft_produtos';

  /// Exclusão definitiva (tombstone) p/ impedir ressurreição pós sync multi‑dispositivo.
  static const String exclusaoProdutoCol = 'exclusao_produto';

  /// Contas a receber / fiado (sync Hive ↔ Firestore).
  static const String contasReceberCol = 'contas_receber';

  /// Path da coleção `lojas/{lojaId}/contas_receber`.
  static String contasReceberColPath(String lojaId) =>
      'lojas/$lojaId/$contasReceberCol';

  /// Path do documento `lojas/{lojaId}/contas_receber/{contaId}`.
  static String contaReceberDocPath(String lojaId, String contaId) =>
      '${contasReceberColPath(lojaId)}/$contaId';

  /// Coleções de clientes (auth catálogo, cupons, perfil) — use com .collection(lojas).doc(lojaId).collection(...)
  /// FASE 4: clientes = FONTE PRINCIPAL; clientes_portal = espelho; clientes_catalogo = cupons/roleta; clientes_web = legado.
  static const String clientesCol = 'clientes';
  static const String clientesCatalogoCol = 'clientes_catalogo'; // USO ESPECÍFICO: cupons roleta
  static const String clientesWebCol = 'clientes_web'; // LEGADO: catálogo admin, não usar para catálogo público
  static const String clientesPortalCol = 'clientes_portal'; // ESPELHO DERIVADO: Meus Pedidos

  /// Coleção de categorias
  static String categoriasCol(String lojaId) => 'lojas/$lojaId/categorias';

  /// Coleção de subcategorias
  static String subcategoriasCol(String lojaId) =>
      'lojas/$lojaId/subcategorias';

  /// Coleção de pedidos
  static String pedidosCol(String lojaId) => PedidoCollectionResolver.collectionPath(
        flowType: PedidoFlowType.pedidos,
        lojaId: lojaId,
      );

  static String prePedidosCol(String lojaId) =>
      PedidoCollectionResolver.collectionPath(
        flowType: PedidoFlowType.prePedidos,
        lojaId: lojaId,
      );

  static String pedidoStatusPublicoCol(String lojaId) =>
      PedidoCollectionResolver.collectionPath(
        flowType: PedidoFlowType.pedidoStatusPublico,
        lojaId: lojaId,
      );

  static String pedidosPendentesCol(String lojaId) =>
      PedidoCollectionResolver.collectionPath(
        flowType: PedidoFlowType.pedidosPendentes,
        lojaId: lojaId,
      );

  static String pedidosTempCol(String lojaId) =>
      PedidoCollectionResolver.collectionPath(
        flowType: PedidoFlowType.pedidosTemp,
        lojaId: lojaId,
      );

  static String pedidoTempLegadoCol(String lojaId) =>
      PedidoCollectionResolver.collectionPath(
        flowType: PedidoFlowType.pedidoTempLegado,
        lojaId: lojaId,
      );

  static String pedidosCatalogoCol(String lojaId) =>
      PedidoCollectionResolver.collectionPath(
        flowType: PedidoFlowType.pedidosCatalogo,
        lojaId: lojaId,
      );

  static String rootPedidosTempCol() =>
      PedidoCollectionResolver.collectionPath(
        flowType: PedidoFlowType.rootPedidosTemp,
      );
}
