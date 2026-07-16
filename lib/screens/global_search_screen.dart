// lib/screens/global_search_screen.dart
// Busca global: produtos, clientes e vendas. Sempre filtrado por [lojaId].

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../core/access_scope_service.dart';
import '../core/hive_box_names.dart';
import '../core/produto_cadastro_gate.dart';
import '../models/produto.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../utils/store_access_guard.dart';
import '../widgets/app_help_icon_button.dart';

class GlobalSearchScreen extends StatefulWidget {
  final String lojaId;

  const GlobalSearchScreen({super.key, required this.lojaId});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(_controller.text.trim());
    });
  }

  Future<void> _runSearch(String q) async {
    if (q.isEmpty) {
      if (mounted) setState(() { _results = []; _searching = false; });
      return;
    }
    if (!mounted) return;
    setState(() => _searching = true);

    String lojaId;
    try {
      lojaId = StoreAccessGuard.requireLojaId(widget.lojaId, context: 'GlobalSearchScreen');
    } on InvalidLojaIdException {
      if (mounted) setState(() { _results = []; _searching = false; });
      return;
    }
    final lower = q.toLowerCase();
    final list = <Map<String, dynamic>>[];

    try {
      {
        final produtosBoxName = HiveBoxNames.produtos(lojaId);
        Box<Produto> produtosBox;
        if (Hive.isBoxOpen(produtosBoxName)) {
          produtosBox = Hive.box<Produto>(produtosBoxName);
        } else {
          StoreAccessGuard.auditBoxAccess(produtosBoxName, lojaId, op: 'open');
          produtosBox = await Hive.openBox<Produto>(produtosBoxName);
        }
        final scope = await AccessScopeService.loadIdentity();
        for (final p in produtosBox.values) {
          if (p.lojaId != lojaId) continue;
          if (!p.nome.toLowerCase().contains(lower)) continue;
          if (scope.isSeller && !produtoEstoqueDisponivelParaVendedor(p)) {
            continue;
          }
          list.add({
            'type': 'produto',
            'id': p.key,
            'title': p.nome,
            'subtitle': 'R\$ ${p.precoFinal.toStringAsFixed(2)}',
            'route': '/estoque',
          });
        }

        final clientesBoxName = HiveBoxNames.clientes(lojaId);
        Box<Cliente> clientesBox;
        if (Hive.isBoxOpen(clientesBoxName)) {
          clientesBox = Hive.box<Cliente>(clientesBoxName);
        } else {
          clientesBox = await Hive.openBox<Cliente>(clientesBoxName);
        }
        for (final c in clientesBox.values) {
          if (c.lojaId != lojaId) continue;
          final match = c.nome.toLowerCase().contains(lower) ||
              (c.telefone.contains(q)) ||
              (c.email?.toLowerCase().contains(lower) ?? false);
          if (match) {
            list.add({'type': 'cliente', 'id': c.key, 'title': c.nome, 'subtitle': c.telefone, 'route': '/clientes'});
          }
        }

        final vendasBoxName = HiveBoxNames.vendas(lojaId);
        Box<Venda> vendasBox;
        if (Hive.isBoxOpen(vendasBoxName)) {
          vendasBox = Hive.box<Venda>(vendasBoxName);
        } else {
          StoreAccessGuard.auditBoxAccess(vendasBoxName, lojaId, op: 'open');
          vendasBox = await Hive.openBox<Venda>(vendasBoxName);
        }
        for (final v in vendasBox.values) {
            if (v.lojaId != lojaId) continue;
            final match = v.clienteNome.toLowerCase().contains(lower) ||
                v.produtosDescricao.toLowerCase().contains(lower);
            if (match) {
              list.add({
                'type': 'venda',
                'id': v.key,
                'title': v.clienteNome,
                'subtitle': 'R\$ ${v.total.toStringAsFixed(2)} - ${v.data.toString().substring(0, 10)}',
                'route': '/vendas',
              });
            }
        }
      }
    } catch (_) {}

    if (mounted) setState(() { _results = list; _searching = false; });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Buscar produtos, clientes, vendas...',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _runSearch(_controller.text.trim()),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          AppHelpIconButton(iconColor: theme.colorScheme.onSurface),
        ],
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _controller.text.trim().isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 64, color: theme.colorScheme.primary.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text(
                        'Digite para buscar na sua loja',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                )
              : _results.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhum resultado para "${_controller.text}"',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final r = _results[i];
                        final type = r['type'] as String;
                        final icon = type == 'produto'
                            ? Icons.inventory_2
                            : type == 'cliente'
                                ? Icons.person
                                : Icons.receipt_long;
                        return ListTile(
                          leading: Icon(icon, color: theme.colorScheme.primary),
                          title: Text(r['title'] as String),
                          subtitle: Text(r['subtitle'] as String? ?? ''),
                          onTap: () {
                            Navigator.pop(context, r['route']);
                          },
                        );
                      },
                    ),
    );
  }
}

