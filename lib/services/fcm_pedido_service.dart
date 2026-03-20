// lib/services/fcm_pedido_service.dart
// Push (FCM) para novo pedido: notificação na barra de status com app fechado e abertura na tela de pedidos.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/update_app_dialog.dart';
import 'notificacao_centro_service.dart';
import 'site_config_service.dart';

class FcmPedidoService {
  static GlobalKey<NavigatorState>? _navKey;
  static bool _inicializado = false;
  static RemoteMessage? _pendingInitialMessage;
  static const String _topicAppUpdates = 'masterpalm_app_updates';

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navKey = key;
  }

  /// Chame quando o navigator estiver pronto (ex.: primeiro frame do MyApp).
  /// Abre a tela de pedidos se o app foi aberto pelo toque numa notificação.
  static void processPendingInitialMessage() {
    final pending = _pendingInitialMessage;
    if (pending == null) return;
    _pendingInitialMessage = null;
    _handleMessage(pending);
  }

  static void _handleMessage(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString();
    if (type == 'app_update') {
      _aoClicarNotificacaoAtualizacao();
      return;
    }
    // Novo pedido: adicionar ao centro de notificações (por loja)
    final lojaId = (message.data['lojaId'] ?? message.data['storeId'] ?? '').toString();
    final pedidoId = (message.data['pedidoId'] ?? '').toString();
    final titulo = (message.notification?.title ?? message.data['title'] ?? 'Novo pedido').toString();
    final corpo = (message.notification?.body ?? message.data['body'] ?? 'Você recebeu um novo pedido.').toString();
    NotificacaoCentroService().add(
      titulo: titulo,
      corpo: corpo,
      tipo: TipoNotificacaoCentro.novoPedido,
      acaoRota: '/pedidos',
      acaoArgs: lojaId.isNotEmpty ? {'lojaId': lojaId, 'pedidoId': pedidoId.isNotEmpty ? pedidoId : null} : null,
      storeId: lojaId.isNotEmpty ? lojaId : null,
    );
    _abrirTelaPedidos(message);
  }

  /// Chamado quando o usuário TOCA na notificação push (app em background ou fechado).
  /// Abre diretamente o site de download do APK.
  static Future<void> _aoClicarNotificacaoAtualizacao() async {
    _adicionarNotificacaoAtualizacaoComUrl();
    try {
      final config = await SiteConfigService.load();
      final url = (config.apkDownloadUrl).trim();
      if (url.isNotEmpty && url.startsWith('http')) {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (_) {}
    // Se o app estiver aberto, também mostra o diálogo
    final key = _navKey;
    final ctx = key?.currentState?.context;
    if (ctx != null && ctx.mounted) {
      UpdateAppDialog.showIfNeeded(ctx);
    }
  }

  static void _mostrarDialogoAtualizacao() {
    _adicionarNotificacaoAtualizacaoComUrl();
    final key = _navKey;
    if (key?.currentState?.context == null) return;
    UpdateAppDialog.showIfNeeded(key!.currentState!.context);
  }

  static Future<void> _adicionarNotificacaoAtualizacaoComUrl() async {
    String? downloadUrl;
    try {
      final config = await SiteConfigService.load();
      final url = (config.apkDownloadUrl).trim();
      if (url.isNotEmpty && url.startsWith('http')) downloadUrl = url;
    } catch (_) {}
    await NotificacaoCentroService().add(
      titulo: 'Atualização disponível',
      corpo: 'Uma nova versão do MasterPalm está disponível. Toque para ir ao site e baixar.',
      tipo: TipoNotificacaoCentro.atualizacaoApk,
      acaoArgs: downloadUrl != null ? {'url': downloadUrl} : null,
    );
  }

  static Future<void> init() async {
    if (_inicializado) return;
    if (kIsWeb) return;

    try {
      final messaging = FirebaseMessaging.instance;

      // Permissão (Android 13+ e iOS)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('⚠️ [FCM] Notificações negadas pelo usuário.');
        return;
      }

      // Token e salvar no Firestore para a CF enviar push
      await _atualizarToken();

      try {
        await messaging.subscribeToTopic(_topicAppUpdates);
        debugPrint('✅ [FCM] Inscrito no tópico $_topicAppUpdates');
      } catch (e) {
        debugPrint('⚠️ [FCM] Erro ao inscrever no tópico (type=${e.runtimeType})');
      }

      messaging.onTokenRefresh.listen((_) => _atualizarToken());

      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

      // App em primeiro plano: notificação de atualização → adicionar ao centro e mostrar diálogo
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        if ((msg.data['type'] ?? '').toString() == 'app_update') {
          _mostrarDialogoAtualizacao();
        }
      });

      // App estava fechado e abriu pelo toque na notificação (navega quando o navigator estiver pronto)
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _pendingInitialMessage = initial;

      _inicializado = true;
      debugPrint('✅ [FCM] Pedido service inicializado.');
    } catch (e) {
      debugPrint('❌ [FCM] Erro ao inicializar (type=${e.runtimeType})');
    }
  }

  static Future<void> _atualizarToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('✅ [FCM] Token salvo no Firestore.');
    } catch (e) {
      debugPrint('⚠️ [FCM] Erro ao salvar token (type=${e.runtimeType})');
    }
  }

  static void _abrirTelaPedidos(RemoteMessage message) {
    final lojaId = (message.data['lojaId'] ?? message.data['storeId'] ?? '').toString();
    if (lojaId.isEmpty) return;

    final pedidoId = (message.data['pedidoId'] ?? '').toString();
    final key = _navKey;
    if (key?.currentState == null) return;

    // Abre direto na tela de pré-pedidos (com pedidoId para destacar o pedido)
    key!.currentState!.pushNamedAndRemoveUntil(
      '/pedidos',
      ModalRoute.withName('/'),
      arguments: {'lojaId': lojaId, 'pedidoId': pedidoId.isNotEmpty ? pedidoId : null},
    );
  }
}
