// lib/services/auto_sync_service.dart
//
// Sincronização automática Firestore → Hive ao conectar.
// Paridade Web/APK: vendas de qualquer plataforma aparecem em todas (por lojaId).
// Executa ao login, ao reconectar internet e pode ser disparada por telas.

import 'dart:async';

import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../models/cliente.dart';
import '../models/fornecedor.dart';
import '../models/venda.dart';
import 'deduplicacao_clientes_service.dart';
import 'fornecedores_firestore_service.dart';
import 'full_sync_service.dart';
import 'reconciliacao_vendas_clientes_service.dart';
import 'store_resolver_facade.dart';
import 'sync_queue_service.dart';
import 'vendas_firestore_service.dart';

/// Resultado da sincronização automática
class AutoSyncResult {
  bool sucesso = false;
  String? erro;
  int produtosSincronizados = 0;
  int clientesSincronizados = 0;
  int vendasSincronizadas = 0;
  int fornecedoresSincronizados = 0;
  int vendasReconciliadas = 0;
  int clientesDeduplicados = 0;
}

/// Serviço de sincronização automática ao conectar.
/// Sincroniza produtos, clientes, vendas, fornecedores, reconciliação e deduplicação.
class AutoSyncService {
  AutoSyncService._();

  static bool _isRunning = false;
  static DateTime? _lastSyncAt;

  /// Última execução (para evitar sync redundante em curto intervalo)
  static DateTime? get lastSyncAt => _lastSyncAt;

  /// Se a sync está em execução
  static bool get isRunning => _isRunning;

  /// Executa sincronização completa Firestore → Hive.
  /// Chamado ao login, ao reconectar internet e opcionalmente ao abrir telas.
  static Future<AutoSyncResult> syncCompleto() async {
    if (_isRunning) {
      logD('🔄 [AUTO-SYNC] Já em execução, ignorando chamada duplicada');
      return AutoSyncResult()..sucesso = true;
    }

    _isRunning = true;
    final result = AutoSyncResult();

    try {
      logD('═══════════════════════════════════════════════════════════');
      logD('🔄 [AUTO-SYNC] INICIANDO SINCRONIZAÇÃO AUTOMÁTICA');
      logD('═══════════════════════════════════════════════════════════');

      String? lojaId = await StoreResolverFacade.resolveForAdminApp()
          .timeout(const Duration(seconds: 12), onTimeout: () => null);
      if (lojaId == null || lojaId.isEmpty) {
        try {
          final sessao = Hive.isBoxOpen('sessao')
              ? Hive.box('sessao')
              : await Hive.openBox('sessao');
          lojaId = (sessao.get('store_id') ?? sessao.get('storeId') ?? '')
              .toString()
              .trim();
        } catch (e) {
          logW('⚠️ [SYNC] Erro ao tentar resolver lojaId a partir da box "sessao" em AutoSync (type=${e.runtimeType})');
        }
      }
      if (lojaId == null || lojaId.isEmpty) {
        result.erro = 'Nenhuma loja encontrada para este usuário';
        logD('❌ [AUTO-SYNC] Erro: ${result.erro}');
        return result;
      }

      // 1. Processar fila pendente (Hive → Firestore)
      try {
        await SyncQueueService.processPending();
      } catch (e) {
        logW('⚠️ [AUTO-SYNC] Erro na fila pendente (type=${e.runtimeType})');
      }

      // 2. FullSync: produtos + clientes
      final fullResult = await FullSyncService.syncInicialCompleto();
      result.produtosSincronizados = fullResult.produtosSincronizados;
      result.clientesSincronizados = fullResult.clientesSincronizados;
      if (!fullResult.sucesso && fullResult.erro != null) {
        logW('⚠️ [AUTO-SYNC] FullSync parcial: ${fullResult.erro}');
      }

      // 3. Abrir boxes necessárias
      final clientesBox = Hive.isBoxOpen(HiveBoxNames.clientes(lojaId))
          ? Hive.box<Cliente>(HiveBoxNames.clientes(lojaId))
          : await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));
      final vendasBox = Hive.isBoxOpen(HiveBoxNames.vendas(lojaId))
          ? Hive.box<Venda>(HiveBoxNames.vendas(lojaId))
          : await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      final fornecedoresBox = Hive.isBoxOpen(HiveBoxNames.fornecedores(lojaId))
          ? Hive.box<Fornecedor>(HiveBoxNames.fornecedores(lojaId))
          : await Hive.openBox<Fornecedor>(HiveBoxNames.fornecedores(lojaId));

      // 4. Sync vendas Firestore → Hive
      try {
        result.vendasSincronizadas = await VendasFirestoreService.syncFirestoreToHive(
          lojaId: lojaId,
          vendasBox: vendasBox,
        );
        logD('✅ [AUTO-SYNC] Vendas: ${result.vendasSincronizadas}');
      } catch (e, st) {
        logE('❌ [AUTO-SYNC] Erro ao sincronizar vendas (type=${e.runtimeType})', error: e, st: st);
      }

      // 5. Sync fornecedores Firestore → Hive
      try {
        result.fornecedoresSincronizados = await FornecedoresFirestoreService.syncFirestoreToHive(
          lojaId: lojaId,
          fornecedoresBox: fornecedoresBox,
        );
        logD('✅ [AUTO-SYNC] Fornecedores: ${result.fornecedoresSincronizados}');
      } catch (e, st) {
        logE('❌ [AUTO-SYNC] Erro ao sincronizar fornecedores (type=${e.runtimeType})', error: e, st: st);
      }

      // 6. Reconciliação vendas ↔ clientes
      try {
        result.vendasReconciliadas = await ReconciliacaoVendasClientesService.reconciliar(
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          lojaId: lojaId,
        );
        if (result.vendasReconciliadas > 0) {
          logD('✅ [AUTO-SYNC] Reconciliação: ${result.vendasReconciliadas} vendas vinculadas');
        }
      } catch (e) {
        logW('⚠️ [AUTO-SYNC] Erro na reconciliação (type=${e.runtimeType})');
      }

      // 7. Deduplicação de clientes
      try {
        result.clientesDeduplicados = await DeduplicacaoClientesService.deduplicar(
          clientesBox,
          vendasBox,
          lojaId,
        );
        if (result.clientesDeduplicados > 0) {
          logD('✅ [AUTO-SYNC] Deduplicação: ${result.clientesDeduplicados} clientes removidos');
        }
      } catch (e) {
        logW('⚠️ [AUTO-SYNC] Erro na deduplicação (type=${e.runtimeType})');
      }

      result.sucesso = true;
      _lastSyncAt = DateTime.now();

      logD('═══════════════════════════════════════════════════════════');
      logD('✅ [AUTO-SYNC] SINCRONIZAÇÃO AUTOMÁTICA FINALIZADA');
      logD('   Produtos: ${result.produtosSincronizados} | Clientes: ${result.clientesSincronizados}');
      logD('   Vendas: ${result.vendasSincronizadas} | Fornecedores: ${result.fornecedoresSincronizados}');
      logD('   Reconciliadas: ${result.vendasReconciliadas} | Deduplicados: ${result.clientesDeduplicados}');
      logD('═══════════════════════════════════════════════════════════');
    } catch (e, st) {
      result.erro = e.toString();
      logE('❌ [AUTO-SYNC] Erro geral (type=${e.runtimeType})', error: e, st: st);
    } finally {
      _isRunning = false;
    }

    return result;
  }

  /// Dispara sync em background (não bloqueia).
  /// Usado ao login e ao reconectar.
  static void syncEmBackground() {
    syncCompleto().then((r) {
      if (r.sucesso) {
        logD('✅ [AUTO-SYNC] Background sync concluída');
      } else {
        logW('⚠️ [AUTO-SYNC] Background sync com erro: ${r.erro}');
      }
    }).catchError((e) {
      logW('⚠️ [AUTO-SYNC] Erro na sync em background (type=${e.runtimeType})');
    });
  }
}
