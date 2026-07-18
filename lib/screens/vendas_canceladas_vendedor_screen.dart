// R5.5 — Vendas canceladas e excluídas (somente vendedor autenticado).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/access_scope_service.dart';
import '../services/loja_id_service.dart';
import '../services/notificacao_vendas_service.dart';
import '../widgets/acesso_admin_only_view.dart';

class VendasCanceladasVendedorScreen extends StatefulWidget {
  const VendasCanceladasVendedorScreen({super.key});

  @override
  State<VendasCanceladasVendedorScreen> createState() =>
      _VendasCanceladasVendedorScreenState();
}

class _VendasCanceladasVendedorScreenState
    extends State<VendasCanceladasVendedorScreen> {
  static const _primary = Color(0xFF6366F1);

  bool _loading = true;
  String? _erro;
  AccessScopeIdentity? _identity;
  String? _lojaId;
  List<NotificacaoVenda> _itens = const [];
  String _filtro = 'todas'; // todas | cancelada | excluida
  StreamSubscription<List<NotificacaoVenda>>? _sub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final id = await AccessScopeService.loadIdentity();
      if (!id.isSeller || id.isAdmin) {
        setState(() {
          _identity = id;
          _loading = false;
          _erro = id.isAdmin
              ? 'Tela exclusiva do vendedor.'
              : 'Perfil de vendedor necessário.';
        });
        return;
      }
      final lojaId = (await LojaIdService.getWithTimeoutThenSessionFallback(
            timeout: const Duration(seconds: 10),
          ))
              ?.trim() ??
          '';
      if (lojaId.isEmpty || id.uid.isEmpty) {
        throw Exception('Loja ou vendedor não identificados.');
      }
      _identity = id;
      _lojaId = lojaId;
      await _carregarOnce();
      _sub?.cancel();
      _sub = NotificacaoVendasService()
          .streamNotificacoes(id.uid, lojaId)
          .listen((list) {
        if (!mounted) return;
        setState(() {
          _itens = _filtrarCanceladas(list, id.uid);
        });
      }, onError: (_) {});
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Falha ao carregar (type=${e.runtimeType})';
        _loading = false;
      });
    }
  }

  Future<void> _carregarOnce() async {
    final id = _identity;
    final lojaId = _lojaId;
    if (id == null || lojaId == null) return;
    final list = await NotificacaoVendasService()
        .getUltimasNotificacoes(id.uid, lojaId, limit: 80);
    if (!mounted) return;
    setState(() {
      _itens = _filtrarCanceladas(list, id.uid);
    });
  }

  List<NotificacaoVenda> _filtrarCanceladas(
    List<NotificacaoVenda> raw,
    String uid,
  ) {
    final mine = raw.where((n) {
      if (n.destinatarioUid != uid) return false;
      return n.tipo == TipoNotificacao.vendaCancelada;
    }).toList();
    mine.sort((a, b) => b.criadaEm.compareTo(a.criadaEm));
    return mine;
  }

  List<NotificacaoVenda> get _visiveis {
    if (_filtro == 'todas') return _itens;
    return _itens.where((n) {
      final tipo = (n.dados?['tipoAcao'] ?? '').toString().toLowerCase();
      if (_filtro == 'cancelada') {
        return tipo == 'cancelada' ||
            n.titulo.toLowerCase().contains('cancelad');
      }
      return tipo == 'excluida' ||
          tipo == 'excluída' ||
          n.titulo.toLowerCase().contains('exclu');
    }).toList();
  }

  Future<void> _marcarLida(NotificacaoVenda n) async {
    final lojaId = _lojaId;
    if (lojaId == null || n.lida) return;
    await NotificacaoVendasService().marcarComoLida(n.id, lojaId);
    await _carregarOnce();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _primary)),
      );
    }
    final id = _identity;
    if (id == null || !id.isSeller || id.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vendas canceladas e excluídas')),
        body: AcessoAdminOnlyView(
          title: _erro ?? 'Acesso restrito',
          subtitle:
              'Somente o vendedor autenticado consulta cancelamentos próprios.',
        ),
      );
    }

    final lista = _visiveis;
    final df = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendas canceladas e excluídas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarOnce,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'todas', label: Text('Todas')),
                ButtonSegment(value: 'cancelada', label: Text('Canceladas')),
                ButtonSegment(value: 'excluida', label: Text('Excluídas')),
              ],
              selected: {_filtro},
              onSelectionChanged: (s) => setState(() => _filtro = s.first),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _carregarOnce,
              child: lista.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'Nenhuma venda cancelada ou excluída.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final n = lista[i];
                        final motivo =
                            (n.dados?['motivo'] ?? '').toString().trim();
                        final adminNome =
                            (n.dados?['adminNome'] ?? n.dados?['adminUid'] ?? '')
                                .toString()
                                .trim();
                        final tipoAcao =
                            (n.dados?['tipoAcao'] ?? '').toString().trim();
                        final tipoLabel = tipoAcao == 'cancelada'
                            ? 'Cancelada'
                            : (tipoAcao.isEmpty ? n.titulo : 'Excluída');
                        final vendaId =
                            (n.pedidoId ?? n.vendaId ?? n.id).trim();
                        return Card(
                          child: ListTile(
                            isThreeLine: true,
                            leading: Icon(
                              n.lida
                                  ? Icons.mark_email_read_outlined
                                  : Icons.mark_email_unread_outlined,
                              color: n.lida ? Colors.grey : _primary,
                            ),
                            title: Text(
                              'Venda nº $vendaId · $tipoLabel',
                              style: TextStyle(
                                fontWeight:
                                    n.lida ? FontWeight.w500 : FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (motivo.isNotEmpty) 'Motivo: $motivo',
                                if (adminNome.isNotEmpty)
                                  'Admin: $adminNome',
                                'Em: ${df.format(n.criadaEm)}',
                                n.lida ? 'Lida' : 'Não lida',
                              ].join('\n'),
                            ),
                            trailing: n.lida
                                ? null
                                : TextButton(
                                    onPressed: () => _marcarLida(n),
                                    child: const Text('Lida'),
                                  ),
                            onTap: () => _mostrarDetalhe(n, df),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDetalhe(NotificacaoVenda n, DateFormat df) {
    final motivo = (n.dados?['motivo'] ?? '').toString().trim();
    final adminNome =
        (n.dados?['adminNome'] ?? n.dados?['adminUid'] ?? '').toString().trim();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(n.titulo, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(n.mensagem),
            if (motivo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Motivo: $motivo',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
            if (adminNome.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Administrador: $adminNome'),
            ],
            const SizedBox(height: 8),
            Text('Data: ${df.format(n.criadaEm)}'),
            const SizedBox(height: 16),
            if (!n.lida)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _marcarLida(n);
                },
                child: const Text('Marcar como lida'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gate de rota: só vendedor (bloqueia deep link admin/outro perfil).
class VendasCanceladasVendedorRoute extends StatelessWidget {
  const VendasCanceladasVendedorRoute({super.key});

  @override
  Widget build(BuildContext context) {
    // Auth check leve: evita abrir sem sessão.
    if (FirebaseAuth.instance.currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Faça login para continuar.')),
      );
    }
    return const VendasCanceladasVendedorScreen();
  }
}
