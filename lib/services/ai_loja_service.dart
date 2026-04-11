// lib/services/ai_loja_service.dart
// Serviço para IA da loja: sugestão de descrição de produto e chat de dicas.
// Chama Cloud Functions. Padrão: Gemini (grátis). OpenAI desabilitado temporariamente.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiLojaService {
  AiLojaService._();

  static const String _keyPreferirModelo = 'ia_preferir_modelo';

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  /// Timeout maior que o padrão (~10s) para respostas longas da IA no APK/web.
  static final HttpsCallableOptions _iaCallableOptions = HttpsCallableOptions(
    timeout: const Duration(seconds: 60),
  );

  static HttpsCallable _httpsIa(String name) =>
      _functions.httpsCallable(name, options: _iaCallableOptions);

  /// Preferência: 'gemini' (padrão). OpenAI desabilitado temporariamente.
  static Future<String> getPreferirModelo() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyPreferirModelo) ?? 'gemini';
    if (v == 'openai') return 'gemini'; // migrar para Gemini (GPT desabilitado)
    return v;
  }

  /// Define qual modelo usar: 'openai' ou 'gemini'.
  static Future<void> setPreferirModelo(String v) async {
    if (v != 'openai' && v != 'gemini') return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPreferirModelo, v);
  }

  static Future<String> _getPref() => getPreferirModelo();

  /// Mensagem amigável para exibir ao usuário (quota 429, conexão, etc.).
  static String messageForUser(Object e) {
    final msg = e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '');
    final lower = msg.toLowerCase();
    if (msg.contains('429') || lower.contains('quota') || lower.contains('excedido') || lower.contains('excedida')) {
      return 'Limite do Gemini (15 pedidos/min). Aguarde 30–60 segundos e tente novamente.';
    }
    if (lower.contains('modelo') && lower.contains('não disponível')) return msg;
    if (lower.contains('chave') && (lower.contains('inválida') || lower.contains('gemini'))) return msg;
    if (msg.trim().isEmpty) return 'Erro ao usar a IA. Verifique a conexão e se a chave da IA está configurada no Firebase.';
    return msg;
  }

  /// Sugere uma descrição para o produto com base em nome, categoria e subcategoria.
  /// Retorna o texto da descrição ou lança em caso de erro.
  static Future<String> sugerirDescricao({
    required String nome,
    String? categoria,
    String? subcategoria,
  }) async {
    try {
      final pref = await _getPref();
      final callable = _httpsIa('sugerirDescricaoProduto');
      final result = await callable.call(<String, dynamic>{
        'nome': nome.trim(),
        if (categoria != null && categoria.trim().isNotEmpty) 'categoria': categoria.trim(),
        if (subcategoria != null && subcategoria.trim().isNotEmpty) 'subcategoria': subcategoria.trim(),
        'preferirModelo': pref,
      });
      final data = result.data as Map<dynamic, dynamic>?;
      final descricao = data?['descricao']?.toString();
      if (descricao == null || descricao.isEmpty) {
        throw Exception('Resposta da IA sem descrição');
      }
      return descricao;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Envia uma mensagem no chat de dicas e retorna a resposta da IA.
  static Future<String> chatDicas({
    required String mensagem,
    List<Map<String, String>>? historico,
  }) async {
    try {
      final pref = await _getPref();
      final callable = _httpsIa('chatDicasLoja');
      final result = await callable.call(<String, dynamic>{
        'mensagem': mensagem.trim(),
        if (historico != null && historico.isNotEmpty) 'historico': historico,
        'preferirModelo': pref,
      });
      final data = result.data as Map<dynamic, dynamic>?;
      final resposta = data?['resposta']?.toString();
      if (resposta == null || resposta.isEmpty) throw Exception('Resposta da IA vazia');
      return resposta;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Tutorial passo a passo para uma tela/área do MasterPalm (Ajuda). Usa o mesmo endpoint com modo especial.
  /// [historico] vazio: gera o tutorial inicial; com mensagem: pergunta de acompanhamento.
  static Future<String> chatAjudaTutorial({
    required String nomeTela,
    String? mensagem,
    List<Map<String, String>>? historico,
  }) async {
    try {
      final pref = await _getPref();
      final callable = _httpsIa('chatDicasLoja');
      final result = await callable.call(<String, dynamic>{
        'modo': 'tutorial_tela',
        'nomeTela': nomeTela.trim(),
        if (mensagem != null && mensagem.trim().isNotEmpty) 'mensagem': mensagem.trim(),
        if (historico != null && historico.isNotEmpty) 'historico': historico,
        'preferirModelo': pref,
      });
      final data = result.data as Map<dynamic, dynamic>?;
      final resposta = data?['resposta']?.toString();
      if (resposta == null || resposta.isEmpty) throw Exception('Resposta da IA vazia');
      return resposta;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  static Future<String> _call(String name, Map<String, dynamic> params) async {
    params['preferirModelo'] = await _getPref();
    final result = await _httpsIa(name).call(params);
    final data = result.data as Map<dynamic, dynamic>?;
    final text = data?.values.first?.toString();
    if (text == null || text.isEmpty) throw Exception('Resposta da IA vazia');
    return text;
  }

  /// Sugere título otimizado para o produto (até ~60 caracteres).
  static Future<String> sugerirTitulo({required String nome, String? categoria}) async {
    try {
      return await _call('sugerirTituloProduto', {
        'nome': nome.trim(),
        if (categoria != null && categoria.trim().isNotEmpty) 'categoria': categoria.trim(),
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Variações de descrição: para feed, WhatsApp e Instagram.
  static Future<Map<String, String>> sugerirVariacoesDescricao({
    required String nome,
    String? descricaoAtual,
  }) async {
    try {
      final pref = await _getPref();
      final callable = _httpsIa('sugerirVariacoesDescricao');
      final result = await callable.call(<String, dynamic>{
        'nome': nome.trim(),
        if (descricaoAtual != null && descricaoAtual.trim().isNotEmpty) 'descricaoAtual': descricaoAtual.trim(),
        'preferirModelo': pref,
      });
      final data = result.data as Map<dynamic, dynamic>?;
      return {
        'paraFeed': (data?['paraFeed'] ?? '').toString(),
        'paraWhatsApp': (data?['paraWhatsApp'] ?? '').toString(),
        'paraInstagram': (data?['paraInstagram'] ?? '').toString(),
      };
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Legenda para Instagram/Reels.
  static Future<String> sugerirLegendaInstagram({required String produtoNome, String? descricao}) async {
    try {
      final pref = await _getPref();
      final data = await _httpsIa('sugerirLegendaInstagram').call(<String, dynamic>{
        'produtoNome': produtoNome.trim(),
        if (descricao != null && descricao.trim().isNotEmpty) 'descricao': descricao.trim(),
        'preferirModelo': pref,
      });
      final out = (data.data as Map<dynamic, dynamic>?)?['legenda']?.toString();
      if (out == null || out.isEmpty) throw Exception('Resposta da IA vazia');
      return out;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Mensagem pronta para WhatsApp. [tipo]: posVenda, recuperacaoCarrinho, promocao, novidade.
  static Future<String> sugerirMensagemWhatsApp({
    required String tipo,
    String? contexto,
  }) async {
    try {
      final pref = await _getPref();
      final data = await _httpsIa('sugerirMensagemWhatsApp').call(<String, dynamic>{
        'tipo': tipo,
        if (contexto != null && contexto.trim().isNotEmpty) 'contexto': contexto.trim(),
        'preferirModelo': pref,
      });
      final out = (data.data as Map<dynamic, dynamic>?)?['mensagem']?.toString();
      if (out == null || out.isEmpty) throw Exception('Resposta da IA vazia');
      return out;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Sugere categoria, subcategoria e tags.
  static Future<Map<String, dynamic>> sugerirCategoriaSubcategoria({
    required String nome,
    String? descricao,
  }) async {
    try {
      final pref = await _getPref();
      final callable = _httpsIa('sugerirCategoriaSubcategoria');
      final result = await callable.call(<String, dynamic>{
        'nome': nome.trim(),
        if (descricao != null && descricao.trim().isNotEmpty) 'descricao': descricao.trim(),
        'preferirModelo': pref,
      });
      final data = result.data as Map<dynamic, dynamic>?;
      final tags = data?['tags'];
      return {
        'categoria': (data?['categoria'] ?? 'Geral').toString(),
        'subcategoria': (data?['subcategoria'] ?? '').toString(),
        'tags': tags is List ? List<String>.from(tags.map((e) => e.toString())) : <String>[],
      };
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Sugestão de promoção para produtos com estoque parado.
  static Future<String> sugerirPromocaoEstoqueParado({
    required List<Map<String, dynamic>> produtos,
  }) async {
    try {
      final pref = await _getPref();
      final data = await _httpsIa('sugerirPromocaoEstoqueParado').call({
        'produtos': produtos,
        'preferirModelo': pref,
      });
      final out = (data.data as Map<dynamic, dynamic>?)?['sugestao']?.toString();
      if (out == null || out.isEmpty) throw Exception('Resposta da IA vazia');
      return out;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Análise de vendas em linguagem natural. [resumoVendas] = texto com dados para contexto.
  static Future<String> analiseVendasNatural({
    required String pergunta,
    String? resumoVendas,
  }) async {
    try {
      final pref = await _getPref();
      final data = await _httpsIa('analiseVendasNatural').call(<String, dynamic>{
        'pergunta': pergunta.trim(),
        if (resumoVendas != null && resumoVendas.trim().isNotEmpty) 'resumoVendas': resumoVendas.trim(),
        'preferirModelo': pref,
      });
      final out = (data.data as Map<dynamic, dynamic>?)?['resposta']?.toString();
      if (out == null || out.isEmpty) throw Exception('Resposta da IA vazia');
      return out;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Atendimento no catálogo: cliente pergunta (estoque, frete). [contexto] = dados da loja.
  static Future<String> chatAtendimentoCatalogo({
    required String pergunta,
    Map<String, dynamic>? contexto,
  }) async {
    try {
      final pref = await _getPref();
      final data = await _httpsIa('chatAtendimentoCatalogo').call(<String, dynamic>{
        'pergunta': pergunta.trim(),
        if (contexto != null && contexto.isNotEmpty) 'contexto': contexto,
        'preferirModelo': pref,
      });
      final out = (data.data as Map<dynamic, dynamic>?)?['resposta']?.toString();
      if (out == null || out.isEmpty) throw Exception('Resposta da IA vazia');
      return out;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Sugestão de preço para combo (itens + soma).
  static Future<String> sugerirPrecoCombo({
    required List<Map<String, dynamic>> itens,
    double somaItens = 0,
  }) async {
    try {
      final pref = await _getPref();
      final data = await _httpsIa('sugerirPrecoCombo').call({
        'itens': itens,
        'somaItens': somaItens,
        'preferirModelo': pref,
      });
      final out = (data.data as Map<dynamic, dynamic>?)?['sugestao']?.toString();
      if (out == null || out.isEmpty) throw Exception('Resposta da IA vazia');
      return out;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }
}
