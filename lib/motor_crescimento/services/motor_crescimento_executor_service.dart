// lib/motor_crescimento/services/motor_crescimento_executor_service.dart
// Executor de campanhas do Motor de Crescimento IA (Etapa 3).
// Cria cupom real, gera link, registra campanha. Sem automação externa.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/logger.dart';
import '../../services/cupom_desconto_service.dart';
import '../models/campanha_motor.dart';
import '../models/campanha_motor_result.dart';
import '../models/oportunidade_crescimento.dart';
import '../models/sugestao_campanha.dart';

const String _baseUrlCatalogo = 'https://app.mastepalm.com.br/loja';

/// Executa a campanha: cria cupom, gera link, registra.
class MotorCrescimentoExecutorService {
  MotorCrescimentoExecutorService._();

  /// Executa a campanha a partir da sugestão.
  /// [lojaId] obrigatório para criar cupom e registrar.
  static Future<CampanhaMotorResult> executar({
    required String lojaId,
    required OportunidadeCrescimento oportunidade,
    required SugestaoCampanha sugestao,
  }) async {
    if (lojaId.trim().isEmpty) {
      return CampanhaMotorResult.erro('Loja não configurada.');
    }

    final codigo = sugestao.codigoCupomSugerido.trim().toUpperCase();
    if (codigo.isEmpty) {
      return CampanhaMotorResult.erro('Código do cupom não informado na sugestão.');
    }

    final linkPromocao = _gerarLinkPromocao(
      lojaId: lojaId,
      codigoCupom: codigo,
      produtoId: oportunidade.entidadeId.trim().isNotEmpty ? oportunidade.entidadeId.trim() : null,
    );

    String? cupomId;
    bool cupomCriado = false;

    final produtoId = oportunidade.entidadeId.trim();

    if (sugestao.percentualDesconto > 0 && sugestao.percentualDesconto <= 100) {
      try {
        cupomId = await CupomDescontoService().criarCupom(
          lojaId: lojaId,
          codigo: codigo,
          nome: sugestao.titulo.isNotEmpty ? sugestao.titulo : 'Motor IA - ${oportunidade.entidadeNome}',
          valor: sugestao.percentualDesconto,
          tipo: 'percentual',
          aplicarEm: 'produtos',
          produtoIds: produtoId.isNotEmpty ? [produtoId] : null,
          usoUnico: false,
          usoUnicoGlobal: false,
          dataInicio: DateTime.now(),
          dataFim: DateTime.now().add(const Duration(days: 30)),
        );
        if (cupomId != null && cupomId.isNotEmpty) {
          cupomCriado = true;
          logD('✅ [Motor] Cupom criado: $codigo');
        }
      } catch (e, st) {
        logE('⚠️ [Motor] Erro ao criar cupom (fallback) (type=${e.runtimeType})', error: e, st: st);
      }
    }

    final textos = <String, String>{
      'textoPromocao': sugestao.textoPromocao,
      'mensagemWhatsApp': sugestao.mensagemWhatsApp,
      'legendaInstagram': sugestao.legendaInstagram,
    };

    final campanha = CampanhaMotor(
      id: '',
      oportunidadeId: oportunidade.id,
      tipoCampanha: sugestao.tipoCampanha,
      codigoCupom: codigo,
      percentualDesconto: sugestao.percentualDesconto,
      linkPromocao: linkPromocao,
      textos: textos,
      status: 'criada',
      criadoEm: DateTime.now(),
    );

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('motor_campanhas')
          .add(campanha.toFirestore());

      logD('✅ [Motor] Campanha registrada: ${docRef.id}');

      if (cupomCriado) {
        return CampanhaMotorResult.sucessoFull(
          campanha: campanha.copyWith(id: docRef.id),
        );
      }
      return CampanhaMotorResult.sucessoFallback(
        campanha: campanha.copyWith(id: docRef.id),
        mensagem: cupomId == null
            ? 'Link gerado. Cupom não foi criado – verifique se o código já existe ou crie manualmente em Fretes e Cupons.'
            : 'Campanha registrada. Cupom pode precisar ser configurado manualmente.',
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [Motor] Sem permissão para registrar campanha – fallback local');
        return CampanhaMotorResult.sucessoFallback(
          campanha: campanha,
          mensagem: 'Link gerado. Campanha não foi registrada (sem permissão). O cupom precisa ser criado manualmente.',
        );
      }
      rethrow;
    }
  }

  /// Gera link da campanha. Se [produtoId] for informado (produto da oportunidade),
  /// o link inclui `&prod=` para o catálogo abrir direto no produto (canônico).
  static String _gerarLinkPromocao({
    required String lojaId,
    required String codigoCupom,
    String? produtoId,
  }) {
    if (lojaId.trim().isEmpty) return '';
    final base = '$_baseUrlCatalogo/$lojaId';
    var link = '$base?cupom=${Uri.encodeComponent(codigoCupom)}';
    if (produtoId != null && produtoId.trim().isNotEmpty) {
      link = '$link&prod=${Uri.encodeComponent(produtoId.trim())}';
    }
    return link;
  }
}
