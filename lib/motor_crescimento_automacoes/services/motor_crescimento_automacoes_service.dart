// lib/motor_crescimento_automacoes/services/motor_crescimento_automacoes_service.dart
// Extensão do Motor de Crescimento: gera sugestões automáticas de campanhas.
// Reutiliza Detector + Sugestor. Não executa campanhas automaticamente.

import '../../motor_crescimento/models/oportunidade_crescimento.dart';
import '../../motor_crescimento/models/sugestao_campanha.dart';
import '../../motor_crescimento/services/motor_crescimento_detector_service.dart';
import '../../motor_crescimento/services/motor_crescimento_sugestor_service.dart';
import '../models/campanha_automatica.dart';

const String _baseUrlCatalogo = 'https://app.mastepalm.com.br/loja';

/// Tempo máximo para cada tipo de detecção (rodam em paralelo, então total ~20s).
const Duration _timeoutDeteccaoPorTipo = Duration(seconds: 20);
/// Timeout da fase de sugestões: retorna o que já tiver após esse tempo.
const Duration _timeoutSugestoes = Duration(seconds: 45);

/// Resultado: campanha sugerida + dados para execução (quando usuário confirmar).
class CampanhaAutomaticaSugerida {
  final CampanhaAutomatica campanha;
  final OportunidadeCrescimento oportunidade;
  final SugestaoCampanha sugestao;

  const CampanhaAutomaticaSugerida({
    required this.campanha,
    required this.oportunidade,
    required this.sugestao,
  });
}

/// Serviço de sugestões automáticas de campanhas.
class MotorCrescimentoAutomacoesService {
  MotorCrescimentoAutomacoesService._();

  /// Máximo de oportunidades processadas por vez (poucas = tela abre rápido).
  static const int maxOportunidadesPorTela = 12;

  /// Gera sugestões de campanhas com base nas oportunidades detectadas.
  /// Processa no máximo [maxOportunidadesPorTela] para a tela abrir rápido.
  /// [onProgress] opcional: (concluídos, total) a cada sugestão gerada.
  static Future<List<CampanhaAutomaticaSugerida>> gerarSugestoesAutomaticas(
    String lojaId, {
    void Function(int concluidos, int total)• onProgress,
  }) async {
    if (lojaId.trim().isEmpty) return [];

    try {
      // Os dois detectores em paralelo, cada um com 15s (total ~15s em vez de 30s)
      const half = maxOportunidadesPorTela ~/ 2;
      final deadline = DateTime.now().add(_timeoutDeteccaoPorTipo);
      final results = await Future.wait([
        MotorCrescimentoDetectorService.detectarProdutosParados(
          lojaId,
          limit: half,
          deadline: deadline,
        ),
        MotorCrescimentoDetectorService.detectarEstoqueBaixo(
          lojaId,
          limit: half,
          deadline: deadline,
        ),
      ]);
      final parados = results[0];
      final estoqueBaixo = results[1];
      final oportunidades = [...parados, ...estoqueBaixo];
      if (oportunidades.isEmpty) return [];

      final sugestoes = <CampanhaAutomaticaSugerida>[];
      final stopAt = DateTime.now().add(_timeoutSugestoes);
      onProgress?.call(0, oportunidades.length);

      for (var i = 0; i < oportunidades.length; i++) {
        if (DateTime.now().isAfter(stopAt)) break;
        final op = oportunidades[i];
        try {
          final sugestao = await MotorCrescimentoSugestorService.sugerirCampanha(op);
          final codigo = sugestao.codigoCupomSugerido.trim().toUpperCase();
          final link = codigo.isNotEmpty
              • '$_baseUrlCatalogo/$lojaId?cupom=${Uri.encodeComponent(codigo)}'
              : '';

          final prioridade = sugestao.tipoCampanha == 'promocao'
              • PrioridadeCampanha.alta
              : PrioridadeCampanha.media;

          final campanha = CampanhaAutomatica(
            id: 'sug_${i}_${op.id}',
            lojaId: lojaId,
            tipoCampanha: sugestao.tipoCampanha,
            entidadeId: op.entidadeId,
            entidadeNome: op.entidadeNome,
            percentualDesconto: sugestao.percentualDesconto,
            codigoCupom: codigo,
            linkPromocao: link,
            textoPromocional: sugestao.textoPromocao,
            status: 'sugerida',
            criadoEm: DateTime.now(),
            executadoEm: null,
            origemOportunidade: op.titulo,
            prioridade: prioridade,
          );

          sugestoes.add(CampanhaAutomaticaSugerida(
            campanha: campanha,
            oportunidade: op,
            sugestao: sugestao,
          ));
          onProgress?.call(sugestoes.length, oportunidades.length);
        } catch (_) {
          // continua com a próxima oportunidade
        }
      }

      sugestoes.sort((a, b) {
        int ordem(PrioridadeCampanha p) => p == PrioridadeCampanha.alta • 0 : (p == PrioridadeCampanha.media • 1 : 2);
        return ordem(a.campanha.prioridade).compareTo(ordem(b.campanha.prioridade));
      });
      return sugestoes;
    } catch (_) {
      return [];
    }
  }
}
