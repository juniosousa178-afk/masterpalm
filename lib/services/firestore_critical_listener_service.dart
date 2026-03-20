// lib/services/firestore_critical_listener_service.dart
//
// Listeners em tempo real para dados críticos (estoque, roleta, permissões).
// Evita dados desatualizados em uso multiusuário.
// Não aplicar listeners globais desnecessários.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'firestore_paths.dart';
import 'produtos_firestore_service.dart';
import 'permissao_service.dart';
import '../models/produto.dart';

class FirestoreCriticalListenerService {
  FirestoreCriticalListenerService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _produtosSub;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _permissoesSub;
  static String? _produtosLojaId;
  static Box<Produto>? _produtosBox;
  static Timer? _syncDebounce;
  static const Duration _syncDebounceDelay = Duration(milliseconds: 500);

  /// Inicia listener de estoque_produtos para sincronizar Hive quando mudar.
  /// Chamar ao abrir tela de vendas/estoque. Cancelar em dispose.
  /// Garante uma única instância ativa por loja (cancela anterior antes de iniciar).
  static void startProdutosListener({
    required String lojaId,
    required Box<Produto> produtosBox,
  }) {
    if (_produtosLojaId == lojaId && _produtosBox == produtosBox) return;

    cancelProdutosListener(); // Garante nenhum listener duplicado

    _produtosLojaId = lojaId;
    _produtosBox = produtosBox;

    _produtosSub = _db
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docChanges.isEmpty) return;
      _syncProdutosOnChangeDebounced();
    });

    debugPrint('📡 [CRITICAL-LISTENER] Listener de produtos ativo para $lojaId');
  }

  static void _syncProdutosOnChangeDebounced() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(_syncDebounceDelay, () {
      _syncDebounce = null;
      _syncProdutosOnChange();
    });
  }

  static Future<void> _syncProdutosOnChange() async {
    final box = _produtosBox;
    final lojaId = _produtosLojaId;
    if (box == null || lojaId == null) return;

    try {
      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: lojaId,
        produtosBox: box,
      );
      debugPrint(
        '🔄 [LISTENER_SYNC] Produtos sincronizados após mudança (lojaId=$lojaId, box=${box.name}, length=${box.length})',
      );
    } catch (e) {
      debugPrint(
        '⚠️ [LISTENER_SYNC] Erro ao sincronizar produtos (type=${e.runtimeType}) '
        '| lojaId=$lojaId | box=${box.name}',
      );
    }
  }

  /// Cancela listener de produtos.
  static void cancelProdutosListener() {
    _syncDebounce?.cancel();
    _syncDebounce = null;
    _produtosSub?.cancel();
    _produtosSub = null;
    _produtosLojaId = null;
    _produtosBox = null;
    debugPrint('📡 [CRITICAL-LISTENER] Listener de produtos cancelado');
  }

  // ===================== LISTENER DE PERMISSÕES =====================

  /// Inicia listener de permissões para admin (usuarios/{email}).
  /// Para vendedor, as permissões já são buscadas do Firestore a cada verificação.
  /// Chamar ao abrir HomeScreen. Cancelar em dispose.
  static void startPermissoesListener({
    required String userEmail,
    required String tipoUsuario,
    String? storeId,
    String? userUid,
  }) {
    final email = userEmail.trim().toLowerCase();
    if (email.isEmpty) return;

    cancelPermissoesListener();

    // Admin/programador: escuta usuarios/{email}
    if (tipoUsuario == 'admin' || tipoUsuario == 'programador') {
      _permissoesSub = _db.collection('usuarios').doc(email).snapshots().listen((snap) {
        if (!snap.exists || snap.data() == null) return;
        _onPermissoesAdminChanged(email, snap.data()!);
      });
      debugPrint('📡 [CRITICAL-LISTENER] Listener de permissões (admin) ativo para $email');
      return;
    }

    // Vendedor: escuta lojas/{storeId}/vendedores/{uid}
    if (tipoUsuario == 'vendedor' && storeId != null && storeId.isNotEmpty && userUid != null && userUid.isNotEmpty) {
      _permissoesSub = _db
          .collection('lojas')
          .doc(storeId)
          .collection('vendedores')
          .doc(userUid)
          .snapshots()
          .listen((snap) {
        if (!snap.exists || snap.data() == null) return;
        _onPermissoesVendedorChanged(snap.data()!);
      });
      debugPrint('📡 [CRITICAL-LISTENER] Listener de permissões (vendedor) ativo para $userUid');
    }
  }

  static Future<void> _onPermissoesAdminChanged(String email, Map<String, dynamic> data) async {
    try {
      final raw = data['permissoes'];
      if (raw is! Map) return;
      final permissoes = Map<String, bool>.from(
        raw.map((k, v) => MapEntry(k.toString(), v == true)),
      );
      await PermissaoService.salvarPermissoesPorUsuario(email, permissoes);
      await PermissaoService.refreshPermissoesLocais();
      debugPrint('🔄 [CRITICAL-LISTENER] Permissões admin atualizadas');
    } catch (e) {
      debugPrint('⚠️ [CRITICAL-LISTENER] Erro ao atualizar permissões admin (type=${e.runtimeType})');
    }
  }

  static Future<void> _onPermissoesVendedorChanged(Map<String, dynamic> data) async {
    try {
      // PermissaoService para vendedor sempre busca do Firestore em possuiPermissao.
      // Este listener garante que ao mudar, o próximo acesso terá dados frescos.
      // Opcional: poderia invalidar cache se existir. Por ora apenas log.
      debugPrint('🔄 [CRITICAL-LISTENER] Permissões vendedor alteradas no Firestore');
    } catch (e) {
      debugPrint('⚠️ [CRITICAL-LISTENER] Erro ao processar permissões vendedor (type=${e.runtimeType})');
    }
  }

  /// Cancela listener de permissões.
  static void cancelPermissoesListener() {
    _permissoesSub?.cancel();
    _permissoesSub = null;
    debugPrint('📡 [CRITICAL-LISTENER] Listener de permissões cancelado');
  }
}
