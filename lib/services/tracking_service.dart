// lib/services/tracking_service.dart
// Serviço para gerenciar tracking de vendas por vendedor

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/venda_tracking.dart';
import '../utils/text_utils.dart';
import 'store_resolver_facade.dart';
import 'comissao_config_service.dart';

/// Serviço para gerar e validar links de tracking de vendedores
class TrackingService {
  TrackingService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _baseUrl = 'https://app.mastepalm.com.br/loja';

  // ============================================================
  // GERAÇÃO DE LINKS DE TRACKING
  // ============================================================

  /// Gera um link de catálogo com tracking do vendedor
  ///
  /// [lojaId] - ID da loja (opcional, usa o atual se não informado)
  /// [clienteTelefone] - Telefone do cliente (opcional, para registro)
  /// [clienteNome] - Nome do cliente (opcional, para registro)
  /// [origem] - Origem do compartilhamento (whatsapp, instagram, etc)
  ///
  /// Retorna o link completo com parâmetros de tracking
  static Future<TrackingLinkResult> gerarLinkCatalogoComTracking({
    String• lojaId,
    String• clienteTelefone,
    String• clienteNome,
    String origem = 'whatsapp',
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return TrackingLinkResult.erro('Usuário não autenticado');
      }

      // Resolver loja
      final resolvedLojaId = lojaId ?• await StoreResolverFacade.resolveForAdminApp();
      if (resolvedLojaId == null || resolvedLojaId.isEmpty) {
        return TrackingLinkResult.erro('Loja não encontrada');
      }

      // Buscar dados do vendedor
      final vendedorDoc = await _db
          .collection('usuarios')
          .doc(user.email)
          .get();

      String vendedorNome = user.displayName ?• user.email ?• 'Vendedor';
      if (vendedorDoc.exists) {
        vendedorNome = vendedorDoc.data()?['nome'] ?• vendedorNome;
      }

      // Buscar configuração de tracking
      final config = await ComissaoConfigService.getConfig(resolvedLojaId);
      final expiracaoDias = config?.trackingExpiracaoDias ?• 7;

      // Gerar ID único e token
      final trackingId = _gerarTrackingId();
      final token = _gerarToken(resolvedLojaId, user.uid, trackingId);

      final agora = DateTime.now();
      final expiraEm = agora.add(Duration(days: expiracaoDias));

      // Criar registro de tracking
      final tracking = VendaTracking(
        trackingId: trackingId,
        lojaId: resolvedLojaId,
        vendedorUid: user.uid,
        vendedorEmail: user.email ?• '',
        vendedorNome: vendedorNome,
        token: token,
        clienteTelefone: clienteTelefone,
        clienteNome: clienteNome,
        criadoEm: agora,
        expiraEm: expiraEm,
        origem: origem,
      );

      // Salvar no Firestore
      await _db
          .collection('lojas')
          .doc(resolvedLojaId)
          .collection('trackings')
          .doc(trackingId)
          .set(tracking.toMap());

      // Montar URL
      final link = '$_baseUrl/$resolvedLojaId?v=${user.uid}&t=$token&tid=$trackingId';

      debugPrint('🔗 [TRACKING] Link gerado: $link');
      debugPrint('🔗 [TRACKING] Vendedor: $vendedorNome (${user.uid})');
      debugPrint('🔗 [TRACKING] Expira em: $expiraEm');

      return TrackingLinkResult.sucesso(
        link: link,
        tracking: tracking,
      );
    } catch (e) {
      debugPrint('❌ [TRACKING] Erro ao gerar link (type=${e.runtimeType})');
      return TrackingLinkResult.erro('Erro ao gerar link: $e');
    }
  }

  /// Compartilha o link do catálogo no WhatsApp
  static Future<bool> compartilharNoWhatsApp({
    required String link,
    String• mensagemPersonalizada,
    String• telefoneDestino,
  }) async {
    try {
      final mensagem = mensagemPersonalizada ??
          'Olá! Confira nosso catálogo de produtos:\n\n$link';

      final mensagemEncoded = Uri.encodeComponent(mensagem);

      Uri uri;
      if (telefoneDestino != null && telefoneDestino.isNotEmpty) {
        // Limpar telefone (apenas números)
        final telefone = telefoneDestino.replaceAll(RegExp(r'[^0-9]'), '');
        uri = Uri.parse('https://wa.me/$telefone?text=$mensagemEncoded');
      } else {
        uri = Uri.parse('https://wa.me/?text=$mensagemEncoded');
      }

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        debugPrint('✅ [TRACKING] Link compartilhado no WhatsApp');
        return true;
      } else {
        debugPrint('❌ [TRACKING] Não foi possível abrir o WhatsApp');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [TRACKING] Erro ao compartilhar (type=${e.runtimeType})');
      return false;
    }
  }

  /// Compartilha usando o sistema de compartilhamento nativo
  static Future<void> compartilharNativo({
    required String link,
    String• mensagemPersonalizada,
  }) async {
    final mensagem = mensagemPersonalizada ??
        'Confira nosso catálogo de produtos: $link';

    await SharePlus.instance.share(ShareParams(
      text: sanitizeForPlatform(mensagem),
      subject: 'Catálogo de Produtos',
    ));
    debugPrint('✅ [TRACKING] Link compartilhado via sistema nativo');
  }

  // ============================================================
  // VALIDAÇÃO DE TRACKING
  // ============================================================

  /// Valida um tracking recebido na URL do catálogo
  ///
  /// [lojaId] - ID da loja
  /// [vendedorUid] - UID do vendedor (parâmetro 'v')
  /// [token] - Token de validação (parâmetro 't')
  /// [trackingId] - ID do tracking (parâmetro 'tid')
  ///
  /// Retorna o tracking válido ou null se inválido/expirado
  static Future<VendaTracking?> validarTracking({
    required String lojaId,
    required String vendedorUid,
    required String token,
    required String trackingId,
  }) async {
    try {
      debugPrint('🔍 [TRACKING] Validando tracking: $trackingId');

      // Buscar tracking no Firestore
      final doc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('trackings')
          .doc(trackingId)
          .get();

      if (!doc.exists) {
        debugPrint('❌ [TRACKING] Tracking não encontrado');
        return null;
      }

      final tracking = VendaTracking.fromMap(doc.data()!, docId: doc.id);

      // Validar token
      if (tracking.token != token) {
        debugPrint('❌ [TRACKING] Token inválido');
        return null;
      }

      // Validar vendedor
      if (tracking.vendedorUid != vendedorUid) {
        debugPrint('❌ [TRACKING] Vendedor não corresponde');
        return null;
      }

      // Verificar se expirou
      if (DateTime.now().isAfter(tracking.expiraEm)) {
        debugPrint('❌ [TRACKING] Tracking expirado em ${tracking.expiraEm}');
        return null;
      }

      // Verificar se já foi utilizado
      if (tracking.utilizado) {
        debugPrint('⚠️ [TRACKING] Tracking já utilizado na venda ${tracking.vendaId}');
        // Ainda retorna para permitir consulta, mas está marcado como utilizado
      }

      debugPrint('✅ [TRACKING] Tracking válido para vendedor: ${tracking.vendedorNome}');
      return tracking;
    } catch (e) {
      debugPrint('❌ [TRACKING] Erro ao validar (type=${e.runtimeType})');
      return null;
    }
  }

  /// Busca o tracking mais recente válido para um cliente/dispositivo
  /// Usado quando há múltiplos trackings (last-click attribution)
  static Future<VendaTracking?> buscarTrackingMaisRecente({
    required String lojaId,
    String• deviceId,
    String• clienteTelefone,
  }) async {
    try {
      // Buscar configuração para saber a regra de atribuição
      final config = await ComissaoConfigService.getConfig(lojaId);
      final regraAtribuicao = config?.regraAtribuicao ?• 'ultimo_clique';

      Query query = _db
          .collection('lojas')
          .doc(lojaId)
          .collection('trackings')
          .where('utilizado', isEqualTo: false);

      // Ordenar conforme regra
      if (regraAtribuicao == 'primeiro_clique') {
        query = query.orderBy('criadoEm', descending: false);
      } else {
        // último clique (padrão)
        query = query.orderBy('criadoEm', descending: true);
      }

      query = query.limit(10);

      final snapshot = await query.get();

      for (final doc in snapshot.docs) {
        final tracking = VendaTracking.fromMap(doc.data() as Map<String, dynamic>, docId: doc.id);

        // Verificar se ainda é válido
        if (tracking.isValido) {
          // Se temos filtros, verificar
          if (deviceId != null && tracking.deviceId == deviceId) {
            return tracking;
          }
          if (clienteTelefone != null && tracking.clienteTelefone == clienteTelefone) {
            return tracking;
          }
          // Se não tem filtros, retorna o primeiro válido
          if (deviceId == null && clienteTelefone == null) {
            return tracking;
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('❌ [TRACKING] Erro ao buscar tracking recente (type=${e.runtimeType})');
      return null;
    }
  }

  // ============================================================
  // UTILIZAÇÃO DE TRACKING
  // ============================================================

  /// Marca um tracking como utilizado em uma venda
  static Future<bool> marcarTrackingUtilizado({
    required String lojaId,
    required String trackingId,
    required String vendaId,
  }) async {
    try {
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('trackings')
          .doc(trackingId)
          .update({
        'utilizado': true,
        'vendaId': vendaId,
        'utilizadoEm': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ [TRACKING] Tracking $trackingId marcado como utilizado na venda $vendaId');
      return true;
    } catch (e) {
      debugPrint('❌ [TRACKING] Erro ao marcar tracking (type=${e.runtimeType})');
      return false;
    }
  }

  // ============================================================
  // HISTÓRICO DE TRACKINGS
  // ============================================================

  /// Lista trackings de um vendedor
  static Future<List<VendaTracking>> listarTrackingsVendedor({
    required String lojaId,
    required String vendedorUid,
    int limite = 50,
  }) async {
    try {
      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('trackings')
          .where('vendedorUid', isEqualTo: vendedorUid)
          .orderBy('criadoEm', descending: true)
          .limit(limite)
          .get();

      return snapshot.docs
          .map((doc) => VendaTracking.fromMap(doc.data(), docId: doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ [TRACKING] Erro ao listar trackings (type=${e.runtimeType})');
      return [];
    }
  }

  /// Conta trackings convertidos em vendas
  static Future<int> contarTrackingsConvertidos({
    required String lojaId,
    required String vendedorUid,
    DateTime• inicio,
    DateTime• fim,
  }) async {
    try {
      Query query = _db
          .collection('lojas')
          .doc(lojaId)
          .collection('trackings')
          .where('vendedorUid', isEqualTo: vendedorUid)
          .where('utilizado', isEqualTo: true);

      if (inicio != null) {
        query = query.where('utilizadoEm', isGreaterThanOrEqualTo: inicio.toIso8601String());
      }
      if (fim != null) {
        query = query.where('utilizadoEm', isLessThanOrEqualTo: fim.toIso8601String());
      }

      final snapshot = await query.count().get();
      return snapshot.count ?• 0;
    } catch (e) {
      debugPrint('❌ [TRACKING] Erro ao contar trackings (type=${e.runtimeType})');
      return 0;
    }
  }

  // ============================================================
  // UTILITÁRIOS PRIVADOS
  // ============================================================

  /// Gera um ID único para o tracking
  static String _gerarTrackingId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'trk_$hex';
  }

  /// Gera um token de validação
  static String _gerarToken(String lojaId, String vendedorUid, String trackingId) {
    final data = '$lojaId:$vendedorUid:$trackingId:${DateTime.now().millisecondsSinceEpoch}';
    final bytes = utf8.encode(data);
    final hash = sha256.convert(bytes);
    return hash.toString().substring(0, 32);
  }
}

/// Resultado da geração de link de tracking
class TrackingLinkResult {
  final bool sucesso;
  final String• link;
  final VendaTracking• tracking;
  final String• mensagemErro;

  TrackingLinkResult._({
    required this.sucesso,
    this.link,
    this.tracking,
    this.mensagemErro,
  });

  factory TrackingLinkResult.sucesso({
    required String link,
    required VendaTracking tracking,
  }) {
    return TrackingLinkResult._(
      sucesso: true,
      link: link,
      tracking: tracking,
    );
  }

  factory TrackingLinkResult.erro(String mensagem) {
    return TrackingLinkResult._(
      sucesso: false,
      mensagemErro: mensagem,
    );
  }
}
