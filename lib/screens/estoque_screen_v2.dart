// lib/screens/estoque_screen_v2.dart
// Tela de estoque com seleção múltipla e ações em lote

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/hive_box_names.dart';
import '../core/logger.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/produto.dart';
import '../services/permissao_service.dart';
import '../services/catalogo_sync_service.dart';
import '../services/produtos_firestore_service.dart';
import '../services/produto_exclusao_remota_service.dart';
import '../services/store_resolver_facade.dart';
import '../services/sync_queue_service.dart';
import '../services/marketplace_service.dart';
import '../utils/responsive.dart';
import 'produto_form_screen.dart';

class EstoqueScreenV2 extends StatefulWidget {
  const EstoqueScreenV2({super.key});

  @override
  State<EstoqueScreenV2> createState() => _EstoqueScreenV2State();
}

class _EstoqueScreenV2State extends State<EstoqueScreenV2> {
  // Cores do tema moderno
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _surfaceColor = Color(0xFFF8FAFC);

  final _pesquisaController = TextEditingController();
  late Box<Produto> _box;

  bool _ready = false;
  bool _temPermissao = true;
  bool _modoSelecao = false;
  bool _processando = false;

  final Set<String> _produtosSelecionados = {};

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    try {
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null) {
        throw StateError('Nenhuma loja ativa');
      }
      final boxName = HiveBoxNames.produtos(lojaId);

      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<Produto>(boxName);
      }

      _box = Hive.box<Produto>(boxName);

      try {
        await SyncQueueService.processPending();
      } catch (_) {}

      try {
        await ProdutosFirestoreService.syncTodosProdutos(
          boxName: _box.name,
          lojaId: lojaId,
        );
        await ProdutosFirestoreService.syncFirestoreToHive(
          lojaId: lojaId,
          produtosBox: _box,
        );
      } catch (e, st) {
        logE('Erro ao sincronizar (type=${e.runtimeType})', error: e, st: st);
      }

      await _verificarPermissao();
    } catch (e) {
      _showError('Erro ao iniciar: $e');
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _verificarPermissao() async {
    final permitido = await PermissaoService.possuiPermissao('estoque');
    if (!mounted) return;
    setState(() => _temPermissao = permitido);
  }

  String _norm(String? s) => (s ?? '').toLowerCase().trim();

  List<Produto> _filtrarProdutos() {
    final lista = _box.values.toList();
    final busca = _norm(_pesquisaController.text);

    if (busca.isEmpty) return lista;

    return lista.where((p) {
      return _norm(p.nome).contains(busca) ||
          _norm(p.descricao).contains(busca) ||
          _norm(p.categoria).contains(busca);
    }).toList();
  }

  void _toggleModoSelecao() {
    setState(() {
      _modoSelecao = !_modoSelecao;
      if (!_modoSelecao) {
        _produtosSelecionados.clear();
      }
    });
  }

  void _toggleSelecaoProduto(String key) {
    setState(() {
      if (_produtosSelecionados.contains(key)) {
        _produtosSelecionados.remove(key);
      } else {
        _produtosSelecionados.add(key);
      }
    });
  }

  void _selecionarTodos() {
    setState(() {
      final produtos = _filtrarProdutos();
      if (_produtosSelecionados.length == produtos.length) {
        _produtosSelecionados.clear();
      } else {
        _produtosSelecionados.clear();
        for (var p in produtos) {
          final key = _box.keys.firstWhere(
            (k) => _box.get(k) == p,
            orElse: () => null,
          );
          if (key != null) {
            _produtosSelecionados.add(key.toString());
          }
        }
      }
    });
  }

  Future<void> _excluirSelecionados() async {
    if (_produtosSelecionados.isEmpty) {
      _showError('Nenhum produto selecionado');
      return;
    }

    final confirmar = await _showConfirmDialog(
      'Excluir ${_produtosSelecionados.length} produto(s)?',
      'Esta ação não pode ser desfeita. Os produtos serão removidos do estoque, catálogo e Firestore.',
      confirmText: 'Excluir',
      confirmColor: _errorColor,
    );

    if (confirmar != true) return;

    setState(() => _processando = true);

    try {
      int sucesso = 0;
      int erro = 0;

      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null || lojaId.isEmpty) {
        _showError('Nenhuma loja ativa');
        return;
      }

      for (var key in _produtosSelecionados) {
        try {
          final produto = _box.get(key);
          if (produto == null) continue;

          await ProdutoExclusaoRemotaService.exclusaoRemotaCompletaImediata(
            produto: produto,
            lojaId: lojaId,
          );
          await _box.delete(key);

          sucesso++;
        } catch (e, st) {
          erro++;
          logE('Erro ao excluir produto (type=${e.runtimeType})', error: e, st: st);
        }
      }

      setState(() {
        _produtosSelecionados.clear();
        _modoSelecao = false;
      });

      _showSuccess('$sucesso produto(s) excluído(s)${erro > 0 ? ' ($erro erro(s))' : ''}');
    } catch (e) {
      _showError('Erro ao excluir: $e');
    } finally {
      setState(() => _processando = false);
    }
  }

  Future<void> _adicionarAoCatalogo() async {
    if (_produtosSelecionados.isEmpty) {
      _showError('Nenhum produto selecionado');
      return;
    }

    setState(() => _processando = true);

    try {
      int sucesso = 0;
      int erro = 0;

      for (var key in _produtosSelecionados) {
        try {
          final produto = _box.get(key);
          if (produto == null) continue;

          await CatalogoSyncService.syncProduto(
            produto,
            target: SyncTarget.live,
          );

          sucesso++;
        } catch (e, st) {
          erro++;
          logE('Erro ao adicionar ao catálogo (type=${e.runtimeType})', error: e, st: st);
        }
      }

      setState(() {
        _produtosSelecionados.clear();
        _modoSelecao = false;
      });

      _showSuccess('$sucesso produto(s) adicionado(s) ao catálogo${erro > 0 ? ' ($erro erro(s))' : ''}');
    } catch (e) {
      _showError('Erro: $e');
    } finally {
      setState(() => _processando = false);
    }
  }

  Future<void> _definirEstoqueMinimoEmMassa() async {
    if (_produtosSelecionados.isEmpty) {
      _showError('Nenhum produto selecionado');
      return;
    }

    final controller = TextEditingController(text: '0');
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estoque mínimo em massa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_produtosSelecionados.length} produto(s) selecionado(s). Defina o estoque mínimo (alerta). 0 = usa padrão 5 no dashboard.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Estoque mínimo',
                hintText: '0',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    final valor = int.tryParse(controller.text.trim()) ?? 0;
    if (valor < 0) {
      _showError('Use um valor ≥ 0');
      return;
    }

    setState(() => _processando = true);

    try {
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null) {
        _showError('Nenhuma loja ativa');
        setState(() => _processando = false);
        return;
      }

      int sucesso = 0;
      int erro = 0;

      for (var key in _produtosSelecionados) {
        try {
          final produto = _box.get(key);
          if (produto == null) continue;

          produto.estoqueMinimo = valor;
          await produto.save();
          await ProdutosFirestoreService.syncProduto(produto, lojaId: lojaId);
          sucesso++;
        } catch (e, st) {
          erro++;
          logE('Erro ao atualizar estoque mínimo (type=${e.runtimeType})', error: e, st: st);
        }
      }

      setState(() {
        _produtosSelecionados.clear();
        _modoSelecao = false;
      });

      _showSuccess('Estoque mínimo aplicado a $sucesso produto(s)${erro > 0 ? ' ($erro erro(s))' : ''}');
    } catch (e) {
      _showError('Erro: $e');
    } finally {
      setState(() => _processando = false);
    }
  }

  Future<void> _removerDoCatalogo() async {
    if (_produtosSelecionados.isEmpty) {
      _showError('Nenhum produto selecionado');
      return;
    }

    setState(() => _processando = true);

    try {
      int sucesso = 0;
      int erro = 0;

      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null || lojaId.isEmpty) {
        _showError('Nenhuma loja ativa');
        return;
      }

      for (var key in _produtosSelecionados) {
        try {
          final produto = _box.get(key);
          if (produto == null) continue;

          await CatalogoSyncService.removeProdutoFromFirestore(
            produto,
            target: SyncTarget.live,
            lojaIdOverride: lojaId,
          );

          sucesso++;
        } catch (e, st) {
          erro++;
          logE('Erro ao remover do catálogo (type=${e.runtimeType})', error: e, st: st);
        }
      }

      setState(() {
        _produtosSelecionados.clear();
        _modoSelecao = false;
      });

      _showSuccess('$sucesso produto(s) removido(s) do catálogo${erro > 0 ? ' ($erro erro(s))' : ''}');
    } catch (e) {
      _showError('Erro: $e');
    } finally {
      setState(() => _processando = false);
    }
  }

  Future<void> _adicionarAoMarketplace(String marketplace) async {
    if (_produtosSelecionados.isEmpty) {
      _showError('Nenhum produto selecionado');
      return;
    }

    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId.isEmpty) {
      _showError('Erro: Nenhuma loja ativa');
      return;
    }

    setState(() => _processando = true);

    Map<String, dynamic> resultado;
    switch (marketplace) {
      case 'Mercado Livre':
        resultado = await MarketplaceService.sincronizarProdutosMercadoLivre(lojaId: lojaId, produtoIds: null);
        break;
      case 'TikTok Shop':
        resultado = await MarketplaceService.sincronizarProdutosTikTok(lojaId: lojaId, produtoIds: null);
        break;
      case 'Shopee':
        resultado = await MarketplaceService.sincronizarProdutosShopee(lojaId: lojaId, produtoIds: null);
        break;
      default:
        resultado = {'success': false, 'error': 'Marketplace não suportado'};
    }

    if (!mounted) return;
    setState(() {
      _processando = false;
      _produtosSelecionados.clear();
      _modoSelecao = false;
    });

    if (resultado['success'] == true) {
      final sincr = resultado['sincronizados'] ?? 0;
      final total = resultado['total'] ?? 0;
      if (total == 0) {
        _showError('Nenhum produto no Firestore. Publique no catálogo antes.');
      } else {
        _showSuccess('$marketplace: $sincr de $total produto(s) sincronizados');
      }
    } else {
      _showError(resultado['error']?.toString() ?? 'Erro ao sincronizar');
    }
  }

  void _mostrarMenuAcoes() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.flash_on, color: _primaryColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ações em Lote',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_produtosSelecionados.length} produto(s) selecionado(s)',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Ações
            _buildAcaoTile(
              icon: Icons.add_shopping_cart,
              titulo: 'Adicionar ao Catálogo',
              subtitulo: 'Publicar produtos no catálogo web',
              cor: _successColor,
              onTap: () {
                Navigator.pop(context);
                _adicionarAoCatalogo();
              },
            ),

            _buildAcaoTile(
              icon: Icons.remove_shopping_cart,
              titulo: 'Remover do Catálogo',
              subtitulo: 'Despublicar do catálogo web',
              cor: _warningColor,
              onTap: () {
                Navigator.pop(context);
                _removerDoCatalogo();
              },
            ),

            _buildAcaoTile(
              icon: Icons.warning_amber_outlined,
              titulo: 'Definir estoque mínimo em massa',
              subtitulo: 'Alerta quando estoque ≤ valor definido (0 = usa padrão 5)',
              cor: _warningColor,
              onTap: () {
                Navigator.pop(context);
                _definirEstoqueMinimoEmMassa();
              },
            ),

            _buildAcaoTile(
              icon: Icons.shopping_bag,
              titulo: 'Mercado Livre',
              subtitulo: 'Adicionar ao Mercado Livre',
              cor: const Color(0xFFFFF159),
              onTap: () {
                Navigator.pop(context);
                _adicionarAoMarketplace('Mercado Livre');
              },
            ),

            _buildAcaoTile(
              icon: Icons.video_library,
              titulo: 'TikTok Shop',
              subtitulo: 'Adicionar ao TikTok Shop',
              cor: Colors.black,
              onTap: () {
                Navigator.pop(context);
                _adicionarAoMarketplace('TikTok Shop');
              },
            ),

            _buildAcaoTile(
              icon: Icons.store,
              titulo: 'Shopee',
              subtitulo: 'Adicionar à Shopee',
              cor: const Color(0xFFEE4D2D),
              onTap: () {
                Navigator.pop(context);
                _adicionarAoMarketplace('Shopee');
              },
            ),

            const Divider(height: 1),

            _buildAcaoTile(
              icon: Icons.delete,
              titulo: 'Excluir Produtos',
              subtitulo: 'Remover permanentemente do estoque',
              cor: _errorColor,
              onTap: () {
                Navigator.pop(context);
                _excluirSelecionados();
              },
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAcaoTile({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required Color cor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cor.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: cor, size: 22),
      ),
      title: Text(
        titulo,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitulo,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<bool?> _showConfirmDialog(
    String titulo,
    String mensagem, {
    String confirmText = 'Confirmar',
    Color confirmColor = _primaryColor,
  }) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: _surfaceColor,
        body: Center(
          child: CircularProgressIndicator(color: _primaryColor),
        ),
      );
    }

    if (!_temPermissao) {
      return const Scaffold(
        backgroundColor: _surfaceColor,
        body: Center(
          child: Text('Sem permissão para acessar o estoque'),
        ),
      );
    }

    final produtos = _filtrarProdutos();
    final todosSelecionados = _produtosSelecionados.length == produtos.length && produtos.isNotEmpty;

    return Scaffold(
      backgroundColor: _surfaceColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: _modoSelecao
            ? Text('${_produtosSelecionados.length} selecionado(s)')
            : const Text(
                'Estoque',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
        actions: [
          if (_modoSelecao) ...[
            IconButton(
              icon: Icon(
                todosSelecionados ? Icons.check_box : Icons.check_box_outline_blank,
              ),
              onPressed: _selecionarTodos,
              tooltip: 'Selecionar todos',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleModoSelecao,
              tooltip: 'Cancelar seleção',
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist),
              onPressed: _toggleModoSelecao,
              tooltip: 'Modo seleção',
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _abrirForm(),
              tooltip: 'Novo produto',
            ),
          ],
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: Column(
        children: [
          // Barra de pesquisa
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _pesquisaController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar produtos...',
                prefixIcon: const Icon(Icons.search, color: _primaryColor),
                suffixIcon: _pesquisaController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _pesquisaController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _primaryColor, width: 2),
                ),
              ),
            ),
          ),

          // Lista de produtos
          Expanded(
            child: produtos.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: produtos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final produto = produtos[index];
                      final key = _box.keys.firstWhere(
                        (k) => _box.get(k) == produto,
                        orElse: () => null,
                      );
                      final keyStr = key?.toString() ?? '';
                      final selecionado = _produtosSelecionados.contains(keyStr);

                      return _buildProdutoCard(produto, keyStr, selecionado);
                    },
                  ),
          ),
        ],
      ),
        ),
      ),
      floatingActionButton: _modoSelecao && _produtosSelecionados.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _processando ? null : _mostrarMenuAcoes,
              backgroundColor: _primaryColor,
              icon: _processando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.flash_on),
              label: Text(_processando ? 'Processando...' : 'Ações'),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _pesquisaController.text.isEmpty
                ? 'Nenhum produto no estoque'
                : 'Nenhum produto encontrado',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _pesquisaController.text.isEmpty
                ? 'Adicione seu primeiro produto'
                : 'Tente outra busca',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildProdutoCard(Produto produto, String key, bool selecionado) {
    return InkWell(
      onTap: _modoSelecao
          ? () => _toggleSelecaoProduto(key)
          : () => _abrirForm(produto: produto),
      onLongPress: !_modoSelecao
          ? () {
              setState(() => _modoSelecao = true);
              _toggleSelecaoProduto(key);
            }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selecionado ? _primaryColor : Colors.grey[200]!,
            width: selecionado ? 2 : 1,
          ),
          boxShadow: [
            if (selecionado)
              BoxShadow(
                color: _primaryColor.withValues(alpha:0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha:0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Checkbox ou Imagem
              if (_modoSelecao)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selecionado ? _primaryColor : Colors.transparent,
                    border: Border.all(
                      color: selecionado ? _primaryColor : Colors.grey,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: selecionado
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                )
              else if (produto.imagens.isNotEmpty)
                Container(
                  width: 60,
                  height: 60,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
                      image: (kIsWeb && produto.imagens.first.startsWith('blob:'))
                          ? const AssetImage('assets/images/placeholder.png') as ImageProvider
                          : NetworkImage(produto.imagens.first) as ImageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else
                Container(
                  width: 60,
                  height: 60,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.image, color: Colors.grey[400]),
                ),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.nome,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _successColor.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'R\$ ${produto.precoFinal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _successColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Est: ${produto.quantidade}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Ícone
              if (!_modoSelecao)
                const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirForm({Produto? produto}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ProdutoFormScreen(produto: produto)),
    );
    if (ok == true && mounted) setState(() {});
  }
}

