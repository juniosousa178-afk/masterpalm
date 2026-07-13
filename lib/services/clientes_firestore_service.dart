// lib/services/clientes_firestore_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/hive_box_names.dart';
import '../core/cupom_pessoal_cliente_busca.dart';
import 'firestore_paths.dart';
import '../core/logger.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/cliente.dart';
import 'store_resolver_facade.dart';
import 'image_upload_service.dart';
import 'sync_queue_service.dart';

/// Serviço para sincronizar clientes do admin com Firestore (estoque_clientes).
/// DOMÍNIO ADMIN (FASE 4): Não é perfil do catálogo. Ver docs/MAPA_CLIENTES_E_PATHS.md.
class ClientesFirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Sincroniza um cliente para o Firestore (com retry para conexões instáveis)
  static Future<void> syncCliente(Cliente cliente, {String? lojaId}) async {
    const maxAttempts = 3;
    const baseDelay = Duration(milliseconds: 500);

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
        if (storeId == null || storeId.isEmpty) {
          logD('❌ [CLIENTES-SYNC] LojaId vazio, não pode sincronizar');
          return;
        }

        // ID único: usa idFirebase (compat.) ou busca existente por telefone+nome ou gera UUID
        String clienteId;
        if (cliente.idFirebase != null && cliente.idFirebase!.isNotEmpty) {
          clienteId = cliente.idFirebase!;
        } else {
          // Compat: buscar cliente existente no Firestore por telefone+nome
          final telNorm = cliente.telefone.replaceAll(RegExp(r'[^0-9]'), '');
          final nomeNorm = cliente.nome.toLowerCase().replaceAll(' ', '_');
          final oldId = '${telNorm}_$nomeNorm';
          if (telNorm.isNotEmpty && nomeNorm.isNotEmpty) {
            final existing = await _db
                .collection('lojas')
                .doc(storeId)
                .collection(FSPaths.estoqueClientesCol)
                .doc(oldId)
                .get();
            clienteId = existing.exists ? oldId : const Uuid().v4();
          } else {
            clienteId = const Uuid().v4();
          }
          cliente.idFirebase = clienteId;
          await cliente.save();
        }

        // 📸 Fazer upload do avatar se for caminho local
        String? avatarUrl;
        if (cliente.avatarPath != null && cliente.avatarPath!.isNotEmpty) {
          if (ImageUploadService.isLocalPath(cliente.avatarPath)) {
            logD('📤 [CLIENTES-SYNC] Fazendo upload do avatar: ${cliente.avatarPath}');
            avatarUrl = await ImageUploadService.uploadImage(
              imagePath: cliente.avatarPath!,
              folder: 'avatares',
              lojaId: storeId,
            );

            if (avatarUrl != null) {
              cliente.avatarPath = avatarUrl;
              await cliente.save();
              logD('✅ [CLIENTES-SYNC] Avatar atualizado com URL do Firebase');
            }
          } else {
            avatarUrl = cliente.avatarPath;
          }
        }

        final clienteData = {
        'id': clienteId,
        'idFirebase': clienteId,
        'lojaId': storeId,
        'nome': cliente.nome,
        'telefone': cliente.telefone,
        'email': cliente.email ?? '',
        'endereco': cliente.endereco ?? '',
        'instagram': cliente.instagram,
        'cep': cliente.cep,
        'cidade': cliente.cidade,
        'avatarUrl': avatarUrl, // ✅ URL do Firebase Storage

        // Metadata
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        };

        await _db
            .collection('lojas')
            .doc(storeId)
            .collection(FSPaths.estoqueClientesCol)
            .doc(clienteId)
            .set(clienteData, SetOptions(merge: true));

        logD('✅ [CLIENTES-SYNC] Cliente ${cliente.nome} sincronizado');
        return;
      } catch (e, st) {
        logE('❌ [CLIENTES-SYNC] Tentativa falhou (type=${e.runtimeType})', error: e, st: st);
        if (attempt < maxAttempts) {
          await Future<void>.delayed(baseDelay * attempt);
        } else {
          logE('❌ [CLIENTES-SYNC] Erro final ao sincronizar cliente (type=${e.runtimeType})', error: e, st: st);
          // Enfileira para retry quando a rede voltar
          final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
          final key = cliente.key;
          final boxName = cliente.box?.name ?? (storeId != null ? HiveBoxNames.clientes(storeId) : null);
          if (storeId != null && key != null && boxName != null) {
            await SyncQueueService.enqueue(
              type: SyncOperationType.upsertCliente,
              lojaId: storeId,
              boxName: boxName,
              entityKey: key is int ? key : int.tryParse(key.toString()) ?? 0,
            );
          }
        }
      }
    }
  }

  /// Sincroniza todos os clientes locais para o Firestore
  static Future<void> syncTodosClientes({required String boxName}) async {
    try {
      logD('🔄 [CLIENTES-SYNC] Iniciando sync de todos os clientes...');

      final storeId = await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return;

      final box = await Hive.openBox<Cliente>(boxName);
      int synced = 0;
      int errors = 0;

      for (int i = 0; i < box.length; i++) {
        final cliente = box.getAt(i);
        if (cliente != null) {
          try {
            await syncCliente(cliente, lojaId: storeId);
            synced++;
          } catch (e, st) {
            errors++;
            logE('❌ [CLIENTES-SYNC] Erro no cliente (type=${e.runtimeType})', error: e, st: st);
          }
        }
      }

      logD('✅ [CLIENTES-SYNC] Sync completo: $synced clientes sincronizados, $errors erros');
    } catch (e, st) {
      logE('❌ [CLIENTES-SYNC] Erro geral (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Sincroniza clientes do Firestore para o Hive (Firestore → Hive)
  static Future<int> syncFirestoreToHive({
    required String lojaId,
    required Box<Cliente> clientesBox,
  }) async {
    try {
      logD('🔄 [CLIENTES-SYNC] Sincronizando clientes do Firestore → Hive...');

      // limit(1000) para evitar timeout em lojas com muitos clientes
      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueClientesCol)
          .limit(1000)
          .get();

      logD('📦 [CLIENTES-SYNC] Encontrados ${snapshot.docs.length} clientes no Firestore');

      int sincronizados = 0;

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final docId = doc.id;

          // Verificar se já existe no Hive (por idFirebase ou telefone+nome para compat)
          final existe = clientesBox.values.any((c) {
            if (c.idFirebase == docId) return true;
            if (c.lojaId != lojaId) return false;
            final tel = (data['telefone'] ?? '').toString();
            return c.telefone == tel && c.nome == (data['nome'] ?? '');
          });

          if (existe) {
            logD('⏭️  Cliente ${data['nome']} já existe no Hive, pulando...');
            continue;
          }

          // Criar novo cliente (idFirebase = doc.id para compatibilidade)
          final cliente = Cliente(
            nome: data['nome'] ?? '',
            telefone: data['telefone'] ?? '',
            email: data['email'],
            endereco: data['endereco'],
            instagram: data['instagram'] ?? '',
            cep: data['cep'] ?? '',
            cidade: data['cidade'] ?? '',
            lojaId: lojaId,
            idFirebase: docId,
          )
            ..avatarPath = data['avatarUrl'];

          await clientesBox.add(cliente);
          sincronizados++;
          logD('✅ Cliente ${cliente.nome} sincronizado');
        } catch (e, st) {
          logE('❌ [CLIENTES-SYNC] Erro ao sincronizar cliente (type=${e.runtimeType})', error: e, st: st);
        }
      }

      // Remover locais que não existem mais no Firestore (excluídos em outro aparelho)
      final firestoreIds = snapshot.docs.map((d) => d.id).toSet();
      final toRemove = <int>[];
      for (final k in clientesBox.keys) {
        final c = clientesBox.get(k);
        if (c != null && c.lojaId == lojaId && (c.idFirebase ?? '').isNotEmpty && !firestoreIds.contains(c.idFirebase)) {
          toRemove.add(k as int);
        }
      }
      for (final k in toRemove) {
        await clientesBox.delete(k);
        logD('🗑️ [CLIENTES-SYNC] Cliente local removido (excluído no Firestore): $k');
      }

      logD('✅ [CLIENTES-SYNC] $sincronizados clientes sincronizados, ${toRemove.length} removidos');
      return sincronizados;
    } catch (e, st) {
      logE('❌ [CLIENTES-SYNC] Erro ao sincronizar do Firestore (type=${e.runtimeType})', error: e, st: st);
      return 0;
    }
  }

  /// Verifica se há clientes no Firestore que ainda não estão no dispositivo.
  static Future<bool> hasDataToImport({
    required String lojaId,
    required int localCount,
  }) async {
    try {
      final aggregate = _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueClientesCol)
          .count();
      final snapshot = await aggregate.get();
      final remoteCount = snapshot.count ?? 0;
      return remoteCount > localCount;
    } catch (e, st) {
      logE('❌ [CLIENTES-SYNC] Erro ao verificar dados para importar (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Busca clientes do Firestore.
  /// FASE 3: Unificado com sync — usa estoque_clientes (mesma coleção de escrita/syncFirestoreToHive).
  static Stream<List<Map<String, dynamic>>> streamClientes({String? lojaId}) async* {
    final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
    if (storeId == null || storeId.isEmpty) {
      yield [];
      return;
    }

    yield* _db
        .collection('lojas')
        .doc(storeId)
        .collection(FSPaths.estoqueClientesCol)
        .orderBy('nome')
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Busca um cliente específico.
  /// FASE 3: Unificado — usa estoque_clientes (mesma coleção de sync).
  static Future<Map<String, dynamic>?> getCliente(String clienteId, {String? lojaId}) async {
    try {
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return null;

      final doc = await _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueClientesCol)
          .doc(clienteId)
          .get();

      return doc.data();
    } catch (e, st) {
      logE('❌ [CLIENTES-SYNC] Erro ao buscar cliente (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Deleta um cliente do Firestore (estoque_clientes = mesma coleção usada pelo sync)
  static Future<void> deleteCliente(String clienteId, {String? lojaId}) async {
    try {
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return;

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueClientesCol)
          .doc(clienteId)
          .delete();

      logD('🗑️ [CLIENTES-SYNC] Cliente $clienteId deletado do Firestore');
    } catch (e, st) {
      logE('❌ [CLIENTES-SYNC] Erro ao deletar cliente (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Busca clientes por nome, e-mail ou telefone (case-insensitive).
  /// FASE 3: Unificado — usa estoque_clientes (mesma coleção de sync).
  ///
  /// Nota: não usa range prefix lowercased em `nome` (quebrava Title Case).
  /// Carrega um lote limitado e filtra localmente — adequado ao admin.
  static Future<List<Map<String, dynamic>>> searchClientes(
    String query, {
    String? lojaId,
  }) async {
    try {
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return [];

      final q = query.trim().toLowerCase();
      if (q.length < 2) return [];

      final snap = await _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueClientesCol)
          .limit(300)
          .get();

      final all = snap.docs
          .map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id})
          .toList();

      return filtrarClientesCupomPessoal(clientes: all, query: q, limit: 10);
    } catch (e, st) {
      logE('❌ [CLIENTES-SYNC] Erro ao buscar clientes (type=${e.runtimeType})', error: e, st: st);
      return [];
    }
  }
}
