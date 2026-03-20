// lib/widgets/notificacao_pedido_listener.dart
// Escuta notificações de novos pedidos e exibe com entusiasmo no app e web

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:hive/hive.dart';

import '../services/loja_id_service.dart';
import '../services/notificacao_vendas_service.dart';
import '../services/notificacao_service.dart';
import '../services/notificacao_centro_service.dart';

/// Envolve o app e escuta notificações de novos pedidos em tempo real.
/// Exibe SnackBar/overlay quando chega um novo pedido.
class NotificacaoPedidoListener extends StatefulWidget {
  final Widget child;

  const NotificacaoPedidoListener({super.key, required this.child});

  @override
  State<NotificacaoPedidoListener> createState() =>
      _NotificacaoPedidoListenerState();
}

class _NotificacaoPedidoListenerState extends State<NotificacaoPedidoListener> {
  Stream<List<NotificacaoVenda>>? _stream;
  final Set<String> _idsVistos = {};
  bool _inicializado = false;
  bool _primeiraCarga =
      true; // Evita mostrar notificações antigas ao abrir o app
  DateTime?
      _horarioAberturaApp; // Só mostrar notificações criadas após abrir o app
  Timer? _retryTimer;
  Timer? _pollTimer;
  StreamSubscription<User?>? _authSub;
  int _retryCount = 0;
  String? _uid;
  String? _storeId;
  static const int _maxRetries = 20; // ~40s no APK até store_id estar na sessão

  /// ✅ Multi-loja: LojaIdService primeiro, Hive apenas fallback offline
  Future<String?> _resolveStoreId() async {
    try {
      final id = await LojaIdService.get();
      if (id != null && id.trim().isNotEmpty) return id.trim();
    } catch (_) {}
    try {
      if (Hive.isBoxOpen('sessao')) {
        final s = Hive.box('sessao').get('store_id')?.toString().trim();
        if (s != null && s.isNotEmpty) return s;
      }
      if (Hive.isBoxOpen('config')) {
        final c = Hive.box('config').get('store_id')?.toString().trim();
        if (c != null && c.isNotEmpty) return c;
      }
    } catch (_) {}
    return null;
  }

  /// Reseta listener ao trocar de conta (evita stream em lojas/master com usuário novo)
  void _resetParaNovaConta() {
    if (!mounted) return;
    _inicializado = false;
    _stream = null;
    _uid = null;
    _storeId = null;
    _retryCount = 0;
    setState(() {});
  }

  Future<void> _iniciarListener() async {
    if (_inicializado) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final storeId = await _resolveStoreId();
    if (storeId == null || storeId.isEmpty) return;

    if (!mounted) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _inicializado = true;
    _uid = user.uid;
    _storeId = storeId;
    _horarioAberturaApp =
        DateTime.now(); // Só notificações criadas depois disso
    _stream = NotificacaoVendasService().streamNotificacoes(user.uid, storeId);

    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _pollNovosPedidos());
  }

  Future<void> _pollNovosPedidos() async {
    if (_uid == null || _storeId == null || !mounted) return;
    final horarioAbertura = _horarioAberturaApp;
    if (horarioAbertura == null) return;
    try {
      final list = await NotificacaoVendasService()
          .getUltimasNotificacoes(_uid!, _storeId!, limit: 20);
      if (!mounted) return;
      for (final n in list) {
        if (_idsVistos.contains(n.id)) continue;
        _idsVistos.add(n.id);
        // Só mostrar se for nova venda e criada DEPOIS de abrir o app (evita testes antigos)
        if (n.tipo == TipoNotificacao.novaVenda &&
            n.criadaEm.isAfter(horarioAbertura)) {
          if (mounted) _mostrarNotificacao(context, n);
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    // Ao trocar de conta: cancelar stream da loja anterior (evita PERMISSION_DENIED em lojas/master)
    _authSub = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      final newUid = user?.uid;
      if (_uid != null && _uid != newUid) {
        _resetParaNovaConta();
      }
    });
    // No APK o store_id pode ser gravado pelo router depois da primeira build.
    // Re-tentar a cada 2s até inicializar (máx. ~40s).
    _retryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      _retryCount++;
      if (_retryCount > _maxRetries) {
        _retryTimer?.cancel();
        return;
      }
      _iniciarListener();
      if (_inicializado) _retryTimer?.cancel();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _retryTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _iniciarListener(); // async, não bloqueia build

    if (_stream == null) {
      return widget.child;
    }

    return StreamBuilder<List<NotificacaoVenda>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Stream falhou (ex.: índice Firestore); o polling continua garantindo avisos
        }
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final horarioAbertura = _horarioAberturaApp;
          if (_primeiraCarga) {
            _primeiraCarga = false;
            for (final n in snapshot.data!) {
              _idsVistos.add(n.id);
            }
          } else if (horarioAbertura != null) {
            for (final n in snapshot.data!) {
              if (n.tipo == TipoNotificacao.novaVenda &&
                  !_idsVistos.contains(n.id) &&
                  n.criadaEm.isAfter(horarioAbertura)) {
                _idsVistos.add(n.id);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _mostrarNotificacao(context, n);
                });
              } else {
                _idsVistos.add(n.id);
              }
            }
          }
        }
        return widget.child;
      },
    );
  }

  void _mostrarNotificacao(BuildContext context, NotificacaoVenda n) {
    if (!context.mounted) return;

    // Som de alerta para novo pedido (nativo do Flutter, funciona em app e web)
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    // Adicionar ao centro de notificações (badge na barra) — por loja
    NotificacaoCentroService().add(
      titulo: n.titulo,
      corpo: '${n.mensagem.split('\n').first}${n.valor != null ? ' ? R\$ ${n.valor!.toStringAsFixed(2).replaceAll('.', ',')}' : ''}',
      tipo: TipoNotificacaoCentro.novoPedido,
      acaoRota: '/pedidos',
      acaoArgs: {'lojaId': n.storeId, 'pedidoId': n.pedidoId},
      storeId: n.storeId,
    );

    final valorStr = n.valor != null
        ? 'R\$ ${n.valor!.toStringAsFixed(2).replaceAll('.', ',')}'
        : '';
    final storeId = n.storeId;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Text('🎉 ', style: TextStyle(fontSize: 24)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (valorStr.isNotEmpty)
                    Text(
                      '$valorStr ? ${n.mensagem.split('\n').first}',
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        action: SnackBarAction(
          label: 'Ver pedido',
          textColor: Colors.white,
          onPressed: () {
            if (!context.mounted) return;
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/pedidos',
              ModalRoute.withName('/'),
              arguments: {'lojaId': storeId, 'pedidoId': n.pedidoId},
            );
          },
        ),
      ),
    );

    // No app nativo (Android), também dispara notificação local
    if (!kIsWeb) {
      try {
        NotificacaoService.enviarNotificacao(
          titulo: n.titulo,
          corpo: '${n.mensagem.split('\n').first} $valorStr',
        );
      } catch (_) {}
    }
  }
}
