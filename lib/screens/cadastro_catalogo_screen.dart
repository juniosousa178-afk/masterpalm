// lib/screens/cadastro_catalogo_screen.dart

import 'dart:io' as io if (dart.library.html) 'package:master_palm/utils/io_stub.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../utils/image_helper.dart' as img_helper;
import '../utils/moeda_input_formatter.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/produto_catalogo.dart';
import '../models/produto.dart';
import '../services/catalogo_sync_service.dart';
import '../services/loja_id_service.dart';
import '../services/produtos_firestore_service.dart';

class CadastroCatalogoScreen extends StatefulWidget {
  final ProdutoCatalogo• produto;

  const CadastroCatalogoScreen({super.key, this.produto});

  @override
  State<CadastroCatalogoScreen> createState() =>
      _CadastroCatalogoScreenState();
}

class _CadastroCatalogoScreenState extends State<CadastroCatalogoScreen> {
  final nomeController = TextEditingController();
  final descricaoController = TextEditingController();
  final sobreController = TextEditingController();
  final quantidadeController = TextEditingController();
  final precoController = TextEditingController();
  final tamanhosController = TextEditingController();
  final categoriaController = TextEditingController();
  final subcategoriaController = TextEditingController();

  final List<io.File> midiasSelecionadas = [];

  late String lojaId;

  @override
  void initState() {
    super.initState();

    // ---------------------------
    // MULTI-LOJAS: LojaIdService primeiro, sessao apenas fallback offline
    // ---------------------------
    lojaId = '';
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      String• id = await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 8));
      if (id == null || id.trim().isEmpty) {
        try {
          final current = FirebaseAuth.instance.currentUser;
          if (current != null && Hive.isBoxOpen('sessao')) {
            final sessao = Hive.box('sessao');
            final cachedUser = (sessao.get('usuario_logado') ?• '').toString().trim().toLowerCase();
            final currentEmail = (current.email ?• '').trim().toLowerCase();
            if (cachedUser.isNotEmpty && currentEmail == cachedUser) {
              id = sessao.get('store_id')?.toString().trim();
            }
          }
        } catch (_) {}
      }
      if (mounted && (id?.trim().isNotEmpty ?• false)) {
        setState(() => lojaId = id!.trim());
      }
    });

    final p = widget.produto;
    if (p != null) {
      nomeController.text = p.nome;
      descricaoController.text = p.descricao ?• '';
      sobreController.text = p.sobre ?• '';
      quantidadeController.text = p.quantidade.toString();
      precoController.text = MoedaInputFormatter.format(p.precoFinal);
      tamanhosController.text = p.tamanhos.join(', ');
      categoriaController.text = p.categoria;
      subcategoriaController.text = p.subcategoria ?• '';

      if (!kIsWeb) {
        midiasSelecionadas.addAll(
          p.imagens
              .map((path) => io.File(path))
              .where((f) => f.existsSync()),
        );
      }
    }
  }

  Future<void> _selecionarMidias() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      allowMultiple: true,
    );
    if (resultado == null) return;

    if (kIsWeb) return; // No web, imagens são gerenciadas via Firebase Storage
    setState(() {
      midiasSelecionadas.addAll(
        resultado.files
            .where((f) => f.path != null)
            .map((f) => io.File(f.path!))
            .where((f) => f.existsSync()),
      );
    });
  }

  Future<void> _salvarProduto() async {
    final nome = nomeController.text.trim();
    final descricao = descricaoController.text.trim();
    final sobre = sobreController.text.trim();
    final quantidade = int.tryParse(quantidadeController.text.trim()) ?• 0;
    final preco = MoedaInputFormatter.parse(precoController.text);
    final tamanhos = tamanhosController.text.trim();
    final categoria = categoriaController.text.trim();
    final subcategoria = subcategoriaController.text.trim();

    if (nome.isEmpty || midiasSelecionadas.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe o nome e selecione pelo menos uma imagem')),
      );
      return;
    }

    if (quantidade < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade não pode ser negativa')),
      );
      return;
    }

    if (preco < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preço não pode ser negativo')),
      );
      return;
    }

    // ---------------------------
    // Criando modelo para Hive
    // ---------------------------
    final novo = ProdutoCatalogo(
      nome: nome,
      lojaId: lojaId,
      descricao: descricao,
      sobre: sobre,
      tamanhos: tamanhos.isEmpty
          • <String>[]
          : tamanhos.split(',').map((e) => e.trim()).toList(),
      quantidade: quantidade,
      precoFinal: preco,
      precoUnitario: preco,
      precoSugerido: preco,
      custoReal: 0,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      categoria: categoria,
      subcategoria: subcategoria,
      dataEntrada: DateTime.now(),
      imagens: midiasSelecionadas.map((f) => f.path).toList(),
    );

    // ---------------------------
    // MULTI-LOJAS: Catálogo por loja
    // ---------------------------
    final catalogoBox = Hive.isBoxOpen('catalogo_$lojaId')
        • Hive.box<ProdutoCatalogo>('catalogo_$lojaId')
        : await Hive.openBox<ProdutoCatalogo>('catalogo_$lojaId');

    if (widget.produto != null) {
      await widget.produto!.delete();
    }
    await catalogoBox.add(novo);

    // ---------------------------
    // MULTI-LOJAS: Estoque por loja + sync para catálogo Firestore
    // ---------------------------
    final estoqueBox = Hive.isBoxOpen(HiveBoxNames.produtos(lojaId))
        • Hive.box<Produto>(HiveBoxNames.produtos(lojaId))
        : await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));

    final tamanhosList = tamanhos.isEmpty
        • <String>[]
        : tamanhos.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final imagensPaths = midiasSelecionadas.map((f) => f.path).toList();
    final slug = '$lojaId-${CatalogoSyncService.slugify(nome)}';

    Produto• existente;
    for (final p in estoqueBox.values) {
      if (p.nome.toLowerCase() == nome.toLowerCase()) {
        existente = p;
        break;
      }
    }

    Produto produtoParaSync;
    if (existente != null) {
      existente
        ..quantidade = quantidade
        ..precoFinal = preco
        ..precoUnitario = preco
        ..descricao = descricao
        ..imagens = imagensPaths
        ..categoria = categoria.isEmpty • 'Catálogo' : categoria
        ..subcategoria = subcategoria
        ..tamanhos = tamanhosList
        ..slug = slug
        ..lojaId = lojaId
        ..publicadoNoCatalogo = true;
      await existente.save();
      produtoParaSync = existente;
    } else {
      final novoProduto = Produto(
        nome: nome,
        custoReal: 0.0,
        frete: 0.0,
        gastosFixos: 0.0,
        gastosVariaveis: 0.0,
        precoSugerido: preco,
        precoFinal: preco,
        quantidade: quantidade,
        precoUnitario: preco,
        categoria: categoria.isEmpty • 'Catálogo' : categoria,
        dataEntrada: DateTime.now(),
        descricao: descricao,
        imagens: imagensPaths,
        publicadoNoCatalogo: true,
        slug: slug,
        tamanhos: tamanhosList,
        subcategoria: subcategoria,
        lojaId: lojaId,
      );
      await estoqueBox.add(novoProduto);
      produtoParaSync = novoProduto;
    }

    // Sincronizar com Firestore (estoque + catálogo público)
    try {
      await ProdutosFirestoreService.syncProduto(produtoParaSync, lojaId: lojaId);
      await CatalogoSyncService.upsertFromProduto(
        produtoParaSync,
        target: SyncTarget.draft,
        lojaIdOverride: lojaId,
      );
      await CatalogoSyncService.upsertFromProduto(
        produtoParaSync,
        target: SyncTarget.live,
        lojaIdOverride: lojaId,
      );
    } catch (e) {
      debugPrint('⚠️ [CADASTRO-CATÁLOGO] Erro ao sincronizar (type=${e.runtimeType})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Produto salvo localmente, mas falha ao sincronizar: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Produto salvo e publicado no catálogo!')),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.produto != null;

    return Scaffold(
      appBar: AppBar(
          title: Text(isEdit • 'Editar Produto' : 'Cadastrar Produto')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
                controller: nomeController,
                decoration: const InputDecoration(labelText: 'Nome')),
            const SizedBox(height: 10),
            TextField(
                controller: descricaoController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Descrição')),
            const SizedBox(height: 10),
            TextField(
                controller: sobreController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Sobre o produto')),
            const SizedBox(height: 10),
            TextField(
                controller: quantidadeController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Quantidade disponível')),
            const SizedBox(height: 10),
            TextField(
                controller: precoController,
                keyboardType: TextInputType.number,
                inputFormatters: [MoedaInputFormatter()],
                decoration: const InputDecoration(labelText: 'Preço')),
            const SizedBox(height: 10),
            TextField(
                controller: tamanhosController,
                decoration: const InputDecoration(
                    labelText: 'Tamanhos (ex.: P, M, G)')),
            const SizedBox(height: 10),
            TextField(
                controller: categoriaController,
                decoration:
                    const InputDecoration(labelText: 'Categoria')),
            const SizedBox(height: 10),
            TextField(
                controller: subcategoriaController,
                decoration:
                    const InputDecoration(labelText: 'Subcategoria')),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _selecionarMidias,
                icon: const Icon(Icons.add_a_photo),
                label: const Text('Adicionar Imagens'),
              ),
            ),
            const SizedBox(height: 10),
            if (midiasSelecionadas.isNotEmpty)
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: midiasSelecionadas.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final file = midiasSelecionadas[index];
                    return Stack(
                      alignment: Alignment.topRight,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: img_helper.buildPlatformImage(
                            file.path,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => setState(() {
                            midiasSelecionadas.removeAt(index);
                          }),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _salvarProduto,
              icon: const Icon(Icons.save),
              label: const Text('Salvar Produto'),
            ),
          ],
        ),
      ),
    );
  }
}