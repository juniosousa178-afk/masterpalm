// lib/services/cupom_service.dart

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/cupom_premio.dart';

/// Serviço para gerenciar cupons de prêmio da roleta
class CupomService {
  /// Busca cupom por código
  static Future<CupomPremio?> buscarCupom(String codigo, String lojaId) async {
    try {
      final box = await Hive.openBox<CupomPremio>('cupons_premio');

      for (var cupom in box.values) {
        if (cupom.codigo.toUpperCase() == codigo.toUpperCase() &&
            cupom.lojaId == lojaId) {
          return cupom;
        }
      }

      return null;
    } catch (e) {
      debugPrint('❌ Erro ao buscar cupom (type=${e.runtimeType})');
      return null;
    }
  }

  /// Valida cupom e retorna informações sobre desconto
  static Future<Map<String, dynamic>> validarCupom(
    String codigo,
    String lojaId,
    double valorCompra,
  ) async {
    final cupom = await buscarCupom(codigo, lojaId);

    if (cupom == null) {
      return {
        'valido': false,
        'mensagem': 'Cupom não encontrado',
      };
    }

    if (!cupom.isValido) {
      if (cupom.usado) {
        return {
          'valido': false,
          'mensagem': 'Cupom já foi utilizado em ${_formatarData(cupom.dataUso!)}',
        };
      } else if (cupom.expirou) {
        return {
          'valido': false,
          'mensagem': 'Cupom expirado em ${_formatarData(cupom.dataExpiracao)}',
        };
      }
    }

    final desconto = cupom.calcularDesconto(valorCompra);

    String mensagem;
    if (cupom.tipo == 'frete_gratis') {
      mensagem = '🎉 Frete grátis aplicado!';
    } else if (cupom.tipo == 'percentual') {
      mensagem = '🎉 Desconto de ${cupom.valorDesconto.toStringAsFixed(0)}% aplicado! (R\$ ${desconto.toStringAsFixed(2)})';
    } else {
      mensagem = '🎉 Desconto de R\$ ${desconto.toStringAsFixed(2)} aplicado!';
    }

    return {
      'valido': true,
      'cupom': cupom,
      'desconto': desconto,
      'mensagem': mensagem,
    };
  }

  /// Aplica cupom na venda (marca como usado)
  static Future<void> aplicarCupom(
    CupomPremio cupom,
    String vendaId,
  ) async {
    try {
      await cupom.marcarComoUsado(vendaId);
      debugPrint('✅ Cupom ${cupom.codigo} aplicado na venda $vendaId');
    } catch (e) {
      debugPrint('❌ Erro ao aplicar cupom (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Lista cupons válidos do cliente
  static Future<List<CupomPremio>> listarCuponsValidos({
    String? lojaId,
    String? clienteEmail,
  }) async {
    try {
      final box = await Hive.openBox<CupomPremio>('cupons_premio');

      return box.values.where((cupom) {
        if (!cupom.isValido) return false;
        if (lojaId != null && cupom.lojaId != lojaId) return false;
        if (clienteEmail != null && cupom.clienteEmail != clienteEmail) {
          return false;
        }
        return true;
      }).toList();
    } catch (e) {
      debugPrint('❌ Erro ao listar cupons (type=${e.runtimeType})');
      return [];
    }
  }

  /// Lista todos os cupons (válidos e inválidos)
  static Future<List<CupomPremio>> listarTodosCupons({
    String? lojaId,
    String? clienteEmail,
  }) async {
    try {
      final box = await Hive.openBox<CupomPremio>('cupons_premio');

      return box.values.where((cupom) {
        if (lojaId != null && cupom.lojaId != lojaId) return false;
        if (clienteEmail != null && cupom.clienteEmail != clienteEmail) {
          return false;
        }
        return true;
      }).toList();
    } catch (e) {
      debugPrint('❌ Erro ao listar cupons (type=${e.runtimeType})');
      return [];
    }
  }

  /// Conta cupons por status
  static Future<Map<String, int>> contarCuponsPorStatus(String lojaId) async {
    try {
      final box = await Hive.openBox<CupomPremio>('cupons_premio');

      int validos = 0;
      int usados = 0;
      int expirados = 0;

      for (var cupom in box.values) {
        if (cupom.lojaId != lojaId) continue;

        if (cupom.usado) {
          usados++;
        } else if (cupom.expirou) {
          expirados++;
        } else if (cupom.isValido) {
          validos++;
        }
      }

      return {
        'validos': validos,
        'usados': usados,
        'expirados': expirados,
        'total': validos + usados + expirados,
      };
    } catch (e) {
      debugPrint('❌ Erro ao contar cupons (type=${e.runtimeType})');
      return {
        'validos': 0,
        'usados': 0,
        'expirados': 0,
        'total': 0,
      };
    }
  }

  /// Deleta cupons expirados
  static Future<int> limparCuponsExpirados(String lojaId) async {
    try {
      final box = await Hive.openBox<CupomPremio>('cupons_premio');
      int deletados = 0;

      final cuponsParaDeletar = <dynamic>[];

      for (var entry in box.toMap().entries) {
        final cupom = entry.value;
        if (cupom.lojaId == lojaId && cupom.expirou) {
          cuponsParaDeletar.add(entry.key);
        }
      }

      for (var key in cuponsParaDeletar) {
        await box.delete(key);
        deletados++;
      }

      debugPrint('🗑️ $deletados cupons expirados deletados');
      return deletados;
    } catch (e) {
      debugPrint('❌ Erro ao limpar cupons expirados (type=${e.runtimeType})');
      return 0;
    }
  }

  // Helper para formatar data
  static String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
  }
}
