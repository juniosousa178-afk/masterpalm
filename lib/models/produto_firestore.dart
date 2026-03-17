// lib/models/produto_firestore.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ProdutoFirestore {
  final String id;
  final String nome;
  final double preco;
  final String? descricao;
  final String categoriaId;
  final String subcategoriaId;
  final List<String> imagens;
  final Map<String, int>? estoquePorTamanho;
  final Map<String, int>? estoquePorCor;
  final int? quantidade;

  ProdutoFirestore({
    required this.id,
    required this.nome,
    required this.preco,
    required this.categoriaId,
    required this.subcategoriaId,
    this.descricao,
    this.imagens = const [],
    this.estoquePorTamanho,
    this.estoquePorCor,
    this.quantidade,
  });

  factory ProdutoFirestore.fromSnap(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};

    // preço tolerante
    final num nPreco =
        (m['preco'] ?? m['precoVenda'] ?? m['price'] ?? 0) as num;

    // imagens tolerantes
    List<String> imagens() {
      if (m['imagens'] is List) {
        return (m['imagens'] as List).map((e) => e.toString()).toList();
      }
      final unica =
          (m['imagem'] ?? m['imageUrl'] ?? m['foto'] ?? '').toString();
      return unica.isEmpty ? <String>[] : <String>[unica];
    }

    // estoque por tamanho (opcional)
    Map<String, int>? estoqueTamanho() {
      final v = m['estoquePorTamanho'];
      if (v is Map) {
        return v.map((k, val) {
          final n = (val is num) ? val.toInt() : int.tryParse('$val') ?? 0;
          return MapEntry('$k', n);
        });
      }
      return null;
    }

    // estoque por cor (opcional)
    Map<String, int>? estoqueCor() {
      final v = m['estoquePorCor'];
      if (v is Map) {
        return v.map((k, val) {
          final n = (val is num) ? val.toInt() : int.tryParse('$val') ?? 0;
          return MapEntry('$k', n);
        });
      }
      return null;
    }

    return ProdutoFirestore(
      id: d.id,
      nome: (m['nome'] ?? m['name'] ?? '').toString(),
      preco: nPreco.toDouble(),
      descricao: (m['descricao'] ?? m['description'] ?? '').toString(),
      categoriaId: (m['categoriaId'] ?? m['categoria'] ?? '').toString(),
      subcategoriaId:
          (m['subcategoriaId'] ?? m['subcategoria'] ?? '').toString(),
      imagens: imagens(),
      estoquePorTamanho: estoqueTamanho(),
      estoquePorCor: estoqueCor(),
      quantidade:
          (m['quantidade'] is num) ? (m['quantidade'] as num).toInt() : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'preco': preco,
        'descricao': descricao,
        'categoriaId': categoriaId,
        'subcategoriaId': subcategoriaId,
        'imagens': imagens,
        'estoquePorTamanho': estoquePorTamanho,
        'estoquePorCor': estoquePorCor,
        'quantidade': quantidade,
      };
}
