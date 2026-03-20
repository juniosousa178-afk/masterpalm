// lib/core/loja_id_adapter.dart
// Camada de compatibilidade para lojaId/store_id/storeId.
// ETAPA 2 - Padronização segura: leitura tolerante, escrita canônica.
//
// PADRÃO CANÔNICO:
// - No código Dart: usar variável [lojaId]
// - No Firestore (users, usuarios): campo [store_id]
// - No Hive (sessao, config): chave [store_id]
//
// Este adapter permite ler documentos/boxes legados que usam lojaId, store_id ou storeId.

import 'package:hive/hive.dart';

/// Chaves possíveis em documentos Firestore ou boxes Hive (ordem de prioridade).
/// ownerStoreId: usado em usuarios/{email} (cadastro/vendedores).
const List<String> _lojaIdKeys = ['store_id', 'lojaId', 'storeId', 'ownerStoreId'];

/// Extrai lojaId de um Map (Firestore doc, JSON) com fallback para campos legados.
/// Retorna o primeiro valor não vazio encontrado em [lojaId], [store_id], [storeId], [ownerStoreId].
String? normalizeFromMap(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return null;
  for (final k in _lojaIdKeys) {
    final v = data[k];
    if (v != null) {
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
  }
  return null;
}

/// Lê lojaId de uma Box Hive com fallback para chaves legadas.
/// Ordem: store_id, lojaId, storeId.
String? normalizeFromBox(Box box, {List<String>? keys}) {
  final k = keys ?? ['store_id', 'lojaId', 'storeId'];
  for (final key in k) {
    final v = box.get(key);
    if (v != null) {
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
  }
  return null;
}

/// Chave canônica para escrita no Hive (sessao, config).
const String kCanonicalHiveKey = 'store_id';
