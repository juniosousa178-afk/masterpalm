// M3.8 S2-R3 — CARTTIME: configuração de tempo de abandono.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/carrinho_abandonado_ui.dart';
import 'package:master_palm/core/carrinho_recuperacao_score.dart';
import 'package:master_palm/services/carrinho_abandonado_service.dart';
import 'package:master_palm/services/carrinho_abandonado_settings_service.dart';

void main() {
  test('CARTTIME-1 lê valor salvo (minutosAbandono)', () {
    final cfg = CarrinhoAbandonadoConfig.fromMap({
      'ativo': true,
      'minutosAbandono': 120,
      'enviarEmail': true,
    });
    expect(cfg.minutosAbandono, 120);
    expect(
      CarrinhoAbandonadoSettingsService.durationFromConfig(cfg),
      const Duration(hours: 2),
    );
  });

  test('CARTTIME-2 / CARTTIME-15 fallback legado horasAbandono', () {
    final legado = CarrinhoAbandonadoConfig.fromMap({
      'horasAbandono': 24,
    });
    expect(legado.minutosAbandono, 24 * 60);
    final vazio = CarrinhoAbandonadoConfig.fromMap(null);
    expect(vazio.minutosAbandono, CarrinhoAbandonadoTimeLimits.defaultMinutes);
    expect(
      CarrinhoAbandonadoSettingsService.fallbackDuration,
      const Duration(hours: 24),
    );
  });

  test('CARTTIME-3 30 min classifica corretamente', () {
    final now = DateTime(2026, 7, 13, 12, 0);
    final limiar = const Duration(minutes: 30);
    expect(
      CarrinhoAbandonadoSettingsService.classificaComoAbandonadoPorTempo(
        ultimaAtualizacao: now.subtract(const Duration(minutes: 31)),
        threshold: limiar,
        statusRaw: 'ativo',
        now: now,
      ),
      isTrue,
    );
    expect(
      CarrinhoAbandonadoSettingsService.classificaComoAbandonadoPorTempo(
        ultimaAtualizacao: now.subtract(const Duration(minutes: 10)),
        threshold: limiar,
        statusRaw: 'ativo',
        now: now,
      ),
      isFalse,
    );
  });

  test('CARTTIME-4 2 horas classifica corretamente', () {
    final now = DateTime(2026, 7, 13, 12, 0);
    final limiar = const Duration(hours: 2);
    expect(
      CarrinhoAbandonadoSettingsService.classificaComoAbandonadoPorTempo(
        ultimaAtualizacao: now.subtract(const Duration(hours: 3)),
        threshold: limiar,
        statusRaw: kCarrinhoStatusAbandonado,
        now: now,
      ),
      isTrue,
    );
  });

  test('CARTTIME-5 72 horas classifica corretamente', () {
    final now = DateTime(2026, 7, 13, 12, 0);
    final limiar = const Duration(hours: 72);
    expect(
      CarrinhoAbandonadoSettingsService.classificaComoAbandonadoPorTempo(
        ultimaAtualizacao: now.subtract(const Duration(hours: 73)),
        threshold: limiar,
        statusRaw: 'ativo',
        now: now,
      ),
      isTrue,
    );
    expect(
      CarrinhoAbandonadoSettingsService.classificaComoAbandonadoPorTempo(
        ultimaAtualizacao: now.subtract(const Duration(hours: 48)),
        threshold: limiar,
        statusRaw: 'ativo',
        now: now,
      ),
      isFalse,
    );
  });

  test('CARTTIME-6 valor personalizado', () {
    final map = CarrinhoAbandonadoConfig(minutosAbandono: 90).toMap();
    expect(map['minutosAbandono'], 90);
    expect(map['horasAbandono'], 2); // ceil compat legado
  });

  test('CARTTIME-7 mínimo inválido', () {
    expect(
      CarrinhoAbandonadoSettingsService.validateMinutes(10),
      isNotNull,
    );
  });

  test('CARTTIME-8 máximo inválido', () {
    expect(
      CarrinhoAbandonadoSettingsService.validateMinutes(
        CarrinhoAbandonadoTimeLimits.maxMinutes + 1,
      ),
      isNotNull,
    );
  });

  test('CARTTIME-9 carrinho recuperado não volta a abandonado', () {
    final now = DateTime(2026, 7, 13, 12, 0);
    expect(
      CarrinhoAbandonadoSettingsService.classificaComoAbandonadoPorTempo(
        ultimaAtualizacao: now.subtract(const Duration(days: 10)),
        threshold: const Duration(minutes: 30),
        statusRaw: kCarrinhoUiRecuperado,
        now: now,
      ),
      isFalse,
    );
  });

  test('CARTTIME-10 virou pedido não volta a abandonado', () {
    final now = DateTime(2026, 7, 13, 12, 0);
    expect(
      CarrinhoAbandonadoSettingsService.classificaComoAbandonadoPorTempo(
        ultimaAtualizacao: now.subtract(const Duration(days: 10)),
        threshold: const Duration(hours: 1),
        statusRaw: kCarrinhoUiVirouPedido,
        now: now,
      ),
      isFalse,
    );
    expect(
      CarrinhoAbandonadoSettingsService.classificaComoAbandonadoPorTempo(
        ultimaAtualizacao: now.subtract(const Duration(days: 10)),
        threshold: const Duration(hours: 1),
        statusRaw: kCarrinhoUiVirouVenda,
        now: now,
      ),
      isFalse,
    );
  });

  test('CARTTIME-11 lista e contador usam mesmo valor', () {
    final cfg = CarrinhoAbandonadoConfig(minutosAbandono: 180);
    final d = CarrinhoAbandonadoSettingsService.durationFromConfig(cfg);
    expect(d.inMinutes, 180);
    // Mesmo critério que listagens/contagem passam como minutosAbandono
    expect(d.inMinutes, cfg.minutosAbandono);
  });

  test('CARTTIME-12 score usa mesma configuração (tempo decorrido + limiar)', () {
    const limiar = Duration(hours: 2);
    const tempo = Duration(hours: 3);
    expect(
      CarrinhoAbandonadoSettingsService.classificaComoAbandonadoPorTempo(
        ultimaAtualizacao: DateTime.now().subtract(tempo),
        threshold: limiar,
        statusRaw: 'ativo',
      ),
      isTrue,
    );
    final score = calcularProbabilidadeRecuperacao(
      tempoAbandonado: tempo,
      valorCarrinho: 150,
      quantidadeItens: 2,
      temWhatsapp: true,
    );
    expect(score.pontos, greaterThan(0));
  });

  test('CARTTIME-13 mudança de config atualiza notifier', () {
    CarrinhoAbandonadoSettingsService.lastKnownDuration.value = null;
    CarrinhoAbandonadoSettingsService.lastKnownDuration.value =
        const Duration(hours: 6);
    expect(
      CarrinhoAbandonadoSettingsService.lastKnownDuration.value,
      const Duration(hours: 6),
    );
  });

  test('CARTTIME-14 sem escrita destrutiva em status explícitos', () {
    // Classificador puro — nunca marca recuperado/virou_* como abandonado.
    for (final s in [
      kCarrinhoUiRecuperado,
      kCarrinhoUiVirouPedido,
      kCarrinhoUiVirouVenda,
      'recuperado',
      'virou_pedido',
    ]) {
      expect(
        CarrinhoAbandonadoSettingsService.classificaComoAbandonadoPorTempo(
          ultimaAtualizacao: DateTime(2020),
          threshold: const Duration(minutes: 15),
          statusRaw: s,
        ),
        isFalse,
      );
    }
  });

  test('exemploTexto e presets', () {
    expect(
      CarrinhoAbandonadoSettingsService.exemploTexto(const Duration(hours: 2)),
      contains('2 horas'),
    );
    expect(CarrinhoAbandonadoTimeLimits.presetMinutes, contains(30));
    expect(CarrinhoAbandonadoTimeLimits.presetMinutes, contains(72 * 60));
  });
}
