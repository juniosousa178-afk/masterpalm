// lib/services/frete_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'shipping_provider_selection.dart';
import 'superfrete_service.dart';
import 'superfrete_integration_service.dart';
import 'via_cep_service.dart';
import 'frete_helpers.dart' as frete_helpers;

/// Serviço unificado para cálculo de frete
/// Suporta: Manual, Correios, Melhor Envio, SuperFrete, Frenet
class FreteService {
  static const String _melhorEnvioBaseUrl = 'https://melhorenvio.com.br/api/v2';
  static const String _frenetBaseUrl = 'https://api.frenet.com.br';

  /// User-Agent obrigatório pela documentação Melhor Envio
  static const String _melhorEnvioUserAgent = 'MasterPalm (contato@mastepalm.com.br)';

  static bool _isSuperFreteConfigured(Map<String, dynamic> config) =>
      ShippingProviderSelection.isSuperFreteConfigured(config);

  static bool _isMelhorEnvioConfigured(Map<String, dynamic> config) =>
      ShippingProviderSelection.isMelhorEnvioConfigured(config);

  static void _stripMelhorEnvioSecretsFromConfig(Map<String, dynamic> config) {
    if (config['melhorEnvio'] is Map) {
      config.remove('melhorEnvio');
    }
    config.remove('melhor_envio_token');
    config.remove('melhorEnvioToken');
  }

  static void _stripSuperFreteSecretsFromConfig(Map<String, dynamic> config) {
    if (config['superfrete'] != null) {
      config.remove('superfrete');
    }
    config.remove('superfrete_token');
    config.remove('superfreteToken');
  }
  /// Mensagem segura quando o provedor selecionado não devolve cotação.
  static const String mensagemFalhaProvedor =
      'Não foi possível calcular o frete agora. Tente novamente em instantes ou escolha uma opção de entrega manual.';

  /// Calcula o frete com o provedor selecionado pela loja (`config/fretes.provider`).
  ///
  /// Só o provedor selecionado é consultado (sem agregar nem trocar de provedor).
  /// Se ele falhar, [FreteCalculoResultado.erroProvedor] traz [mensagemFalhaProvedor]
  /// e só os fretes manuais da loja (`plataforma: manual`) são devolvidos.
  static Future<FreteCalculoResultado> calcularFrete({
    required String lojaId,
    required String cep,
    required double peso,
    required double valorDeclarado,
    double altura = 10,
    double largura = 20,
    double comprimento = 30,
    /// Itens do carrinho (`[{productId, quantidade}]`): o servidor calcula o pacote
    /// e devolve `shipping_quote_id` por opção (Melhor Envio / SuperFrete).
    List<Map<String, dynamic>>? itensCotacao,
  }) async {
    try {
      final config = await _buscarConfigFrete(lojaId);
      return await calcularComConfig(
        config: config,
        lojaId: lojaId,
        cep: cep,
        peso: peso,
        valorDeclarado: valorDeclarado,
        altura: altura,
        largura: largura,
        comprimento: comprimento,
        itensCotacao: itensCotacao,
      );
    } catch (e) {
      debugPrint('❌ [FRETE] Erro ao calcular frete (type=${e.runtimeType})');
      return FreteCalculoResultado(
        provider: ShippingProviderSelection.manual,
        opcoes: _comPlataformaManual(_fretePadrao()),
        erroProvedor: mensagemFalhaProvedor,
      );
    }
  }

  @visibleForTesting
  static Future<FreteCalculoResultado> calcularComConfig({
    required Map<String, dynamic> config,
    required String lojaId,
    required String cep,
    required double peso,
    required double valorDeclarado,
    double altura = 10,
    double largura = 20,
    double comprimento = 30,
    List<Map<String, dynamic>>? itensCotacao,
    FreteCotadores cotadores = FreteCotadores.padrao,
  }) async {
    final provider = ShippingProviderSelection.resolve(config);
    final pedido = FreteCotacaoPedido(
      config: config,
      lojaId: lojaId,
      cep: cep,
      peso: peso,
      valorDeclarado: valorDeclarado,
      altura: altura,
      largura: largura,
      comprimento: comprimento,
      itensCotacao: itensCotacao,
    );
    debugPrint('🚚 [FRETE] Provedor selecionado: $provider');

    final opcoes = <Map<String, dynamic>>[];
    String? erroProvedor;
    final cotador = cotadores.para(provider);
    if (cotador != null) {
      if (!_provedorConfigurado(provider, config)) {
        debugPrint('⚠️  [FRETE] $provider selecionado sem integração ativa; só fretes manuais');
      } else {
        try {
          final validas = (await cotador(pedido))
              .where((o) => ((o['valor'] as num?)?.toDouble() ?? 0) > 0)
              .toList();
          if (validas.isEmpty) {
            erroProvedor = mensagemFalhaProvedor;
          } else {
            for (final o in validas) {
              o['plataforma'] = provider;
            }
            opcoes.addAll(validas);
          }
        } catch (e) {
          debugPrint('⚠️  [FRETE] Falha na cotação $provider (type=${e.runtimeType})');
          erroProvedor = mensagemFalhaProvedor;
        }
      }
    }

    final manualFretes = config['manualFretes'] as List? ?? [];
    if (manualFretes.isNotEmpty) {
      opcoes.addAll(_comPlataformaManual(_calcularManual(config)));
    }
    if (opcoes.isEmpty) {
      opcoes.addAll(_comPlataformaManual(_fretePadrao()));
    }

    opcoes.sort((a, b) {
      final valorA = (a['valor'] as num?)?.toDouble() ?? 999999;
      final valorB = (b['valor'] as num?)?.toDouble() ?? 999999;
      return valorA.compareTo(valorB);
    });
    debugPrint('🎉 [FRETE] $provider: ${opcoes.length} opções, falha=${erroProvedor != null}');
    return FreteCalculoResultado(provider: provider, opcoes: opcoes, erroProvedor: erroProvedor);
  }

  static bool _provedorConfigurado(String provider, Map<String, dynamic> config) {
    switch (provider) {
      case ShippingProviderSelection.melhorEnvio:
        return _isMelhorEnvioConfigured(config);
      case ShippingProviderSelection.superFrete:
        return _isSuperFreteConfigured(config);
      case ShippingProviderSelection.frenet:
        return (config['frenet']?['token'] ?? '').toString().isNotEmpty;
      case ShippingProviderSelection.correios:
        return (config['correios']?['usuario'] ?? '').toString().isNotEmpty &&
            (config['correios']?['senha'] ?? '').toString().isNotEmpty;
      default:
        return false;
    }
  }

  static List<Map<String, dynamic>> _comPlataformaManual(List<Map<String, dynamic>> opcoes) {
    for (final o in opcoes) {
      o['plataforma'] = 'manual';
    }
    return opcoes;
  }

  static Future<List<Map<String, dynamic>>> _cotarMelhorEnvio(FreteCotacaoPedido p) =>
      _calcularMelhorEnvio(
        config: p.config,
        lojaId: p.lojaId,
        cep: p.cep,
        peso: p.peso,
        valorDeclarado: p.valorDeclarado,
        altura: p.altura,
        largura: p.largura,
        comprimento: p.comprimento,
        itensCotacao: p.itensCotacao,
      );

  static Future<List<Map<String, dynamic>>> _cotarSuperFrete(FreteCotacaoPedido p) async {
    final cepOrigem =
        (p.config['cepOrigem'] ?? '01310100').toString().replaceAll(RegExp(r'\D'), '');
    final docId = (p.config['_resolvedLojaDocId'] ?? p.lojaId).toString().trim();
    final resultado = await SuperFreteIntegrationService.quote(
      lojaId: docId,
      destinationCep: p.cep.replaceAll(RegExp(r'\D'), ''),
      pesoGrams: p.peso < 300 ? 300.0 : p.peso,
      altura: p.altura < 1 ? 2 : p.altura,
      largura: p.largura < 1 ? 11 : p.largura,
      comprimento: p.comprimento < 1 ? 16 : p.comprimento,
      valorDeclarado: p.valorDeclarado > 0 ? p.valorDeclarado : 10.0,
      cepOrigem: cepOrigem,
      items: p.itensCotacao,
    );
    if (resultado['sucesso'] != true) {
      throw StateError('SuperFrete sem cotação');
    }
    final opcoesRaw = resultado['opcoes'] as List? ?? [];
    return opcoesRaw.map<Map<String, dynamic>>((o) {
      final m = o is Map ? Map<String, dynamic>.from(o) : <String, dynamic>{};
      return {
        'nome': (m['nome'] ?? 'SuperFrete').toString(),
        'valor': (m['preco'] as num?)?.toDouble() ?? 0.0,
        'prazo': (m['prazo'] as num?)?.toInt() ?? 0,
        'empresa': (m['empresa'] ?? 'SuperFrete').toString(),
        'plataforma': 'superfrete',
        'servico_id': m['servico_id'],
        if (m['shippingQuoteId'] != null)
          'shipping_quote_id': m['shippingQuoteId'].toString(),
      };
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> _cotarFrenet(FreteCotacaoPedido p) =>
      _calcularFrenet(
        config: p.config,
        cep: p.cep,
        peso: p.peso,
        valorDeclarado: p.valorDeclarado,
        altura: p.altura,
        largura: p.largura,
        comprimento: p.comprimento,
      );

  static Future<List<Map<String, dynamic>>> _cotarCorreios(FreteCotacaoPedido p) =>
      _calcularCorreios(
        config: p.config,
        cep: p.cep,
        peso: p.peso,
        valorDeclarado: p.valorDeclarado,
        altura: p.altura,
        largura: p.largura,
        comprimento: p.comprimento,
      );

  /// Busca configuração de frete do Firestore.
  /// Lê config/fretes, config/config (frete_config) e draft_config/config como fallbacks.
  static Future<Map<String, dynamic>> _buscarConfigFrete(String lojaId) async {
    try {
      debugPrint('🚚 [FRETE] _buscarConfigFrete');
      String docId = lojaId.trim();
      final lojaDoc = await FirebaseFirestore.instance.collection('lojas').doc(docId).get();
      if (!lojaDoc.exists) {
        debugPrint('⚠️ [FRETE] Doc lojas/$docId não existe, buscando por slug...');
        final bySlug = await FirebaseFirestore.instance
            .collection('lojas')
            .where('slug', isEqualTo: docId.toLowerCase())
            .limit(1)
            .get();
        if (bySlug.docs.isNotEmpty) {
          docId = bySlug.docs.first.id;
          debugPrint('✅ [FRETE] Loja resolvida por slug');
        }
      } else {
        debugPrint('✅ [FRETE] Doc lojas/$docId existe');
      }

      final base = FirebaseFirestore.instance.collection('lojas').doc(docId).collection('config');
      final docFretes = await base.doc('fretes').get();
      Map<String, dynamic> config = docFretes.exists ? (docFretes.data() ?? {}) : {};
      debugPrint('📄 [FRETE] config/fretes existe=${docFretes.exists}, melhorEnvioConfigured=${_isMelhorEnvioConfigured(config)}, superfreteConfigured=${_isSuperFreteConfigured(config)}');
      _stripSuperFreteSecretsFromConfig(config);
      _stripMelhorEnvioSecretsFromConfig(config);

      // Helper para aplicar config pública de draft — sem tokens de transportadora.
      void applyTokensFrom(Map<String, dynamic> data) {
        final fc = data['frete_config'] as Map<String, dynamic>?;
        if (fc != null) {
          final prov = (fc['provider'] ?? '').toString().trim();
          if (prov.isNotEmpty && (config['provider'] ?? '').toString().trim().isEmpty) {
            config = Map<String, dynamic>.from(config);
            config['provider'] = prov;
          }
          final cepO = (fc['cep_origem'] ?? fc['cepOrigem'] ?? '').toString().trim();
          if (cepO.isNotEmpty && (config['cepOrigem'] ?? '').toString().trim().isEmpty) {
            config = Map<String, dynamic>.from(config);
            config['cepOrigem'] = cepO;
          }
          final frenetT = (fc['frenet_token'] ?? '').toString().trim();
          if (frenetT.isNotEmpty && (config['frenet']?['token'] ?? '').toString().trim().isEmpty) {
            config = Map<String, dynamic>.from(config);
            config['frenet'] = {'token': frenetT};
          }
          final corUser = (fc['correios_user'] ?? '').toString().trim();
          final corSenha = (fc['correios_senha'] ?? '').toString().trim();
          if (corUser.isNotEmpty && (config['correios']?['usuario'] ?? '').toString().trim().isEmpty) {
            config = Map<String, dynamic>.from(config);
            config['correios'] = {'usuario': corUser, 'senha': corSenha};
          }
        }
        final manualList = config['manualFretes'] as List? ?? [];
        if (manualList.isEmpty && data['fretes'] is List && (data['fretes'] as List).isNotEmpty) {
          config = Map<String, dynamic>.from(config);
          config['manualFretes'] = data['fretes'];
        }
      }

      // Fallback 1: config/config
      if (!_isMelhorEnvioConfigured(config)) {
        final docConfig = await base.doc('config').get();
        if (docConfig.exists && docConfig.data() != null) {
          applyTokensFrom(docConfig.data()!);
          _stripMelhorEnvioSecretsFromConfig(config);
        }
        if (!_isMelhorEnvioConfigured(config)) {
          try {
            final draftRef = FirebaseFirestore.instance
                .collection('lojas')
                .doc(docId)
                .collection('draft_config')
                .doc('config');
            final docDraft = await draftRef.get();
            if (docDraft.exists && docDraft.data() != null) {
              applyTokensFrom(docDraft.data()!);
              _stripMelhorEnvioSecretsFromConfig(config);
            }
          } on FirebaseException catch (e) {
            debugPrint(
              '⚠️ [FRETE] draft_config não aplicado (${e.code}) — seguindo com config já carregada',
            );
          } catch (e) {
            debugPrint('⚠️ [FRETE] draft_config: $e');
          }
        }
      }

      if (config.isEmpty) {
        debugPrint('⚠️  [FRETE] Config não encontrada, usando manual');
        return {'provider': 'manual', 'manualFretes': [], '_resolvedLojaDocId': docId};
      }

      _stripSuperFreteSecretsFromConfig(config);
      _stripMelhorEnvioSecretsFromConfig(config);
      config['_resolvedLojaDocId'] = docId;

      final hasME = _isMelhorEnvioConfigured(config);
      final hasSF = _isSuperFreteConfigured(config);
      debugPrint('📤 [FRETE] Retornando config: MelhorEnvio=$hasME, SuperFrete=$hasSF, cepOrigem=${(config['cepOrigem'] ?? '').toString().isNotEmpty}');
      return config;
    } catch (e, st) {
      debugPrint('❌ [FRETE] Erro ao buscar config (type=${e.runtimeType})');
      debugPrint('❌ [FRETE] Stack: $st');
      return {'provider': 'manual', 'manualFretes': []};
    }
  }

  /// Fretes manuais/fixos
  static List<Map<String, dynamic>> _calcularManual(Map<String, dynamic> config) {
    final manualFretes = config['manualFretes'] as List? ?? [];

    if (manualFretes.isEmpty) {
      debugPrint('⚠️  [FRETE] Nenhum frete manual configurado, usando padrão');
      return _fretePadrao();
    }

    return manualFretes.map<Map<String, dynamic>>((f) {
      final nome = (f['nome'] ?? 'Frete').toString();
      final valor = (f['valor'] is num)
          ? (f['valor'] as num).toDouble()
          : double.tryParse('${f['valor']}') ?? 0.0;

      return {
        'nome': nome,
        'valor': valor,
        'prazo': 0,
        'empresa': 'Loja',
        'tipo': f['tipo'] ?? 'manual', // ✅ ADICIONA O TIPO
      };
    }).toList();
  }

  /// Frete padrão (fallback)
  static List<Map<String, dynamic>> _fretePadrao() {
    return [
      {
        'nome': 'Retirada',
        'valor': 0.0,
        'prazo': 0,
        'empresa': 'Loja',
        'tipo': 'retirada', // ✅ ADICIONA O TIPO
      },
    ];
  }

  /// Aceita número, string com ponto ou vírgula (ex.: Melhor Envio em pt-BR).
  static double? _parseMoneyMelhorEnvio(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    var s = raw.toString().trim();
    if (s.isEmpty) return null;
    if (s.contains(',') && !s.contains('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(s);
  }

  static List<Map<String, dynamic>> _parsearOpcoesMelhorEnvio(
    List<dynamic> data,
    Map<String, dynamic> config,
  ) {
    final opcoes = <Map<String, dynamic>>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      if (item['error'] == true) continue;

      final company = item['company'];
      final companyName = company is Map
          ? (company['name'] ?? 'Melhor Envio').toString()
          : 'Melhor Envio';
      final companyId =
          company is Map ? company['id'] : null;
      final nome = (item['name'] ??
              item['service_name'] ??
              item['title'] ??
              companyName)
          .toString()
          .trim();
      if (nome.isEmpty) continue;

      double valor = 0.0;
      for (final key in const [
        'price',
        'custom_price',
        'customPrice',
        'total',
        'final_price',
      ]) {
        final v = _parseMoneyMelhorEnvio(item[key]);
        if (v != null && v > 0) {
          valor = v;
          break;
        }
      }

      final deliveryTime = item['delivery_time'] ?? item['custom_delivery_time'];
      final rawId = item['id'];
      final serviceId =
          rawId is num ? rawId.toInt() : (rawId != null ? int.tryParse(rawId.toString()) : null);

      opcoes.add({
        'nome': nome.isEmpty ? 'Melhor Envio' : nome,
        'valor': valor,
        'prazo': (deliveryTime is num) ? deliveryTime.toInt() : int.tryParse('$deliveryTime') ?? 0,
        'empresa': companyName,
        if (companyId != null) 'company_id': companyId,
        'tipo': nome.toLowerCase().replaceAll(' ', '_'),
        if (serviceId != null) 'service_id': serviceId,
        if (item['shippingQuoteId'] != null)
          'shipping_quote_id': item['shippingQuoteId'].toString(),
      });
    }

    debugPrint('✅ [MELHOR_ENVIO] Processou ${opcoes.length} opções');
    return opcoes;
  }

  /// Melhor Envio via Cloud Function (token só no backend). Erros propagam para
  /// [calcularComConfig] — nunca viram frete manual com rótulo do provedor.
  static Future<List<Map<String, dynamic>>> _calcularMelhorEnvio({
    required Map<String, dynamic> config,
    required String lojaId,
    required String cep,
    required double peso,
    required double valorDeclarado,
    required double altura,
    required double largura,
    required double comprimento,
    List<Map<String, dynamic>>? itensCotacao,
  }) async {
    final resolvedLojaId =
        (config['_resolvedLojaDocId'] ?? lojaId).toString().trim();
    final cepOrigem = (config['cepOrigem'] ?? '01310100').toString().replaceAll(RegExp(r'\D'), '');
    final cepDestino = cep.replaceAll(RegExp(r'\D'), '');

    final alturaFinal = altura < 1 ? 2 : altura;
    final larguraFinal = largura < 1 ? 11 : largura;
    final comprimentoFinal = comprimento < 1 ? 16 : comprimento;
    final pesoFinal = peso < 300 ? 300 : peso;
    final pesoKg = pesoFinal / 1000;

    debugPrint('📏 [MELHOR_ENVIO] Dimensões: ${alturaFinal}x${larguraFinal}x${comprimentoFinal}cm, Peso: ${pesoFinal}g');

    final functions = FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final callable = functions.httpsCallable('calcularMelhorEnvio');
    final result = await callable.call({
      'lojaId': resolvedLojaId,
      'origem': cepOrigem,
      'destino': cepDestino,
      'peso': pesoKg,
      'altura': alturaFinal.toInt(),
      'largura': larguraFinal.toInt(),
      'comprimento': comprimentoFinal.toInt(),
      'valorProdutos': valorDeclarado > 0 ? valorDeclarado : 10.0,
      'servico': '1,2,3,4,17',
      if (itensCotacao != null && itensCotacao.isNotEmpty)
        'items': itensCotacao,
    });
    final data = result.data as Map?;
    final servicos = data?['servicos'];
    final list = servicos is List ? servicos : <dynamic>[];
    return _parsearOpcoesMelhorEnvio(list, config);
  }

  static List<Map<String, dynamic>> _parsearOpcoesFrenet(
    List<dynamic> shipping,
    Map<String, dynamic> config,
  ) {
    if (shipping.isEmpty) return [];

    return shipping
        .map<Map<String, dynamic>?>((item) {
          if (item['Error'] == true) return null;
          final nome = item['ServiceDescription'] ?? 'Frenet';
          final valorRaw = item['ShippingPrice'];
          final valor = valorRaw is num
              ? valorRaw.toDouble()
              : double.tryParse(valorRaw?.toString() ?? '0') ?? 0.0;
          final prazoRaw = item['DeliveryTime'];
          final prazo = prazoRaw is num
              ? prazoRaw.toInt()
              : int.tryParse(prazoRaw?.toString() ?? '0') ?? 0;
          final empresa = item['Carrier'] ?? 'Frenet';
          return {
            'nome': nome,
            'valor': valor,
            'prazo': prazo,
            'empresa': empresa,
            'tipo': nome.toString().toLowerCase().replaceAll(' ', '_'),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Frenet API
  static Future<List<Map<String, dynamic>>> _calcularFrenet({
    required Map<String, dynamic> config,
    required String cep,
    required double peso,
    required double valorDeclarado,
    required double altura,
    required double largura,
    required double comprimento,
  }) async {
    try {
      final token = (config['frenet']?['token'] ?? '').toString();
      if (token.isEmpty) {
        debugPrint('⚠️  [FRETE] Token Frenet não configurado');
        return [];
      }

      final cepOrigem = (config['cepOrigem'] ?? '01310100').toString();

      debugPrint('📡 [FRENET] Iniciando chamada API');
      debugPrint('   CEP Origem: $cepOrigem');
      debugPrint('   CEP Destino: $cep');
      debugPrint('   Peso: ${peso / 1000}kg');
      debugPrint('   Dimensões: ${altura.toInt()}x${largura.toInt()}x${comprimento.toInt()} cm');
      debugPrint('   Valor: R\$ $valorDeclarado');
      debugPrint('   Token: ${token.substring(0, 10)}...');

      // Na web: Cloud Function evita CORS
      if (kIsWeb) {
        try {
          final functions = FirebaseFunctions.instanceFor(region: 'southamerica-east1');
          final callable = functions.httpsCallable('calcularFrenet');
          final result = await callable.call({
            'token': token,
            'cepOrigem': cepOrigem.replaceAll(RegExp(r'\D'), ''),
            'cepDestino': cep.replaceAll(RegExp(r'\D'), ''),
            'peso': peso / 1000,
            'altura': altura.toInt(),
            'largura': largura.toInt(),
            'comprimento': comprimento.toInt(),
            'valorProdutos': valorDeclarado,
          });
          final data = result.data as Map?;
          final shipping = data?['ShippingSevicesArray'] as List? ?? [];
          return _parsearOpcoesFrenet(shipping, config);
        } catch (e) {
          debugPrint('⚠️ [FRENET] Cloud Function erro (web) (type=${e.runtimeType})');
          return [];
        }
      }

      final requestBody = {
        'SellerCEP': cepOrigem,
        'RecipientCEP': cep,
        'ShipmentInvoiceValue': valorDeclarado,
        'ShippingItemArray': [
          {
            'Weight': peso / 1000, // Frenet usa kg
            'Length': comprimento.toInt(),
            'Height': altura.toInt(),
            'Width': largura.toInt(),
            'Quantity': 1,
          }
        ],
      };

      debugPrint('📤 [FRENET] Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse('$_frenetBaseUrl/shipping/quote'),
        headers: {
          'Content-Type': 'application/json',
          'token': token,
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      debugPrint('📥 [FRENET] Status: ${response.statusCode}');
      debugPrint('📥 [FRENET] Response: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final shipping = data['ShippingSevicesArray'] as List? ?? [];
        debugPrint('✅ [FRENET] ${shipping.length} opções retornadas');
        return _parsearOpcoesFrenet(shipping, config);
      } else {
        debugPrint('❌ [FRETE] Frenet erro ${response.statusCode}: ${response.body}');
        return [];
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [FRETE] Erro Frenet (type=${e.runtimeType})');
      debugPrint('   StackTrace: $stackTrace');
      return [];
    }
  }

  /// Correios API (simulação - requer contrato com Correios)
  static Future<List<Map<String, dynamic>>> _calcularCorreios({
    required Map<String, dynamic> config,
    required String cep,
    required double peso,
    required double valorDeclarado,
    required double altura,
    required double largura,
    required double comprimento,
  }) async {
    try {
      final usuario = (config['correios']?['usuario'] ?? '').toString();
      final senha = (config['correios']?['senha'] ?? '').toString();

      if (usuario.isEmpty || senha.isEmpty) {
        debugPrint('⚠️  [FRETE] Credenciais Correios não configuradas');
        return [];
      }

      // Correios Web Service (exemplo simplificado)
      // Na prática, precisa de contrato empresarial com Correios
      // cepOrigem disponível em config para futura integração com API real

      // Simulação: PAC e SEDEX
      // Para produção, integrar com: https://www.correios.com.br/enviar/precisa-de-ajuda/contrato-pos-pago

      debugPrint('⚠️  [FRETE] Correios requer contrato empresarial - usando simulação');

      // Valores simulados (substitua por API real quando tiver contrato)
      return [
        {
          'nome': 'PAC',
          'valor': 15.00 + (peso / 1000) * 2.0, // Simulação básica
          'prazo': 10,
          'empresa': 'Correios',
          'tipo': 'pac',
        },
        {
          'nome': 'SEDEX',
          'valor': 25.00 + (peso / 1000) * 3.0,
          'prazo': 3,
          'empresa': 'Correios',
          'tipo': 'sedex',
        },
      ];
    } catch (e) {
      debugPrint('❌ [FRETE] Erro Correios (type=${e.runtimeType})');
      return [];
    }
  }

  /// Valida CEP (apenas números, 8 dígitos)
  static bool validarCep(String cep) {
    return frete_helpers.freteValidarCep(cep);
  }

  /// Formata CEP (12345678 -> 12345-678)
  static String formatarCep(String cep) {
    return frete_helpers.freteFormatarCep(cep);
  }

  // ================================================================
  // 🎯 CRIAR PRÉ-PEDIDO NA PLATAFORMA DE FRETE
  // ================================================================

  /// Cria um pré-pedido/cotação na plataforma de frete.
  /// @deprecated O backend cria o carrinho via onPrePedidoShippingPreOrder.
  static Future<Map<String, dynamic>?> criarPrePedidoNaPlataforma({
    required String lojaId,
    required Map<String, dynamic> pedido,
    required Map<String, dynamic> cliente,
    required Map<String, dynamic> freteSelecionado,
  }) async {
    debugPrint(
      'ℹ️  [FRETE] criarPrePedidoNaPlataforma ignorado — use trigger backend',
    );
    return null;
  }

  /// @deprecated Implementação legada — não chamar API a partir do cliente.
  static Future<Map<String, dynamic>?> _criarPrePedidoNaPlataformaLegacy({
    required String lojaId,
    required Map<String, dynamic> config,
    required Map<String, dynamic> pedido,
    required Map<String, dynamic> cliente,
    required Map<String, dynamic> freteSelecionado,
  }) async {
    try {
      final token = (config['melhorEnvio']?['token'] ?? '').toString();
      if (token.isEmpty) {
        debugPrint('⚠️  [FRETE] Token Melhor Envio não configurado');
        return null;
      }

      // Extrair dados do cliente
      final endereco = cliente['endereco'] as Map<String, dynamic>? ?? {};
      final cepDestino = (endereco['cep'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      final nomeCliente = (cliente['nome'] ?? 'Cliente').toString();
      final telefoneCliente = (cliente['telefone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      final emailCliente = (cliente['email'] ?? '').toString();

      // Endereço destino: API exige ao menos 2 caracteres em address
      String ruaDestino = (endereco['rua'] ?? '').toString().trim();
      if (ruaDestino.length < 2) ruaDestino = 'S/N';

      // CEP de origem e dados do remetente (API Melhor Envio exige from.name, from.address, from.city)
      final cepOrigem = (config['cepOrigem'] ?? '01310100').toString().replaceAll(RegExp(r'[^0-9]'), '');
      // Dados do remetente (loja) - API exige from.name, from.address, from.city
      // CNPJ em from identifica loja como PJ e evita erro "CPF remetente e destinatário iguais"
      String fromName = 'Loja';
      String fromAddress = 'Centro';
      String fromCity = 'São Paulo';
      String fromDistrict = 'Centro';
      String fromState = 'SP';
      String fromCnpj = '';
      try {
        // Formatar lojaId/slug para exibição: nathy-pratas-e-folheados → Nathy Pratas e Folheados
        String formatarNomeLoja(String s) {
          if (s.isEmpty) return s;
          return s.replaceAll('-', ' ').split(' ').map((w) {
            if (w.isEmpty) return w;
            if (w.toLowerCase() == 'e' || w.toLowerCase() == 'de' || w.toLowerCase() == 'da' || w.toLowerCase() == 'do') return w.toLowerCase();
            return w[0].toUpperCase() + w.substring(1).toLowerCase();
          }).join(' ');
        }
        final lojaDoc = await FirebaseFirestore.instance.collection('lojas').doc(lojaId).get();
        if (lojaDoc.exists && lojaDoc.data() != null) {
          final data = lojaDoc.data()!;
          final nomeLoja = (data['name'] ?? data['nome'] ?? '').toString().trim();
          final slug = (data['slug'] ?? lojaId).toString().trim();
          if (nomeLoja.isNotEmpty && nomeLoja.toLowerCase() != 'minha loja' && nomeLoja.toLowerCase() != 'loja') {
            fromName = nomeLoja;
          } else {
            fromName = formatarNomeLoja(slug.isNotEmpty ? slug : lojaId);
          }
          final rodape = data['rodape'] as Map<String, dynamic>?;
          if (rodape != null) {
            final cnpj = (rodape['cnpj'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
            if (cnpj.length == 14) fromCnpj = cnpj;
          }
          if (fromCnpj.isEmpty) {
            for (final col in ['draft_config', 'config']) {
              final cfg = await FirebaseFirestore.instance
                  .collection('lojas').doc(lojaId).collection(col).doc('config').get();
              if (cfg.exists && cfg.data() != null) {
                final d = cfg.data()!;
                final rodapeD = d['rodape'] as Map<String, dynamic>?;
                final fc = d['frete_config'] as Map<String, dynamic>?;
                final cnpj = (rodapeD?['cnpj'] ?? fc?['cnpj'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
                if (cnpj.length == 14) { fromCnpj = cnpj; break; }
              }
            }
          }
        } else {
          fromName = formatarNomeLoja(lojaId);
        }
        final viaCep = await ViaCepService.buscar(cepOrigem);
        if (viaCep != null) {
          fromAddress = viaCep.logradouro.isNotEmpty ? viaCep.logradouro : 'Centro';
          fromCity = viaCep.localidade.isNotEmpty ? viaCep.localidade : 'São Paulo';
          fromDistrict = viaCep.bairro.isNotEmpty ? viaCep.bairro : 'Centro';
          fromState = viaCep.uf.isNotEmpty ? viaCep.uf : 'SP';
        }
      } catch (e) {
        debugPrint('⚠️  [MELHOR ENVIO] Fallback dados origem (type=${e.runtimeType})');
      }

      // Calcular dimensões e peso do pedido
      final itens = pedido['itens'] as List? ?? [];
      double pesoTotal = 0;
      double valorTotal = 0;

      for (final item in itens) {
        final qty = (item['quantidade'] as int?) ?? 1;
        final peso = ((item['peso'] as num?)?.toDouble() ?? 200.0); // peso padrão 200g por item
        pesoTotal += peso * qty;
        valorTotal += ((item['total'] as num?)?.toDouble() ?? 0);
      }

      // Dimensões padrão se não especificadas
      final altura = (pedido['altura'] as num?)?.toDouble() ?? 10.0;
      final largura = (pedido['largura'] as num?)?.toDouble() ?? 20.0;
      final comprimento = (pedido['comprimento'] as num?)?.toDouble() ?? 30.0;

      // Montar payload para Melhor Envio API
      // from: PJ com CNPJ evita erro "CPF remetente e destinatário iguais" quando lojista testa com próprio CPF
      final fromObj = <String, dynamic>{
        'name': fromName,
        'address': fromAddress,
        'number': 'S/N',
        'district': fromDistrict,
        'city': fromCity,
        'postal_code': cepOrigem,
        'state_abbr': fromState,
        'state_register': fromCnpj.isNotEmpty ? '' : '',
        'country_id': 'BR',
      };
      if (fromCnpj.isNotEmpty) {
        fromObj['company_document'] = fromCnpj;
        fromObj['document'] = '';
      } else {
        fromObj['company_document'] = '';
        fromObj['document'] = '';
      }
      final requestBody = {
        'service': freteSelecionado['service_id'] ?? 1,
        'from': fromObj,
        'to': {
          'name': nomeCliente,
          'phone': telefoneCliente,
          'email': emailCliente,
          'document': (cliente['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), ''),
          'company_document': '',
          'state_register': 'ISENTO',
          'postal_code': cepDestino,
          'address': ruaDestino,
          'number': endereco['numero'] ?? 'S/N',
          'complement': endereco['complemento'] ?? '',
          'district': endereco['bairro'] ?? '',
          'city': endereco['cidade'] ?? '',
          'state_abbr': endereco['estado'] ?? 'SP',
          'country_id': 'BR',
        },
        'products': [
          {
            'name': 'Pedido ${pedido['id'] ?? 'N/A'}',
            'quantity': 1,
            'unitary_value': valorTotal,
          }
        ],
        'volumes': [
          {
            'height': altura.toInt(),
            'width': largura.toInt(),
            'length': comprimento.toInt(),
            'weight': pesoTotal / 1000, // kg
          }
        ],
        'options': {
          'insurance_value': valorTotal,
          'receipt': false,
          'own_hand': false,
          'collect': false,
          'reverse': false,
          'non_commercial': true,
        },
      };

      debugPrint('📤 [MELHOR ENVIO] Criando pedido no carrinho...');
      debugPrint('   Payload: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse('$_melhorEnvioBaseUrl/me/cart'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'User-Agent': _melhorEnvioUserAgent,
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 20));

      debugPrint('📥 [MELHOR ENVIO] Status: ${response.statusCode}');
      debugPrint('📥 [MELHOR ENVIO] Response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        debugPrint('✅ [MELHOR ENVIO] Pedido adicionado ao carrinho!');
        debugPrint('   ID: ${data['id']}');
        debugPrint('   Protocol: ${data['protocol']}');

        return {
          'success': true,
          'plataforma': 'melhor_envio',
          'cart_id': data['id'],
          'protocol': data['protocol'],
          'message': 'Pedido adicionado ao carrinho do Melhor Envio',
          'instrucoes': 'Acesse https://melhorenvio.com.br/painel/carrinho para finalizar',
        };
      } else {
        debugPrint('❌ [MELHOR ENVIO] Erro ${response.statusCode}: ${response.body}');
        String errorMsg = 'Erro ao adicionar ao carrinho: ${response.statusCode}';
        String? instrucoes;
        try {
          final errBody = jsonDecode(response.body);
          final err = errBody['error'] ?? errBody['message'];
          if (err != null) {
            final str = err is String ? err : (err is Map ? (err['message'] ?? err.values.join(', ')) : err.toString());
            errorMsg = str.toString();
            if (str.toString().toLowerCase().contains('cpf') && str.toString().toLowerCase().contains('iguais')) {
              instrucoes = 'O CPF do cliente é igual ao da conta Melhor Envio. '
                  'Cadastre o CNPJ da loja em Config > Rodapé para envios como pessoa jurídica, '
                  'ou crie o envio manualmente em melhorenvio.com.br/painel/carrinho';
            }
          }
        } catch (_) {}
        return {
          'success': false,
          'error': errorMsg,
          'plataforma': 'melhor_envio',
          if (instrucoes != null) 'instrucoes': instrucoes,
        };
      }
    } catch (e, st) {
      debugPrint('❌ [MELHOR ENVIO] Erro ao criar pré-pedido (type=${e.runtimeType})');
      debugPrint('   StackTrace: $st');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Cria pedido no carrinho da SuperFrete (igual ao Melhor Envio)
  static Future<Map<String, dynamic>?> _criarPrePedidoSuperFrete({
    required String lojaId,
    required Map<String, dynamic> config,
    required Map<String, dynamic> pedido,
    required Map<String, dynamic> cliente,
    required Map<String, dynamic> freteSelecionado,
  }) async {
    try {
      if (!_isSuperFreteConfigured(config)) {
        debugPrint('⚠️  [FRETE] SuperFrete não configurada com segurança');
        return null;
      }

      final servicoId = freteSelecionado['servico_id'];
      if (servicoId == null) {
        debugPrint('⚠️  [FRETE] SuperFrete: servico_id não encontrado na opção selecionada');
        return {
          'success': false,
          'plataforma': 'superfrete',
          'error': 'Serviço de frete inválido. Recalcule o frete e tente novamente.',
        };
      }

      final endereco = cliente['endereco'] as Map<String, dynamic>? ?? {};
      final cepDestino = (endereco['cep'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      final nomeCliente = (cliente['nome'] ?? 'Cliente').toString();
      final telefoneCliente = (cliente['telefone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      final emailCliente = (cliente['email'] ?? '').toString();
      String ruaDestino = (endereco['rua'] ?? '').toString().trim();
      if (ruaDestino.length < 2) ruaDestino = 'S/N';

      final cepOrigem = (config['cepOrigem'] ?? '01310100').toString().replaceAll(RegExp(r'[^0-9]'), '');
      String fromAddress = 'Centro';
      String fromCity = 'São Paulo';
      String fromState = 'SP';
      String fromDistrict = 'Centro';
      try {
        final viaCep = await ViaCepService.buscar(cepOrigem);
        if (viaCep != null) {
          fromAddress = viaCep.logradouro.isNotEmpty ? viaCep.logradouro : 'Centro';
          fromCity = viaCep.localidade.isNotEmpty ? viaCep.localidade : 'São Paulo';
          fromDistrict = viaCep.bairro.isNotEmpty ? viaCep.bairro : 'Centro';
          fromState = viaCep.uf.isNotEmpty ? viaCep.uf : 'SP';
        }
      } catch (_) {}

      final itens = pedido['itens'] as List? ?? [];
      double pesoTotal = 0;
      double valorTotal = 0;
      for (final item in itens) {
        final qty = (item['quantidade'] as int?) ?? 1;
        final peso = ((item['peso'] as num?)?.toDouble() ?? 200.0);
        pesoTotal += peso * qty;
        valorTotal += ((item['total'] as num?)?.toDouble() ?? 0);
      }
      final altura = (pedido['altura'] as num?)?.toDouble() ?? 10.0;
      final largura = (pedido['largura'] as num?)?.toDouble() ?? 20.0;
      final comprimento = (pedido['comprimento'] as num?)?.toDouble() ?? 30.0;

      final from = <String, dynamic>{
        'postal_code': cepOrigem,
        'address': fromAddress,
        'city': fromCity,
        'state': fromState,
        'district': fromDistrict,
        'number': 'S/N',
      };
      final to = <String, dynamic>{
        'name': nomeCliente,
        'phone': telefoneCliente,
        'email': emailCliente,
        'document': (cliente['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), ''),
        'postal_code': cepDestino,
        'address': ruaDestino,
        'number': (endereco['numero'] ?? 'S/N').toString(),
        'complement': (endereco['complemento'] ?? '').toString(),
        'district': (endereco['bairro'] ?? '').toString(),
        'city': (endereco['cidade'] ?? '').toString(),
        'state': (endereco['estado'] ?? 'SP').toString(),
      };
      final package = <String, dynamic>{
        'height': altura.toInt().clamp(1, 999),
        'width': largura.toInt().clamp(1, 999),
        'length': comprimento.toInt().clamp(1, 999),
        'weight': (pesoTotal / 1000).toStringAsFixed(2),
      };

      final resultado = await SuperFreteService.criarEnvioNoCarrinho(
        lojaId: lojaId,
        servicoId: servicoId,
        from: from,
        to: to,
        package: package,
        valorDeclarado: valorTotal > 0 ? valorTotal : 10.0,
        pedidoRef: (pedido['id'] ?? '').toString(),
      );

      if (resultado['sucesso'] == true) {
        debugPrint('✅ [SUPERFRETE] Pedido adicionado ao carrinho');
        return {
          'success': true,
          'plataforma': 'superfrete',
          'cart_id': resultado['id'],
          'protocol': resultado['protocol'],
          'message': resultado['message'] ?? 'Pedido adicionado ao carrinho da SuperFrete',
          'instrucoes': 'Acesse https://web.superfrete.com para finalizar e gerar a etiqueta',
        };
      }

      return {
        'success': false,
        'plataforma': 'superfrete',
        'error': (resultado['erro'] ?? 'Erro ao adicionar ao carrinho').toString(),
        'instrucoes': 'Confira os dados do pedido e do CEP. Se persistir, crie o envio manualmente em web.superfrete.com',
      };
    } catch (e) {
      debugPrint('❌ [SUPERFRETE] Erro ao criar pré-pedido (type=${e.runtimeType})');
      return {
        'success': false,
        'plataforma': 'superfrete',
        'error': e.toString(),
      };
    }
  }

  /// Busca pedidos pendentes no carrinho do Melhor Envio
  static Future<List<Map<String, dynamic>>> buscarPedidosPendentesMelhorEnvio({
    required String lojaId,
  }) async {
    try {
      final config = await _buscarConfigFrete(lojaId);
      final token = (config['melhorEnvio']?['token'] ?? '').toString();

      if (token.isEmpty) {
        debugPrint('⚠️  [FRETE] Token Melhor Envio não configurado');
        return [];
      }

      final response = await http.get(
        Uri.parse('$_melhorEnvioBaseUrl/me/cart'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'User-Agent': _melhorEnvioUserAgent,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        debugPrint('✅ [MELHOR ENVIO] ${data.length} pedidos no carrinho');
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        debugPrint('❌ [MELHOR ENVIO] Erro ao buscar carrinho: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('❌ [MELHOR ENVIO] Erro ao buscar carrinho (type=${e.runtimeType})');
      return [];
    }
  }
}

/// Resultado do cálculo de frete com o provedor selecionado.
class FreteCalculoResultado {
  const FreteCalculoResultado({
    required this.provider,
    required this.opcoes,
    this.erroProvedor,
  });

  final String provider;
  final List<Map<String, dynamic>> opcoes;

  /// Mensagem segura para o cliente quando o provedor selecionado falhou.
  final String? erroProvedor;
}

class FreteCotacaoPedido {
  const FreteCotacaoPedido({
    required this.config,
    required this.lojaId,
    required this.cep,
    required this.peso,
    required this.valorDeclarado,
    required this.altura,
    required this.largura,
    required this.comprimento,
    this.itensCotacao,
  });

  final Map<String, dynamic> config;
  final String lojaId;
  final String cep;
  final double peso;
  final double valorDeclarado;
  final double altura;
  final double largura;
  final double comprimento;
  final List<Map<String, dynamic>>? itensCotacao;
}

typedef FreteCotador = Future<List<Map<String, dynamic>>> Function(FreteCotacaoPedido pedido);

class FreteCotadores {
  const FreteCotadores({
    required this.melhorEnvio,
    required this.superFrete,
    required this.frenet,
    required this.correios,
  });

  static const FreteCotadores padrao = FreteCotadores(
    melhorEnvio: FreteService._cotarMelhorEnvio,
    superFrete: FreteService._cotarSuperFrete,
    frenet: FreteService._cotarFrenet,
    correios: FreteService._cotarCorreios,
  );

  final FreteCotador melhorEnvio;
  final FreteCotador superFrete;
  final FreteCotador frenet;
  final FreteCotador correios;

  FreteCotador? para(String provider) {
    switch (provider) {
      case ShippingProviderSelection.melhorEnvio:
        return melhorEnvio;
      case ShippingProviderSelection.superFrete:
        return superFrete;
      case ShippingProviderSelection.frenet:
        return frenet;
      case ShippingProviderSelection.correios:
        return correios;
      default:
        return null;
    }
  }
}
