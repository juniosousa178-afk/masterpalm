// lib/services/reconciliacao_vendas_clientes_service.dart
//
// Reconcilia vendas com histórico de clientes.
// Garante que cada venda na vendasBox esteja no historico do cliente correto.
// NÃO cria novos clientes (evita duplicação) - apenas vincula a clientes existentes.

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../utils/text_utils.dart';

class ReconciliacaoVendasClientesService {
  /// Reconcilia vendas com histórico de clientes.
  /// Apenas vincula vendas a clientes EXISTENTES - nunca cria novos (evita duplicação).
  static Future<int> reconciliar({
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String lojaId,
  }) async {
    int vinculadas = 0;

    try {
      debugPrint('🔄 [RECONCILIACAO] Iniciando');

      for (final venda in vendasBox.values) {
        if (venda.lojaId != null &&
            venda.lojaId!.isNotEmpty &&
            venda.lojaId != lojaId) {
          continue;
        }

        final nomeCliente = venda.clienteNome.trim();
        if (nomeCliente.isEmpty) continue;

        final nomeNorm = normalizeText(nomeCliente);

        // 1) Preferir match por clienteId (vendas novas)
        Cliente? cliente = venda.clienteId != null && venda.clienteId!.isNotEmpty
            ? clientesBox.values.firstWhereOrNull(
                (c) =>
                    _lojaMatch(c.lojaId, lojaId) &&
                    (c.key?.toString() == venda.clienteId ||
                        c.idFirebase == venda.clienteId))
            : null;

        // 2) Match por nome exato (trim + lowercase)
        cliente ??= clientesBox.values.firstWhereOrNull(
            (c) =>
                _lojaMatch(c.lojaId, lojaId) &&
                c.nome.trim().toLowerCase() == nomeCliente.toLowerCase(),
          );

        // 3) Match por nome normalizado (remove acentos)
        cliente ??= clientesBox.values.firstWhereOrNull(
            (c) =>
                _lojaMatch(c.lojaId, lojaId) &&
                normalizeText(c.nome) == nomeNorm,
          );

        // 4) Múltiplos candidatos com mesmo nome: NÃO atribuir (evita mistura)
        if (cliente == null) {
          final candidatos = clientesBox.values
              .where((c) =>
                  _lojaMatch(c.lojaId, lojaId) &&
                  normalizeText(c.nome) == nomeNorm)
              .toList();
          if (candidatos.length == 1) {
            cliente = candidatos.first;
          } else if (candidatos.length > 1) {
            debugPrint(
                '⚠️ [RECONCILIACAO] Múltiplos clientes para "$nomeCliente" - venda não atribuída (evita erro)',
            );
            continue; // não atribuir quando ambíguo
          }
        }

        // NÃO criar novo cliente - apenas vincular se encontrou
        if (cliente == null) continue;

        // ignore: experimental_member_use
        cliente.historico ??= HiveList(vendasBox);
        final jaTem = cliente.historico!.any((v) => v.key == venda.key);
        if (!jaTem) {
          cliente.historico!.add(venda);
          await cliente.save();
          vinculadas++;
        }
        // Preencher clienteId em vendas antigas (compatibilidade)
        if (venda.clienteId == null || venda.clienteId!.isEmpty) {
          venda.clienteId = cliente.key?.toString() ?? cliente.idFirebase;
          await venda.save();
        }
      }

      debugPrint('✅ [RECONCILIACAO] $vinculadas vendas vinculadas ao histórico');
    } catch (e) {
      debugPrint('❌ [RECONCILIACAO] Erro (type=${e.runtimeType})');
    }

    return vinculadas;
  }

  /// Legado: cliente sem lojaId (cLoja vazio) é tratado como pertencente ao contexto atual (box já é por loja).
  static bool _lojaMatch(String? cLoja, String lojaId) {
    if (cLoja == null || cLoja.isEmpty) return true;
    return cLoja == lojaId;
  }
}
