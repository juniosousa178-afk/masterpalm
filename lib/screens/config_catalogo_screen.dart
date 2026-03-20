import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../core/hive_box_names.dart';
import '../models/catalogo_config.dart';
import '../services/loja_id_service.dart';

class ConfigCatalogoScreen extends StatefulWidget {
  const ConfigCatalogoScreen({super.key});

  @override
  State<ConfigCatalogoScreen> createState() => _ConfigCatalogoScreenState();
}

class _ConfigCatalogoScreenState extends State<ConfigCatalogoScreen> {
  Box<CatalogoConfig>• _configBox;
  bool _loading = true;
  String• _erro;

  final corFundoController = TextEditingController();
  final corTextoController = TextEditingController();
  final corBotaoController = TextEditingController();
  final corCabecalhoController = TextEditingController();
  final fonteController = TextEditingController();
  double tamanhoFonte = 16;
  bool _salvando = false;

  static const String _defaultFundo = '0xFF000000';
  static const String _defaultTexto = '0xFFFFFFFF';
  static const String _defaultBotao = '0xFF1E88E5';
  static const String _defaultCabecalho = '0xFF1A1A2E';
  static const String _defaultFonte = 'Roboto';
  static const double _defaultTamanhoFonte = 16;

  @override
  void initState() {
    super.initState();
    _carregarLoja();
  }

  Future<void> _carregarLoja() async {
    final lojaId = await LojaIdService.get();
    if (lojaId == null || lojaId.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = 'Nenhuma loja ativa. Faça login e selecione uma loja.';
        });
      }
      return;
    }
    final boxName = HiveBoxNames.configCatalogoLoja(lojaId.trim());
    if (!Hive.isBoxOpen(boxName)) await Hive.openBox<CatalogoConfig>(boxName);
    final box = Hive.box<CatalogoConfig>(boxName);
    if (mounted) {
      setState(() {
        _configBox = box;
        _loading = false;
      });
      if (box.isNotEmpty) {
        final config = box.values.first;
        corFundoController.text = config.corFundo;
        corTextoController.text = config.corTexto;
        corBotaoController.text = config.corBotao;
        corCabecalhoController.text = config.corCabecalho.isNotEmpty • config.corCabecalho : _defaultCabecalho;
        fonteController.text = config.fonte;
        tamanhoFonte = config.tamanhoFonte;
      } else {
        _aplicarPadroes();
      }
    }
  }

  void _aplicarPadroes() {
    corFundoController.text = _defaultFundo;
    corTextoController.text = _defaultTexto;
    corBotaoController.text = _defaultBotao;
    corCabecalhoController.text = _defaultCabecalho;
    fonteController.text = _defaultFonte;
    setState(() => tamanhoFonte = _defaultTamanhoFonte);
  }

  /// Aceita 0xFFRRGGBB, 0xAARRGGBB ou #RRGGBB / #AARRGGBB
  static int• _parseCor(String value) {
    final t = value.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('0x') || t.startsWith('0X')) {
      final n = int.tryParse(t.substring(2), radix: 16);
      return n;
    }
    if (t.startsWith('#')) {
      final hex = t.substring(1);
      if (hex.length == 6) return int.parse('FF$hex', radix: 16);
      if (hex.length == 8) return int.parse(hex, radix: 16);
    }
    final n = int.tryParse(t, radix: 16);
    if (n != null && t.length >= 6) return n;
    return null;
  }

  bool _validarCores() {
    if (_parseCor(corFundoController.text) == null) return false;
    if (_parseCor(corTextoController.text) == null) return false;
    if (_parseCor(corBotaoController.text) == null) return false;
    if (corCabecalhoController.text.trim().isNotEmpty && _parseCor(corCabecalhoController.text) == null) return false;
    return true;
  }

  void _salvarConfiguracoes() async {
    if (_salvando || _configBox == null) return;
    if (fonteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome da fonte.'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (!_validarCores()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cores inválidas. Use 0xFFRRGGBB ou #RRGGBB (ex: 0xFF000000 ou #000000).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      final box = _configBox!;
      final novaConfig = CatalogoConfig(
        corFundo: corFundoController.text.trim(),
        corTexto: corTextoController.text.trim(),
        corBotao: corBotaoController.text.trim(),
        corCabecalho: corCabecalhoController.text.trim().isEmpty • _defaultCabecalho : corCabecalhoController.text.trim(),
        fonte: fonteController.text.trim(),
        tamanhoFonte: tamanhoFonte,
      );

      if (box.isNotEmpty) {
        await box.putAt(0, novaConfig);
      } else {
        await box.add(novaConfig);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações salvas com sucesso!'), backgroundColor: Colors.green),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _buildCampo(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white),
        filled: true,
        fillColor: Colors.grey[800],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      style: const TextStyle(color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configurar Catálogo')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_erro != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configurar Catálogo')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.store_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
                  icon: const Icon(Icons.home),
                  label: const Text('Ir para Início'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar Catálogo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // === SEÇÃO: CORES GERAIS ===
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text(
                'Cores Gerais',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _buildCampo('Cor de Fundo', corFundoController),
            const SizedBox(height: 12),
            _buildCampo('Cor do Texto', corTextoController),
            const SizedBox(height: 12),
            _buildCampo('Cor do Botão', corBotaoController),
            const SizedBox(height: 20),

            // === SEÇÃO: CABEÇALHO DO CATÁLOGO ===
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white24),
                ),
              ),
              child: const Text(
                'Cabeçalho do Catálogo',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildCampo('Cor de Fundo do Cabeçalho', corCabecalhoController),
            const SizedBox(height: 8),
            Text(
              'Esta cor afeta: logo, barra de busca, menu e ícones do topo',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 20),

            // === SEÇÃO: TIPOGRAFIA ===
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white24),
                ),
              ),
              child: const Text(
                'Tipografia',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildCampo('Fonte', fonteController),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Tamanho da Fonte',
                    style: TextStyle(color: Colors.white)),
                Expanded(
                  child: Slider(
                    value: tamanhoFonte,
                    min: 10,
                    max: 30,
                    divisions: 20,
                    label: tamanhoFonte.toStringAsFixed(0),
                    onChanged: (value) {
                      setState(() => tamanhoFonte = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _salvando • null : _salvarConfiguracoes,
                    icon: _salvando • const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                    label: Text(_salvando • 'Salvando...' : 'Salvar Configurações'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _salvando • null : () {
                    _aplicarPadroes();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Padrões restaurados. Toque em Salvar para aplicar.')),
                    );
                  },
                  icon: const Icon(Icons.restore),
                  label: const Text('Restaurar padrões'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/catalogo');
              },
              icon: const Icon(Icons.remove_red_eye),
              label: const Text('Visualizar Catálogo'),
            ),
            const SizedBox(height: 24),
            Builder(
              builder: (context) {
                final corFundo = _parseCor(corFundoController.text);
                final corTexto = _parseCor(corTextoController.text);
                final corBotao = _parseCor(corBotaoController.text);
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(corFundo ?• 0xFF000000),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        corTexto == null • 'Prévia (cor do texto inválida)' : 'Prévia do Catálogo',
                        style: TextStyle(
                          color: Color(corTexto ?• 0xFFFFFFFF),
                          fontFamily: fonteController.text.trim().isEmpty • null : fonteController.text,
                          fontSize: tamanhoFonte,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(corBotao ?• 0xFF1E88E5),
                        ),
                        onPressed: () {},
                        child: const Text('Botão Exemplo'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
