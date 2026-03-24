// lib/services/nota_fiscal_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/nota_fiscal.dart';

/// Serviço de integração com API de Nota Fiscal
///
/// Este serviço pode ser integrado com:
/// - API Sebrae NFe
/// - Focus NFe
/// - WebMania
/// - Bling
/// - Outros provedores
class NotaFiscalService {
  // ========================================
  // CONFIGURAÇÃO DA API
  // ========================================

  /// Timeout para chamadas HTTP à Focus (emissão/consulta/cancelamento).
  static const Duration httpTimeout = Duration(seconds: 90);

  /// URL base da API (configurar conforme provedor)
  static const String _baseUrl = 'https://api.focusnfe.com.br/v2'; // Exemplo: Focus NFe

  /// Token de autenticação (deve ser armazenado em variável de ambiente)
  static String? _apiToken;

  /// Ambiente (homologacao ou producao)
  static bool _isProducao = false;

  /// Configura o serviço
  static void configure({
    required String apiToken,
    bool producao = false,
  }) {
    _apiToken = apiToken;
    _isProducao = producao;
  }

  /// Converte status retornado pela Focus (e variações) para o modelo interno da UI:
  /// `emitida`, `pendente`, `cancelada`, `erro`.
  static String normalizarStatusApiParaApp(String statusRaw) {
    final s = statusRaw.trim().toLowerCase();
    if (s.isEmpty) return 'pendente';
    switch (s) {
      case 'autorizado':
      case 'autorizada':
        return 'emitida';
      case 'cancelado':
      case 'cancelada':
        return 'cancelada';
      case 'denegado':
      case 'rejeitado':
      case 'erro_autorizacao':
        return 'erro';
      case 'processando_autorizacao':
      case 'processando':
        return 'pendente';
      case 'emitida':
      case 'pendente':
      case 'erro':
        return s;
      default:
        if (s.contains('autoriz')) return 'emitida';
        if (s.contains('cancel')) return 'cancelada';
        if (s.contains('rejeit') || s.contains('deneg') || s.contains('erro')) {
          return 'erro';
        }
        return 'pendente';
    }
  }

  /// Mensagem amigável para exibir ao usuário (timeout, rede, JSON inválido, API).
  static String mensagemErroHumano(Object erro) {
    if (erro is TimeoutException) {
      return 'Tempo esgotado ao falar com a Focus NFe. Verifique a conexão e tente de novo.';
    }
    if (erro is http.ClientException) {
      return 'Falha de conexão com a API Focus. Verifique a internet e tente de novo.';
    }
    if (erro is FormatException) {
      return 'Resposta inválida da API (formato inesperado). Tente novamente ou contate o suporte.';
    }
    final t = erro.toString();
    if (t.startsWith('Exception: ')) return t.substring('Exception: '.length);
    return t;
  }

  static String _mensagemCorpoRespostaApi(String body) {
    if (body.isEmpty) return 'Resposta vazia do servidor.';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final m = decoded['mensagem'] ?? decoded['message'] ?? decoded['erro'];
        if (m != null && m.toString().isNotEmpty) return m.toString();
      }
    } catch (_) {}
    final trimmed = body.trim();
    return trimmed.length > 280 ? '${trimmed.substring(0, 280)}…' : trimmed;
  }

  // ========================================
  // EMISSÃO DE NOTA FISCAL
  // ========================================

  /// Emite uma nota fiscal
  static Future<Map<String, dynamic>> emitirNotaFiscal(NotaFiscal nota) async {
    if (_apiToken == null || _apiToken!.isEmpty) {
      throw Exception('API Token não configurado. Salve o token na aba Config ou reabra a tela após configurar.');
    }

    try {
      debugPrint('🧾 [NF-e] Emitindo nota fiscal ${nota.numero}...');

      // Monta o payload conforme especificação da API
      final payload = _montarPayloadNFe(nota);

      // Endpoint de emissão
      final url = Uri.parse('$_baseUrl/nfe');

      // Headers
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Basic ${base64Encode(utf8.encode('$_apiToken:'))}',
      };

      // Envia requisição
      final response = await http
          .post(
            url,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(httpTimeout);

      debugPrint('🧾 [NF-e] Status Code: ${response.statusCode}');
      debugPrint('🧾 [NF-e] Response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        Map<String, dynamic> data;
        try {
          data = jsonDecode(response.body) as Map<String, dynamic>;
        } on FormatException {
          throw Exception(
            'Resposta inválida da Focus após emissão (corpo não é JSON).',
          );
        }

        // Atualizar nota com dados retornados
        if (data['chave_nfe'] != null) {
          nota.chaveAcesso = data['chave_nfe'].toString();
        }
        if (data['protocolo'] != null) {
          nota.protocoloAutorizacao = data['protocolo'].toString();
        }
        final statusApi = data['status']?.toString() ?? 'emitida';
        nota.status = normalizarStatusApiParaApp(statusApi);
        if (data['caminho_xml_nota_fiscal'] != null) {
          nota.xmlUrl = data['caminho_xml_nota_fiscal'].toString();
        }
        if (data['caminho_danfe'] != null) {
          nota.pdfUrl = data['caminho_danfe'].toString();
        }

        await nota.save();

        debugPrint('✅ [NF-e] Nota fiscal emitida com sucesso!');
        return {
          'success': true,
          'chaveAcesso': nota.chaveAcesso,
          'protocolo': nota.protocoloAutorizacao,
          'status': nota.status,
          'xmlUrl': nota.xmlUrl,
          'pdfUrl': nota.pdfUrl,
        };
      } else {
        throw Exception(
          'Erro ao emitir NF-e (HTTP ${response.statusCode}): ${_mensagemCorpoRespostaApi(response.body)}',
        );
      }
    } catch (e) {
      debugPrint('❌ [NF-e] Erro ao emitir nota (type=${e.runtimeType})');
      nota.status = 'erro';
      await nota.save();
      rethrow;
    }
  }

  /// Monta o payload da NF-e conforme especificação da API
  static Map<String, dynamic> _montarPayloadNFe(NotaFiscal nota) {
    return {
      'natureza_operacao': 'Venda de mercadoria',
      'data_emissao': nota.dataEmissao.toIso8601String(),
      'tipo_documento': '1', // 1=Saída
      'finalidade_emissao': '1', // 1=Normal
      'ambiente': _isProducao ? '1' : '2', // 1=Produção, 2=Homologação

      // Destinatário (Cliente)
      'destinatario': {
        'cpf_cnpj': nota.clienteCpfCnpj.replaceAll(RegExp(r'[^0-9]'), ''),
        'nome': nota.clienteNome,
        'endereco': nota.clienteEndereco ?? '',
        'bairro': '',
        'municipio': nota.clienteCidade ?? '',
        'uf': nota.clienteEstado ?? '',
        'cep': nota.clienteCep?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
        'telefone': '',
        'email': '',
      },

      // Itens
      'items': nota.itens.map((item) => {
        'numero_item': nota.itens.indexOf(item) + 1,
        'codigo_produto': item.codigoProduto ?? '',
        'descricao': item.produtoNome,
        'cfop': item.cfop ?? '5102', // 5102 = Venda de mercadoria
        'unidade_comercial': item.unidade,
        'quantidade_comercial': item.quantidade.toString(),
        'valor_unitario_comercial': item.valorUnitario.toStringAsFixed(2),
        'valor_bruto': item.valorTotal.toStringAsFixed(2),
        'ncm': item.ncm ?? '00000000',

        // Tributação (simplificado - ajustar conforme regime tributário)
        'icms_origem': '0',
        'icms_situacao_tributaria': '102', // 102 = Tributada sem permissão de crédito
      }).toList(),

      // Totais
      'valor_produtos': nota.valorProdutos.toStringAsFixed(2),
      'valor_frete': nota.valorFrete.toStringAsFixed(2),
      'valor_desconto': nota.valorDesconto.toStringAsFixed(2),
      'valor_total': nota.valorTotal.toStringAsFixed(2),

      // Informações adicionais
      'informacoes_adicionais_contribuinte': nota.observacoes ?? '',
    };
  }

  // ========================================
  // CONSULTA DE NOTA FISCAL
  // ========================================

  /// Consulta o status de uma nota fiscal pela chave de acesso
  static Future<Map<String, dynamic>> consultarNota(String chaveAcesso) async {
    if (_apiToken == null || _apiToken!.isEmpty) {
      throw Exception('API Token não configurado');
    }

    try {
      debugPrint('🔍 [NF-e] Consultando nota: $chaveAcesso');

      final url = Uri.parse('$_baseUrl/nfe/$chaveAcesso');
      final headers = {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$_apiToken:'))}',
      };

      final response =
          await http.get(url, headers: headers).timeout(httpTimeout);

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          debugPrint('✅ [NF-e] Nota consultada: ${data['status']}');
          return data;
        } on FormatException {
          throw Exception('Resposta da consulta não é JSON válido.');
        }
      } else {
        throw Exception(
          'Erro ao consultar NF-e (HTTP ${response.statusCode}): ${_mensagemCorpoRespostaApi(response.body)}',
        );
      }
    } catch (e) {
      debugPrint('❌ [NF-e] Erro ao consultar nota (type=${e.runtimeType})');
      rethrow;
    }
  }

  // ========================================
  // CANCELAMENTO DE NOTA FISCAL
  // ========================================

  /// Cancela uma nota fiscal
  static Future<Map<String, dynamic>> cancelarNota({
    required String chaveAcesso,
    required String justificativa,
  }) async {
    if (_apiToken == null || _apiToken!.isEmpty) {
      throw Exception('API Token não configurado');
    }

    if (justificativa.length < 15) {
      throw Exception('Justificativa deve ter no mínimo 15 caracteres');
    }

    try {
      debugPrint('🚫 [NF-e] Cancelando nota: $chaveAcesso');

      final url = Uri.parse('$_baseUrl/nfe/$chaveAcesso');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Basic ${base64Encode(utf8.encode('$_apiToken:'))}',
      };

      final payload = {
        'justificativa': justificativa,
      };

      // Focus NFe v2: DELETE /v2/nfe/{referencia} com JSON { "justificativa": "..." }
      final response = await http
          .delete(
            url,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(httpTimeout);

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (response.body.isEmpty) {
          debugPrint('✅ [NF-e] Nota cancelada com sucesso (sem corpo)');
          return <String, dynamic>{};
        }
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          debugPrint('✅ [NF-e] Nota cancelada com sucesso');
          return data;
        } on FormatException {
          debugPrint('✅ [NF-e] Cancelamento OK; corpo não era JSON');
          return <String, dynamic>{};
        }
      } else {
        throw Exception(
          'Erro ao cancelar NF-e (HTTP ${response.statusCode}): ${_mensagemCorpoRespostaApi(response.body)}',
        );
      }
    } catch (e) {
      debugPrint('❌ [NF-e] Erro ao cancelar nota (type=${e.runtimeType})');
      rethrow;
    }
  }

  // ========================================
  // DOWNLOAD DE ARQUIVOS
  // ========================================

  /// Baixa o XML da nota fiscal
  static Future<String?> baixarXml(String chaveAcesso) async {
    try {
      final dados = await consultarNota(chaveAcesso);
      return dados['caminho_xml_nota_fiscal'];
    } catch (e) {
      debugPrint('❌ [NF-e] Erro ao baixar XML (type=${e.runtimeType})');
      return null;
    }
  }

  /// Baixa o DANFE (PDF) da nota fiscal
  static Future<String?> baixarDanfe(String chaveAcesso) async {
    try {
      final dados = await consultarNota(chaveAcesso);
      return dados['caminho_danfe'];
    } catch (e) {
      debugPrint('❌ [NF-e] Erro ao baixar DANFE (type=${e.runtimeType})');
      return null;
    }
  }

  // ========================================
  // GERAÇÃO DE NÚMERO DE NOTA
  // ========================================

  /// Gera o próximo número de nota fiscal (sequencial no Firestore)
  static Future<String> gerarProximoNumero({
    required String lojaId,
    required String serie,
  }) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('nota_fiscal_sequencial');

      final result = await FirebaseFirestore.instance.runTransaction<String>(
        (tx) async {
          final snap = await tx.get(ref);
          int proximo = 1;
          if (snap.exists && snap.data() != null) {
            final atual = (snap.data()!['serie_$serie'] as num?)?.toInt() ?? 0;
            proximo = atual + 1;
          }
          tx.set(ref, {'serie_$serie': proximo}, SetOptions(merge: true));
          return proximo.toString();
        },
      );
      return result;
    } catch (e) {
      debugPrint('⚠️ [NF-e] Erro ao gerar sequencial, usando timestamp (type=${e.runtimeType})');
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }
}
