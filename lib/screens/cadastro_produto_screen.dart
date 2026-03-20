// lib/screens/cadastro_produto_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/text_utils.dart';
import '../utils/moeda_input_formatter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class CadastroProdutoScreen extends StatefulWidget {
  final String idLoja;

  const CadastroProdutoScreen({super.key, required this.idLoja});

  @override
  State<CadastroProdutoScreen> createState() => _CadastroProdutoScreenState();
}

class _CadastroProdutoScreenState extends State<CadastroProdutoScreen> {
  // Modern color scheme
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _cardColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _surfaceColor = Color(0xFF1E293B);

  final _formKey = GlobalKey<FormState>();

  // Controladores de texto
  final _nomeCtrl = TextEditingController();
  final _precoCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  final _categoriaCtrl = TextEditingController();
  final _subcategoriaCtrl = TextEditingController();
  final _quantidadeCtrl = TextEditingController(text: '1');

  // Ativo na preview
  bool _ativoNoRascunho = true;

  // Midias
  final List<PlatformFile> _arquivos = [];
  final List<String> _imagensUrls = [];

  bool _salvando = false;

  // Categorias/subcategorias existentes (para autocomplete)
  List<String> _categoriasExistentes = [];
  List<String> _subcategoriasExistentes = [];

  // ================== TAMANHOS ==================
  final List<_EstoqueItem> _tamanhos = [];
  final _novoTamanhoCtrl = TextEditingController();
  final _novoTamanhoQtdCtrl = TextEditingController(text: '0');

  // ================== CORES ==================
  final List<_EstoqueItem> _cores = [];
  final _novaCorCtrl = TextEditingController();
  final _novaCorQtdCtrl = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _carregarCategoriasExistentes();
  }

  Future<void> _carregarCategoriasExistentes() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.idLoja)
          .collection('estoque_produtos')
          .limit(500)
          .get();
      final categorias = <String>{};
      final subcategorias = <String>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final c = (d['categoria'] ?• '').toString().trim();
        final s = (d['subcategoria'] ?• '').toString().trim();
        if (c.isNotEmpty) categorias.add(c);
        if (s.isNotEmpty) subcategorias.add(s);
      }
      if (mounted) {
        setState(() {
          _categoriasExistentes = categorias.toList()..sort();
          _subcategoriasExistentes = subcategorias.toList()..sort();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _precoCtrl.dispose();
    _descricaoCtrl.dispose();
    _categoriaCtrl.dispose();
    _subcategoriaCtrl.dispose();
    _quantidadeCtrl.dispose();
    _novoTamanhoCtrl.dispose();
    _novoTamanhoQtdCtrl.dispose();
    _novaCorCtrl.dispose();
    _novaCorQtdCtrl.dispose();
    super.dispose();
  }

  // ================== MIDIAS ==================

  Future<void> _selecionarImagens() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (pick == null || pick.files.isEmpty) return;
    setState(() => _arquivos.addAll(pick.files));
  }

  void _removerArquivo(int i) {
    setState(() => _arquivos.removeAt(i));
  }

  void _reordenarArquivo(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final f = _arquivos.removeAt(oldIndex);
      _arquivos.insert(newIndex, f);
    });
  }

  String _guessContentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  Future<List<String>> _uploadImagens(String productId) async {
    final storage = FirebaseStorage.instance;
    final List<String> urls = [];

    for (final f in _arquivos) {
      try {
        final fileName = f.name;
        final ref = storage
            .ref('lojas/${widget.idLoja}/draft_produtos/$productId/$fileName');

        UploadTask task;
        if (kIsWeb) {
          if (f.bytes == null) continue;
          task = ref.putData(
            f.bytes!,
            SettableMetadata(contentType: _guessContentType(fileName)),
          );
        } else {
          final path = f.path;
          if (path == null) continue;
          task = ref.putFile(
            File(path),
            SettableMetadata(contentType: _guessContentType(fileName)),
          );
        }

        final snap = await task;
        final url = await snap.ref.getDownloadURL();
        urls.add(url);
      } catch (e) {
        // Continua para proxima imagem
      }
    }
    return urls;
  }

  // ================== PARSE/HELPERS ==================

  double _parsePreco(String s) {
    return MoedaInputFormatter.parse(s);
  }

  int _parseQtd(String s) {
    final norm = s.replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(norm) ?• 0;
  }

  // ================== TAMANHOS - CRUD ==================

  void _adicionarTamanho() {
    final nome = _novoTamanhoCtrl.text.trim().toUpperCase();
    final qtd = int.tryParse(_novoTamanhoQtdCtrl.text) ?• 0;

    if (nome.isEmpty) {
      _showModernSnackBar('Digite o nome do tamanho', isError: true);
      return;
    }

    // Verificar duplicata
    if (_tamanhos.any((t) => t.nome.toUpperCase() == nome)) {
      _showModernSnackBar('Este tamanho ja existe', isError: true);
      return;
    }

    setState(() {
      _tamanhos.add(_EstoqueItem(nome: nome, quantidade: qtd));
      _novoTamanhoCtrl.clear();
      _novoTamanhoQtdCtrl.text = '0';
    });
  }

  void _removerTamanho(int index) {
    setState(() => _tamanhos.removeAt(index));
  }

  void _editarQuantidadeTamanho(int index, int novaQtd) {
    setState(() {
      _tamanhos[index] = _EstoqueItem(
        nome: _tamanhos[index].nome,
        quantidade: novaQtd,
      );
    });
  }

  // ================== CORES - CRUD ==================

  void _adicionarCor() {
    final nome = _novaCorCtrl.text.trim();
    final qtd = int.tryParse(_novaCorQtdCtrl.text) ?• 0;

    if (nome.isEmpty) {
      _showModernSnackBar('Digite o nome da cor', isError: true);
      return;
    }

    // Verificar duplicata
    if (_cores.any((c) => c.nome.toLowerCase() == nome.toLowerCase())) {
      _showModernSnackBar('Esta cor ja existe', isError: true);
      return;
    }

    setState(() {
      _cores.add(_EstoqueItem(nome: nome, quantidade: qtd));
      _novaCorCtrl.clear();
      _novaCorQtdCtrl.text = '0';
    });
  }

  void _removerCor(int index) {
    setState(() => _cores.removeAt(index));
  }

  void _editarQuantidadeCor(int index, int novaQtd) {
    setState(() {
      _cores[index] = _EstoqueItem(
        nome: _cores[index].nome,
        quantidade: novaQtd,
      );
    });
  }

  // ================== SNACKBAR MODERNO ==================

  void _showModernSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isError • Icons.error_outline :
                isSuccess • Icons.check_circle_outline : Icons.info_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError • _errorColor : isSuccess • _successColor : _primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ================== SALVAR ==================

  Future<void> _salvarProduto() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    try {
      final preco = _parsePreco(_precoCtrl.text);
      final quantidade = _parseQtd(_quantidadeCtrl.text);

      // Converter listas para Map
      final Map<String, int>• estoquePorTamanho =
          _tamanhos.isEmpty • null : {for (var t in _tamanhos) t.nome: t.quantidade};

      final Map<String, int>• estoquePorCor =
          _cores.isEmpty • null : {for (var c in _cores) c.nome: c.quantidade};

      // 1) Cria o doc vazio para gerar id
      final col = FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.idLoja)
          .collection('draft_produtos');

      final docRef = col.doc();

      // 2) Sobe imagens (se tiver)
      final urls = await _uploadImagens(docRef.id);
      _imagensUrls
        ..clear()
        ..addAll(urls);

      // 3) Payload (capitaliza nomes)
      final data = <String, dynamic>{
        'nome': capitalizeWords(_nomeCtrl.text.trim()),
        'descricao': _descricaoCtrl.text.trim(),
        'preco': preco,
        // Compatibilidade: salva tanto 'categoria' quanto 'categoriaId'
        'categoria': capitalizeWords(_categoriaCtrl.text.trim()),
        'categoriaId': capitalizeWords(_categoriaCtrl.text.trim()),
        // Compatibilidade: salva tanto 'subcategoria' quanto 'subcategoriaId'
        'subcategoria': capitalizeWords(_subcategoriaCtrl.text.trim()),
        'subcategoriaId': capitalizeWords(_subcategoriaCtrl.text.trim()),
        'imagens': _imagensUrls,
        'ativo': _ativoNoRascunho,
        'quantidade': (estoquePorTamanho == null && estoquePorCor == null)
            • quantidade
            : null,
        'estoquePorTamanho': estoquePorTamanho,
        'estoquePorCor': estoquePorCor,
        'criadoEm': FieldValue.serverTimestamp(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      };

      await docRef.set(data, SetOptions(merge: false));

      if (!mounted) return;
      _showModernSnackBar(
        'Produto salvo como rascunho. Para publicar no estoque e nas outras plataformas, use a opção de publicar na tela de rascunhos.',
        isSuccess: true,
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showModernSnackBar('Erro ao salvar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // ================== UI ==================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Modern App Bar
              SliverAppBar(
                expandedHeight: 120,
                floating: false,
                pinned: true,
                elevation: 0,
                backgroundColor: _primaryColor,
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text(
                    'Cadastrar Produto',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _primaryColor,
                          _primaryColor.withValues(alpha:0.8),
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -50,
                          top: -50,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha:0.1),
                            ),
                          ),
                        ),
                        Positioned(
                          left: -30,
                          bottom: -30,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha:0.1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Content
              SliverToBoxAdapter(
                child: Form(
                  key: _formKey,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // ========== AVISO RASCUNHO vs ESTOQUE ==========
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _warningColor.withValues(alpha:0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _warningColor.withValues(alpha:0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: _warningColor,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Salvamento em rascunho',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: _surfaceColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Este produto será salvo apenas como rascunho. '
                                      'Para aparecer no estoque e nas outras plataformas (Web, APK), '
                                      'é necessário publicá-lo a partir da tela de rascunhos.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ========== SECAO: STATUS ==========
                        _buildModernSectionCard(
                          title: 'Status do Produto',
                          icon: Icons.visibility_outlined,
                          iconColor: _primaryColor,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _ativoNoRascunho
                                  • _successColor.withValues(alpha:0.1)
                                  : _warningColor.withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _ativoNoRascunho
                                    • _successColor.withValues(alpha:0.3)
                                    : _warningColor.withValues(alpha:0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _ativoNoRascunho • _successColor : _warningColor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _ativoNoRascunho • Icons.visibility : Icons.visibility_off,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _ativoNoRascunho • 'Visivel no Catalogo' : 'Oculto no Catalogo',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: _ativoNoRascunho • _successColor : _warningColor,
                                        ),
                                      ),
                                      Text(
                                        _ativoNoRascunho
                                            • 'O produto aparecera no catalogo'
                                            : 'O produto ficara oculto no catalogo',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _ativoNoRascunho,
                                  onChanged: (v) => setState(() => _ativoNoRascunho = v),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ========== SECAO: INFORMACOES BASICAS ==========
                        _buildModernSectionCard(
                          title: 'Informacoes Basicas',
                          icon: Icons.info_outline,
                          iconColor: _primaryColor,
                          child: Column(
                            children: [
                              _buildModernTextField(
                                controller: _nomeCtrl,
                                label: 'Nome do Produto',
                                hint: 'Ex: Camiseta Basica',
                                icon: Icons.shopping_bag_outlined,
                                isRequired: true,
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    • 'Informe o nome'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              _buildModernTextField(
                                controller: _descricaoCtrl,
                                label: 'Descricao',
                                hint: 'Descreva o produto...',
                                icon: Icons.description_outlined,
                                maxLines: 3,
                              ),
                              const SizedBox(height: 16),
                              _buildModernTextField(
                                controller: _precoCtrl,
                                label: 'Preco',
                                hint: 'Ex: 99,90',
                                icon: Icons.attach_money,
                                prefix: 'R\$ ',
                                isRequired: true,
                                keyboardType: TextInputType.number,
                                inputFormatters: [MoedaInputFormatter()],
                                validator: (v) {
                                  final val = _parsePreco(v ?• '');
                                  return (val <= 0) • 'Informe um preco valido' : null;
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ========== SECAO: CATEGORIA (autocomplete) ==========
                        _buildModernSectionCard(
                          title: 'Categoria',
                          icon: Icons.category_outlined,
                          iconColor: _warningColor,
                          child: Column(
                            children: [
                              _buildCategoriaAutocomplete(
                                controller: _categoriaCtrl,
                                label: 'Categoria',
                                hint: 'Ex: Roupas',
                                icon: Icons.folder_outlined,
                                opcoes: _categoriasExistentes,
                                isRequired: true,
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    • 'Informe a categoria'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              _buildCategoriaAutocomplete(
                                controller: _subcategoriaCtrl,
                                label: 'Subcategoria',
                                hint: 'Ex: Camisetas',
                                icon: Icons.folder_open_outlined,
                                opcoes: _subcategoriasExistentes,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ========== SECAO: TAMANHOS ==========
                        _buildModernSectionCard(
                          title: 'Estoque por Tamanho',
                          icon: Icons.straighten,
                          iconColor: _successColor,
                          subtitle: 'Adicione tamanhos e suas quantidades em estoque',
                          child: Column(
                            children: [
                              // Lista de tamanhos adicionados
                              if (_tamanhos.isNotEmpty) ...[
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Column(
                                    children: _tamanhos.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final item = entry.value;
                                      return _buildModernEstoqueItemTile(
                                        item: item,
                                        onDelete: () => _removerTamanho(index),
                                        onQtdChanged: (qtd) =>
                                            _editarQuantidadeTamanho(index, qtd),
                                        isLast: index == _tamanhos.length - 1,
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // Formulario para adicionar novo tamanho
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: _buildModernTextField(
                                      controller: _novoTamanhoCtrl,
                                      label: 'Tamanho',
                                      hint: 'P, M, G, GG...',
                                      icon: Icons.straighten,
                                      textCapitalization: TextCapitalization.characters,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildModernTextField(
                                      controller: _novoTamanhoQtdCtrl,
                                      label: 'Qtd',
                                      hint: '0',
                                      icon: Icons.inventory_2_outlined,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [_primaryColor, _primaryColor.withValues(alpha:0.8)],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: _primaryColor.withValues(alpha:0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _adicionarTamanho,
                                          borderRadius: BorderRadius.circular(12),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 16,
                                            ),
                                            child: Icon(Icons.add, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // Sugestoes rapidas de tamanhos
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: ['PP', 'P', 'M', 'G', 'GG', 'XG', '36', '38', '40', '42', '44']
                                    .map((t) => _buildQuickChip(
                                          label: t,
                                          onTap: () {
                                            if (!_tamanhos.any((x) => x.nome == t)) {
                                              setState(() {
                                                _tamanhos.add(
                                                    _EstoqueItem(nome: t, quantidade: 0));
                                              });
                                            }
                                          },
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ========== SECAO: CORES ==========
                        _buildModernSectionCard(
                          title: 'Estoque por Cor',
                          icon: Icons.palette_outlined,
                          iconColor: _errorColor,
                          subtitle: 'Adicione cores e suas quantidades em estoque',
                          child: Column(
                            children: [
                              // Lista de cores adicionadas
                              if (_cores.isNotEmpty) ...[
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Column(
                                    children: _cores.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final item = entry.value;
                                      return _buildModernEstoqueItemTile(
                                        item: item,
                                        onDelete: () => _removerCor(index),
                                        onQtdChanged: (qtd) =>
                                            _editarQuantidadeCor(index, qtd),
                                        isLast: index == _cores.length - 1,
                                        showColorPreview: true,
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // Formulario para adicionar nova cor
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: _buildModernTextField(
                                      controller: _novaCorCtrl,
                                      label: 'Cor',
                                      hint: 'Preto, Branco, Azul...',
                                      icon: Icons.palette_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildModernTextField(
                                      controller: _novaCorQtdCtrl,
                                      label: 'Qtd',
                                      hint: '0',
                                      icon: Icons.inventory_2_outlined,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [_primaryColor, _primaryColor.withValues(alpha:0.8)],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: _primaryColor.withValues(alpha:0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _adicionarCor,
                                          borderRadius: BorderRadius.circular(12),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 16,
                                            ),
                                            child: Icon(Icons.add, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // Sugestoes rapidas de cores
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildModernColorChip('Preto', Colors.black),
                                  _buildModernColorChip('Branco', Colors.white),
                                  _buildModernColorChip('Vermelho', Colors.red),
                                  _buildModernColorChip('Azul', Colors.blue),
                                  _buildModernColorChip('Verde', Colors.green),
                                  _buildModernColorChip('Amarelo', Colors.yellow),
                                  _buildModernColorChip('Rosa', Colors.pink),
                                  _buildModernColorChip('Roxo', Colors.purple),
                                  _buildModernColorChip('Laranja', Colors.orange),
                                  _buildModernColorChip('Cinza', Colors.grey),
                                  _buildModernColorChip('Marrom', Colors.brown),
                                  _buildModernColorChip('Bege', const Color(0xFFF5F5DC)),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ========== SECAO: QUANTIDADE GERAL ==========
                        if (_tamanhos.isEmpty && _cores.isEmpty)
                          _buildModernSectionCard(
                            title: 'Quantidade em Estoque',
                            icon: Icons.inventory_2_outlined,
                            iconColor: _primaryColor,
                            subtitle: 'Use este campo apenas se nao cadastrar tamanhos ou cores',
                            child: _buildModernTextField(
                              controller: _quantidadeCtrl,
                              label: 'Quantidade',
                              hint: '1',
                              icon: Icons.numbers,
                              keyboardType: TextInputType.number,
                            ),
                          ),

                        if (_tamanhos.isEmpty && _cores.isEmpty)
                          const SizedBox(height: 16),

                        // ========== SECAO: IMAGENS ==========
                        _buildModernSectionCard(
                          title: 'Imagens do Produto',
                          icon: Icons.image_outlined,
                          iconColor: _successColor,
                          child: Column(
                            children: [
                              // Botao de selecionar imagens
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: _primaryColor.withValues(alpha:0.3),
                                    width: 2,
                                    style: BorderStyle.solid,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Material(
                                  color: _primaryColor.withValues(alpha:0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: _selecionarImagens,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 20),
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: _primaryColor.withValues(alpha:0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.add_photo_alternate_outlined,
                                              color: _primaryColor,
                                              size: 32,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _arquivos.isEmpty
                                                • 'Selecionar Imagens'
                                                : 'Adicionar Mais Imagens',
                                            style: const TextStyle(
                                              color: _primaryColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Toque para escolher fotos do seu dispositivo',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Preview das imagens
                              if (_arquivos.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _successColor.withValues(alpha:0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle, color: _successColor, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${_arquivos.length} imagem(ns) selecionada(s)',
                                        style: const TextStyle(
                                          color: _successColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Arraste para reordenar. A primeira é a capa do catálogo.',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: (_arquivos.length * 130.0).clamp(130.0, 300.0),
                                  child: ReorderableListView.builder(
                                    shrinkWrap: true,
                                    buildDefaultDragHandles: false,
                                    itemCount: _arquivos.length,
                                    onReorder: _reordenarArquivo,
                                    itemBuilder: (_, i) => ReorderableDragStartListener(
                                      key: ValueKey('arq_$i'),
                                      index: i,
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: _buildImagePreview(i),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ========== BOTAO SALVAR ==========
                        Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_primaryColor, _primaryColor.withValues(alpha:0.8)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryColor.withValues(alpha:0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _salvando • null : _salvarProduto,
                              borderRadius: BorderRadius.circular(16),
                              child: const Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.save_outlined, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text(
                                      'Salvar Rascunho',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Loading Overlay
          if (_salvando)
            Container(
              color: Colors.black.withValues(alpha:0.5),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Salvando produto...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _surfaceColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Aguarde enquanto processamos',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ================== WIDGETS AUXILIARES ==================

  Widget _buildModernSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
    String• subtitle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade100),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _surfaceColor,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriaAutocomplete({
    required TextEditingController controller,
    required String label,
    String• hint,
    required IconData icon,
    required List<String> opcoes,
    bool isRequired = false,
    String• Function(String?)• validator,
  }) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return opcoes;
        final lower = textEditingValue.text.toLowerCase();
        return opcoes.where((s) => s.toLowerCase().contains(lower)).toList();
      },
      onSelected: (value) {
        controller.text = value;
        setState(() {});
      },
      fieldViewBuilder: (context, fieldController, focusNode, onSubmit) {
        if (fieldController.text != controller.text) {
          fieldController.text = controller.text;
        }
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          validator: validator,
          decoration: InputDecoration(
            labelText: isRequired • '$label *' : label,
            hintText: hint,
            prefixIcon: Icon(icon, color: _primaryColor.withValues(alpha:0.7), size: 22),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryColor, width: 2),
            ),
          ),
          onChanged: (v) {
            controller.text = v;
            setState(() {});
          },
          onFieldSubmitted: (_) => onSubmit(),
        );
      },
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    String• hint,
    IconData• icon,
    String• prefix,
    bool isRequired = false,
    int maxLines = 1,
    TextInputType• keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String• Function(String?)• validator,
    List<TextInputFormatter>• inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: isRequired • '$label *' : label,
        hintText: hint,
        prefixIcon: icon != null
            • Icon(icon, color: _primaryColor.withValues(alpha:0.7), size: 22)
            : null,
        prefixText: prefix,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _errorColor),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildModernEstoqueItemTile({
    required _EstoqueItem item,
    required VoidCallback onDelete,
    required Function(int) onQtdChanged,
    required bool isLast,
    bool showColorPreview = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: !isLast
            • Border(bottom: BorderSide(color: Colors.grey.shade200))
            : null,
      ),
      child: Row(
        children: [
          // Preview de cor (se aplicavel)
          if (showColorPreview) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _getColorFromName(item.nome),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Nome
          Expanded(
            flex: 2,
            child: Text(
              item.nome,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: _surfaceColor,
              ),
            ),
          ),

          // Controle de quantidade
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: item.quantidade > 0
                      • () => onQtdChanged(item.quantidade - 1)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.remove,
                      size: 18,
                      color: item.quantidade > 0 • _primaryColor : Colors.grey,
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${item.quantidade}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: _surfaceColor,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => onQtdChanged(item.quantidade + 1),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.add, size: 18, color: _primaryColor),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Botao de remover
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _errorColor.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_outline, color: _errorColor, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip({required String label, required VoidCallback onTap}) {
    final isSelected = _tamanhos.any((t) => t.nome == label);
    return InkWell(
      onTap: isSelected • null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected • _successColor.withValues(alpha:0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected • _successColor : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check, size: 14, color: _successColor),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected • _successColor : _surfaceColor,
                fontWeight: isSelected • FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernColorChip(String nome, Color cor) {
    final isSelected = _cores.any((c) => c.nome.toLowerCase() == nome.toLowerCase());
    return InkWell(
      onTap: isSelected
          • null
          : () {
              setState(() {
                _cores.add(_EstoqueItem(nome: nome, quantidade: 0));
              });
            },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected • _successColor.withValues(alpha:0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected • _successColor : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: cor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade400, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (isSelected) ...[
              const Icon(Icons.check, size: 14, color: _successColor),
              const SizedBox(width: 4),
            ],
            Text(
              nome,
              style: TextStyle(
                color: isSelected • _successColor : _surfaceColor,
                fontWeight: isSelected • FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(int index) {
    final f = _arquivos[index];
    Widget thumb;
    if (kIsWeb && f.bytes != null) {
      thumb = Image.memory(
        f.bytes!,
        width: 110,
        height: 110,
        fit: BoxFit.contain,
      );
    } else if (f.path != null) {
      thumb = Image.file(
        File(f.path!),
        width: 110,
        height: 110,
        fit: BoxFit.contain,
      );
    } else {
      thumb = Container(
        width: 110,
        height: 110,
        color: Colors.grey.shade200,
        child: Icon(Icons.image, color: Colors.grey.shade400),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(width: 110, height: 110, child: thumb),
          ),
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.drag_handle, size: 16, color: Colors.white),
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: InkWell(
              onTap: () => _removerArquivo(index),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _errorColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _errorColor.withValues(alpha:0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
          if (index == 0)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _successColor,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: _successColor.withValues(alpha:0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Principal',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getColorFromName(String nome) {
    final Map<String, Color> coresMap = {
      'preto': Colors.black,
      'branco': Colors.white,
      'vermelho': Colors.red,
      'azul': Colors.blue,
      'verde': Colors.green,
      'amarelo': Colors.yellow,
      'rosa': Colors.pink,
      'roxo': Colors.purple,
      'laranja': Colors.orange,
      'cinza': Colors.grey,
      'marrom': Colors.brown,
      'bege': const Color(0xFFF5F5DC),
    };

    return coresMap[nome.toLowerCase()] ?• Colors.grey;
  }
}

// Classe auxiliar para itens de estoque
class _EstoqueItem {
  final String nome;
  final int quantidade;

  _EstoqueItem({required this.nome, required this.quantidade});
}

