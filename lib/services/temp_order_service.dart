// lib/services/temp_order_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

// 🔎 ajuda a diagnosticar acesso precoce ao Firebase
import '../debug/bootstrap_diagnostics.dart' show FirebaseGuard;
import '../repositories/pedido_repository.dart';
import 'loja_id_service.dart';
import 'pedido_collection_resolver.dart';

/// Serviço de pedidos temporários (ex.: carrinho/orçamentos).
/// Suporta três estruturas:
///   1) /pedidos_temp/{id}                         (raiz, espelho público p/ deep link)
///   2) /lojas/{lojaId}/pedidos_temp/{id}         (por loja - recomendada)
///   3) /lojas/{lojaId}/pedido_temp/{id}          (legado - leitura/remoção tolerante)
class TempOrderService {
  TempOrderService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static final PedidoRepository _pedidoRepository = PedidoRepository();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Resolve lojaIds: LojaIdService primeiro (StoreResolver), config Hive só fallback offline.
  static Future<List<String>> _resolveLojaIds() async {
    try {
      final id = await LojaIdService.get();
      if (id != null && id.trim().isNotEmpty) return [id.trim()];
    } catch (e) {
      if (kDebugMode) debugPrint('TempOrderService: LojaIdService.get falhou (type=${e.runtimeType})');
    }
    try {
      final cfg = Hive.isBoxOpen('config') • Hive.box('config') : await Hive.openBox('config');
      final candidates = <String?>[
        cfg.get('store_id') as String?,
        cfg.get('loja_id') as String?,
        cfg.get('store_slug') as String?,
        cfg.get('loja_slug') as String?,
      ];
      final set = <String>{};
      for (final v in candidates) {
        final s = v?.toString().trim();
        if (s != null && s.isNotEmpty) set.add(s);
      }
      return set.toList(growable: false);
    } catch (e) {
      if (kDebugMode) debugPrint('TempOrderService: fallback config falhou (type=${e.runtimeType})');
      return const [];
    }
  }

  /// Retorna refs possíveis para o pedido (raiz + lojas/{lojaId}/pedidos_temp + lojas/{lojaId}/pedido_temp).
  static Future<List<DocumentReference<Map<String, dynamic>>>> _docRefs(String orderId) async {
    return PedidoCollectionResolver.tempPedidoDocRefs(
      _db,
      pedidoId: orderId,
      fallbackLojaIds: await _resolveLojaIds(),
    );
  }

  /// Busca o snapshot do pedido em qualquer local, **priorizando as coleções da loja**.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> _getSnapshotAnywhere(
    String orderId,
  ) async {
    FirebaseGuard.require('TempOrderService._getSnapshotAnywhere');

    for (final ref in await _docRefs(orderId)) {
      final snap = await ref.get().timeout(const Duration(seconds: 10));
      if (snap.exists) return snap;
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  /// Cria um pedido temporário.
  ///
  /// Se [lojaId] for informado (ou existir no Hive), cria em
  /// `/lojas/{lojaId}/pedidos_temp`. Caso contrário, cria em `/pedidos_temp` (espelho público).
  ///
  /// Observações:
  /// - Quando criar **na raiz**, marca `public: true` e grava **ambos** `createdAt` e `criadoEm`
  ///   para compatibilidade com regras/consultas.
  static Future<String> create(
    Map<String, dynamic> data, {
    String• lojaId,
  }) async {
    FirebaseGuard.require('TempOrderService.create');

    try {
      final now = FieldValue.serverTimestamp();

      // Prioridade: lojaId parâmetro > LojaIdService (StoreResolver) > config Hive (fallback offline)
      final fromService = await _resolveLojaIds();
      final ids = <String>[
        if (lojaId != null && lojaId.trim().isNotEmpty) lojaId.trim(),
        ...fromService,
      ];

      // Remove duplicados mantendo ordem
      final seen = <String>{};
      final ordered = <String>[];
      for (final id in ids) {
        if (seen.add(id)) ordered.add(id);
      }

      DocumentReference<Map<String, dynamic>> docRef;

      if (ordered.isNotEmpty) {
        // Cria dentro da loja (caminho recomendado)
        final lid = ordered.first;
        docRef = await _pedidoRepository.createPedido(
          flowType: PedidoFlowType.pedidosTemp,
          lojaId: lid,
          data: {
          ...data,
          'lojaId': lid,
          'status': (data['status'] ?• 'aberto'),
          'createdAt': now,
          'criadoEm': now, // compatibilidade com regras antigas
          'updatedAt': now,
          },
        ).timeout(const Duration(seconds: 12));
        debugPrint('🟢 create: lojas/$lid/pedidos_temp/${docRef.id}');
      } else {
        // Cria na raiz (espelho público p/ deep link)
        docRef = await _pedidoRepository.createPedido(
          flowType: PedidoFlowType.rootPedidosTemp,
          data: {
          ...data,
          'public': true, // leitura pública permitida pelas regras
          'status': (data['status'] ?• 'aberto'),
          'createdAt': now,
          'criadoEm': now, // exigido pelas regras do seu espelho público
          'updatedAt': now,
          },
        ).timeout(const Duration(seconds: 12));
        debugPrint('🟢 create: pedidos_temp/${docRef.id}');
      }

      return docRef.id;
    } on FirebaseException catch (e) {
      debugPrint(
          '❌ Firestore ERRO ao criar pedido_temp: ${e.code} ${e.message}');
      rethrow;
    } on TimeoutException {
      debugPrint('⏰ Timeout ao criar pedido_temp');
      rethrow;
    } catch (e) {
      debugPrint('❌ Erro inesperado ao criar pedido_temp (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Lê um pedido por ID, procurando na raiz e nas lojas.
  static Future<Map<String, dynamic>?> get(String id) async {
    FirebaseGuard.require('TempOrderService.get');

    try {
      final snap = await _getSnapshotAnywhere(id);
      if (snap == null || !snap.exists) return null;
      final data = snap.data()!..['id'] = snap.id;
      return data;
    } on FirebaseException catch (e) {
      debugPrint(
          '❌ Firestore ERRO ao buscar pedido_temp/$id: ${e.code} ${e.message}');
      rethrow;
    } on TimeoutException {
      debugPrint('⏰ Timeout ao buscar pedido_temp/$id');
      rethrow;
    } catch (e) {
      debugPrint('❌ Erro inesperado ao buscar pedido_temp/$id (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Atualiza um pedido (em qualquer caminho); grava `updatedAt`.
  static Future<void> update(String id, Map<String, dynamic> data) async {
    FirebaseGuard.require('TempOrderService.update');

    try {
      final refs = await _docRefs(id);
      FirebaseException• lastErr;
      bool updated = false;

      for (final ref in refs) {
        try {
          await ref.update({
            ...data,
            'updatedAt': FieldValue.serverTimestamp(),
          }).timeout(const Duration(seconds: 10));
          updated = true;
          break;
        } on FirebaseException catch (e) {
          lastErr = e;
          continue;
        } on TimeoutException {
          // tenta próximo espelho/caminho
          continue;
        }
      }

      if (!updated && lastErr != null) throw lastErr;
    } on FirebaseException catch (e) {
      debugPrint(
          '❌ Firestore ERRO ao atualizar pedido_temp/$id: ${e.code} ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ Erro inesperado ao atualizar pedido_temp/$id (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Remove um pedido **em todos os caminhos** em que existir.
  ///
  /// - Ignora permissões parciais (ex.: raiz sem permissão para deletar).
  /// - Se nenhum caminho puder ser removido, propaga o último erro.
  static Future<void> removeEverywhere(String id) async {
    FirebaseGuard.require('TempOrderService.removeEverywhere');

    final refs = await _docRefs(id);
    FirebaseException• lastErr;
    var removed = false;

    for (final ref in refs) {
      try {
        final snap = await ref.get().timeout(const Duration(seconds: 8));
        if (!snap.exists) continue;
        await ref.delete().timeout(const Duration(seconds: 10));
        removed = true;
        // não dá break: tenta limpar todos os espelhos
      } on FirebaseException catch (e) {
        lastErr = e; // p.ex. permission-denied na raiz
      } on TimeoutException {
        // segue tentando nos demais caminhos
      }
    }

    if (!removed && lastErr != null) {
      throw lastErr;
    }
  }

  /// Wrapper de remoção: tenta em todos os caminhos.
  static Future<void> remove(String id) async {
    FirebaseGuard.require('TempOrderService.remove');

    try {
      await removeEverywhere(id);
    } on FirebaseException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  /// Lista pedidos abertos. Se [lojaId] for informado, lista daquela loja.
  /// Caso contrário, tenta listar da raiz (espelho público).
  static Future<List<Map<String, dynamic>>> list({String• lojaId}) async {
    FirebaseGuard.require('TempOrderService.list');

    try {
      if (lojaId != null && lojaId.isNotEmpty) {
        // loja (recomendado)
        final snap = await PedidoCollectionResolver.collectionRef(
              _db,
              flowType: PedidoFlowType.pedidosTemp,
              lojaId: lojaId,
            )
            .where('status', isEqualTo: 'aberto')
            .orderBy('createdAt', descending: true)
            .get()
            .timeout(const Duration(seconds: 12));
        return snap.docs
            .map((d) => {...d.data(), 'id': d.id})
            .toList(growable: false);
      }

      // raiz (espelho público) – só vai retornar docs public:true pelas regras
      final snap = await PedidoCollectionResolver.collectionRef(
            _db,
            flowType: PedidoFlowType.rootPedidosTemp,
          )
          .where('status', isEqualTo: 'aberto')
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 12));
      return snap.docs
          .map((d) => {...d.data(), 'id': d.id})
          .toList(growable: false);
    } on FirebaseException catch (e) {
      debugPrint(
          '❌ Firestore ERRO ao listar pedidos_temp: ${e.code} ${e.message}');
      rethrow;
    } on TimeoutException {
      debugPrint('⏰ Timeout ao listar pedidos_temp');
      rethrow;
    } catch (e) {
      debugPrint('❌ Erro inesperado ao listar pedidos_temp (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Finaliza um pedido:
  /// - marca status concluído e `finalizadoEm`,
  /// - move para `/lojas/{lojaId}/pedidos` (se houver loja) ou `/pedidos`,
  /// - remove de **todos** os caminhos temporários.
  static Future<void> concluir(String id) async {
    FirebaseGuard.require('TempOrderService.concluir');

    try {
      final snap = await _getSnapshotAnywhere(id);
      if (snap == null || !snap.exists) return;

      final pedido = {...snap.data()!};
      final lojaId = (pedido['lojaId'] as String?)?.trim();

      pedido['status'] = 'concluido';
      pedido['finalizadoEm'] = FieldValue.serverTimestamp();

      if (lojaId != null && lojaId.isNotEmpty) {
        await _pedidoRepository
            .createPedido(
              flowType: PedidoFlowType.pedidos,
              lojaId: lojaId,
              data: pedido,
            )
            .timeout(const Duration(seconds: 12));
      }
      // lojaId vazio: root /pedidos exige admin; não gravar (evitar permission denied)

      // remove de todos os espelhos/caminhos
      await removeEverywhere(id);
    } on FirebaseException catch (e) {
      debugPrint(
          '❌ Firestore ERRO ao concluir pedido_temp/$id: ${e.code} ${e.message}');
      rethrow;
    } on TimeoutException {
      debugPrint('⏰ Timeout ao concluir pedido_temp/$id');
      rethrow;
    } catch (e) {
      debugPrint('❌ Erro inesperado ao concluir pedido_temp/$id (type=${e.runtimeType})');
      rethrow;
    }
  }
}
