// lib/screens/fretes_cupons_screen.dart
// Tela moderna de Fretes e Cupons com layout padronizado

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../services/cloud_sync_service.dart';
import '../services/store_resolver_facade.dart';
import '../services/cupom_desconto_service.dart';
import '../services/indicacao_config_service.dart';
import '../services/carrinho_abandonado_service.dart';
import 'carrinhos_abandonados_screen.dart';
import '../models/cupom.dart';
import '../widgets/app_help_icon_button.dart';

class FretesCuponsScreen extends StatefulWidget {
  final String? slug;

  const FretesCuponsScreen({super.key, this.slug});

  @override
  State<FretesCuponsScreen> createState() => _FretesCuponsScreenState();
}

class _FretesCuponsScreenState extends State<FretesCuponsScreen>
    with TickerProviderStateMixin {
  // Cores do tema moderno (igual EstoqueScreenV2)
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _surfaceColor = Color(0xFFF8FAFC);

  late TabController _tabController;
  late Box _config;
  late Box configPerStore;

  String? _slug;
  bool _salvando = false;

  // FRETES
  final List<Map<String, dynamic>> _fretes = [
    {'nome': 'Retirada', 'valor': 0.0},
    {'nome': 'Entrega local', 'valor': 10.0},
    {'nome': 'Combinar com vendedor', 'valor': 0.0},
  ];
  final TextEditingController _freteNomeCtrl = TextEditingController();
  final TextEditingController _freteValorCtrl = TextEditingController();

  String _freteProvider = 'manual';
  final TextEditingController _cepOrigemCtrl = TextEditingController();
  final TextEditingController _melhorEnvioTokenCtrl = TextEditingController();

  // Programa de indicação (indicar amigo)
  bool _indicacaoAtivo = false;
  String _indicacaoTipo = 'percentual';
  final TextEditingController _indicacaoValorCtrl = TextEditingController(text: '10');
  final TextEditingController _indicacaoValidadeCtrl = TextEditingController(text: '60');
  bool _indicacaoSalvando = false;

  // Recuperação de carrinho abandonado
  bool _carrinhoAbandonadoAtivo = false;
  final TextEditingController _carrinhoAbandonadoHorasCtrl = TextEditingController(text: '24');
  bool _carrinhoAbandonadoSalvando = false;
  final TextEditingController _correiosUserCtrl = TextEditingController();
  final TextEditingController _correiosSenhaCtrl = TextEditingController();
  final TextEditingController _frenetTokenCtrl = TextEditingController();
  final TextEditingController _superFreteTokenCtrl = TextEditingController();

  // =================== EMBALAGENS ===================
  List<Map<String, dynamic>> _embalagens = [
    {'id': 'padrao', 'nome': 'Padrão', 'peso': 50.0, 'tamanho': 1, 'altura': 10.0, 'largura': 15.0, 'comprimento': 20.0},
    {'id': 'pequena', 'nome': 'Pequena', 'peso': 100.0, 'tamanho': 2, 'altura': 15.0, 'largura': 20.0, 'comprimento': 25.0},
    {'id': 'media', 'nome': 'Média', 'peso': 200.0, 'tamanho': 3, 'altura': 20.0, 'largura': 25.0, 'comprimento': 30.0},
    {'id': 'grande', 'nome': 'Grande', 'peso': 350.0, 'tamanho': 4, 'altura': 25.0, 'largura': 30.0, 'comprimento': 40.0},
  ];
  int? _editandoEmbalagemIdx;
  final TextEditingController _embalagemNomeCtrl = TextEditingController();
  final TextEditingController _embalagemPesoCtrl = TextEditingController();
  final TextEditingController _embalagemTamanhoCtrl = TextEditingController();
  final TextEditingController _embalagemAlturaCtrl = TextEditingController();
  final TextEditingController _embalagemLarguraCtrl = TextEditingController();
  final TextEditingController _embalagemComprimentoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  Future<void> _init() async {
    await _ensureBoxes();
    await _bootstrap();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _freteNomeCtrl.dispose();
    _freteValorCtrl.dispose();
    _cepOrigemCtrl.dispose();
    _melhorEnvioTokenCtrl.dispose();
    _correiosUserCtrl.dispose();
    _correiosSenhaCtrl.dispose();
    _frenetTokenCtrl.dispose();
    _superFreteTokenCtrl.dispose();
    _indicacaoValorCtrl.dispose();
    _indicacaoValidadeCtrl.dispose();
    _carrinhoAbandonadoHorasCtrl.dispose();
    _embalagemNomeCtrl.dispose();
    _embalagemPesoCtrl.dispose();
    _embalagemTamanhoCtrl.dispose();
    _embalagemAlturaCtrl.dispose();
    _embalagemLarguraCtrl.dispose();
    _embalagemComprimentoCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureBoxes() async {
    if (!Hive.isBoxOpen('config')) {
      await Hive.openBox('config');
    }
    _config = Hive.box('config');

    if (!Hive.isBoxOpen('sessao')) {
      await Hive.openBox('sessao');
    }
  }

  Future<void> _putConfig(String key, dynamic value) async {
    await _config.put(key, value);
    if (_slug != null) {
      await configPerStore.put(key, value);
    }
  }

  Future<void> _bootstrap() async {
    final sessao = Hive.box('sessao');
    String? slugSessao =
        (sessao.get('store_id') as String?)?.trim().toLowerCase();

    // StoreResolver primeiro (mesma lógica da loja modelo); widget.slug e sessao são fallbacks
    final initialSlug = (await StoreResolverFacade.resolveForAdminApp()) ??
        widget.slug ??
        (slugSessao != null && slugSessao.isNotEmpty ? slugSessao : _emailPrefix());

    _slug = initialSlug;

    final perStoreName = 'config_${_slug!}';
    if (!Hive.isBoxOpen(perStoreName)) {
      await Hive.openBox(perStoreName);
    }
    configPerStore = Hive.box(perStoreName);

    if (configPerStore.isNotEmpty) {
      for (final key in configPerStore.keys) {
        await _config.put(key, configPerStore.get(key));
      }
    }

    await _putConfig('store_id', _slug!);
    await _putConfig('store_slug', _slug!);

    final rawFretes = _config.get('fretes');
    if (rawFretes is List) {
      _fretes
        ..clear()
        ..addAll(rawFretes.map<Map<String, dynamic>>((e) {
          final m = (e is Map)
              ? e.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          final nome = (m['nome'] ?? '').toString();
          final val = (m['valor'] is num)
              ? (m['valor'] as num).toDouble()
              : double.tryParse('${m['valor']}') ?? 0.0;
          return {'nome': nome, 'valor': val};
        }));
    }

    _freteProvider = (_config.get('frete_provider') ?? 'manual').toString();
    _cepOrigemCtrl.text = (_config.get('frete_cep_origem') ?? '').toString();
    _melhorEnvioTokenCtrl.text =
        (_config.get('frete_melhor_envio_token') ?? '').toString();
    _correiosUserCtrl.text =
        (_config.get('frete_correios_user') ?? '').toString();
    _correiosSenhaCtrl.text =
        (_config.get('frete_correios_senha') ?? '').toString();
    _frenetTokenCtrl.text = (_config.get('frete_frenet_token') ?? '').toString();
    _superFreteTokenCtrl.text =
        (_config.get('frete_superfrete_token') ?? '').toString();

    final rawEmbalagens = _config.get('embalagens');
    if (rawEmbalagens is List && rawEmbalagens.isNotEmpty) {
      _embalagens = _parseEmbalagensList(rawEmbalagens);
    }

    if (_slug != null) {
      await _loadEmbalagensFromFirestorePreferRemote(_slug!);
      await _loadFreteConfigFromFirestore(_slug!);
      await _loadIndicacaoConfig(_slug!);
      await _loadCarrinhoAbandonadoConfig(_slug!);
    }

    if (mounted) setState(() {});
  }

  Future<void> _loadIndicacaoConfig(String lojaId) async {
    try {
      final cfg = await IndicacaoConfigService.getConfig(lojaId);
      if (mounted) {
        setState(() {
          _indicacaoAtivo = cfg.ativo;
          _indicacaoTipo = cfg.tipo;
          _indicacaoValorCtrl.text = cfg.valor.toStringAsFixed(cfg.tipo == 'percentual' ? 0 : 2);
          _indicacaoValidadeCtrl.text = '${cfg.validadeDias}';
        });
      }
    } catch (_) {}
  }

  Future<void> _salvarIndicacaoConfig() async {
    if (_slug == null) return;
    setState(() => _indicacaoSalvando = true);
    try {
      final valor = double.tryParse(_indicacaoValorCtrl.text.replaceAll(',', '.')) ?? 10.0;
      final dias = int.tryParse(_indicacaoValidadeCtrl.text) ?? 60;
      await IndicacaoConfigService.setConfig(
        _slug!,
        IndicacaoConfig(
          ativo: _indicacaoAtivo,
          tipo: _indicacaoTipo,
          valor: valor,
          validadeDias: dias.clamp(7, 365),
        ),
      );
      if (mounted) _snack('✅ Programa de indicação salvo.');
    } catch (e) {
      if (mounted) _snack('❌ Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _indicacaoSalvando = false);
    }
  }

  Future<void> _loadCarrinhoAbandonadoConfig(String lojaId) async {
    try {
      final config = await CarrinhoAbandonadoService.getConfig(lojaId);
      if (mounted) {
        setState(() {
        _carrinhoAbandonadoAtivo = config.ativo;
        _carrinhoAbandonadoHorasCtrl.text = '${config.horasAbandono}';
      });
      }
    } catch (_) {}
  }

  Future<void> _salvarCarrinhoAbandonadoConfig() async {
    if (_slug == null) return;
    setState(() => _carrinhoAbandonadoSalvando = true);
    try {
      final horas = int.tryParse(_carrinhoAbandonadoHorasCtrl.text) ?? 24;
      await CarrinhoAbandonadoService.setConfig(
        _slug!,
        CarrinhoAbandonadoConfig(
          ativo: _carrinhoAbandonadoAtivo,
          horasAbandono: horas.clamp(1, 168),
          enviarEmail: true,
        ),
      );
      if (mounted) _snack('✅ Configuração de carrinho abandonado salva.');
    } catch (e) {
      if (mounted) _snack('❌ Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _carrinhoAbandonadoSalvando = false);
    }
  }

  /// Mesmo formato usado ao ler `embalagens` do Hive.
  static List<Map<String, dynamic>> _parseEmbalagensList(dynamic rawEmbalagens) {
    if (rawEmbalagens is! List || rawEmbalagens.isEmpty) {
      return [];
    }
    return rawEmbalagens.map<Map<String, dynamic>>((e) {
      if (e is Map) {
        final m = e.map((k, v) => MapEntry(k.toString(), v));
        return {
          'id': m['id']?.toString() ?? '',
          'nome': m['nome']?.toString() ?? '',
          'peso': (m['peso'] is num) ? (m['peso'] as num).toDouble() : double.tryParse('${m['peso']}') ?? 0.0,
          'tamanho': (m['tamanho'] is num) ? (m['tamanho'] as num).toInt() : int.tryParse('${m['tamanho']}') ?? 0,
          'altura': (m['altura'] is num) ? (m['altura'] as num).toDouble() : double.tryParse('${m['altura']}') ?? 0.0,
          'largura': (m['largura'] is num) ? (m['largura'] as num).toDouble() : double.tryParse('${m['largura']}') ?? 0.0,
          'comprimento': (m['comprimento'] is num) ? (m['comprimento'] as num).toDouble() : double.tryParse('${m['comprimento']}') ?? 0.0,
        };
      }
      return {'id': '', 'nome': '', 'peso': 0.0, 'tamanho': 0, 'altura': 0.0, 'largura': 0.0, 'comprimento': 0.0};
    }).toList();
  }

  /// Embalagens: prioridade Firestore (mesmo doc em que o save grava) — evita outro aparelho ficar só com Hive antigo.
  Future<void> _loadEmbalagensFromFirestorePreferRemote(String lojaId) async {
    try {
      final base = FirebaseFirestore.instance.collection('lojas').doc(lojaId);

      final liveSnap = await base.collection('config').doc('fretes').get();
      if (liveSnap.exists) {
        final emb = liveSnap.data()?['embalagens'];
        final parsed = _parseEmbalagensList(emb);
        if (parsed.isNotEmpty) {
          if (mounted) {
            setState(() => _embalagens = parsed);
          } else {
            _embalagens = parsed;
          }
          await _putConfig('embalagens', _embalagens);
          debugPrint('[FRETES/CUPONS] Embalagens carregadas de config/fretes (${_embalagens.length})');
          return;
        }
      }

      final draftSnap = await base.collection('draft_config').doc('config').get();
      if (draftSnap.exists) {
        final emb = draftSnap.data()?['embalagens'];
        final parsed = _parseEmbalagensList(emb);
        if (parsed.isNotEmpty) {
          if (mounted) {
            setState(() => _embalagens = parsed);
          } else {
            _embalagens = parsed;
          }
          await _putConfig('embalagens', _embalagens);
          debugPrint('[FRETES/CUPONS] Embalagens carregadas de draft_config/config (${_embalagens.length})');
        }
      }
    } catch (e) {
      debugPrint('[FRETES/CUPONS] Erro ao carregar embalagens remotas (type=${e.runtimeType})');
    }
  }

  Future<void> _loadFreteConfigFromFirestore(String lojaId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('draft_config')
          .doc('fretes')
          .get();

      if (!snap.exists) return;
      final data = snap.data() ?? {};

      final Map<String, dynamic> config =
          (data['config'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final itensRaw = data['itens'];

      setState(() {
        _freteProvider = (config['provider'] ?? 'manual').toString();
        _cepOrigemCtrl.text = (config['cep_origem'] ?? '').toString();
        _melhorEnvioTokenCtrl.text =
            (config['melhor_envio_token'] ?? '').toString();
        _correiosUserCtrl.text = (config['correios_user'] ?? '').toString();
        _correiosSenhaCtrl.text = (config['correios_senha'] ?? '').toString();
        _frenetTokenCtrl.text = (config['frenet_token'] ?? '').toString();
        _superFreteTokenCtrl.text =
            (config['superfrete_token'] ?? '').toString();

        _fretes
          ..clear()
          ..addAll(
            (itensRaw is List ? itensRaw : const [])
                .whereType<Map>()
                .map<Map<String, dynamic>>((e) {
              final m = Map<String, dynamic>.from(e);
              final nome = (m['nome'] ?? '').toString();
              final val = (m['valor'] is num)
                  ? (m['valor'] as num).toDouble()
                  : double.tryParse('${m['valor']}') ?? 0.0;
              return {'nome': nome, 'valor': val};
            }),
          );
      });
    } catch (e) {
      debugPrint('[FRETES/CUPONS] Erro ao carregar frete do Firestore (type=${e.runtimeType})');
    }
  }

  String _emailPrefix() {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'minha-loja';
    return email.split('@').first;
  }

  Map<String, dynamic> _ownerIdentity() {
    final u = FirebaseAuth.instance.currentUser;
    return {
      'uid': u?.uid,
      'email': u?.email,
      'emailPrefix': _emailPrefix(),
    };
  }

  Future<void> _upsertLojaFirestoreDraft({
    required Map<String, dynamic> partial,
    String? lojaIdOverride,
  }) async {
    final id = lojaIdOverride ?? _slug;
    if (id == null || id.isEmpty) return;
    final base = FirebaseFirestore.instance.collection('lojas').doc(id);

    final data = {
      ...partial,
      'slug': id,
      'ownerUid': FirebaseAuth.instance.currentUser?.uid,
      'owner': _ownerIdentity(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await base
        .collection('draft_config')
        .doc('config')
        .set(data, SetOptions(merge: true));

    await base.set({...data, 'config': partial}, SetOptions(merge: true));
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s),
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.startsWith('✅')
            ? _successColor
            : s.startsWith('❌')
                ? _errorColor
                : null,
      ),
    );
  }

  // =================== FUNÇÕES DE TESTE DE APIs ===================

  Future<void> _testarMelhorEnvio() async {
    final token = _melhorEnvioTokenCtrl.text.trim();
    if (token.isEmpty) {
      _snack('⚠️ Digite o token do Melhor Envio primeiro');
      return;
    }

    _snack('🔄 Testando conexão com Melhor Envio...');

    try {
      final response = await http.get(
        Uri.parse('https://melhorenvio.com.br/api/v2/me'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'User-Agent': 'MasterPalm (contato@mastepalm.com.br)',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final nome = data['firstname'] ?? 'Usuário';
        _snack('✅ Conectado com sucesso! Bem-vindo, $nome');
      } else if (response.statusCode == 401) {
        _snack('❌ Token inválido ou expirado');
      } else {
        _snack('❌ Erro: ${response.statusCode}');
      }
    } catch (e) {
      _snack('❌ Erro ao conectar: $e');
    }
  }

  Future<void> _testarFrenet() async {
    final token = _frenetTokenCtrl.text.trim();
    final cepOrigem = _cepOrigemCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (token.isEmpty) {
      _snack('⚠️ Digite o token da Frenet primeiro');
      return;
    }

    if (cepOrigem.length != 8) {
      _snack('⚠️ Digite um CEP de origem válido com 8 dígitos');
      return;
    }

    _snack('🔄 Testando conexão com Frenet...');

    try {
      final response = await http.post(
        Uri.parse('https://api.frenet.com.br/shipping/quote'),
        headers: {
          'Content-Type': 'application/json',
          'token': token,
        },
        body: jsonEncode({
          'SellerCEP': cepOrigem,
          'RecipientCEP': '01310100',
          'ShipmentInvoiceValue': 100.00,
          'ShippingItemArray': [
            {
              'Weight': 0.3,
              'Length': 20,
              'Height': 10,
              'Width': 15,
              'Quantity': 1,
            }
          ],
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ShippingServicesArray'] != null &&
            data['ShippingServicesArray'].isNotEmpty) {
          final qtdOpcoes = data['ShippingServicesArray'].length;
          _snack('✅ Conectado! $qtdOpcoes opções de frete encontradas');
        } else {
          _snack('✅ API conectada, mas nenhum frete disponível no teste');
        }
      } else if (response.statusCode == 401) {
        _snack('❌ Token inválido');
      } else {
        _snack('❌ Erro: ${response.statusCode}');
      }
    } catch (e) {
      _snack('❌ Erro ao conectar: $e');
    }
  }

  Future<void> _testarSuperFrete() async {
    final token = _superFreteTokenCtrl.text.trim();
    if (token.isEmpty) {
      _snack('⚠️ Digite o token do SuperFrete primeiro');
      return;
    }

    _snack('🔄 Testando conexão com SuperFrete...');

    try {
      final response = await http.get(
        Uri.parse('https://api.superfrete.com/api/v0/me'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _snack('✅ Conectado com sucesso ao SuperFrete!');
      } else if (response.statusCode == 401) {
        _snack('❌ Token inválido ou expirado');
      } else {
        _snack('❌ Erro: ${response.statusCode}');
      }
    } catch (e) {
      _snack('❌ Erro ao conectar: $e');
    }
  }

  Future<void> _testarCorreios() async {
    final usuario = _correiosUserCtrl.text.trim();
    final senha = _correiosSenhaCtrl.text.trim();
    final cepOrigem = _cepOrigemCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (usuario.isEmpty || senha.isEmpty) {
      _snack('⚠️ Digite usuário e senha dos Correios primeiro');
      return;
    }

    if (cepOrigem.length != 8) {
      _snack('⚠️ Digite um CEP de origem válido com 8 dígitos');
      return;
    }

    _snack('🔄 Testando conexão com Correios...');

    try {
      final url = Uri.parse(
        'http://ws.correios.com.br/calculador/CalcPrecoPrazo.asmx/CalcPrecoPrazo?'
        'nCdEmpresa=$usuario&'
        'sDsSenha=$senha&'
        'nCdServico=04510&'
        'sCepOrigem=$cepOrigem&'
        'sCepDestino=01310100&'
        'nVlPeso=0.3&'
        'nCdFormato=1&'
        'nVlComprimento=20&'
        'nVlAltura=10&'
        'nVlLargura=15&'
        'nVlDiametro=0&'
        'sCdMaoPropria=N&'
        'nVlValorDeclarado=0&'
        'sCdAvisoRecebimento=N',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = response.body;

        if (body.contains('<Erro>0</Erro>') ||
            body.contains('<Erro>-33</Erro>')) {
          _snack('✅ Credenciais válidas! Conexão com Correios OK');
        } else if (body.contains('<Erro>')) {
          final erroMatch = RegExp(r'<Erro>(\d+)</Erro>').firstMatch(body);
          final msgErroMatch =
              RegExp(r'<MsgErro>(.*?)</MsgErro>').firstMatch(body);

          final codigoErro = erroMatch?.group(1) ?? '?';
          final msgErro = msgErroMatch?.group(1) ?? 'Erro desconhecido';

          _snack('❌ Erro $codigoErro: $msgErro');
        } else {
          _snack('✅ Resposta recebida dos Correios');
        }
      } else {
        _snack('❌ Erro HTTP: ${response.statusCode}');
      }
    } catch (e) {
      _snack('❌ Erro ao conectar: $e');
    }
  }

  // ========= SALVAR FRETES =========
  Future<void> _salvarFretesECupons() async {
    final lojaId = await StoreResolverFacade.resolveForAdminApp() ?? _slug;
    if (lojaId == null || lojaId.isEmpty) {
      _snack('❌ Loja atual não definida. Faça login e tente novamente.');
      return;
    }

    setState(() => _salvando = true);
    try {
      await _putConfig(
        'fretes',
        _fretes.map((f) {
          final nome = (f['nome'] ?? '').toString();
          final val = (f['valor'] is num)
              ? (f['valor'] as num).toDouble()
              : double.tryParse('${f['valor']}') ?? 0.0;
          return {'nome': nome, 'valor': val};
        }).toList(),
      );

      await _putConfig('frete_provider', _freteProvider);
      await _putConfig('frete_cep_origem', _cepOrigemCtrl.text.trim());
      await _putConfig(
          'frete_melhor_envio_token', _melhorEnvioTokenCtrl.text.trim());
      await _putConfig('frete_correios_user', _correiosUserCtrl.text.trim());
      await _putConfig('frete_correios_senha', _correiosSenhaCtrl.text.trim());
      await _putConfig('frete_frenet_token', _frenetTokenCtrl.text.trim());
      await _putConfig(
          'frete_superfrete_token', _superFreteTokenCtrl.text.trim());
      await _putConfig('embalagens', _embalagens);

      await _config.flush();
      await configPerStore.flush();

      try {
        final base = FirebaseFirestore.instance.collection('lojas').doc(lojaId);

        final pesoEmb = _embalagens.isNotEmpty && _embalagens.first['peso'] != null
            ? ((_embalagens.first['peso'] as num).toDouble())
            : 50.0;
        final fretesDoc = {
          'provider': _freteProvider,
          'cepOrigem': _cepOrigemCtrl.text.trim(),
          'pesoEmbalagem': pesoEmb,
          'embalagens': _embalagens.map((e) => {
            'id': (e['id'] ?? '').toString(),
            'nome': (e['nome'] ?? '').toString(),
            'peso': (e['peso'] is num) ? (e['peso'] as num).toDouble() : double.tryParse('${e['peso']}') ?? 0.0,
            'tamanho': (e['tamanho'] is num) ? (e['tamanho'] as num).toInt() : int.tryParse('${e['tamanho']}') ?? 1,
            'altura': (e['altura'] is num) ? (e['altura'] as num).toDouble() : double.tryParse('${e['altura']}') ?? 0.0,
            'largura': (e['largura'] is num) ? (e['largura'] as num).toDouble() : double.tryParse('${e['largura']}') ?? 0.0,
            'comprimento': (e['comprimento'] is num) ? (e['comprimento'] as num).toDouble() : double.tryParse('${e['comprimento']}') ?? 0.0,
          }).toList(),
          'manualFretes': _fretes.map((f) {
            final nome = (f['nome'] ?? '').toString();
            final val = (f['valor'] is num)
                ? (f['valor'] as num).toDouble()
                : double.tryParse('${f['valor']}') ?? 0.0;
            return {'nome': nome, 'valor': val};
          }).toList(),
          'melhorEnvio': {
            'token': _melhorEnvioTokenCtrl.text.trim(),
          },
          'correios': {
            'usuario': _correiosUserCtrl.text.trim(),
            'senha': _correiosSenhaCtrl.text.trim(),
          },
          'frenet': {
            'token': _frenetTokenCtrl.text.trim(),
          },
          'superfrete': {
            'token': _superFreteTokenCtrl.text.trim(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        };

        await base
            .collection('config')
            .doc('fretes')
            .set(fretesDoc, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[FRETES/CUPONS] Erro ao salvar config/fretes (type=${e.runtimeType})');
      }

      final parcial = {
        'fretes': List<Map<String, dynamic>>.from(
          _config.get('fretes') ?? const [],
        ),
        'frete_config': {
          'provider': _freteProvider,
          'cep_origem': _cepOrigemCtrl.text.trim(),
          'melhor_envio_token': _melhorEnvioTokenCtrl.text.trim(),
          'correios_user': _correiosUserCtrl.text.trim(),
          'correios_senha': _correiosSenhaCtrl.text.trim(),
          'frenet_token': _frenetTokenCtrl.text.trim(),
          'superfrete_token': _superFreteTokenCtrl.text.trim(),
        },
        'embalagens': _embalagens,
      };

      await _upsertLojaFirestoreDraft(partial: parcial, lojaIdOverride: lojaId);
      try {
        await CloudSyncService.pushProfile();
      } catch (e) {
        debugPrint('[FRETES/CUPONS] pushProfile falhou (fretes já salvos) (type=${e.runtimeType})');
        if (mounted) {
          _snack('✅ Fretes salvos. Aviso: sincronização do perfil falhou – tente salvar de novo.');
        }
        return;
      }
      _snack('✅ Configurações de frete salvas com sucesso!');
    } catch (e) {
      debugPrint('[FRETES/CUPONS] Erro ao salvar (type=${e.runtimeType})');
      _snack('❌ Falha ao salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Fretes & Cupons',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [
          AppHelpIconButton(iconColor: Colors.white),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.local_shipping), text: 'Fretes'),
            Tab(icon: Icon(Icons.local_offer), text: 'Cupons'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAbaFretes(),
          _buildAbaCupons(),
        ],
      ),
    );
  }

  // ============== ABA FRETES ==============
  Widget _buildAbaFretes() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCardProvedor(),
        const SizedBox(height: 16),
        _buildCardFretesManuais(),
        const SizedBox(height: 16),
        _buildCardEmbalagens(),
      ],
    );
  }

  Widget _buildCardProvedor() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.settings,
                    color: _primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Provedor de Frete',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _salvando ? null : _salvarFretesECupons,
                  icon: _salvando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Salvar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _successColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _freteProvider,
              decoration: InputDecoration(
                labelText: 'Escolha o provedor de frete',
                prefixIcon: const Icon(Icons.local_shipping),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: _surfaceColor,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'manual',
                  child: Text('Manual (Fretes Fixos)'),
                ),
                DropdownMenuItem(
                  value: 'melhor_envio',
                  child: Text('Melhor Envio'),
                ),
                DropdownMenuItem(
                  value: 'superfrete',
                  child: Text('SuperFrete'),
                ),
                DropdownMenuItem(
                  value: 'frenet',
                  child: Text('Frenet'),
                ),
                DropdownMenuItem(
                  value: 'correios',
                  child: Text('Correios (Contrato)'),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _freteProvider = v);
              },
            ),
            const SizedBox(height: 20),
            _buildProvedorDetalhes(),
          ],
        ),
      ),
    );
  }

  Widget _buildProvedorDetalhes() {
    switch (_freteProvider) {
      case 'manual':
        return _buildGuiaManual();
      case 'melhor_envio':
        return _buildGuiaMelhorEnvio();
      case 'superfrete':
        return _buildGuiaSuperFrete();
      case 'frenet':
        return _buildGuiaFrenet();
      case 'correios':
        return _buildGuiaCorreios();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildGuiaManual() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Fretes Manuais (Fixos)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '✅ Ideal para: Entregas locais, retirada em loja\n'
            '✅ Configuração: Defina valores fixos de frete abaixo\n'
            '✅ Vantagens: Simples, sem necessidade de API\n'
            '⚠️ Limitação: Valores não variam por distância ou peso',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 12),
          const Text(
            '💡 Configure seus fretes fixos na seção abaixo',
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuiaMelhorEnvio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade50, Colors.green.shade100],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Melhor Envio (Recomendado)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '📦 O que faz:\n'
                '? Compara fretes de Correios, Jadlog, Azul Cargo e mais\n'
                '? Mostra o melhor preço automaticamente\n'
                '? Rastreamento integrado\n\n'
                '🔧 Como configurar:\n'
                '1. Cadastre-se em melhorenvio.com.br\n'
                '2. Acesse: Configurações → Token de API\n'
                '3. Copie o token e cole abaixo\n'
                '4. Clique em "Testar" para validar',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cepOrigemCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'CEP de Origem (sua loja)',
            hintText: '00000-000',
            prefixIcon: const Icon(Icons.location_on),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: _surfaceColor,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _melhorEnvioTokenCtrl,
                decoration: InputDecoration(
                  labelText: 'Token da API',
                  prefixIcon: const Icon(Icons.vpn_key),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: _surfaceColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _testarMelhorEnvio,
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('Testar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _successColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGuiaSuperFrete() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.blue.shade100],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'SuperFrete',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '⚡ O que faz:\n'
                '? Comparação rápida de fretes em tempo real\n'
                '? Múltiplas transportadoras\n'
                '? API simples e eficiente\n\n'
                '🔧 Como configurar:\n'
                '1. Cadastre-se em superfrete.com\n'
                '2. Acesse: Configurações → API\n'
                '3. Gere um token de acesso\n'
                '4. Cole abaixo e teste',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cepOrigemCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'CEP de Origem (sua loja)',
            hintText: '00000-000',
            prefixIcon: const Icon(Icons.location_on),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: _surfaceColor,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _superFreteTokenCtrl,
                decoration: InputDecoration(
                  labelText: 'Token da API',
                  prefixIcon: const Icon(Icons.key),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: _surfaceColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _testarSuperFrete,
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('Testar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _successColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGuiaFrenet() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade50, Colors.orange.shade100],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_shipping, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Frenet',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '🚚 O que faz:\n'
                '? Integração com múltiplas transportadoras\n'
                '? Cálculo baseado em tabelas de frete\n'
                '? Suporte a diferentes modalidades\n\n'
                '🔧 Como configurar:\n'
                '1. Cadastre-se em frenet.com.br\n'
                '2. Configure suas transportadoras\n'
                '3. Gere o token de API\n'
                '4. Cole abaixo e teste',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cepOrigemCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'CEP de Origem (sua loja)',
            hintText: '00000-000',
            prefixIcon: const Icon(Icons.location_on),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: _surfaceColor,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _frenetTokenCtrl,
                decoration: InputDecoration(
                  labelText: 'Token da API',
                  prefixIcon: const Icon(Icons.key),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: _surfaceColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _testarFrenet,
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('Testar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _successColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGuiaCorreios() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.yellow.shade50, Colors.yellow.shade100],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.yellow.shade700),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.markunread_mailbox, color: Colors.yellow.shade900, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Correios (Contrato Empresarial)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.yellow.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '📮 O que faz:\n'
                '? Usa PAC e SEDEX diretamente dos Correios\n'
                '? Preços do seu contrato empresarial\n'
                '? Rastreamento nativo\n\n'
                '🔧 Como configurar:\n'
                '1. Tenha um contrato com os Correios\n'
                '2. Acesse correios.com.br e faça login\n'
                '3. Obtenha seu código de usuário e senha\n'
                '4. Preencha abaixo e teste\n\n'
                '⚠️ Sem contrato? Use Melhor Envio ou SuperFrete',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cepOrigemCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'CEP de Origem (sua loja)',
            hintText: '00000-000',
            prefixIcon: const Icon(Icons.location_on),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: _surfaceColor,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _correiosUserCtrl,
          decoration: InputDecoration(
            labelText: 'Código de Usuário',
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: _surfaceColor,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _correiosSenhaCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Senha',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: _surfaceColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _testarCorreios,
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('Testar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _successColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCardFretesManuais() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _warningColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.edit_note,
                    color: _warningColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Fretes Fixos Personalizados',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Configure fretes com valores fixos (ex: Retirada, Entrega local)',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _fretes.asMap().entries.map((e) {
                final i = e.key;
                final f = e.value;
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: _primaryColor,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  label: Text(
                    '${f['nome']} — R\$ ${(f['valor'] as num).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => setState(() => _fretes.removeAt(i)),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _freteNomeCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nome (ex: Retirada)',
                      prefixIcon: const Icon(Icons.label),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: _surfaceColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _freteValorCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Valor (R\$)',
                      prefixIcon: const Icon(Icons.attach_money),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: _surfaceColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    final nome = _freteNomeCtrl.text.trim();
                    final valor = double.tryParse(
                            _freteValorCtrl.text.replaceAll(',', '.')) ??
                        0;
                    if (nome.isEmpty) {
                      _snack('⚠️ Digite um nome para o frete');
                      return;
                    }
                    setState(() {
                      _fretes.add({'nome': nome, 'valor': valor});
                      _freteNomeCtrl.clear();
                      _freteValorCtrl.clear();
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _descricaoPrioridadeEmbalagem(int tamanho) {
    if (_embalagens.isEmpty) return '';
    final maxT = _embalagens.map((e) => (e['tamanho'] is num) ? (e['tamanho'] as num).toInt() : 0).fold(0, (a, b) => a > b ? a : b);
    if (tamanho == 1) return 'menor';
    if (tamanho == maxT) return 'maior';
    return 'intermediária';
  }

  Widget _buildCardEmbalagens() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.inventory_2, color: _primaryColor, size: 24),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Tipos de Embalagem',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Configure os tipos de embalagem disponíveis. O sistema selecionará automaticamente a maior embalagem necessária no carrinho.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            TextField(
              controller: _embalagemNomeCtrl,
              decoration: InputDecoration(
                labelText: 'Nome da embalagem (ex: Pequena)',
                prefixIcon: const Icon(Icons.inventory_2),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: _surfaceColor,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _embalagemPesoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                    decoration: InputDecoration(
                      labelText: 'Peso (g)',
                      prefixIcon: const Icon(Icons.scale),
                      helperText: 'Ex: 50',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: _surfaceColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _embalagemTamanhoCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Prioridade',
                      prefixIcon: const Icon(Icons.stairs),
                      helperText: '1=menor',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: _surfaceColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _embalagemAlturaCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Altura (cm)',
                      prefixIcon: const Icon(Icons.height),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: _surfaceColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _embalagemLarguraCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Largura (cm)',
                      prefixIcon: const Icon(Icons.width_normal),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: _surfaceColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _embalagemComprimentoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Comprimento (cm)',
                      prefixIcon: const Icon(Icons.straighten),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: _surfaceColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                final nome = _embalagemNomeCtrl.text.trim();
                final peso = double.tryParse(_embalagemPesoCtrl.text.trim()) ?? 0.0;
                final tamanho = int.tryParse(_embalagemTamanhoCtrl.text.trim()) ?? 0;
                final altura = double.tryParse(_embalagemAlturaCtrl.text.trim()) ?? 0.0;
                final largura = double.tryParse(_embalagemLarguraCtrl.text.trim()) ?? 0.0;
                final comprimento = double.tryParse(_embalagemComprimentoCtrl.text.trim()) ?? 0.0;
                if (nome.isEmpty || peso <= 0 || tamanho <= 0) {
                  _snack('Preencha nome, peso e prioridade da embalagem.');
                  return;
                }
                if (altura <= 0 || largura <= 0 || comprimento <= 0) {
                  _snack('Preencha altura, largura e comprimento (valores maiores que zero).');
                  return;
                }
                final id = nome.toLowerCase().replaceAll(' ', '_');
                if (_editandoEmbalagemIdx != null) {
                  setState(() {
                    _embalagens[_editandoEmbalagemIdx!] = {
                      'id': _embalagens[_editandoEmbalagemIdx!]['id'] ?? id,
                      'nome': nome,
                      'peso': peso,
                      'tamanho': tamanho,
                      'altura': altura,
                      'largura': largura,
                      'comprimento': comprimento,
                    };
                    _editandoEmbalagemIdx = null;
                  });
                } else {
                  if (_embalagens.any((emb) => emb['id'] == id)) {
                    _snack('Essa embalagem já existe.');
                    return;
                  }
                  setState(() {
                    _embalagens.add({
                      'id': id,
                      'nome': nome,
                      'peso': peso,
                      'tamanho': tamanho,
                      'altura': altura,
                      'largura': largura,
                      'comprimento': comprimento,
                    });
                  });
                }
                _embalagens.sort((a, b) => ((a['tamanho'] as num?)?.toInt() ?? 0).compareTo((b['tamanho'] as num?)?.toInt() ?? 0));
                _embalagemNomeCtrl.clear();
                _embalagemPesoCtrl.clear();
                _embalagemTamanhoCtrl.clear();
                _embalagemAlturaCtrl.clear();
                _embalagemLarguraCtrl.clear();
                _embalagemComprimentoCtrl.clear();
                _salvarFretesECupons();
              },
              icon: Icon(_editandoEmbalagemIdx != null ? Icons.save : Icons.add),
              label: Text(_editandoEmbalagemIdx != null ? 'Salvar embalagem' : 'Adicionar embalagem'),
              style: FilledButton.styleFrom(
                backgroundColor: _successColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Embalagens cadastradas:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            if (_embalagens.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Nenhuma embalagem cadastrada ainda.', style: TextStyle(color: Colors.grey[600])),
              )
            else
              ..._embalagens.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                final altura = (e['altura'] as num?)?.toDouble() ?? 0.0;
                final largura = (e['largura'] as num?)?.toDouble() ?? 0.0;
                final comprimento = (e['comprimento'] as num?)?.toDouble() ?? 0.0;
                final tam = (e['tamanho'] as num?)?.toInt() ?? 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _primaryColor.withOpacity(0.2),
                      child: Text('$tam', style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryColor)),
                    ),
                    title: Text('${e['nome']} — ${e['peso']}g', style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Prioridade: $tam (${_descricaoPrioridadeEmbalagem(tam)})', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        if (altura > 0 || largura > 0 || comprimento > 0)
                          Text('Medidas: ${altura}cm (A) × ${largura}cm (L) × ${comprimento}cm (C)', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Editar',
                          onPressed: () {
                            setState(() {
                              _editandoEmbalagemIdx = i;
                              _embalagemNomeCtrl.text = e['nome']?.toString() ?? '';
                              _embalagemPesoCtrl.text = (e['peso'] as num?)?.toString() ?? '';
                              _embalagemTamanhoCtrl.text = (e['tamanho'] as num?)?.toString() ?? '';
                              _embalagemAlturaCtrl.text = (e['altura'] as num?)?.toString() ?? '';
                              _embalagemLarguraCtrl.text = (e['largura'] as num?)?.toString() ?? '';
                              _embalagemComprimentoCtrl.text = (e['comprimento'] as num?)?.toString() ?? '';
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: 'Excluir',
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Excluir embalagem?'),
                                content: Text('Deseja remover "${e['nome']}"?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                                    child: const Text('Excluir'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && mounted) {
                              setState(() {
                                _embalagens.removeAt(i);
                                if (_editandoEmbalagemIdx == i) {
                                  _editandoEmbalagemIdx = null;
                                  _embalagemNomeCtrl.clear();
                                  _embalagemPesoCtrl.clear();
                                  _embalagemTamanhoCtrl.clear();
                                  _embalagemAlturaCtrl.clear();
                                  _embalagemLarguraCtrl.clear();
                                  _embalagemComprimentoCtrl.clear();
                                } else if (_editandoEmbalagemIdx != null && _editandoEmbalagemIdx! > i) {
                                  _editandoEmbalagemIdx = _editandoEmbalagemIdx! - 1;
                                }
                              });
                              _salvarFretesECupons();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ============== ABA CUPONS ==============
  Widget _buildAbaCupons() {
    if (_slug == null) {
      return const Center(child: Text('Loja não identificada'));
    }

    final cupomService = CupomDescontoService();

    return StreamBuilder<List<Cupom>>(
      stream: cupomService.listarTodos(_slug!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // ✅ Tratamento de erro de permissão
        if (snapshot.hasError) {
          final error = snapshot.error.toString();
          if (error.contains('permission-denied') || error.contains('PERMISSION_DENIED')) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Sem permissão para visualizar cupons',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Entre em contato com o administrador',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          // Outro erro
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Erro ao carregar cupons: ${snapshot.error}',
                style: const TextStyle(color: _errorColor),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final cupons = snapshot.data ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildCardIndicacao(),
            const SizedBox(height: 16),
            _buildCardCarrinhoAbandonado(),
            const SizedBox(height: 16),
            _buildCardCriarCupom(),
            const SizedBox(height: 16),
            _buildCardListaCupons(cupons),
          ],
        );
      },
    );
  }

  Widget _buildCardIndicacao() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _successColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.card_giftcard, color: _successColor, size: 24),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Programa de indicação',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: _indicacaoAtivo,
                  onChanged: (v) => setState(() => _indicacaoAtivo = v),
                  thumbColor: MaterialStateProperty.resolveWith((s) =>
                      s.contains(MaterialState.selected) ? _primaryColor : null),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Cliente indica um amigo; quando o amigo comprar, os dois ganham cupom. O cupom de quem indicou só vale após o amigo usar o dele.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            if (_indicacaoAtivo) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Tipo de desconto:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _indicacaoTipo,
                    items: const [
                      DropdownMenuItem(value: 'percentual', child: Text('Percentual (%)')),
                      DropdownMenuItem(value: 'valor', child: Text('Valor fixo (R\$)')),
                    ],
                    onChanged: (v) => setState(() => _indicacaoTipo = v ?? 'percentual'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _indicacaoValorCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _indicacaoTipo == 'percentual' ? 'Valor (%)' : 'Valor (R\$)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _indicacaoValidadeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Validade (dias)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _indicacaoSalvando ? null : _salvarIndicacaoConfig,
                icon: _indicacaoSalvando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save, size: 20),
                label: Text(_indicacaoSalvando ? 'Salvando...' : 'Salvar indicação'),
                style: ElevatedButton.styleFrom(backgroundColor: _successColor, foregroundColor: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCardCarrinhoAbandonado() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _warningColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shopping_cart_outlined, color: _warningColor, size: 24),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Recuperação de carrinho abandonado',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: _carrinhoAbandonadoAtivo,
                  onChanged: (v) => setState(() => _carrinhoAbandonadoAtivo = v),
                  thumbColor: MaterialStateProperty.resolveWith((s) =>
                      s.contains(MaterialState.selected) ? _primaryColor : null),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Listar carrinhos não finalizados e enviar lembrete por e-mail ou WhatsApp.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                const Text(
                  'Considerar abandonado após (horas):',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _carrinhoAbandonadoHorasCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                Text(
                  '(1 a 168)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: _carrinhoAbandonadoSalvando ? null : _salvarCarrinhoAbandonadoConfig,
                  icon: _carrinhoAbandonadoSalvando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save, size: 20),
                  label: Text(_carrinhoAbandonadoSalvando ? 'Salvando...' : 'Salvar'),
                  style: ElevatedButton.styleFrom(backgroundColor: _warningColor, foregroundColor: Colors.white),
                ),
                OutlinedButton.icon(
                  onPressed: _slug == null
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CarrinhosAbandonadosScreen(lojaId: _slug!),
                            ),
                          );
                        },
                  icon: const Icon(Icons.list_alt, size: 20),
                  label: const Text('Ver carrinhos abandonados'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardCriarCupom() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.add_circle_outline,
                    color: _primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Criar Novo Cupom',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Crie cupons de desconto para seus clientes',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _mostrarDialogCriarCupomSimples(),
              icon: const Icon(Icons.local_offer),
              label: const Text('Criar Cupom Agora'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardListaCupons(List<Cupom> cupons) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _successColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.list_alt,
                    color: _successColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Cupons Ativos (${cupons.where((c) => c.ativo).length})',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),
            if (cupons.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.local_offer_outlined,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhum cupom criado',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Clique em "Criar Cupom" acima para começar',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...cupons.map((cupom) => _buildCupomCard(cupom)),
          ],
        ),
      ),
    );
  }

  Widget _buildCupomCard(Cupom cupom) {
    final desconto = cupom.tipo == 'percentual'
        ? '${cupom.valor.toStringAsFixed(0)}%'
        : 'R\$ ${cupom.valor.toStringAsFixed(2)}';

    Color tagColor = _primaryColor;
    String tagText = 'GLOBAL';
    IconData tagIcon = Icons.public;

    if (cupom.clienteId != null) {
      tagColor = const Color(0xFF9C27B0);
      tagText = 'VALE-COMPRA';
      tagIcon = Icons.card_giftcard;
    } else if (cupom.usoUnicoGlobal) {
      tagColor = _warningColor;
      tagText = 'USO ÚNICO';
      tagIcon = Icons.looks_one;
    } else if (cupom.usoUnico) {
      tagColor = Colors.blue;
      tagText = 'USO ÚNICO/CLIENTE';
      tagIcon = Icons.person;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: cupom.ativo ? tagColor.withOpacity(0.3) : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cupom.ativo
                        ? tagColor.withOpacity(0.1)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    tagIcon,
                    color: cupom.ativo ? tagColor : Colors.grey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            cupom.codigo,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: tagColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: tagColor.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              tagText,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: tagColor,
                              ),
                            ),
                          ),
                          if (!cupom.ativo)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _errorColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _errorColor.withOpacity(0.3),
                                ),
                              ),
                              child: const Text(
                                'INATIVO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _errorColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cupom.nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _successColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          desconto,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _successColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    if (value == 'toggle') {
                      await _toggleCupomAtivo(cupom);
                    } else if (value == 'delete') {
                      await _deletarCupom(cupom);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(cupom.ativo
                              ? Icons.visibility_off
                              : Icons.visibility),
                          const SizedBox(width: 12),
                          Text(cupom.ativo ? 'Desativar' : 'Ativar'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: _errorColor),
                          SizedBox(width: 12),
                          Text(
                            'Excluir',
                            style: TextStyle(color: _errorColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (cupom.freteGratis)
                  _buildInfoChip(
                    Icons.local_shipping,
                    'Frete Grátis',
                    _successColor,
                  ),
                if (cupom.valorMinimo != null && cupom.valorMinimo! > 0)
                  _buildInfoChip(
                    Icons.shopping_cart,
                    'Mín: R\$ ${cupom.valorMinimo!.toStringAsFixed(2)}',
                    Colors.orange,
                  ),
                if (cupom.qtdUsosAtuais > 0)
                  _buildInfoChip(
                    Icons.people,
                    'Usado ${cupom.qtdUsosAtuais}x',
                    Colors.blue,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogCriarCupomSimples() async {
    final codigoCtrl = TextEditingController();
    final nomeCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final valorMinimoCtrl = TextEditingController();

    String tipo = 'percentual';
    bool freteGratis = false;
    bool usoUnico = false;
    bool usoUnicoGlobal = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_offer, color: _primaryColor),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Criar Cupom de Desconto',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: codigoCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Código do Cupom',
                      hintText: 'Ex: DESCONTO10',
                      prefixIcon: const Icon(Icons.qr_code),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      helperText: 'Use letras maiúsculas e números',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nomeCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nome/Descrição',
                      hintText: 'Ex: Desconto de 10%',
                      prefixIcon: const Icon(Icons.label),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: tipo,
                          decoration: InputDecoration(
                            labelText: 'Tipo de Desconto',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'percentual',
                              child: Row(
                                children: [
                                  Icon(Icons.percent, size: 18),
                                  SizedBox(width: 8),
                                  Text('Percentual (%)'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'fixo',
                              child: Row(
                                children: [
                                  Icon(Icons.attach_money, size: 18),
                                  SizedBox(width: 8),
                                  Text('Valor Fixo (R\$)'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (v) => setDialogState(() => tipo = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: valorCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: tipo == 'percentual'
                                ? 'Valor (%)'
                                : 'Valor (R\$)',
                            hintText: tipo == 'percentual' ? '10' : '50.00',
                            prefixIcon: Icon(
                              tipo == 'percentual'
                                  ? Icons.percent
                                  : Icons.attach_money,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: valorMinimoCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Valor Mínimo da Compra (opcional)',
                      hintText: '100.00',
                      prefixIcon: const Icon(Icons.shopping_cart),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      helperText:
                          'Deixe vazio se não houver valor mínimo',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Opções do Cupom',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Frete Grátis'),
                    subtitle: const Text('Cliente não paga frete'),
                    value: freteGratis,
                    onChanged: (v) => setDialogState(() => freteGratis = v),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Uso Único por Cliente'),
                    subtitle:
                        const Text('Cada cliente pode usar apenas 1 vez'),
                    value: usoUnico,
                    onChanged: (v) => setDialogState(() {
                      usoUnico = v;
                      if (v) usoUnicoGlobal = false;
                    }),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Uso Único Global'),
                    subtitle: const Text(
                        'Apenas 1 pessoa pode usar (primeira compra)'),
                    value: usoUnicoGlobal,
                    onChanged: (v) => setDialogState(() {
                      usoUnicoGlobal = v;
                      if (v) usoUnico = false;
                    }),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check),
              label: const Text('Criar Cupom'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true && _slug != null) {
      final codigo = codigoCtrl.text.trim().toUpperCase();
      final nome = nomeCtrl.text.trim();
      final valor = double.tryParse(valorCtrl.text.trim()) ?? 0.0;
      final valorMinimo =
          double.tryParse(valorMinimoCtrl.text.trim());

      if (codigo.isEmpty || nome.isEmpty || valor <= 0) {
        _snack('⚠️ Preencha código, nome e valor corretamente');
        return;
      }

      try {
        await CupomDescontoService().criarCupom(
          lojaId: _slug!,
          codigo: codigo,
          nome: nome,
          valor: valor,
          tipo: tipo,
          aplicarEm: 'produtos',
          freteGratis: freteGratis,
          usoUnico: usoUnico,
          usoUnicoGlobal: usoUnicoGlobal,
          valorMinimo: valorMinimo,
        );
        _snack('✅ Cupom "$codigo" criado com sucesso!');
      } catch (e) {
        _snack('❌ Erro ao criar cupom: $e');
      }
    }
  }

  Future<void> _toggleCupomAtivo(Cupom cupom) async {
    if (_slug == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(_slug!)
          .collection('cupons')
          .doc(cupom.id)
          .update({'ativo': !cupom.ativo});

      _snack(cupom.ativo ? '✅ Cupom desativado' : '✅ Cupom ativado');
    } catch (e) {
      _snack('❌ Erro ao atualizar cupom: $e');
    }
  }

  Future<void> _deletarCupom(Cupom cupom) async {
    if (_slug == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _errorColor),
            SizedBox(width: 12),
            Text('Confirmar Exclusão'),
          ],
        ),
        content: Text(
          'Deseja realmente excluir o cupom "${cupom.codigo}"?\n\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await FirebaseFirestore.instance
            .collection('lojas')
            .doc(_slug!)
            .collection('cupons')
            .doc(cupom.id)
            .delete();

        _snack('✅ Cupom excluído com sucesso');
      } catch (e) {
        _snack('❌ Erro ao excluir cupom: $e');
      }
    }
  }
}


