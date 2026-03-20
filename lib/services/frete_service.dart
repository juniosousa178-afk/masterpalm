// lib/services/frete_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'superfrete_service.dart';
import 'via_cep_service.dart';
import 'frete_helpers.dart' as frete_helpers;

/// Serviço unificado para cálculo de frete
/// Suporta: Manual, Correios, Melhor Envio, SuperFrete, Frenet
class FreteService {
  static const String _melhorEnvioBaseUrl = 'https://melhorenvio.com.br/api/v2';
  static const String _frenetBaseUrl = 'https://api.frenet.com.br';

  /// User-Agent obrigatório pela documentação Melhor Envio
  static const String _melhorEnvioUserAgent = 'MasterPalm (contato@mastepalm.com.br)';

  /// Calcula frete para um pedido consultando TODAS as plataformas cadastradas
  ///
  /// Parâmetros:
  /// - [lojaId]: ID da loja
  /// - [cep]: CEP de destino (somente números)
  /// - [peso]: Peso total em gramas
  /// - [valorDeclarado]: Valor total dos produtos em reais
  /// - [altura]: Altura total em cm (padrão: 10)
  /// - [largura]: Largura total em cm (padrão: 20)
  /// - [comprimento]: Comprimento total em cm (padrão: 30)
  ///
  /// Retorna: List<Map> com TODAS as opções de frete de TODAS as plataformas:
  /// ```dart
  /// [
  ///   {
  ///     'nome': 'PAC',
  ///     'valor': 25.50,
  ///     'prazo': 10,
  ///     'empresa': 'Correios',
  ///     'plataforma': 'melhor_envio'
  ///   },
  ///   {
  ///     'nome': 'SEDEX',
  ///     'valor': 35.00,
  ///     'prazo': 3,
  ///     'empresa': 'Correios',
  ///     'plataforma': 'frenet'
  ///   }
  /// ]
  /// ```
  static Future<List<Map<String, dynamic>>> calcularFrete({
    required String lojaId,
    required String cep,
    required double peso,
    required double valorDeclarado,
    double altura = 10,
    double largura = 20,
    double comprimento = 30,
  }) async {
    try {
      // 1. Buscar configuração de frete da loja
      final config = await _buscarConfigFrete(lojaId);

      debugPrint('🚚 [FRETE] Calculando frete para CEP: $cep');
      debugPrint('📦 [FRETE] Consultando TODAS as plataformas cadastradas...');

      // Lista para armazenar todas as opções de todas as plataformas
      List<Map<String, dynamic>> todasOpcoes = [];

      // 2. Verificar quais plataformas estão configuradas e consultar TODAS

      // MELHOR ENVIO
      final tokenMelhorEnvio = (config['melhorEnvio']?['token'] ?• '').toString();
      if (tokenMelhorEnvio.isNotEmpty) {
        debugPrint('🔄 [FRETE] Consultando Melhor Envio...');
        try {
          final opcoesMelhorEnvio = await _calcularMelhorEnvio(
            config: config,
            cep: cep,
            peso: peso,
            valorDeclarado: valorDeclarado,
            altura: altura,
            largura: largura,
            comprimento: comprimento,
          );

          // Adicionar identificador da plataforma
          for (var opcao in opcoesMelhorEnvio) {
            opcao['plataforma'] = 'melhor_envio';
          }

          todasOpcoes.addAll(opcoesMelhorEnvio);
          debugPrint('✅ [FRETE] Melhor Envio: ${opcoesMelhorEnvio.length} opções');
          debugPrint('🔍 [DEBUG] Primeira opção após add plataforma: ${opcoesMelhorEnvio.isNotEmpty • opcoesMelhorEnvio[0] : "vazio"}');
        } catch (e) {
          debugPrint('⚠️  [FRETE] Erro ao consultar Melhor Envio (type=${e.runtimeType})');
        }
      }

      // FRENET
      final tokenFrenet = (config['frenet']?['token'] ?• '').toString();
      if (tokenFrenet.isNotEmpty) {
        debugPrint('🔄 [FRETE] Consultando Frenet...');
        try {
          final opcoesFrenet = await _calcularFrenet(
            config: config,
            cep: cep,
            peso: peso,
            valorDeclarado: valorDeclarado,
            altura: altura,
            largura: largura,
            comprimento: comprimento,
          );

          // Adicionar identificador da plataforma
          for (var opcao in opcoesFrenet) {
            opcao['plataforma'] = 'frenet';
          }

          todasOpcoes.addAll(opcoesFrenet);
          debugPrint('✅ [FRETE] Frenet: ${opcoesFrenet.length} opções');
        } catch (e) {
          debugPrint('⚠️  [FRETE] Erro ao consultar Frenet (type=${e.runtimeType})');
        }
      }

      // CORREIOS
      final usuarioCorreios = (config['correios']?['usuario'] ?• '').toString();
      final senhaCorreios = (config['correios']?['senha'] ?• '').toString();
      if (usuarioCorreios.isNotEmpty && senhaCorreios.isNotEmpty) {
        debugPrint('🔄 [FRETE] Consultando Correios...');
        try {
          final opcoesCorreios = await _calcularCorreios(
            config: config,
            cep: cep,
            peso: peso,
            valorDeclarado: valorDeclarado,
            altura: altura,
            largura: largura,
            comprimento: comprimento,
          );

          // Adicionar identificador da plataforma
          for (var opcao in opcoesCorreios) {
            opcao['plataforma'] = 'correios';
          }

          todasOpcoes.addAll(opcoesCorreios);
          debugPrint('✅ [FRETE] Correios: ${opcoesCorreios.length} opções');
        } catch (e) {
          debugPrint('⚠️  [FRETE] Erro ao consultar Correios (type=${e.runtimeType})');
        }
      }

      // SUPERFRETE
      final tokenSuperFrete = (config['superfrete']?['token'] ?• '').toString();
      final superFreteSandbox = config['superfrete']?['sandbox'] == true;
      if (tokenSuperFrete.isNotEmpty) {
        debugPrint('🔄 [FRETE] SuperFrete: sandbox=$superFreteSandbox (config["superfrete"]=${config['superfrete']})');
        try {
          Map<String, dynamic> resultado;
          final cepOrigem = (config['cepOrigem'] ?• '01310100').toString().replaceAll(RegExp(r'\D'), '');
          final cepDestino = cep.replaceAll(RegExp(r'\D'), '');
          final pesoFinal = peso < 300 • 300.0 : peso;

          if (kIsWeb) {
            final functions = FirebaseFunctions.instanceFor(region: 'southamerica-east1');
            final callable = functions.httpsCallable('calcularSuperFrete');
            final res = await callable.call({
              'token': tokenSuperFrete,
              'cepOrigem': cepOrigem,
              'cepDestino': cepDestino,
              'peso': pesoFinal,
              'altura': altura < 1 • 2 : altura,
              'largura': largura < 1 • 11 : largura,
              'comprimento': comprimento < 1 • 16 : comprimento,
              'valorDeclarado': valorDeclarado > 0 • valorDeclarado : 10.0,
            });
            final data = res.data as Map?;
            resultado = {
              'sucesso': data?['sucesso'] == true,
              'opcoes': data?['opcoes'] ?• [],
              if (data?['erro'] != null) 'erro': data!['erro'],
            };
          } else {
            resultado = await SuperFreteService.calcularFrete(
              token: tokenSuperFrete,
              cepOrigem: cepOrigem,
              cepDestino: cepDestino,
              peso: pesoFinal,
              valorDeclarado: valorDeclarado > 0 • valorDeclarado : 10.0,
              altura: altura < 1 • 2 : altura,
              largura: largura < 1 • 11 : largura,
              comprimento: comprimento < 1 • 16 : comprimento,
              useSandbox: superFreteSandbox,
            );
          }

          if (resultado['sucesso'] == true) {
            final opcoesRaw = resultado['opcoes'] as List• ?• [];
            final opcoesSuperFrete = opcoesRaw.map<Map<String, dynamic>>((o) {
              return {
                'nome': (o['nome'] ?• 'SuperFrete').toString(),
                'valor': (o['preco'] as num?)?.toDouble() ?• 0.0,
                'prazo': (o['prazo'] as num?)?.toInt() ?• 0,
                'empresa': (o['empresa'] ?• 'SuperFrete').toString(),
                'plataforma': 'superfrete',
                'servico_id': o['servico_id'],
              };
            }).toList();

            todasOpcoes.addAll(opcoesSuperFrete);
            debugPrint('✅ [FRETE] SuperFrete: ${opcoesSuperFrete.length} opções');
          } else {
            debugPrint('⚠️  [FRETE] SuperFrete: ${resultado['erro']}');
          }
        } catch (e) {
          debugPrint('⚠️  [FRETE] Erro ao consultar SuperFrete (type=${e.runtimeType})');
        }
      }

      // FRETES MANUAIS (sempre incluir se existirem)
      final manualFretes = config['manualFretes'] as List• ?• [];
      if (manualFretes.isNotEmpty) {
        debugPrint('🔄 [FRETE] Adicionando fretes manuais...');
        final opcoesManual = _calcularManual(config);

        // Adicionar identificador da plataforma
        for (var opcao in opcoesManual) {
          opcao['plataforma'] = 'manual';
        }

        todasOpcoes.addAll(opcoesManual);
        debugPrint('✅ [FRETE] Manual: ${opcoesManual.length} opções');
      }

      // 3. Se nenhuma plataforma retornou opções, usar fallback
      if (todasOpcoes.isEmpty) {
        debugPrint('⚠️  [FRETE] Nenhuma opção de frete disponível, usando padrão');
        final opcoesPadrao = _fretePadrao();
        for (var opcao in opcoesPadrao) {
          opcao['plataforma'] = 'manual';
        }
        todasOpcoes = opcoesPadrao;
      }

      // 4. Debug antes de ordenar
      debugPrint('🔍 [DEBUG] Antes de ordenar - ${todasOpcoes.length} opções:');
      for (int i = 0; i < (todasOpcoes.length > 5 • 5 : todasOpcoes.length); i++) {
        debugPrint('   [$i] ${todasOpcoes[i]['nome']} - valor: ${todasOpcoes[i]['valor']} (${todasOpcoes[i]['valor'].runtimeType})');
      }

      // Ordenar por valor (mais barato primeiro)
      todasOpcoes.sort((a, b) {
        final valorA = (a['valor'] as num?)?.toDouble() ?• 999999;
        final valorB = (b['valor'] as num?)?.toDouble() ?• 999999;
        return valorA.compareTo(valorB);
      });

      debugPrint('🎉 [FRETE] TOTAL: ${todasOpcoes.length} opções de frete disponíveis');
      debugPrint('   Melhor opção: ${todasOpcoes.first['nome']} - R\$ ${todasOpcoes.first['valor']}');

      return todasOpcoes;
    } catch (e) {
      debugPrint('❌ [FRETE] Erro ao calcular frete (type=${e.runtimeType})');
      // Fallback: retorna fretes padrão
      return _fretePadrao().map((opcao) {
        opcao['plataforma'] = 'manual';
        return opcao;
      }).toList();
    }
  }

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
      Map<String, dynamic> config = docFretes.exists • (docFretes.data() ?• {}) : {};
      debugPrint('📄 [FRETE] config/fretes existe=${docFretes.exists}, melhorEnvio.token=${(config['melhorEnvio']?['token'] ?• '').toString().isNotEmpty}, superfrete.token=${(config['superfrete']?['token'] ?• '').toString().isNotEmpty}');

      // Helper para aplicar tokens de um Map (config ou draft)
      void applyTokensFrom(Map<String, dynamic> data) {
        final fc = data['frete_config'] as Map<String, dynamic>?;
        final rootME = (data['melhorEnvioToken'] ?• data['melhor_envio_token'] ?• '').toString().trim();
        final rootSF = (data['superfreteToken'] ?• data['superfrete_token'] ?• '').toString().trim();
        final tokenME = (config['melhorEnvio']?['token'] ?• '').toString().trim();
        final tokenSF = (config['superfrete']?['token'] ?• '').toString().trim();
        if (tokenME.isEmpty && rootME.isNotEmpty) {
          config = Map<String, dynamic>.from(config);
          config['melhorEnvio'] = {'token': rootME};
        }
        if (tokenSF.isEmpty && rootSF.isNotEmpty) {
          config = Map<String, dynamic>.from(config);
          final sf = config['superfrete'] as Map<String, dynamic>• ?• {};
          config['superfrete'] = Map<String, dynamic>.from(sf)..['token'] = rootSF;
        }
        if (fc != null) {
          if (tokenME.isEmpty) {
            final t = (fc['melhor_envio_token'] ?• '').toString().trim();
            if (t.isNotEmpty) {
              config = Map<String, dynamic>.from(config);
              config['melhorEnvio'] = {'token': t};
            }
          }
          if (tokenSF.isEmpty) {
            final t = (fc['superfrete_token'] ?• '').toString().trim();
            if (t.isNotEmpty) {
              config = Map<String, dynamic>.from(config);
              final sf = (config['superfrete'] as Map<String, dynamic>?) ?• {};
              config['superfrete'] = Map<String, dynamic>.from(sf)
                ..['token'] = t
                ..['sandbox'] = fc['superfrete_sandbox'] == true;
            }
          } else if (fc['superfrete_sandbox'] != null) {
            config = Map<String, dynamic>.from(config);
            final sf = Map<String, dynamic>.from(config['superfrete'] as Map• ?• {});
            sf['sandbox'] = fc['superfrete_sandbox'] == true;
            config['superfrete'] = sf;
          }
          final cepO = (fc['cep_origem'] ?• fc['cepOrigem'] ?• '').toString().trim();
          if (cepO.isNotEmpty && (config['cepOrigem'] ?• '').toString().trim().isEmpty) {
            config = Map<String, dynamic>.from(config);
            config['cepOrigem'] = cepO;
          }
          final frenetT = (fc['frenet_token'] ?• '').toString().trim();
          if (frenetT.isNotEmpty && (config['frenet']?['token'] ?• '').toString().trim().isEmpty) {
            config = Map<String, dynamic>.from(config);
            config['frenet'] = {'token': frenetT};
          }
          final corUser = (fc['correios_user'] ?• '').toString().trim();
          final corSenha = (fc['correios_senha'] ?• '').toString().trim();
          if (corUser.isNotEmpty && (config['correios']?['usuario'] ?• '').toString().trim().isEmpty) {
            config = Map<String, dynamic>.from(config);
            config['correios'] = {'usuario': corUser, 'senha': corSenha};
          }
        }
        final manualList = config['manualFretes'] as List• ?• [];
        if (manualList.isEmpty && data['fretes'] is List && (data['fretes'] as List).isNotEmpty) {
          config = Map<String, dynamic>.from(config);
          config['manualFretes'] = data['fretes'];
        }
      }

      // Fallback 1: config/config
      final tokenME = (config['melhorEnvio']?['token'] ?• '').toString().trim();
      final tokenSF = (config['superfrete']?['token'] ?• '').toString().trim();
      if (tokenME.isEmpty || tokenSF.isEmpty) {
        final docConfig = await base.doc('config').get();
        if (docConfig.exists && docConfig.data() != null) {
          applyTokensFrom(docConfig.data()!);
          if (((config['melhorEnvio']?['token'] ?• '').toString().isNotEmpty) ||
              ((config['superfrete']?['token'] ?• '').toString().isNotEmpty)) {
            debugPrint('✅ [FRETE] Tokens obtidos de config/config');
          }
        }
        // Fallback 2: draft_config/config (quando admin salvou em Fretes mas não publicou)
        final tokenME2 = (config['melhorEnvio']?['token'] ?• '').toString().trim();
        final tokenSF2 = (config['superfrete']?['token'] ?• '').toString().trim();
        if (tokenME2.isEmpty || tokenSF2.isEmpty) {
          final draftRef = FirebaseFirestore.instance
              .collection('lojas')
              .doc(docId)
              .collection('draft_config')
              .doc('config');
          final docDraft = await draftRef.get();
          if (docDraft.exists && docDraft.data() != null) {
            applyTokensFrom(docDraft.data()!);
            if (((config['melhorEnvio']?['token'] ?• '').toString().isNotEmpty) ||
                ((config['superfrete']?['token'] ?• '').toString().isNotEmpty)) {
              debugPrint('✅ [FRETE] Tokens obtidos de draft_config/config');
            }
          }
        }
        // Fallback 3: doc raiz da loja (config/config às vezes espelhado aqui)
        final tokenME3 = (config['melhorEnvio']?['token'] ?• '').toString().trim();
        final tokenSF3 = (config['superfrete']?['token'] ?• '').toString().trim();
        if (tokenME3.isEmpty || tokenSF3.isEmpty) {
          final lojaDocRef = await FirebaseFirestore.instance.collection('lojas').doc(docId).get();
          if (lojaDocRef.exists && lojaDocRef.data() != null) {
            applyTokensFrom(lojaDocRef.data()!);
            if (((config['melhorEnvio']?['token'] ?• '').toString().isNotEmpty) ||
                ((config['superfrete']?['token'] ?• '').toString().isNotEmpty)) {
              debugPrint('✅ [FRETE] Tokens obtidos do doc raiz da loja');
            }
          }
        }
      }

      if (config.isEmpty) {
        debugPrint('⚠️  [FRETE] Config não encontrada, usando manual');
        return {'provider': 'manual', 'manualFretes': []};
      }

      final hasME = (config['melhorEnvio']?['token'] ?• '').toString().trim().isNotEmpty;
      final hasSF = (config['superfrete']?['token'] ?• '').toString().trim().isNotEmpty;
      debugPrint('📤 [FRETE] Retornando config: MelhorEnvio=$hasME, SuperFrete=$hasSF, cepOrigem=${(config['cepOrigem'] ?• '').toString().isNotEmpty}');
      return config;
    } catch (e, st) {
      debugPrint('❌ [FRETE] Erro ao buscar config (type=${e.runtimeType})');
      debugPrint('❌ [FRETE] Stack: $st');
      return {'provider': 'manual', 'manualFretes': []};
    }
  }

  /// Fretes manuais/fixos
  static List<Map<String, dynamic>> _calcularManual(Map<String, dynamic> config) {
    final manualFretes = config['manualFretes'] as List• ?• [];

    if (manualFretes.isEmpty) {
      debugPrint('⚠️  [FRETE] Nenhum frete manual configurado, usando padrão');
      return _fretePadrao();
    }

    return manualFretes.map<Map<String, dynamic>>((f) {
      final nome = (f['nome'] ?• 'Frete').toString();
      final valor = (f['valor'] is num)
          • (f['valor'] as num).toDouble()
          : double.tryParse('${f['valor']}') ?• 0.0;

      return {
        'nome': nome,
        'valor': valor,
        'prazo': 0,
        'empresa': 'Loja',
        'tipo': f['tipo'] ?• 'manual', // ✅ ADICIONA O TIPO
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

  static List<Map<String, dynamic>> _parsearOpcoesMelhorEnvio(
    List<dynamic> data,
    Map<String, dynamic> config,
  ) {
    final opcoes = data.map<Map<String, dynamic>>((item) {
      final nome = item['name'] ?• 'Melhor Envio';
      final priceRaw = item['price'];
      final deliveryTime = item['delivery_time'];
      final companyName = item['company']?['name'] ?• 'Melhor Envio';

      double valor = 0.0;
      if (priceRaw is num) {
        valor = priceRaw.toDouble();
      } else if (priceRaw is String) {
        valor = double.tryParse(priceRaw) ?• 0.0;
      }

      final rawId = item['id'];
      final serviceId = rawId is num • rawId.toInt() : (rawId != null • int.tryParse(rawId.toString()) : null);

      return {
        'nome': nome,
        'valor': valor,
        'prazo': (deliveryTime is num) • deliveryTime.toInt() : 0,
        'empresa': companyName,
        'tipo': nome.toString().toLowerCase().replaceAll(' ', '_'),
        if (serviceId != null) 'service_id': serviceId,
      };
    }).toList();

    debugPrint('✅ [MELHOR_ENVIO] Processou ${opcoes.length} opções');
    return opcoes;
  }

  /// Melhor Envio API
  /// Na web (navegador) usa Cloud Function para evitar CORS.
  static Future<List<Map<String, dynamic>>> _calcularMelhorEnvio({
    required Map<String, dynamic> config,
    required String cep,
    required double peso,
    required double valorDeclarado,
    required double altura,
    required double largura,
    required double comprimento,
  }) async {
    try {
      final token = (config['melhorEnvio']?['token'] ?• '').toString();
      if (token.isEmpty) {
        debugPrint('⚠️  [FRETE] Token Melhor Envio não configurado');
        return _calcularManual(config);
      }

      final cepOrigem = (config['cepOrigem'] ?• '01310100').toString().replaceAll(RegExp(r'\D'), '');
      final cepDestino = cep.replaceAll(RegExp(r'\D'), '');

      final alturaFinal = altura < 1 • 2 : altura;
      final larguraFinal = largura < 1 • 11 : largura;
      final comprimentoFinal = comprimento < 1 • 16 : comprimento;
      final pesoFinal = peso < 300 • 300 : peso;
      final pesoKg = pesoFinal / 1000;

      debugPrint('📏 [MELHOR_ENVIO] Dimensões: ${alturaFinal}x${larguraFinal}x${comprimentoFinal}cm, Peso: ${pesoFinal}g');

      // Na web: Cloud Function evita CORS (APIs bloqueiam requisições cross-origin no navegador)
      if (kIsWeb) {
        try {
          final functions = FirebaseFunctions.instanceFor(region: 'southamerica-east1');
          final callable = functions.httpsCallable('calcularMelhorEnvio');
          final result = await callable.call({
            'token': token,
            'origem': cepOrigem,
            'destino': cepDestino,
            'peso': pesoKg,
            'altura': alturaFinal.toInt(),
            'largura': larguraFinal.toInt(),
            'comprimento': comprimentoFinal.toInt(),
            'valorProdutos': valorDeclarado > 0 • valorDeclarado : 10.0,
            'servico': '1,2,3,4,17', // PAC, SEDEX, Jadlog .Package, .Com, Mini Envios (17)
          });
          final data = result.data as Map?;
          final servicos = data?['servicos'];
          final list = servicos is List • servicos : <dynamic>[];
          return _parsearOpcoesMelhorEnvio(list, config);
        } catch (e) {
          debugPrint('⚠️ [MELHOR_ENVIO] Cloud Function erro (web) (type=${e.runtimeType})');
          return _calcularManual(config);
        }
      }

      final response = await http.post(
        Uri.parse('$_melhorEnvioBaseUrl/me/shipment/calculate'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'User-Agent': _melhorEnvioUserAgent,
        },
        body: jsonEncode({
          'from': {'postal_code': cepOrigem},
          'to': {'postal_code': cepDestino},
          'package': {
            'height': alturaFinal.toInt(),
            'width': larguraFinal.toInt(),
            'length': comprimentoFinal.toInt(),
            'weight': pesoFinal / 1000, // Melhor Envio usa kg
          },
          'services': '1,2,3,4,17', // PAC, SEDEX, Jadlog .Package, .Com, Mini Envios (17)
          'options': {
            'insurance_value': valorDeclarado > 0 • valorDeclarado : 10.0,
            'receipt': false,
            'own_hand': false,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      final respBody = response.body.trim().toLowerCase();
      if (respBody.startsWith('<!') || respBody.startsWith('<html')) {
        debugPrint('❌ [MELHOR_ENVIO] Resposta HTML em vez de JSON. Verifique token e URL da API.');
        return _calcularManual(config);
      }

      if (response.statusCode == 200) {
        final rawData = jsonDecode(response.body);
        final data = rawData is List • rawData : <dynamic>[];
        if (data.isEmpty && rawData is Map) {
          debugPrint('❌ [MELHOR_ENVIO] API retornou objeto de erro: $rawData');
          return _calcularManual(config);
        }

        debugPrint('✅ [MELHOR_ENVIO] API retornou ${data.length} opções');
        return _parsearOpcoesMelhorEnvio(data, config);
      } else {
        debugPrint('❌ [FRETE] Melhor Envio erro ${response.statusCode}: ${response.body}');
        return _calcularManual(config);
      }
    } catch (e) {
      debugPrint('❌ [FRETE] Erro Melhor Envio (type=${e.runtimeType})');
      return _calcularManual(config);
    }
  }

  static List<Map<String, dynamic>> _parsearOpcoesFrenet(
    List<dynamic> shipping,
    Map<String, dynamic> config,
  ) {
    if (shipping.isEmpty) return _calcularManual(config);

    return shipping
        .map<Map<String, dynamic>?>((item) {
          if (item['Error'] == true) return null;
          final nome = item['ServiceDescription'] ?• 'Frenet';
          final valorRaw = item['ShippingPrice'];
          final valor = valorRaw is num
              • valorRaw.toDouble()
              : double.tryParse(valorRaw?.toString() ?• '0') ?• 0.0;
          final prazoRaw = item['DeliveryTime'];
          final prazo = prazoRaw is num
              • prazoRaw.toInt()
              : int.tryParse(prazoRaw?.toString() ?• '0') ?• 0;
          final empresa = item['Carrier'] ?• 'Frenet';
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
      final token = (config['frenet']?['token'] ?• '').toString();
      if (token.isEmpty) {
        debugPrint('⚠️  [FRETE] Token Frenet não configurado');
        return _calcularManual(config);
      }

      final cepOrigem = (config['cepOrigem'] ?• '01310100').toString();

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
          final shipping = data?['ShippingSevicesArray'] as List• ?• [];
          return _parsearOpcoesFrenet(shipping, config);
        } catch (e) {
          debugPrint('⚠️ [FRENET] Cloud Function erro (web) (type=${e.runtimeType})');
          return _calcularManual(config);
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
        final shipping = data['ShippingSevicesArray'] as List• ?• [];
        debugPrint('✅ [FRENET] ${shipping.length} opções retornadas');
        return _parsearOpcoesFrenet(shipping, config);
      } else {
        debugPrint('❌ [FRETE] Frenet erro ${response.statusCode}: ${response.body}');
        return _calcularManual(config);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [FRETE] Erro Frenet (type=${e.runtimeType})');
      debugPrint('   StackTrace: $stackTrace');
      return _calcularManual(config);
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
      final usuario = (config['correios']?['usuario'] ?• '').toString();
      final senha = (config['correios']?['senha'] ?• '').toString();

      if (usuario.isEmpty || senha.isEmpty) {
        debugPrint('⚠️  [FRETE] Credenciais Correios não configuradas');
        return _calcularManual(config);
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
      return _calcularManual(config);
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

  /// Cria um pré-pedido/cotação na plataforma de frete
  /// Após o cliente finalizar o pedido no app, este método adiciona
  /// o pedido no carrinho da plataforma para o lojista finalizar manualmente
  ///
  /// Retorna: Map com informações do pré-pedido criado
  static Future<Map<String, dynamic>?> criarPrePedidoNaPlataforma({
    required String lojaId,
    required Map<String, dynamic> pedido,
    required Map<String, dynamic> cliente,
    required Map<String, dynamic> freteSelecionado,
  }) async {
    try {
      // Buscar configuração
      final config = await _buscarConfigFrete(lojaId);

      // Identificar a plataforma através do campo 'plataforma' do frete selecionado
      final plataforma = freteSelecionado['plataforma'] as String• ?• 'manual';

      debugPrint('📦 [FRETE] Criando pré-pedido na plataforma: $plataforma');
      debugPrint('   Frete selecionado: ${freteSelecionado['nome']} - ${freteSelecionado['empresa']}');

      switch (plataforma) {
        case 'melhor_envio':
          return await _criarPrePedidoMelhorEnvio(
            lojaId: lojaId,
            config: config,
            pedido: pedido,
            cliente: cliente,
            freteSelecionado: freteSelecionado,
          );

        case 'superfrete':
          return await _criarPrePedidoSuperFrete(
            lojaId: lojaId,
            config: config,
            pedido: pedido,
            cliente: cliente,
            freteSelecionado: freteSelecionado,
          );

        case 'frenet':
          debugPrint('⚠️  [FRETE] Frenet não suporta criação automática de pedidos');
          debugPrint('   ℹ️  Frenet é APENAS um cotador de preços');
          debugPrint('   ℹ️  Você precisa criar o envio manualmente no site da transportadora');
          return {
            'success': false,
            'plataforma': 'frenet',
            'message': 'Frenet apenas cotou o preço',
            'instrucoes': 'Acesse o site da ${freteSelecionado['empresa']} para criar o envio manualmente',
          };

        case 'correios':
          debugPrint('⚠️  [FRETE] Correios requer integração manual no site');
          return {
            'success': false,
            'plataforma': 'correios',
            'message': 'Correios requer criação manual',
            'instrucoes': 'Acesse www.correios.com.br para criar o envio',
          };

        case 'manual':
        default:
          debugPrint('ℹ️  [FRETE] Frete manual não requer pré-pedido');
          return null;
      }
    } catch (e) {
      debugPrint('❌ [FRETE] Erro ao criar pré-pedido (type=${e.runtimeType})');
      return null;
    }
  }

  /// Cria pedido no carrinho do Melhor Envio
  static Future<Map<String, dynamic>?> _criarPrePedidoMelhorEnvio({
    required String lojaId,
    required Map<String, dynamic> config,
    required Map<String, dynamic> pedido,
    required Map<String, dynamic> cliente,
    required Map<String, dynamic> freteSelecionado,
  }) async {
    try {
      final token = (config['melhorEnvio']?['token'] ?• '').toString();
      if (token.isEmpty) {
        debugPrint('⚠️  [FRETE] Token Melhor Envio não configurado');
        return null;
      }

      // Extrair dados do cliente
      final endereco = cliente['endereco'] as Map<String, dynamic>• ?• {};
      final cepDestino = (endereco['cep'] ?• '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      final nomeCliente = (cliente['nome'] ?• 'Cliente').toString();
      final telefoneCliente = (cliente['telefone'] ?• '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      final emailCliente = (cliente['email'] ?• '').toString();

      // Endereço destino: API exige ao menos 2 caracteres em address
      String ruaDestino = (endereco['rua'] ?• '').toString().trim();
      if (ruaDestino.length < 2) ruaDestino = 'S/N';

      // CEP de origem e dados do remetente (API Melhor Envio exige from.name, from.address, from.city)
      final cepOrigem = (config['cepOrigem'] ?• '01310100').toString().replaceAll(RegExp(r'[^0-9]'), '');
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
          final nomeLoja = (data['name'] ?• data['nome'] ?• '').toString().trim();
          final slug = (data['slug'] ?• lojaId).toString().trim();
          if (nomeLoja.isNotEmpty && nomeLoja.toLowerCase() != 'minha loja' && nomeLoja.toLowerCase() != 'loja') {
            fromName = nomeLoja;
          } else {
            fromName = formatarNomeLoja(slug.isNotEmpty • slug : lojaId);
          }
          final rodape = data['rodape'] as Map<String, dynamic>?;
          if (rodape != null) {
            final cnpj = (rodape['cnpj'] ?• '').toString().replaceAll(RegExp(r'[^0-9]'), '');
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
                final cnpj = (rodapeD?['cnpj'] ?• fc?['cnpj'] ?• '').toString().replaceAll(RegExp(r'[^0-9]'), '');
                if (cnpj.length == 14) { fromCnpj = cnpj; break; }
              }
            }
          }
        } else {
          fromName = formatarNomeLoja(lojaId);
        }
        final viaCep = await ViaCepService.buscar(cepOrigem);
        if (viaCep != null) {
          fromAddress = viaCep.logradouro.isNotEmpty • viaCep.logradouro : 'Centro';
          fromCity = viaCep.localidade.isNotEmpty • viaCep.localidade : 'São Paulo';
          fromDistrict = viaCep.bairro.isNotEmpty • viaCep.bairro : 'Centro';
          fromState = viaCep.uf.isNotEmpty • viaCep.uf : 'SP';
        }
      } catch (e) {
        debugPrint('⚠️  [MELHOR ENVIO] Fallback dados origem (type=${e.runtimeType})');
      }

      // Calcular dimensões e peso do pedido
      final itens = pedido['itens'] as List• ?• [];
      double pesoTotal = 0;
      double valorTotal = 0;

      for (final item in itens) {
        final qty = (item['quantidade'] as int?) ?• 1;
        final peso = ((item['peso'] as num?)?.toDouble() ?• 200.0); // peso padrão 200g por item
        pesoTotal += peso * qty;
        valorTotal += ((item['total'] as num?)?.toDouble() ?• 0);
      }

      // Dimensões padrão se não especificadas
      final altura = (pedido['altura'] as num?)?.toDouble() ?• 10.0;
      final largura = (pedido['largura'] as num?)?.toDouble() ?• 20.0;
      final comprimento = (pedido['comprimento'] as num?)?.toDouble() ?• 30.0;

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
        'state_register': fromCnpj.isNotEmpty • '' : '',
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
        'service': freteSelecionado['service_id'] ?• 1,
        'from': fromObj,
        'to': {
          'name': nomeCliente,
          'phone': telefoneCliente,
          'email': emailCliente,
          'document': (cliente['cpf'] ?• '').toString().replaceAll(RegExp(r'[^0-9]'), ''),
          'company_document': '',
          'state_register': 'ISENTO',
          'postal_code': cepDestino,
          'address': ruaDestino,
          'number': endereco['numero'] ?• 'S/N',
          'complement': endereco['complemento'] ?• '',
          'district': endereco['bairro'] ?• '',
          'city': endereco['cidade'] ?• '',
          'state_abbr': endereco['estado'] ?• 'SP',
          'country_id': 'BR',
        },
        'products': [
          {
            'name': 'Pedido ${pedido['id'] ?• 'N/A'}',
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
        String• instrucoes;
        try {
          final errBody = jsonDecode(response.body);
          final err = errBody['error'] ?• errBody['message'];
          if (err != null) {
            final str = err is String • err : (err is Map • (err['message'] ?• err.values.join(', ')) : err.toString());
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
      final token = (config['superfrete']?['token'] ?• '').toString();
      if (token.isEmpty) {
        debugPrint('⚠️  [FRETE] Token SuperFrete não configurado');
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

      final endereco = cliente['endereco'] as Map<String, dynamic>• ?• {};
      final cepDestino = (endereco['cep'] ?• '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      final nomeCliente = (cliente['nome'] ?• 'Cliente').toString();
      final telefoneCliente = (cliente['telefone'] ?• '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      final emailCliente = (cliente['email'] ?• '').toString();
      String ruaDestino = (endereco['rua'] ?• '').toString().trim();
      if (ruaDestino.length < 2) ruaDestino = 'S/N';

      final cepOrigem = (config['cepOrigem'] ?• '01310100').toString().replaceAll(RegExp(r'[^0-9]'), '');
      String fromAddress = 'Centro';
      String fromCity = 'São Paulo';
      String fromState = 'SP';
      String fromDistrict = 'Centro';
      try {
        final viaCep = await ViaCepService.buscar(cepOrigem);
        if (viaCep != null) {
          fromAddress = viaCep.logradouro.isNotEmpty • viaCep.logradouro : 'Centro';
          fromCity = viaCep.localidade.isNotEmpty • viaCep.localidade : 'São Paulo';
          fromDistrict = viaCep.bairro.isNotEmpty • viaCep.bairro : 'Centro';
          fromState = viaCep.uf.isNotEmpty • viaCep.uf : 'SP';
        }
      } catch (_) {}

      final itens = pedido['itens'] as List• ?• [];
      double pesoTotal = 0;
      double valorTotal = 0;
      for (final item in itens) {
        final qty = (item['quantidade'] as int?) ?• 1;
        final peso = ((item['peso'] as num?)?.toDouble() ?• 200.0);
        pesoTotal += peso * qty;
        valorTotal += ((item['total'] as num?)?.toDouble() ?• 0);
      }
      final altura = (pedido['altura'] as num?)?.toDouble() ?• 10.0;
      final largura = (pedido['largura'] as num?)?.toDouble() ?• 20.0;
      final comprimento = (pedido['comprimento'] as num?)?.toDouble() ?• 30.0;

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
        'document': (cliente['cpf'] ?• '').toString().replaceAll(RegExp(r'[^0-9]'), ''),
        'postal_code': cepDestino,
        'address': ruaDestino,
        'number': (endereco['numero'] ?• 'S/N').toString(),
        'complement': (endereco['complemento'] ?• '').toString(),
        'district': (endereco['bairro'] ?• '').toString(),
        'city': (endereco['cidade'] ?• '').toString(),
        'state': (endereco['estado'] ?• 'SP').toString(),
      };
      final package = <String, dynamic>{
        'height': altura.toInt().clamp(1, 999),
        'width': largura.toInt().clamp(1, 999),
        'length': comprimento.toInt().clamp(1, 999),
        'weight': (pesoTotal / 1000).toStringAsFixed(2),
      };

      final resultado = await SuperFreteService.criarEnvioNoCarrinho(
        token: token,
        servicoId: servicoId,
        from: from,
        to: to,
        package: package,
        valorDeclarado: valorTotal > 0 • valorTotal : 10.0,
        pedidoRef: (pedido['id'] ?• '').toString(),
      );

      if (resultado['sucesso'] == true) {
        debugPrint('✅ [SUPERFRETE] Pedido adicionado ao carrinho');
        return {
          'success': true,
          'plataforma': 'superfrete',
          'cart_id': resultado['id'],
          'protocol': resultado['protocol'],
          'message': resultado['message'] ?• 'Pedido adicionado ao carrinho da SuperFrete',
          'instrucoes': 'Acesse https://web.superfrete.com para finalizar e gerar a etiqueta',
        };
      }

      return {
        'success': false,
        'plataforma': 'superfrete',
        'error': (resultado['erro'] ?• 'Erro ao adicionar ao carrinho').toString(),
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
      final token = (config['melhorEnvio']?['token'] ?• '').toString();

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
