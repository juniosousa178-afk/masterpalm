// M3.8 S2-R3 — fonte única do tempo de abandono de carrinho.

import 'package:flutter/foundation.dart';

import 'carrinho_abandonado_service.dart';
import '../core/carrinho_abandonado_ui.dart';

/// Limites e presets da configuração de tempo.
abstract final class CarrinhoAbandonadoTimeLimits {
  static const int minMinutes = 15;
  static const int maxMinutes = 30 * 24 * 60; // 30 dias
  /// Fallback legado comprovado em [CarrinhoAbandonadoConfig] (24h).
  static const int defaultMinutes = 24 * 60;
  static const List<int> presetMinutes = [
    30,
    60,
    2 * 60,
    6 * 60,
    12 * 60,
    24 * 60,
    48 * 60,
    72 * 60,
  ];
}

/// Serviço único: lê/grava config, Duration canônica, validação e classificação.
class CarrinhoAbandonadoSettingsService {
  CarrinhoAbandonadoSettingsService._();

  static final ValueNotifier<Duration?> lastKnownDuration =
      ValueNotifier<Duration?>(null);

  static Duration get fallbackDuration =>
      const Duration(minutes: CarrinhoAbandonadoTimeLimits.defaultMinutes);

  static Duration durationFromConfig(CarrinhoAbandonadoConfig config) =>
      Duration(minutes: config.minutosAbandono);

  static Future<CarrinhoAbandonadoConfig> load(String lojaId) async {
    final cfg = await CarrinhoAbandonadoService.getConfig(lojaId);
    lastKnownDuration.value = durationFromConfig(cfg);
    return cfg;
  }

  static Future<Duration> resolveDuration(String lojaId) async {
    try {
      final cfg = await load(lojaId);
      return durationFromConfig(cfg);
    } catch (_) {
      return fallbackDuration;
    }
  }

  static Future<int> resolveMinutos(String lojaId) async =>
      (await resolveDuration(lojaId)).inMinutes;

  /// Valida minutos; retorna null se inválido.
  static String? validateMinutes(int minutes) {
    if (minutes < CarrinhoAbandonadoTimeLimits.minMinutes) {
      return 'Mínimo: ${CarrinhoAbandonadoTimeLimits.minMinutes} minutos';
    }
    if (minutes > CarrinhoAbandonadoTimeLimits.maxMinutes) {
      return 'Máximo: 30 dias';
    }
    return null;
  }

  static Future<void> save({
    required String lojaId,
    required int minutosAbandono,
    bool? ativo,
    bool? enviarEmail,
    String? atualizadoPor,
  }) async {
    final err = validateMinutes(minutosAbandono);
    if (err != null) {
      throw ArgumentError(err);
    }
    final current = await CarrinhoAbandonadoService.getConfig(lojaId);
    final next = CarrinhoAbandonadoConfig(
      ativo: ativo ?? current.ativo,
      minutosAbandono: minutosAbandono,
      enviarEmail: enviarEmail ?? current.enviarEmail,
      atualizadoEm: DateTime.now(),
      atualizadoPor: atualizadoPor ?? current.atualizadoPor,
    );
    await CarrinhoAbandonadoService.setConfig(lojaId, next);
    lastKnownDuration.value = durationFromConfig(next);
  }

  static Future<void> restoreDefault(String lojaId) async {
    await save(
      lojaId: lojaId,
      minutosAbandono: CarrinhoAbandonadoTimeLimits.defaultMinutes,
    );
  }

  /// Classificação dinâmica por tempo. Status explícitos prevalecem.
  static bool classificaComoAbandonadoPorTempo({
    required DateTime? ultimaAtualizacao,
    required Duration threshold,
    required String statusRaw,
    DateTime? now,
  }) {
    final status = normalizarStatusCarrinhoAbandonado(statusRaw);
    if (status == kCarrinhoUiRecuperado ||
        status == kCarrinhoUiVirouPedido ||
        status == kCarrinhoUiVirouVenda) {
      return false;
    }
    if (ultimaAtualizacao == null) return false;
    final ref = now ?? DateTime.now();
    return !ultimaAtualizacao.isAfter(ref.subtract(threshold));
  }

  static String exemploTexto(Duration d) {
    final label = formatarDuracaoAbandono(d);
    return 'Carrinhos sem atualização por mais de $label serão classificados como abandonados.';
  }

  static String formatarDuracaoAbandono(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} minutos';
    if (d.inMinutes % (24 * 60) == 0) {
      final days = d.inDays;
      return days == 1 ? '1 dia' : '$days dias';
    }
    if (d.inMinutes % 60 == 0) {
      final h = d.inHours;
      return h == 1 ? '1 hora' : '$h horas';
    }
    return '${d.inHours}h ${d.inMinutes % 60}min';
  }
}
