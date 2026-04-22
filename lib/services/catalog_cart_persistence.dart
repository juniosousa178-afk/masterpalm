// lib/services/catalog_cart_persistence.dart
// Carrinho do catálogo público (visitante: SharedPreferences; logado: Firestore via ClienteAuth).

import 'package:shared_preferences/shared_preferences.dart';

import 'cliente_auth_service.dart';

class CatalogCartPersistence {
  CatalogCartPersistence._();

  static Future<void> clearLocalGuestCart(String lojaId) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('catalog_cart_items_$lid');
    } catch (_) {}
  }

  /// Após pagamento aprovado no MP (catálogo): zera carrinho local e o persistido do cliente logado.
  static Future<void> clearAfterSuccessfulCatalogPayment(String lojaId) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) return;
    await clearLocalGuestCart(lid);
    try {
      final cliente = await ClienteAuthService.getClienteLogado();
      final cid = cliente?['clienteId']?.toString().trim();
      if (cid != null && cid.isNotEmpty) {
        await ClienteAuthService.saveCarrinho(
          lojaId: lid,
          clienteId: cid,
          items: const [],
        );
      }
    } catch (_) {}
  }
}
