// lib/services/shipping_provider_selection.dart
//
// Provedor de frete ativo da loja (`config/fretes.provider`).
// `configured` = credencial/integração existe no servidor;
// `enabled` = integração ativa para cotação pública (só o provedor selecionado).

class ShippingProviderSelection {
  ShippingProviderSelection._();

  static const String manual = 'manual';
  static const String melhorEnvio = 'melhor_envio';
  static const String superFrete = 'superfrete';
  static const String frenet = 'frenet';
  static const String correios = 'correios';

  static const Set<String> supported = {
    manual,
    melhorEnvio,
    superFrete,
    frenet,
    correios,
  };

  static String? _normalize(Object? raw) {
    final v = (raw ?? '').toString().trim().toLowerCase();
    return supported.contains(v) ? v : null;
  }

  static bool _integrationConfigured(Map<String, dynamic> config, String key) {
    final integrations = config['integrations'];
    if (integrations is! Map) return false;
    final m = integrations[key];
    return m is Map && m['configured'] == true && m['enabled'] != false;
  }

  static bool isMelhorEnvioConfigured(Map<String, dynamic> config) =>
      _integrationConfigured(config, melhorEnvio);

  static bool isSuperFreteConfigured(Map<String, dynamic> config) =>
      _integrationConfigured(config, superFrete);

  /// Provedor que o catálogo deve cotar. Sem `provider` válido (doc antigo),
  /// só infere quando exatamente uma integração segura está ativa; nunca agrega.
  static String resolve(Map<String, dynamic> config) {
    final selected = _normalize(config['provider']);
    if (selected != null) return selected;
    final me = isMelhorEnvioConfigured(config);
    final sf = isSuperFreteConfigured(config);
    if (me && !sf) return melhorEnvio;
    if (sf && !me) return superFrete;
    return manual;
  }

  /// Mapa `integrations` gravado em `config/fretes` ao salvar/publicar.
  /// Preserva `configured` (credenciais ficam em `fretes_secrets`) e liga só o selecionado.
  static Map<String, dynamic> integrationsForSave({
    required String provider,
    required bool melhorEnvioConfigured,
    required bool melhorEnvioSandbox,
    required bool superFreteConfigured,
    required bool superFreteSandbox,
  }) {
    final selected = _normalize(provider) ?? manual;
    return {
      superFrete: {
        'configured': superFreteConfigured,
        'enabled': selected == superFrete,
        'sandbox': superFreteSandbox,
      },
      melhorEnvio: {
        'configured': melhorEnvioConfigured,
        'enabled': selected == melhorEnvio,
        'sandbox': melhorEnvioSandbox,
      },
    };
  }
}
