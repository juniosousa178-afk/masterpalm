// lib/widgets/notificacao_pedido_listener.dart
// Escuta notificações de novos pedidos e alertas de venda cancelada/excluída.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:hive/hive.dart';

import '../core/venda_cancelada_alerta_gate.dart';
import '../main.dart' show scaffoldMessengerKey;
import '../services/loja_id_service.dart';
import '../services/notificacao_vendas_service.dart';
import '../services/notificacao_service.dart';
import '../services/notificacao_centro_service.dart';

/// Envolve o app e escuta notificações em tempo real.
class NotificacaoPedidoListener extends StatefulWidget {
  final Widget child;

  const NotificacaoPedidoListener({super.key, required this.child});

  @override
  State<NotificacaoPedidoListener> createState() =>
      _NotificacaoPedidoListenerState();
}

class _NotificacaoPedidoListenerState extends State<NotificacaoPedidoListener> {
  Stream<List<NotificacaoVenda>>? _stream;
  final Set<String> _idsVistosPedido = {};
  bool _inicializado = false;
  bool _primeiraCargaPedido = true;
  DateTime? _horarioAberturaApp;
  Timer? _retryTimer;
  Timer? _pollTimer;
  StreamSubscription<User?>? _authSub;
  int _retryCount = 0;
  String? _uid;
  String? _storeId;
  static const int _maxRetries = 20;
  VoidCallback? _exclusaoBadgeListener;
  VoidCallback? _exclusaoAlertaListener;
  final VendaCanceladaAlertaGate _alertaGate = VendaCanceladaAlertaGate();
  Set<String> _persistedDisplayed = {};
  bool _persistedLoaded = false;

  bool _isFirebaseReady() {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

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

  void _resetParaNovaConta() {
    if (!mounted) return;
    _detachExclusaoListeners();
    _inicializado = false;
    _stream = null;
    _uid = null;
    _storeId = null;
    _retryCount = 0;
    _primeiraCargaPedido = true;
    _idsVistosPedido.clear();
    _alertaGate.sessionShown.clear();
    _alertaGate.baselineIds.clear();
    _alertaGate.baselineSeeded = false;
    _persistedDisplayed = {};
    _persistedLoaded = false;
    VendaCanceladaAlertaGate.trace('listener_disposed', {'reason': 'account_switch'});
    setState(() {});
  }

  void _detachExclusaoListeners() {
    if (_exclusaoBadgeListener != null) {
      NotificacaoVendasService.exclusaoBadgeTick
          .removeListener(_exclusaoBadgeListener!);
    }
    if (_exclusaoAlertaListener != null) {
      NotificacaoVendasService.exclusaoAlertaTick
          .removeListener(_exclusaoAlertaListener!);
    }
  }

  Future<void> _ensurePersistedLoaded() async {
    if (_persistedLoaded || _uid == null || _storeId == null) return;
    _persistedDisplayed = await VendaCanceladaAlertaGate.loadPersistedDisplayed(
      storeId: _storeId!,
      uid: _uid!,
    );
    _persistedLoaded = true;
  }

  Future<void> _iniciarListener() async {
    if (_inicializado) return;
    if (!_isFirebaseReady()) return;

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
    _horarioAberturaApp = DateTime.now();
    _stream = NotificacaoVendasService().streamNotificacoes(user.uid, storeId);

    VendaCanceladaAlertaGate.trace('listener_mounted', {
      'current_uid': _uid,
      'tenant': _storeId,
    });

    await _ensurePersistedLoaded();

    // Baseline: só IDs já existentes ANTES desta sessão (Ctrl+F5 não realerta).
    // Itens com criadaEm >= abertura permanecem elegíveis ao alerta.
    try {
      final seed = await NotificacaoVendasService()
          .getUltimasNotificacoes(_uid!, _storeId!, limit: 80);
      final ab = _horarioAberturaApp ?? DateTime.now();
      _alertaGate.seedBaseline(
        seed
            .where((n) => !n.criadaEm.isAfter(ab))
            .map((n) => n.id),
      );
    } catch (_) {
      _alertaGate.seedBaseline(const []);
    }

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollNovosEventos(),
    );

    _exclusaoBadgeListener ??= () {
      VendaCanceladaAlertaGate.trace('badge_tick', {
        'current_uid': _uid,
        'tenant': _storeId,
      });
      _pollNovosEventos();
    };
    NotificacaoVendasService.exclusaoBadgeTick
        .addListener(_exclusaoBadgeListener!);

    _exclusaoAlertaListener ??= () {
      final n = NotificacaoVendasService.lastExclusaoAlerta;
      final source = NotificacaoVendasService.lastExclusaoAlertaSource;
      if (n == null) return;
      VendaCanceladaAlertaGate.trace('notification_received', {
        'notification_source': source,
        'notification_id': n.id,
        'venda_id': n.pedidoId,
        'tipo': n.tipo.name,
        'destinatario_uid': n.destinatarioUid,
        'current_uid': _uid,
        'tenant': _storeId,
      });
      _tryShowCancelamentoAlerta(n, source: source);
    };
    NotificacaoVendasService.exclusaoAlertaTick
        .addListener(_exclusaoAlertaListener!);

    // Alerta criado durante o init (antes do listener) + sync remoto.
    final pending = NotificacaoVendasService.lastExclusaoAlerta;
    if (pending != null) {
      await _tryShowCancelamentoAlerta(
        pending,
        source: NotificacaoVendasService.lastExclusaoAlertaSource.isEmpty
            ? 'bus'
            : NotificacaoVendasService.lastExclusaoAlertaSource,
      );
    }
    await _pollNovosEventos();
  }

  Future<void> _pollNovosEventos() async {
    if (_uid == null || _storeId == null || !mounted) return;
    final horarioAbertura = _horarioAberturaApp;
    if (horarioAbertura == null) return;
    try {
      final list = await NotificacaoVendasService()
          .getUltimasNotificacoes(_uid!, _storeId!, limit: 30);
      if (!mounted) return;

      if (!_alertaGate.baselineSeeded) {
        final ab = _horarioAberturaApp ?? DateTime.now();
        _alertaGate.seedBaseline(
          list
              .where((n) => !n.criadaEm.isAfter(ab))
              .map((n) => n.id),
        );
      }

      for (final n in list) {
        if (n.tipo == TipoNotificacao.vendaCancelada) {
          await _tryShowCancelamentoAlerta(n, source: 'firestore|local');
          continue;
        }
        // Pedidos novos (comportamento legado).
        if (_idsVistosPedido.contains(n.id)) continue;
        if (n.tipo == TipoNotificacao.novaVenda &&
            n.criadaEm.isAfter(horarioAbertura)) {
          _idsVistosPedido.add(n.id);
          if (mounted) _mostrarNotificacao(context, n);
        } else {
          _idsVistosPedido.add(n.id);
        }
      }
    } catch (_) {}
  }

  Future<void> _tryShowCancelamentoAlerta(
    NotificacaoVenda n, {
    required String source,
  }) async {
    final uid = _uid;
    final storeId = _storeId;
    if (uid == null || storeId == null) return;
    await _ensurePersistedLoaded();

    final show = _alertaGate.shouldShow(
      notificationId: n.id,
      sessionUid: uid,
      destinatarioUid: n.destinatarioUid,
      tipoName: n.tipo.name,
      persistedDisplayed: _persistedDisplayed,
    );
    VendaCanceladaAlertaGate.trace('evaluate', {
      'notification_id': n.id,
      'is_new': show,
      'is_read': n.lida,
      'notification_source': source,
    });
    if (!show) return;

    _alertaGate.markShown(n.id);
    _persistedDisplayed.add(n.id);
    await VendaCanceladaAlertaGate.persistDisplayed(
      storeId: storeId,
      uid: uid,
      notificationId: n.id,
    );

    if (!mounted) return;
    VendaCanceladaAlertaGate.trace('alert_show_start', {
      'notification_id': n.id,
      'venda_id': n.pedidoId,
    });
    try {
      _mostrarNotificacaoCancelamento(n);
      VendaCanceladaAlertaGate.trace('alert_show_success', {
        'notification_id': n.id,
        'is_displayed': true,
      });
    } catch (e) {
      VendaCanceladaAlertaGate.trace('alert_show_failure', {
        'notification_id': n.id,
        'error': e.runtimeType.toString(),
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (!_isFirebaseReady()) return;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      final newUid = user?.uid;
      if (_uid != null && _uid != newUid) {
        _resetParaNovaConta();
      }
    });
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
    VendaCanceladaAlertaGate.trace('listener_disposed', {
      'current_uid': _uid,
      'tenant': _storeId,
    });
    _authSub?.cancel();
    _retryTimer?.cancel();
    _pollTimer?.cancel();
    _detachExclusaoListeners();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _iniciarListener();

    if (_stream == null) {
      return widget.child;
    }

    return StreamBuilder<List<NotificacaoVenda>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Stream falhou; poll + alerta bus cobrem cancelamentos.
        }
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final horarioAbertura = _horarioAberturaApp;
          final list = snapshot.data!;

          if (!_alertaGate.baselineSeeded) {
            final ab = _horarioAberturaApp ?? DateTime.now();
            _alertaGate.seedBaseline(
              list
                  .where((n) => !n.criadaEm.isAfter(ab))
                  .map((n) => n.id),
            );
          }

          if (_primeiraCargaPedido) {
            _primeiraCargaPedido = false;
            for (final n in list) {
              _idsVistosPedido.add(n.id);
            }
          } else if (horarioAbertura != null) {
            for (final n in list) {
              if (n.tipo == TipoNotificacao.vendaCancelada) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _tryShowCancelamentoAlerta(n, source: 'firestore');
                });
                continue;
              }
              if (n.tipo == TipoNotificacao.novaVenda &&
                  !_idsVistosPedido.contains(n.id) &&
                  n.criadaEm.isAfter(horarioAbertura)) {
                _idsVistosPedido.add(n.id);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _mostrarNotificacao(context, n);
                });
              } else {
                _idsVistosPedido.add(n.id);
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

    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    NotificacaoCentroService().add(
      titulo: n.titulo,
      corpo:
          '${n.mensagem.split('\n').first}${n.valor != null ? ' · R\$ ${n.valor!.toStringAsFixed(2).replaceAll('.', ',')}' : ''}',
      tipo: TipoNotificacaoCentro.novoPedido,
      acaoRota: '/pedidos',
      acaoArgs: {'lojaId': n.storeId, 'pedidoId': n.pedidoId},
      storeId: n.storeId,
    );

    final valorStr = n.valor != null
        ? 'R\$ ${n.valor!.toStringAsFixed(2).replaceAll('.', ',')}'
        : '';
    final storeId = n.storeId;

    final messenger =
        scaffoldMessengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
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
                      '$valorStr · ${n.mensagem.split('\n').first}',
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
            final nav = Navigator.of(context, rootNavigator: true);
            nav.pushNamedAndRemoveUntil(
              '/pedidos',
              ModalRoute.withName('/'),
              arguments: {'lojaId': storeId, 'pedidoId': n.pedidoId},
            );
          },
        ),
      ),
    );

    if (!kIsWeb) {
      try {
        NotificacaoService.enviarNotificacao(
          titulo: n.titulo,
          corpo: '${n.mensagem.split('\n').first} $valorStr',
        );
      } catch (_) {}
    }
  }

  void _mostrarNotificacaoCancelamento(NotificacaoVenda n) {
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    final titulo = VendaCanceladaAlertaGate.buildTitulo();
    final vendaId = (n.pedidoId ?? n.vendaId ?? n.id).trim();
    final motivo = (n.dados?['motivo'] ?? '').toString().trim();
    final mensagem = VendaCanceladaAlertaGate.buildMensagem(
      vendaId: vendaId,
      motivo: motivo.isEmpty ? null : motivo,
    );

    NotificacaoCentroService().add(
      titulo: titulo,
      corpo: mensagem,
      tipo: TipoNotificacaoCentro.outro,
      acaoRota: '/vendas_canceladas_vendedor',
      storeId: n.storeId,
    );

    final messenger = scaffoldMessengerKey.currentState;
    messenger?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              mensagem,
              style: const TextStyle(fontSize: 13),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 12),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        action: SnackBarAction(
          label: 'Ver detalhes',
          textColor: Colors.white,
          onPressed: () {
            final navCtx = scaffoldMessengerKey.currentContext;
            if (navCtx == null) return;
            Navigator.of(navCtx, rootNavigator: true)
                .pushNamed('/vendas_canceladas_vendedor');
          },
        ),
      ),
    );

    if (!kIsWeb) {
      try {
        NotificacaoService.enviarNotificacao(
          titulo: titulo,
          corpo: mensagem.split('\n').first,
        );
      } catch (_) {}
    }
  }
}
