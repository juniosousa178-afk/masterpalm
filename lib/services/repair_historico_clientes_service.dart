// lib/services/repair_historico_clientes_service.dart
//
// Desmistura histórico de clientes usando vendas como fonte de verdade.
// Remove vendas incorretas do historico e reatribui apenas as que pertencem
// ao cliente correto (venda.clienteId ou clienteNome).

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/cliente.dart';
import '../models/venda.dart';
import '../utils/text_utils.dart';

class RepairHistoricoClientesService {
  /// Resultado do reparo.
  static const String keyVendasAtribuidas = 'vendasAtribuidas';
  static const String keyClientesLimpados = 'clientesLimpados';
  static const String keyVendasSemCliente = 'vendasSemCliente';
  static const String keyVendasAmbiguas = 'vendasAmbiguas';

  /// Desmistura o histórico de clientes usando vendasBox como fonte de verdade.
  /// Retorna um mapa com contadores: vendasAtribuidas, clientesLimpados, etc.
  static Future<Map<String, int>> reparar({
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String lojaId,
  }) async {
    final result = <String, int>{
      keyVendasAtribuidas: 0,
      keyClientesLimpados: 0,
      keyVendasSemCliente: 0,
      keyVendasAmbiguas: 0,
    };

    try {
      debugPrint('🔧 [REPAIR] Desmisturando histórico (loja: $lojaId)');

      // 1. Limpar todo o historico
      for (final cliente in clientesBox.values) {
        if (!_lojaMatch(cliente.lojaId, lojaId)) continue;
        if (cliente.historico != null && cliente.historico!.isNotEmpty) {
          cliente.historico!.clear();
          await cliente.save();
          result[keyClientesLimpados] = (result[keyClientesLimpados] ?? 0) + 1;
        }
      }

      // Map nome normalizado -> clientes (O(C)) para match por nome
      final nomeToClientes = <String, List<Cliente>>{};
      for (final c in clientesBox.values) {
        if (!_lojaMatch(c.lojaId, lojaId)) continue;
        final norm = normalizeText(c.nome);
        nomeToClientes.putIfAbsent(norm, () => []).add(c);
      }

      // 2. Reconstruir a partir de vendasBox
      for (final venda in vendasBox.values) {
        if (venda.lojaId != null &&
            venda.lojaId!.isNotEmpty &&
            venda.lojaId != lojaId) {
          continue;
        }
        if (venda.clienteNome.trim().isEmpty) {
          result[keyVendasSemCliente] = (result[keyVendasSemCliente] ?? 0) + 1;
          continue;
        }

        Cliente? cliente;
        // (E) Preferir match por clienteId
        if (venda.clienteId != null && venda.clienteId!.trim().isNotEmpty) {
          final list = clientesBox.values
              .where((c) =>
                  _lojaMatch(c.lojaId, lojaId) &&
                  (c.key?.toString() == venda.clienteId ||
                      c.idFirebase == venda.clienteId))
              .toList();
          if (list.length == 1) cliente = list.first;
        }
        // Senão: match por nome normalizado
        if (cliente == null) {
          final nomeNorm = normalizeText(venda.clienteNome);
          final candidatos = nomeToClientes[nomeNorm] ?? [];
          if (candidatos.length == 1) {
            cliente = candidatos.first;
          } else if (candidatos.length > 1) {
            result[keyVendasAmbiguas] = (result[keyVendasAmbiguas] ?? 0) + 1;
            continue;
          }
        }

        if (cliente == null) {
          result[keyVendasSemCliente] = (result[keyVendasSemCliente] ?? 0) + 1;
          continue;
        }

        // ignore: experimental_member_use
        cliente.historico ??= HiveList(vendasBox);
        if (!cliente.historico!.any((v) => v.key == venda.key)) {
          cliente.historico!.add(venda);
          await cliente.save();
          result[keyVendasAtribuidas] = (result[keyVendasAtribuidas] ?? 0) + 1;
        }

        if (venda.clienteId == null || venda.clienteId!.isEmpty) {
          venda.clienteId = cliente.key?.toString() ?? cliente.idFirebase;
          await venda.save();
        }
      }

      // (D) Ordenar histórico por data (mais recente primeiro)
      for (final c in clientesBox.values) {
        if (!_lojaMatch(c.lojaId, lojaId)) continue;
        if (c.historico != null && c.historico!.length > 1) {
          c.historico!.sort((a, b) => b.data.compareTo(a.data));
          await c.save();
        }
      }

      debugPrint('✅ [REPAIR] Concluído: ${result[keyVendasAtribuidas]} vendas atribuídas');
    } catch (e) {
      debugPrint('❌ [REPAIR] Erro (type=${e.runtimeType})');
      rethrow;
    }

    return result;
  }

  /// Legado: cliente sem lojaId (cLoja vazio) é tratado como pertencente ao contexto atual (box já é por loja).
  static bool _lojaMatch(String? cLoja, String lojaId) {
    if (cLoja == null || cLoja.isEmpty) return true;
    return cLoja == lojaId;
  }
}
