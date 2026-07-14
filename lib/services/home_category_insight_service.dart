// M3.8 S2-R4 — insights leves por categoria (badges opcionais).

import 'carrinho_abandonado_settings_service.dart';
import 'carrinho_abandonado_service.dart';

class HomeCategoryInsight {
  const HomeCategoryInsight({required this.label, required this.count});
  final String label;
  final int count;
}

/// Badges contextuais. Sem dado → lista vazia (não exibir).
abstract final class HomeCategoryInsightService {
  /// Desliga loads Firestore/Hive pesados (testes de UI).
  static bool enableRemoteLoads = true;

  static Future<Map<String, List<HomeCategoryInsight>>> load(String lojaId) async {
    final out = <String, List<HomeCategoryInsight>>{
      'vendas': [],
      'marketing': [],
      'clientes': [],
      'financeiro': [],
      'operacoes': [],
      'configuracoes': [],
    };
    if (!enableRemoteLoads || lojaId.trim().isEmpty) return out;

    try {
      final minutos =
          await CarrinhoAbandonadoSettingsService.resolveMinutos(lojaId);
      final carts =
          await CarrinhoAbandonadoService.listarCarrinhosAbandonadosCatalogo(
        lojaId: lojaId,
        minutosAbandono: minutos,
      );
      final abandonados = carts
          .where((c) => c.status.toLowerCase().contains('abandon'))
          .length;
      if (abandonados > 0) {
        out['vendas']!.add(HomeCategoryInsight(
          label: abandonados == 1
              ? '1 carrinho'
              : '$abandonados carrinhos',
          count: abandonados,
        ));
      }
    } catch (_) {}

    return out;
  }
}
