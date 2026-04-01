import 'package:hive/hive.dart';

import '../core/compra_item_pipeline_constants.dart';

part 'compra_item_pipeline.g.dart';

/// Item vindo de compra confirmada, até finalização no estoque.
/// Chave Hive [id] = [compraId]_[itemCompraId] (ver [CompraItemPipeline.docId]).
@HiveType(typeId: 34)
class CompraItemPipeline extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String lojaId;

  @HiveField(2)
  String compraId;

  @HiveField(3)
  String itemCompraId;

  @HiveField(4)
  String fornecedorNome;

  @HiveField(5)
  String referenciaCompra;

  @HiveField(6)
  String nomeProdutoProvisorio;

  @HiveField(7)
  int quantidade;

  @HiveField(8)
  double custoUnitario;

  @HiveField(9)
  String codigoInterno;

  @HiveField(10)
  String codigoBarras;

  @HiveField(11)
  String observacaoItem;

  @HiveField(12)
  String unidade;

  /// idFirebase do produto já existente (opcional), definido na compra.
  @HiveField(13)
  String? productIdFirebase;

  @HiveField(14)
  String estado;

  @HiveField(15)
  double precoSugerido;

  @HiveField(16)
  double precoFinal;

  @HiveField(17)
  double precoPretendidoUsuario;

  @HiveField(18)
  int? produtoHiveKey;

  @HiveField(19)
  String produtoIdFirebaseGravado;

  @HiveField(20)
  DateTime atualizadoEm;

  CompraItemPipeline({
    required this.id,
    required this.lojaId,
    required this.compraId,
    required this.itemCompraId,
    this.fornecedorNome = '',
    this.referenciaCompra = '',
    required this.nomeProdutoProvisorio,
    required this.quantidade,
    required this.custoUnitario,
    this.codigoInterno = '',
    this.codigoBarras = '',
    this.observacaoItem = '',
    this.unidade = '',
    this.productIdFirebase,
    this.estado = CompraItemPipelineEstado.aguardandoPrecificacao,
    this.precoSugerido = 0,
    this.precoFinal = 0,
    this.precoPretendidoUsuario = 0,
    this.produtoHiveKey,
    this.produtoIdFirebaseGravado = '',
    DateTime? atualizadoEm,
  }) : atualizadoEm = atualizadoEm ?? DateTime.now();

  static String docId(String compraId, String itemCompraId) {
    final c = compraId.trim();
    final i = itemCompraId.trim();
    return '${c}_$i';
  }

  CompraItemPipeline copyWith({
    String? id,
    String? lojaId,
    String? compraId,
    String? itemCompraId,
    String? fornecedorNome,
    String? referenciaCompra,
    String? nomeProdutoProvisorio,
    int? quantidade,
    double? custoUnitario,
    String? codigoInterno,
    String? codigoBarras,
    String? observacaoItem,
    String? unidade,
    String? productIdFirebase,
    String? estado,
    double? precoSugerido,
    double? precoFinal,
    double? precoPretendidoUsuario,
    int? produtoHiveKey,
    String? produtoIdFirebaseGravado,
    DateTime? atualizadoEm,
  }) {
    return CompraItemPipeline(
      id: id ?? this.id,
      lojaId: lojaId ?? this.lojaId,
      compraId: compraId ?? this.compraId,
      itemCompraId: itemCompraId ?? this.itemCompraId,
      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      referenciaCompra: referenciaCompra ?? this.referenciaCompra,
      nomeProdutoProvisorio:
          nomeProdutoProvisorio ?? this.nomeProdutoProvisorio,
      quantidade: quantidade ?? this.quantidade,
      custoUnitario: custoUnitario ?? this.custoUnitario,
      codigoInterno: codigoInterno ?? this.codigoInterno,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      observacaoItem: observacaoItem ?? this.observacaoItem,
      unidade: unidade ?? this.unidade,
      productIdFirebase: productIdFirebase ?? this.productIdFirebase,
      estado: estado ?? this.estado,
      precoSugerido: precoSugerido ?? this.precoSugerido,
      precoFinal: precoFinal ?? this.precoFinal,
      precoPretendidoUsuario:
          precoPretendidoUsuario ?? this.precoPretendidoUsuario,
      produtoHiveKey: produtoHiveKey ?? this.produtoHiveKey,
      produtoIdFirebaseGravado:
          produtoIdFirebaseGravado ?? this.produtoIdFirebaseGravado,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
    );
  }
}
