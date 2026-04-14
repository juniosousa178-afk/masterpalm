// lib/services/controle_compras_fornecedor_service.dart
// Registro apenas para conferência — não alimenta FinanceiroService, relatórios nem metas.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/hive_box_names.dart';
import 'controle_compras_fornecedor_firestore_service.dart';

/// Uma linha de compra para controle (totais por fornecedor).
class LinhaControleCompraFornecedor {
  LinhaControleCompraFornecedor({
    required this.id,
    required this.fornecedorNome,
    required this.valor,
    required this.frete,
    required this.desconto,
    required this.total,
    required this.dataCompra,
    required this.criadoEm,
  });

  final String id;
  final String fornecedorNome;
  final double valor;
  final double frete;
  final double desconto;
  final double total;
  /// Data da compra (operacional — escolhida pelo usuário).
  final DateTime dataCompra;
  /// Data/hora em que o registro foi lançado no controle.
  final DateTime criadoEm;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fornecedorNome': fornecedorNome,
        'valor': valor,
        'frete': frete,
        'desconto': desconto,
        'total': total,
        'dataCompra': dataCompra.toIso8601String(),
        'criadoEm': criadoEm.toIso8601String(),
      };

  static LinhaControleCompraFornecedor fromJson(Map<String, dynamic> m) {
    final criadoEm = DateTime.tryParse((m['criadoEm'] ?? '').toString()) ??
        DateTime.now();
    final rawDc = m['dataCompra'];
    final parsedDc = rawDc != null
        ? DateTime.tryParse(rawDc.toString())
        : null;
    final dataCompra = parsedDc ??
        DateTime(criadoEm.year, criadoEm.month, criadoEm.day);

    return LinhaControleCompraFornecedor(
      id: (m['id'] ?? '').toString(),
      fornecedorNome: (m['fornecedorNome'] ?? '').toString().trim(),
      valor: (m['valor'] as num?)?.toDouble() ?? 0,
      frete: (m['frete'] as num?)?.toDouble() ?? 0,
      desconto: (m['desconto'] as num?)?.toDouble() ?? 0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      dataCompra: dataCompra,
      criadoEm: criadoEm,
    );
  }
}

class ControleComprasFornecedorService {
  ControleComprasFornecedorService._();
  static const _kJson = 'linhas_json';

  static Future<Box<String>> _box(String lojaId) async {
    final name = HiveBoxNames.controleTotaisCompraFornecedor(lojaId.trim());
    if (Hive.isBoxOpen(name)) return Hive.box<String>(name);
    return Hive.openBox<String>(name);
  }

  static Future<List<LinhaControleCompraFornecedor>> carregar(
      String lojaId) async {
    try {
      final box = await _box(lojaId);
      final raw = box.get(_kJson);
      List<LinhaControleCompraFornecedor> local = [];
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        local = list
            .map((e) => LinhaControleCompraFornecedor.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      final remotoMaps =
          await ControleComprasFornecedorFirestoreService.listarMaps(lojaId);
      final remoto = remotoMaps
          .map((m) => LinhaControleCompraFornecedor.fromJson(m))
          .toList();
      if (remoto.isEmpty) {
        if (local.isNotEmpty) {
          try {
            final cfg = Hive.isBoxOpen('config')
                ? Hive.box('config')
                : await Hive.openBox('config');
            final flagKey =
                'controle_compra_migr_fs_${lojaId.trim()}';
            if (cfg.get(flagKey) != true) {
              for (final l in local) {
                await ControleComprasFornecedorFirestoreService.upsertMap(
                  lojaId,
                  l.id,
                  l.toJson(),
                );
              }
              await cfg.put(flagKey, true);
            }
          } catch (_) {}
        }
        local.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
        return local;
      }

      final byId = <String, LinhaControleCompraFornecedor>{};
      for (final l in local) {
        byId[l.id] = l;
      }
      for (final r in remoto) {
        byId[r.id] = r;
      }
      final merged = byId.values.toList()
        ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      await salvarTodas(lojaId, merged);
      return merged;
    } catch (e) {
      debugPrint('[CONTROLE_COMPRAS_FORN] carregar (type=${e.runtimeType})');
      return [];
    }
  }

  static Future<void> salvarTodas(
    String lojaId,
    List<LinhaControleCompraFornecedor> linhas,
  ) async {
    final box = await _box(lojaId);
    final json = jsonEncode(linhas.map((e) => e.toJson()).toList());
    await box.put(_kJson, json);
  }

  /// Total por nome de fornecedor (case-insensitive trim).
  static Map<String, double> totaisPorFornecedor(
    List<LinhaControleCompraFornecedor> linhas,
  ) {
    final map = <String, double>{};
    for (final l in linhas) {
      final key = l.fornecedorNome.trim().isEmpty
          ? '(sem nome)'
          : l.fornecedorNome.trim();
      map[key] = (map[key] ?? 0) + l.total;
    }
    return map;
  }

  static Future<void> adicionar({
    required String lojaId,
    required String fornecedorNome,
    required double valor,
    required double frete,
    required double desconto,
    required DateTime dataCompra,
  }) async {
    final total = valor + frete - desconto;
    final dc = DateTime(dataCompra.year, dataCompra.month, dataCompra.day);
    final linhas = await carregar(lojaId);
    linhas.insert(
      0,
      LinhaControleCompraFornecedor(
        id: const Uuid().v4(),
        fornecedorNome: fornecedorNome.trim(),
        valor: valor,
        frete: frete,
        desconto: desconto,
        total: total,
        dataCompra: dc,
        criadoEm: DateTime.now(),
      ),
    );
    await salvarTodas(lojaId, linhas);
    final nova = linhas.first;
    await ControleComprasFornecedorFirestoreService.upsertMap(
      lojaId,
      nova.id,
      nova.toJson(),
    );
  }

  /// Remove só do Hive (uso interno: soft delete já apagou a nuvem).
  static Future<void> removerApenasHive(String lojaId, String id) async {
    final linhas = await _carregarSomenteHive(lojaId);
    linhas.removeWhere((e) => e.id == id);
    await salvarTodas(lojaId, linhas);
  }

  static Future<List<LinhaControleCompraFornecedor>> _carregarSomenteHive(
      String lojaId) async {
    try {
      final box = await _box(lojaId);
      final raw = box.get(_kJson);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => LinhaControleCompraFornecedor.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('[CONTROLE_COMPRAS_FORN] _carregarSomenteHive (type=${e.runtimeType})');
      return [];
    }
  }

  /// Restaura uma linha após desfazer exclusão (Hive + nuvem).
  static Future<void> reinserirLinha(
    String lojaId,
    LinhaControleCompraFornecedor linha,
  ) async {
    final linhas = await _carregarSomenteHive(lojaId);
    if (linhas.any((e) => e.id == linha.id)) {
      await ControleComprasFornecedorFirestoreService.upsertMap(
        lojaId,
        linha.id,
        linha.toJson(),
      );
      return;
    }
    linhas.insert(0, linha);
    await salvarTodas(lojaId, linhas);
    await ControleComprasFornecedorFirestoreService.upsertMap(
      lojaId,
      linha.id,
      linha.toJson(),
    );
  }

  static Future<void> remover(String lojaId, String id) async {
    await removerApenasHive(lojaId, id);
    await ControleComprasFornecedorFirestoreService.deleteLinha(lojaId, id);
  }
}
