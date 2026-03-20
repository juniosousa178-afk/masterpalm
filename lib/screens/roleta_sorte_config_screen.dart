// lib/screens/roleta_sorte_config_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/moeda_input_formatter.dart';

/// Tela de configuração da Roleta da Sorte
/// Independente das campanhas de sorteio
class RoletaSorteConfigScreen extends StatefulWidget {
  final String lojaId;

  const RoletaSorteConfigScreen({
    super.key,
    required this.lojaId,
  });

  @override
  State<RoletaSorteConfigScreen> createState() => _RoletaSorteConfigScreenState();
}

class _RoletaSorteConfigScreenState extends State<RoletaSorteConfigScreen> {
  bool _carregando = true;
  bool _ativa = false;
  double _valorMinimo = 0.0;
  int _frequenciaPremio = 10;
  List<Map<String, dynamic>> _premios = [];

  final _valorMinimoController = TextEditingController();
  final _frequenciaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarConfig();
  }

  @override
  void dispose() {
    _valorMinimoController.dispose();
    _frequenciaController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('config')
          .doc('roleta_sorte')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _ativa = data['ativa'] == true;
          _valorMinimo = (data['valorMinimo'] as num?)?.toDouble() ?• 0.0;
          _frequenciaPremio = data['frequenciaPremio'] as int• ?• 10;
          _premios = List<Map<String, dynamic>>.from(data['premios'] ?• []);

          _valorMinimoController.text = MoedaInputFormatter.format(_valorMinimo);
          _frequenciaController.text = _frequenciaPremio.toString();

          _carregando = false;
        });
      } else {
        setState(() {
          _carregando = false;
          // Valores padrão
          _premios = [
            {'label': 'Cupom 10% OFF', 'tipo': 'desconto', 'valor': 10.0},
            {'label': 'Frete Grátis', 'tipo': 'frete_gratis', 'valor': 0.0},
            {'label': 'Tente novamente', 'tipo': 'nenhum', 'valor': 0.0},
          ];
          _valorMinimoController.text = '0,00';
          _frequenciaController.text = '10';
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar config da roleta (type=${e.runtimeType})');
      setState(() => _carregando = false);
    }
  }

  Future<void> _salvarConfig() async {
    try {
      final valorMinimo = MoedaInputFormatter.parse(_valorMinimoController.text);
      final frequencia = int.tryParse(_frequenciaController.text) ?• 10;

      if (valorMinimo < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Valor mínimo deve ser maior ou igual a zero.'), backgroundColor: Colors.red),
        );
        return;
      }
      if (frequencia < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Frequência deve ser pelo menos 1.'), backgroundColor: Colors.red),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('config')
          .doc('roleta_sorte')
          .set({
        'ativa': _ativa,
        'valorMinimo': valorMinimo,
        'frequenciaPremio': frequencia,
        'premios': _premios,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Configurações salvas com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('❌ Erro ao salvar config (type=${e.runtimeType})');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao salvar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _adicionarPremio() {
    showDialog(
      context: context,
      builder: (context) {
        String label = '';
        String tipo = 'desconto';
        double valor = 0.0;
        int quantidadeMaxima = 0;
        int diasValidade = 30;
        final validadeCtrl = TextEditingController(text: '30');

        return AlertDialog(
          backgroundColor: const Color(0xFF0F1117),
          title: const Text('Novo Prêmio', style: TextStyle(color: Colors.white)),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Descrição',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (v) => label = v,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: tipo,
                      dropdownColor: const Color(0xFF0F1117),
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      items: const [
                        DropdownMenuItem(value: 'desconto', child: Text('Desconto (%)')),
                        DropdownMenuItem(value: 'frete_gratis', child: Text('Frete Grátis')),
                        DropdownMenuItem(value: 'brinde', child: Text('Brinde')),
                        DropdownMenuItem(value: 'nenhum', child: Text('Nenhum (Tente novamente)')),
                      ],
                      onChanged: (v) {
                        setDialogState(() => tipo = v!);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (tipo == 'desconto')
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Valor (%)',
                          labelStyle: TextStyle(color: Colors.white70),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white30),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => valor = double.tryParse(v) ?• 0.0,
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Quantidade máxima (0 = ilimitado)',
                        labelStyle: TextStyle(color: Colors.white70),
                        helperText: 'Ex: 5 = este prêmio pode sair no máximo 5 vezes',
                        helperStyle: TextStyle(color: Colors.white54, fontSize: 11),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) => quantidadeMaxima = int.tryParse(v) ?• 0,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: validadeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Validade (dias)',
                        labelStyle: TextStyle(color: Colors.white70),
                        helperText: 'Ex: 30 = cupom válido por 30 dias após ganhar',
                        helperStyle: TextStyle(color: Colors.white54, fontSize: 11),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) => diasValidade = int.tryParse(v) ?• 30,
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (label.isNotEmpty) {
                  setState(() {
                    _premios.add({
                      'label': label,
                      'tipo': tipo,
                      'valor': valor,
                      'quantidadeMaxima': quantidadeMaxima,
                      'quantidadeUsada': 0,
                      'diasValidade': diasValidade,
                      'ativo': true,
                    });
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
              child: const Text('Adicionar', style: TextStyle(color: Colors.black)),
            ),
          ],
        );
      },
    );
  }

  void _removerPremio(int index) async {
    final premio = _premios[index];
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1117),
        title: const Text('Remover prêmio?', style: TextStyle(color: Colors.white)),
        content: Text(
          'O prêmio "${premio['label']}" será removido. Deseja continuar?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmar == true && mounted) {
      setState(() => _premios.removeAt(index));
    }
  }

  void _editarPremio(int index) {
    final premio = Map<String, dynamic>.from(_premios[index]);
    final labelCtrl = TextEditingController(text: premio['label']?.toString() ?• '');
    final valorCtrl = TextEditingController(
      text: premio['tipo'] == 'desconto' • (premio['valor']?.toString() ?• '0') : '',
    );
    String tipo = premio['tipo']?.toString() ?• 'desconto';
    int quantidadeMaxima = premio['quantidadeMaxima'] as int• ?• 0;
    int diasValidade = premio['diasValidade'] as int• ?• 30;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F1117),
          title: const Text('Editar Prêmio', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descrição',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onChanged: (v) => premio['label'] = v,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: tipo,
                  dropdownColor: const Color(0xFF0F1117),
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  ),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'desconto', child: Text('Desconto (%)')),
                    DropdownMenuItem(value: 'frete_gratis', child: Text('Frete Grátis')),
                    DropdownMenuItem(value: 'brinde', child: Text('Brinde')),
                    DropdownMenuItem(value: 'nenhum', child: Text('Nenhum (Tente novamente)')),
                  ],
                  onChanged: (v) => setDialogState(() => tipo = v!),
                ),
                const SizedBox(height: 16),
                if (tipo == 'desconto')
                  TextField(
                    controller: valorCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Valor (%)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                    ),
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => premio['valor'] = double.tryParse(v) ?• 0.0,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                premio['label'] = labelCtrl.text;
                premio['tipo'] = tipo;
                premio['valor'] = tipo == 'desconto' • (double.tryParse(valorCtrl.text) ?• 0.0) : 0.0;
                premio['quantidadeMaxima'] = quantidadeMaxima;
                premio['diasValidade'] = diasValidade;
                setState(() => _premios[index] = premio);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
              child: const Text('Salvar', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.greenAccent),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF05060A),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _salvarConfig,
        backgroundColor: Colors.greenAccent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.save),
        label: const Text('SALVAR'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Card Ativar/Desativar
            Card(
              color: const Color(0xFF10121A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SwitchListTile(
                value: _ativa,
                onChanged: (v) {
                  setState(() => _ativa = v);
                },
                title: const Text(
                  'Roleta da Sorte',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _ativa • 'Ativa - clientes podem girar após finalizar compra' : 'Inativa',
                  style: TextStyle(color: _ativa • Colors.greenAccent : Colors.white54),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                ),
            ),

            const SizedBox(height: 24),

            // ✅ Configurações
            const Text(
              'Configurações',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            Card(
              color: const Color(0xFF10121A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: 'Valor mínimo que o cliente precisa gastar para poder girar a roleta.',
                      child: TextField(
                      controller: _valorMinimoController,
                      decoration: const InputDecoration(
                        labelText: 'Valor mínimo da compra (R\$)',
                        labelStyle: TextStyle(color: Colors.white70),
                        hintText: '0,00',
                        hintStyle: TextStyle(color: Colors.white30),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.greenAccent),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      inputFormatters: [MoedaInputFormatter()],
                    ),
                    ),
                    const SizedBox(height: 16),
                    Tooltip(
                      message: 'A cada X vendas finalizadas, 1 cliente ganha um prêmio. Ex: 10 = 1 em cada 10 vendas.',
                      child: TextField(
                      controller: _frequenciaController,
                      decoration: const InputDecoration(
                        labelText: 'Frequência de prêmio (a cada X vendas)',
                        labelStyle: TextStyle(color: Colors.white70),
                        hintText: '10',
                        hintStyle: TextStyle(color: Colors.white30),
                        helperText: 'Ex: 10 = a cada 10 vendas, 1 ganha prêmio. Mínimo: 1.',
                        helperStyle: TextStyle(color: Colors.white54, fontSize: 12),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.greenAccent),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ✅ Prêmios
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Prêmios',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: _adicionarPremio,
                  icon: const Icon(Icons.add_circle, color: Colors.greenAccent, size: 32),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_premios.isEmpty)
              const Card(
                color: Color(0xFF10121A),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Nenhum prêmio configurado.\nClique no + para adicionar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              )
            else
              ...List.generate(_premios.length, (index) {
                final premio = _premios[index];
                final qtdMax = premio['quantidadeMaxima'] as int• ?• 0;
                final qtdUsada = premio['quantidadeUsada'] as int• ?• 0;
                final esgotado = qtdMax > 0 && qtdUsada >= qtdMax;

                return Card(
                  color: const Color(0xFF10121A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      premio['tipo'] == 'desconto'
                          • Icons.discount
                          : premio['tipo'] == 'frete_gratis'
                              • Icons.local_shipping
                              : premio['tipo'] == 'brinde'
                                  • Icons.card_giftcard
                                  : Icons.close,
                      color: esgotado • Colors.grey : Colors.greenAccent,
                    ),
                    title: Text(
                      premio['label'],
                      style: TextStyle(
                        color: esgotado • Colors.grey : Colors.white,
                        decoration: esgotado • TextDecoration.lineThrough : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          premio['tipo'] == 'desconto'
                              • 'Desconto de ${premio['valor']}%'
                              : premio['tipo'] == 'frete_gratis'
                                  • 'Frete grátis'
                                  : premio['tipo'] == 'brinde'
                                      • 'Brinde'
                                      : 'Tente novamente',
                          style: TextStyle(
                            color: esgotado • Colors.grey : Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        if (qtdMax > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              esgotado
                                  • '🚫 ESGOTADO ($qtdUsada/$qtdMax)'
                                  : '📊 Usados: $qtdUsada/$qtdMax',
                              style: TextStyle(
                                color: esgotado • Colors.redAccent : Colors.orangeAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.greenAccent),
                          onPressed: () => _editarPremio(index),
                          tooltip: 'Editar',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => _removerPremio(index),
                          tooltip: 'Remover',
                        ),
                      ],
                    ),
                  ),
                );
              }),

            const SizedBox(height: 80), // Espaço para o FAB
          ],
        ),
      ),
    );
  }
}
