// M3.8 Sprint 2 — testes unitários dos aggregators (somente leitura).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/marketing_dashboard/marketing_dashboard_aggregators.dart';
import 'package:master_palm/services/marketing_dashboard/marketing_period_filter.dart';

void main() {
  group('M3.8 S2 — período', () {
    test('resolve hoje / semana / mês / ano / todo', () {
      final agora = DateTime(2026, 7, 13, 18); // segunda
      final hoje = MarketingPeriodRange.resolve(
        MarketingPeriodFilter.hoje,
        agora: agora,
      );
      expect(hoje.inicio, DateTime(2026, 7, 13));
      expect(hoje.fimExclusivo, DateTime(2026, 7, 14));
      expect(hoje.contains(DateTime(2026, 7, 13, 10)), isTrue);
      expect(hoje.contains(DateTime(2026, 7, 12)), isFalse);

      final semana = MarketingPeriodRange.resolve(
        MarketingPeriodFilter.semana,
        agora: agora,
      );
      expect(semana.inicio, DateTime(2026, 7, 13)); // weekday=1

      final mes = MarketingPeriodRange.resolve(
        MarketingPeriodFilter.mes,
        agora: agora,
      );
      expect(mes.inicio, DateTime(2026, 7, 1));
      expect(mes.fimExclusivo, DateTime(2026, 8, 1));
    });
  });

  group('M3.8 S2 — campanha aggregators', () {
    test('ativa vs encerrada + KPIs combinados', () {
      final agora = DateTime(2026, 7, 13, 12);
      final campanhas = [
        {
          'id': 'c1',
          'nome': 'Campanha A',
          'ativa': true,
          'status': 'aberta',
          'dataInicio': DateTime(2026, 7, 1),
          'dataFim': DateTime(2026, 7, 31),
        },
        {
          'id': 'c2',
          'nome': 'Campanha B',
          'ativa': false,
          'status': 'sorteada',
          'dataInicio': DateTime(2026, 1, 1),
          'dataFim': DateTime(2026, 6, 1),
        },
      ];
      expect(campanhaEstaAtiva(campanhas[0], agora: agora), isTrue);
      expect(campanhaEstaEncerrada(campanhas[1], agora: agora), isTrue);

      final snap = agregarDashboardCampanhas(
        campanhas: campanhas,
        participantesPorCampanha: {
          'c1': [
            {
              'status': 'valido',
              'clienteNome': 'Maria',
              'clienteId': 'cli1',
              'numeroSorte': '10',
              'valorPedido': 200,
              'dataParticipacao': DateTime(2026, 7, 10),
            },
            {
              'status': 'cancelado',
              'clienteNome': 'X',
              'numeroSorte': '11',
              'valorPedido': 50,
              'dataParticipacao': DateTime(2026, 7, 10),
            },
          ],
          'c2': [
            {
              'status': 'valido',
              'clienteNome': 'João',
              'clienteId': 'cli2',
              'numeros': [1, 2, 3],
              'valorCompra': 100,
              'dataParticipacao': DateTime(2026, 5, 1),
            },
          ],
        },
        periodo: MarketingPeriodFilter.mes,
        agora: agora,
      );

      expect(snap.kpis.ativas, 1);
      expect(snap.kpis.encerradas, 1);
      expect(snap.kpis.participantes, 1); // só Maria no mês
      expect(snap.kpis.numerosGerados, 1);
      expect(snap.kpis.receitaGerada, 200);
      expect(snap.kpis.ticketMedio, 200);
      expect(snap.kpis.clientesUnicos, 1);
      expect(snap.topCampanhas.first.nome, 'Campanha A');
    });

    test('todo período inclui campanha encerrada', () {
      final agora = DateTime(2026, 7, 13);
      final snap = agregarDashboardCampanhas(
        campanhas: [
          {
            'id': 'c2',
            'nome': 'B',
            'status': 'finalizada',
            'ativa': false,
          },
        ],
        participantesPorCampanha: {
          'c2': [
            {
              'status': 'valido',
              'clienteNome': 'João',
              'numeros': [1, 2],
              'valorPedido': 80,
              'dataParticipacao': DateTime(2026, 1, 2),
            },
          ],
        },
        periodo: MarketingPeriodFilter.todo,
        agora: agora,
      );
      expect(snap.kpis.participantes, 1);
      expect(snap.kpis.numerosGerados, 2);
      expect(snap.kpis.receitaGerada, 80);
    });
  });

  group('M3.8 S2 — roleta aggregators', () {
    test('giros, prêmios e busca histórico', () {
      final agora = DateTime(2026, 7, 13);
      final k = agregarDashboardRoleta(
        config: {
          'ativa': true,
          'premios': [
            {'quantidadeMaxima': 10, 'quantidadeUsada': 7},
          ],
        },
        logs: [
          {
            'premioTipo': 'desconto',
            'premioValor': 15,
            'criadoEm': DateTime(2026, 7, 12),
            'status': 'pendente',
          },
          {
            'premioTipo': 'nenhum',
            'premioValor': 0,
            'criadoEm': DateTime(2026, 7, 12),
          },
          {
            'premioTipo': 'frete_gratis',
            'premioValor': 20,
            'criadoEm': DateTime(2026, 6, 1),
          },
        ],
        periodo: MarketingPeriodFilter.mes,
        agora: agora,
      );
      expect(k.configAtiva, isTrue);
      expect(k.giros, 2); // só no mês
      expect(k.premios, 1);
      expect(k.valorDistribuido, 15);
      expect(k.premiosPendentes, greaterThanOrEqualTo(1));

      expect(
        roletaHistoricoCorrespondeBusca(
          item: {
            'clienteNome': 'Ana Silva',
            'clienteTelefone': '(11) 99887-7665',
            'premioLabel': '10% OFF',
            'cupom': 'ANA10',
          },
          query: '9988',
        ),
        isTrue,
      );
      expect(
        roletaHistoricoCorrespondeBusca(
          item: {'clienteNome': 'Ana', 'cupom': 'ANA10'},
          query: 'ana10',
        ),
        isTrue,
      );
      expect(
        roletaHistoricoCorrespondeBusca(
          item: {'clienteNome': 'Ana'},
          query: 'pedro',
        ),
        isFalse,
      );
    });
  });

  group('M3.8 S2 — série participantes/dia', () {
    test('agrega por dia', () {
      final s = agregarParticipantesPorDia(
        [
          {
            'status': 'valido',
            'dataParticipacao': DateTime(2026, 7, 10),
          },
          {
            'status': 'valido',
            'dataParticipacao': DateTime(2026, 7, 10, 8),
          },
          {
            'status': 'valido',
            'dataParticipacao': DateTime(2026, 7, 11),
          },
        ],
        periodo: MarketingPeriodFilter.mes,
        agora: DateTime(2026, 7, 13),
      );
      expect(s.length, 2);
      expect(s.first.label, '2026-07-10');
      expect(s.first.valor, 2);
    });
  });
}
