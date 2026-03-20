// lib/screens/visualizar_produto_catalogo_screen.dart
import 'package:flutter/material.dart';

import '../utils/image_helper.dart' as img_helper;
import 'package:hive/hive.dart';

import '../models/produto_catalogo.dart';
import 'cadastro_catalogo_screen.dart';

class VisualizarProdutoCatalogoScreen extends StatelessWidget {
  final ProdutoCatalogo produto;

  const VisualizarProdutoCatalogoScreen({super.key, required this.produto});

  Future<bool> _podeEditarProduto() async {
    try {
      final sessaoBox = await Hive.openBox('sessao');
      final tipo = (sessaoBox.get('tipo_usuario') as String?)
              ?.toLowerCase()
              .trim() ??
          '';

      return tipo == 'admin' || tipo == 'programador';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _podeEditarProduto(),
      builder: (context, snapshot) {
        final podeEditar = snapshot.data ?• false;

        return Scaffold(
          appBar: AppBar(title: const Text('Detalhes do Produto')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (produto.imagens.isNotEmpty)
                  SizedBox(
                    height: 250,
                    child: PageView.builder(
                      itemCount: produto.imagens.length,
                      itemBuilder: (context, index) {
                        final caminho = produto.imagens[index];
                        final lower = caminho.toLowerCase();
                        final isImage = lower.endsWith('.jpg') ||
                            lower.endsWith('.jpeg') ||
                            lower.endsWith('.png') ||
                            lower.endsWith('.webp');

                        if (!isImage || !img_helper.imageFileExists(caminho)) {
                          return const Center(
                            child: Text(
                              'Imagem não suportada ou inexistente',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: img_helper.buildPlatformImage(
                              caminho,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  produto.nome,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                if (produto.descricao != null &&
                    produto.descricao!.isNotEmpty)
                  Text(
                    'Descrição: ${produto.descricao}',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 10),
                if (produto.sobre != null && produto.sobre!.isNotEmpty)
                  Text(
                    'Sobre: ${produto.sobre}',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 10),
                if (produto.tamanhos.isNotEmpty)
                  Text(
                    'Tamanhos disponíveis: ${produto.tamanhos.join(", ")}',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Preço: R\$ ${produto.precoFinal.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, color: Colors.green),
                ),
                const SizedBox(height: 30),
                if (podeEditar)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.edit),
                        label: const Text('Editar'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CadastroCatalogoScreen(produto: produto),
                            ),
                          );
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.delete),
                        label: const Text('Excluir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () async {
                          final confirmar = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Excluir Produto'),
                              content: const Text(
                                  'Deseja realmente excluir este produto?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Confirmar'),
                                ),
                              ],
                            ),
                          );

                          if (confirmar == true) {
                            await produto.delete();
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
