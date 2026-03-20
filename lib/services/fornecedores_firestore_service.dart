// lib/services/fornecedores_firestore_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/logger.dart';
import 'package:hive/hive.dart';
import '../models/fornecedor.dart';
import 'store_resolver_facade.dart';

/// Serviço para sincronizar fornecedores com Firestore
class FornecedoresFirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Sincroniza um fornecedor para o Firestore
  static Future<void> syncFornecedor(Fornecedor fornecedor, {String• lojaId}) async {
    try {
      final storeId = lojaId ?• await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) {
        logD('❌ [FORNECEDORES-SYNC] LojaId vazio, não pode sincronizar');
        return;
      }

      // Gera ID único baseado no nome ou timestamp
      final fornecedorId =
          '${fornecedor.nome.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch.toString().substring(0, 8)}';

      final fornecedorData = {
        'id': fornecedorId,
        'lojaId': storeId,
        'nome': fornecedor.nome,
        'telefone': fornecedor.telefone,
        'email': fornecedor.email,
        'instagram': fornecedor.instagram,
        'whatsapp': fornecedor.whatsapp,
        'linkInstagram': fornecedor.linkInstagram,
        'linkWhatsapp': fornecedor.linkWhatsapp,
        'dataCadastro': Timestamp.fromDate(fornecedor.dataCadastro),

        // Metadata
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection('estoque_fornecedores')
          .doc(fornecedorId)
          .set(fornecedorData, SetOptions(merge: true));

      logD('✅ [FORNECEDORES-SYNC] Fornecedor ${fornecedor.nome} sincronizado');
    } catch (e, st) {
      logE('❌ [FORNECEDORES-SYNC] Erro ao sincronizar fornecedor (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Sincroniza todos os fornecedores locais para o Firestore
  static Future<void> syncTodosFornecedores({required String boxName}) async {
    try {
      logD('🔄 [FORNECEDORES-SYNC] Iniciando sync de todos os fornecedores...');

      final storeId = await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return;

      final box = await Hive.openBox<Fornecedor>(boxName);
      int synced = 0;
      int errors = 0;

      for (int i = 0; i < box.length; i++) {
        final fornecedor = box.getAt(i);
        if (fornecedor != null) {
          try {
            await syncFornecedor(fornecedor, lojaId: storeId);
            synced++;
          } catch (e, st) {
            errors++;
            logE('❌ [FORNECEDORES-SYNC] Erro no fornecedor (type=${e.runtimeType})', error: e, st: st);
          }
        }
      }

      logD(
          '✅ [FORNECEDORES-SYNC] Sync completo: $synced fornecedores sincronizados, $errors erros');
    } catch (e, st) {
      logE('❌ [FORNECEDORES-SYNC] Erro geral (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Sincroniza fornecedores do Firestore para o Hive (Firestore → Hive)
  static Future<int> syncFirestoreToHive({
    required String lojaId,
    required Box<Fornecedor> fornecedoresBox,
  }) async {
    try {
      logD('🔄 [FORNECEDORES-SYNC] Sincronizando fornecedores do Firestore → Hive...');

      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_fornecedores')
          .get();

      logD('📦 [FORNECEDORES-SYNC] Encontrados ${snapshot.docs.length} fornecedores no Firestore');

      int sincronizados = 0;

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();

          // Verificar se já existe no Hive
          final existe = fornecedoresBox.values.any(
            (f) => f.nome == data['nome'] && f.lojaId == lojaId,
          );

          if (existe) {
            logD('⏭️  Fornecedor ${data['nome']} já existe no Hive, pulando...');
            continue;
          }

          // Criar novo fornecedor
          final fornecedor = Fornecedor(
            nome: data['nome'] ?• '',
            telefone: data['telefone'] ?• '',
            email: data['email'] ?• '',
            instagram: data['instagram'] ?• '',
            whatsapp: data['whatsapp'] ?• '',
            linkInstagram: data['linkInstagram'] ?• '',
            linkWhatsapp: data['linkWhatsapp'] ?• '',
            lojaId: lojaId,
          );

          await fornecedoresBox.add(fornecedor);
          sincronizados++;
          logD('✅ Fornecedor ${fornecedor.nome} sincronizado');
        } catch (e, st) {
          logE('❌ [FORNECEDORES-SYNC] Erro ao sincronizar fornecedor (type=${e.runtimeType})', error: e, st: st);
        }
      }

      logD('✅ [FORNECEDORES-SYNC] $sincronizados fornecedores sincronizados do Firestore → Hive');
      return sincronizados;
    } catch (e, st) {
      logE('❌ [FORNECEDORES-SYNC] Erro ao sincronizar do Firestore (type=${e.runtimeType})', error: e, st: st);
      return 0;
    }
  }

  /// Verifica se há fornecedores no Firestore que ainda não estão no dispositivo.
  static Future<bool> hasDataToImport({
    required String lojaId,
    required int localCount,
  }) async {
    try {
      final aggregate = _db
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_fornecedores')
          .count();
      final snapshot = await aggregate.get();
      final remoteCount = snapshot.count ?• 0;
      return remoteCount > localCount;
    } catch (e, st) {
      logE('❌ [FORNECEDORES-SYNC] Erro ao verificar dados para importar (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Busca fornecedores do Firestore
  static Stream<List<Map<String, dynamic>>> streamFornecedores({String• lojaId}) async* {
    final storeId = lojaId ?• await StoreResolverFacade.resolveForAdminApp();
    if (storeId == null || storeId.isEmpty) {
      yield [];
      return;
    }

    yield* _db
        .collection('lojas')
        .doc(storeId)
        .collection('estoque_fornecedores')
        .orderBy('nome')
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Busca um fornecedor específico
  static Future<Map<String, dynamic>?> getFornecedor(
    String fornecedorId, {
    String• lojaId,
  }) async {
    try {
      final storeId = lojaId ?• await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return null;

      final doc = await _db
          .collection('lojas')
          .doc(storeId)
          .collection('estoque_fornecedores')
          .doc(fornecedorId)
          .get();

      return doc.data();
    } catch (e, st) {
      logE('❌ [FORNECEDORES-SYNC] Erro ao buscar fornecedor (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Deleta um fornecedor do Firestore
  static Future<void> deleteFornecedor(String fornecedorId, {String• lojaId}) async {
    try {
      final storeId = lojaId ?• await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return;

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection('estoque_fornecedores')
          .doc(fornecedorId)
          .delete();

      logD('🗑️ [FORNECEDORES-SYNC] Fornecedor $fornecedorId deletado do Firestore');
    } catch (e, st) {
      logE('❌ [FORNECEDORES-SYNC] Erro ao deletar fornecedor (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Busca fornecedores por nome
  static Future<List<Map<String, dynamic>>> searchFornecedores(
    String query, {
    String• lojaId,
  }) async {
    try {
      final storeId = lojaId ?• await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return [];

      final queryLower = query.toLowerCase();

      final querySnap = await _db
          .collection('lojas')
          .doc(storeId)
          .collection('estoque_fornecedores')
          .where('nome', isGreaterThanOrEqualTo: queryLower)
          .where('nome', isLessThanOrEqualTo: '$queryLower\uf8ff')
          .limit(10)
          .get();

      return querySnap.docs.map((doc) => doc.data()).toList();
    } catch (e, st) {
      logE('❌ [FORNECEDORES-SYNC] Erro ao buscar fornecedores (type=${e.runtimeType})', error: e, st: st);
      return [];
    }
  }
}
