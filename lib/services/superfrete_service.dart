// lib/services/superfrete_service.dart
// Fachada SuperFrete — delega somente a Cloud Functions (sem HTTP direto à API).

import 'superfrete_integration_service.dart';

class SuperFreteService {
  SuperFreteService._();

  static Future<Map<String, dynamic>> calcularFrete({
    required String lojaId,
    required String cepOrigem,
    required String cepDestino,
    required double peso,
    required double altura,
    required double largura,
    required double comprimento,
    required double valorDeclarado,
    bool useSandbox = false,
  }) {
    return SuperFreteIntegrationService.quote(
      lojaId: lojaId,
      destinationCep: cepDestino,
      pesoGrams: peso < 300 ? 300.0 : peso,
      altura: altura < 1 ? 2 : altura,
      largura: largura < 1 ? 11 : largura,
      comprimento: comprimento < 1 ? 16 : comprimento,
      valorDeclarado: valorDeclarado > 0 ? valorDeclarado : 10.0,
      cepOrigem: cepOrigem,
    );
  }

  static Future<Map<String, dynamic>> criarEnvioNoCarrinho({
    required String lojaId,
    required dynamic servicoId,
    required Map<String, dynamic> from,
    required Map<String, dynamic> to,
    required Map<String, dynamic> package,
    required double valorDeclarado,
    String? pedidoRef,
    bool useSandbox = false,
  }) {
    return SuperFreteIntegrationService.createCheckout(
      lojaId: lojaId,
      servicoId: servicoId,
      from: from,
      to: to,
      package: package,
      valorDeclarado: valorDeclarado,
      pedidoRef: pedidoRef,
    );
  }

  @Deprecated('Use SuperFreteIntegrationService.testConnection')
  static Future<bool> validarToken(String token, {bool useSandbox = false}) async {
    return false;
  }
}
