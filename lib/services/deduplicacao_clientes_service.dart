// lib/services/deduplicacao_clientes_service.dart
// Remove clientes duplicados (mesmo nome na mesma loja) mantendo o mais completo

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/cliente.dart';
import '../models/venda.dart';
import '../utils/text_utils.dart';

class DeduplicacaoClientesService {
  /// Remove clientes duplicados: mantém 1 por nome (normalizado) e migra histórico
  static Future<int> deduplicar(Box<Cliente> clientesBox, Box<Venda> vendasBox, String lojaId) async {
    int removidos = 0;
    try {
      final clientes = clientesBox.values.where((c) => c.lojaId == lojaId).toList();
      final porNome = <String, List<Cliente>>{};
      for (final c in clientes) {
        final key = normalizeText(c.nome);
        porNome.putIfAbsent(key, () => []).add(c);
      }
      for (final entry in porNome.entries) {
        final lista = entry.value;
        if (lista.length <= 1) continue;
        lista.sort((a, b) {
          final scoreA = _completude(a);
          final scoreB = _completude(b);
          final histA = a.historico?.length ?? 0;
          final histB = b.historico?.length ?? 0;
          if (histA != histB) return histB.compareTo(histA);
          return scoreB.compareTo(scoreA);
        });
        final manter = lista.first;
        // ignore: experimental_member_use
        manter.historico ??= HiveList(vendasBox);
        for (var i = 1; i < lista.length; i++) {
          final duplicado = lista[i];
          if (duplicado.historico != null) {
            for (final v in duplicado.historico!) {
              if (!manter.historico!.any((x) => x.key == v.key)) {
                manter.historico!.add(v);
              }
              v.clienteId = manter.key?.toString() ?? manter.idFirebase;
              await v.save();
            }
          }
          await clientesBox.delete(duplicado.key);
          removidos++;
        }
        await manter.save();
      }
      if (removidos > 0) {
        debugPrint('✅ [DEDUP] $removidos clientes duplicados removidos');
      }
    } catch (e) {
      debugPrint('❌ [DEDUP] Erro (type=${e.runtimeType})');
    }
    return removidos;
  }

  static int _completude(Cliente c) {
    int s = 0;
    if (c.telefone.trim().isNotEmpty) s += 2;
    if ((c.email ?? '').isNotEmpty) s += 1;
    if (c.instagram.trim().isNotEmpty) s += 1;
    if (c.cep.trim().isNotEmpty) s += 1;
    return s;
  }
}
