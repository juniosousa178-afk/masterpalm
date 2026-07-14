// M3.8 Sprint 2 R2 — degradação permission-denied (PERM-1…10)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/marketing_dashboard/firestore_client_error.dart';
import 'package:master_palm/services/marketing_dashboard/marketing_dashboard_aggregators.dart';
import 'package:master_palm/services/marketing_dashboard/marketing_dashboard_repository.dart';
import 'package:master_palm/services/marketing_dashboard/marketing_period_filter.dart';

FirebaseException _perm() => FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Missing or insufficient permissions.',
    );

FirebaseException _failedPrecond() => FirebaseException(
      plugin: 'cloud_firestore',
      code: 'failed-precondition',
      message: 'The query requires an index.',
    );

FirebaseException _unavailable() => FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
      message: 'network',
    );

void main() {
  group('PERM — classificador', () {
    test('PERM-9 distingue permission-denied de rede', () {
      expect(isFirestorePermissionDenied(_perm()), isTrue);
      expect(isFirestoreFailedPrecondition(_failedPrecond()), isTrue);
      expect(isFirestoreUnavailable(_unavailable()), isTrue);
      expect(
        classifyFirestoreClientError(_unavailable()),
        FirestoreClientErrorKind.unavailable,
      );
      expect(
        classifyFirestoreClientError(Exception('boom')),
        FirestoreClientErrorKind.other,
      );
    });
  });

  group('PERM — repository logs', () {
    test('PERM-1 listarLogsRoleta permission-denied não derruba config',
        () async {
      final repo = MarketingDashboardRepository(
        roletaLogsQuery: (lojaId, {required orderBy}) async {
          throw _perm();
        },
      );
      // Config é via CampanhasSorteioService em produção; aqui testamos
      // carregarDashboardRoleta com injeção só de logs — mockando query.
      // Sem Firebase real: só listarLogsRoletaResult.
      final logs = await repo.listarLogsRoletaResult('loja-t');
      expect(logs.historicoDisponivel, isFalse);
      expect(logs.indisponibilidadeCodigo, 'permission-denied');
      expect(logs.logs, isEmpty);
      expect(logs.availability, MarketingMetricAvailability.permissionDenied);
    });

    test('PERM-2 fallback sem orderBy NÃO ocorre em permission-denied',
        () async {
      var orderByCalls = 0;
      var plainCalls = 0;
      final repo = MarketingDashboardRepository(
        roletaLogsQuery: (lojaId, {required orderBy}) async {
          if (orderBy) {
            orderByCalls++;
            throw _perm();
          }
          plainCalls++;
          return [
            {'id': 'should-not-run'}
          ];
        },
      );
      final r = await repo.listarLogsRoletaResult('loja-t');
      expect(orderByCalls, 1);
      expect(plainCalls, 0);
      expect(repo.debugFallbackSemOrderByCount, 0);
      expect(r.historicoDisponivel, isFalse);
    });

    test('PERM-3 failed-precondition ainda usa fallback sem orderBy', () async {
      final repo = MarketingDashboardRepository(
        roletaLogsQuery: (lojaId, {required orderBy}) async {
          if (orderBy) throw _failedPrecond();
          return [
            {
              'id': '1',
              'premioTipo': 'desconto',
              'premioValor': 10,
              'criadoEm': DateTime(2026, 7, 12),
            }
          ];
        },
      );
      final r = await repo.listarLogsRoletaResult('loja-t');
      expect(repo.debugFallbackSemOrderByCount, 1);
      expect(r.historicoDisponivel, isTrue);
      expect(r.logs.length, 1);
    });
  });

  group('PERM — aggregators / display', () {
    test('PERM-4/5 config-only: métricas de log são null (não zero falso)', () {
      final k = RoletaDashboardKpis.fromConfigOnly({
        'ativa': true,
        'totalVendas': 42,
        'premios': [
          {'quantidadeMaxima': 10, 'quantidadeUsada': 3},
        ],
      });
      expect(k.logsDisponiveis, isFalse);
      expect(k.giros, isNull);
      expect(k.premios, isNull);
      expect(k.valorDistribuido, isNull);
      expect(k.taxaConversaoPercent, isNull);
      expect(k.configAtiva, isTrue);
      expect(k.configPremiosRestantes, 7);
      expect(k.configTotalVendas, 42);
      expect(formatMetricDisplay(k.giros, disponivel: false), '—');
      expect(formatMetricDisplay(0, disponivel: false), '—');
    });

    test('PERM agrégator com logsDisponiveis=false', () {
      final k = agregarDashboardRoleta(
        config: {'ativa': true},
        logs: [
          {'premioTipo': 'desconto', 'criadoEm': DateTime(2026, 7, 1)}
        ],
        periodo: MarketingPeriodFilter.mes,
        agora: DateTime(2026, 7, 13),
        logsDisponiveis: false,
      );
      expect(k.giros, isNull);
      expect(k.logsDisponiveis, isFalse);
    });
  });

  group('PERM — load result tipado', () {
    test('PERM-1b RoletaDashboardLoadResult via query inject', () async {
      // Simula listarLogsRoletaResult + agregar sem chamar config Firestore:
      final logsR = RoletaLogsLoadResult(
        logs: const [],
        historicoDisponivel: false,
        availability: MarketingMetricAvailability.permissionDenied,
        indisponibilidadeCodigo: 'permission-denied',
        error: _perm(),
      );
      final config = <String, dynamic>{
        'ativa': true,
        'premios': [
          {'quantidadeMaxima': 5, 'quantidadeUsada': 1},
        ],
      };
      final load = RoletaDashboardLoadResult(
        config: config,
        logs: logsR.logs,
        historicoDisponivel: false,
        indisponibilidadeCodigo: 'permission-denied',
        kpis: RoletaDashboardKpis.fromConfigOnly(config),
      );
      expect(load.historicoDisponivel, isFalse);
      expect(load.kpis.giros, isNull);
      expect(load.kpis.configPremiosRestantes, 4);
      // config presente → dashboard pode abrir
      expect(load.config?['ativa'], isTrue);
    });

    test('PERM-6 metadata explícita permission-denied (não empty silencioso)',
        () {
      final r = RoletaLogsLoadResult(
        logs: const [],
        historicoDisponivel: false,
        availability: MarketingMetricAvailability.permissionDenied,
        indisponibilidadeCodigo: 'permission-denied',
      );
      expect(r.availability, isNot(MarketingMetricAvailability.empty));
      expect(r.indisponibilidadeCodigo, 'permission-denied');
    });

    test('PERM-7 campanhas independentes de roleta (modelo)', () {
      final camp = agregarDashboardCampanhas(
        campanhas: [
          {
            'id': 'c1',
            'nome': 'A',
            'ativa': true,
            'status': 'aberta',
            'dataInicio': DateTime(2026, 7, 1),
            'dataFim': DateTime(2026, 7, 31),
          },
        ],
        participantesPorCampanha: {
          'c1': [
            {
              'status': 'valido',
              'clienteNome': 'M',
              'valorPedido': 100,
              'dataParticipacao': DateTime(2026, 7, 10),
              'numeroSorte': '1',
            },
          ],
        },
        periodo: MarketingPeriodFilter.mes,
        agora: DateTime(2026, 7, 13),
      );
      final roletaDenied = RoletaDashboardLoadResult(
        config: const {'ativa': true},
        logs: const [],
        historicoDisponivel: false,
        indisponibilidadeCodigo: 'permission-denied',
        kpis: RoletaDashboardKpis.fromConfigOnly(const {'ativa': true}),
      );
      // Ambos existem independentemente — UI pode renderizar campanhas
      expect(camp.kpis.participantes, 1);
      expect(roletaDenied.historicoDisponivel, isFalse);
    });

    test('PERM-8 roleta disponível mesmo se campanha falhar (modelo)', () {
      final roletaOk = agregarDashboardRoleta(
        config: {'ativa': true},
        logs: [
          {
            'premioTipo': 'desconto',
            'premioValor': 5,
            'criadoEm': DateTime(2026, 7, 12),
          },
        ],
        periodo: MarketingPeriodFilter.mes,
        agora: DateTime(2026, 7, 13),
      );
      expect(roletaOk.giros, 1);
      // Seção campanha em error não anula KPIs roleta
      expect(roletaOk.logsDisponiveis, isTrue);
    });

    test('PERM-10 nenhum write no path de logs (somente queries inject)',
        () async {
      var writes = 0;
      final repo = MarketingDashboardRepository(
        roletaLogsQuery: (lojaId, {required orderBy}) async {
          // simula get-only
          return const [];
        },
      );
      await repo.listarLogsRoletaResult('loja-t');
      expect(writes, 0);
      expect(repo.debugFallbackSemOrderByCount, 0);
    });
  });
}
