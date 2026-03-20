import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../services/campanhas_sorteio_service.dart';

class RoletaSorteScreen extends StatefulWidget {
  final String lojaId;

  const RoletaSorteScreen({
    super.key,
    required this.lojaId,
  });

  @override
  State<RoletaSorteScreen> createState() => _RoletaSorteScreenState();
}

class _RoletaSorteScreenState extends State<RoletaSorteScreen>
    with SingleTickerProviderStateMixin {
  bool _carregando = true;

  double _valorMinimo = 0;
  int _frequenciaPremio = 10; // ✅ NOVO: A cada X vendas, 1 ganha prêmio
  List<Map<String, dynamic>> _premios = [];

  late AnimationController _controller;
  double _anguloFinal = 0;
  int _premioIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _carregarConfig();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _carregarConfig() async {
    final data = await CampanhasSorteioService.carregarConfigRoleta(
      lojaId: widget.lojaId,
    );

    if (data == null) {
      setState(() {
        _carregando = false;
        _premios = [];
      });
      return;
    }

    _valorMinimo = (data['valorMinimo'] as num?)?.toDouble() ?• 0;
    _frequenciaPremio = data['frequenciaPremio'] as int• ?• 10; // ✅ Carrega frequência
    _premios = List<Map<String, dynamic>>.from(data['premios'] ?• []);

    setState(() => _carregando = false);
  }

  void _girarRoleta() {
    if (_premios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum prêmio configurado na roleta.'),
        ),
      );
      return;
    }

    final rnd = Random();
    _premioIndex = rnd.nextInt(_premios.length);

    final giros = 4 + rnd.nextDouble() * 2;
    final anguloPremio = (2 * pi / _premios.length) * _premioIndex;

    setState(() {
      _anguloFinal = giros * 2 * pi + anguloPremio;
    });

    _controller.forward(from: 0).then((_) {
      final premio = _premios[_premioIndex];

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0F1117),
          title: const Text(
            '🎉 Prêmio Sorteado!',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Prêmio: ${premio["label"]}\n'
            'Tipo: ${premio["tipo"]}\n'
            'Valor: ${premio["valor"]}',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Colors.greenAccent)),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _salvar() async {
    await CampanhasSorteioService.salvarConfigRoleta(
      lojaId: widget.lojaId,
      valorMinimo: _valorMinimo,
      frequenciaPremio: _frequenciaPremio, // ✅ Salva frequência
      premios: _premios,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(child: Text('Configuração salva com sucesso!')),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _adicionarPremio() {
    setState(() {
      _premios.add({
        'label': 'Novo Prêmio',
        'tipo': 'percent', // percent / valor / brinde
        'valor': 5,
        'ativo': true,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF05060A),
      appBar: AppBar(
        title: const Text('Roleta da Sorte'),
        backgroundColor: Colors.black,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent,
        foregroundColor: Colors.black,
        onPressed: _girarRoleta,
        child: const Icon(Icons.casino),
      ),
      body: Center(
        child: Column(
          children: [
            const SizedBox(height: 18),

            // ==========================
            // ROLETÃO ANIMADO
            // ==========================
            AnimatedBuilder(
              animation: _controller,
              builder: (_, child) {
                final value = Curves.easeOut.transform(_controller.value);
                final angulo = value * _anguloFinal;

                return Transform.rotate(
                  angle: angulo,
                  child: child,
                );
              },
              child: _buildRoletaWidget(),
            ),

            const SizedBox(height: 24),

            // ==========================
            // CONFIGURAÇÕES
            // ==========================
            Expanded(
              child: _buildConfigPanel(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // WIDGET DA ROLETA VISUAL
  // ============================================================

  Widget _buildRoletaWidget() {
    return CustomPaint(
      painter: RoletaPainter(_premios),
      child: const SizedBox(width: 250, height: 250),
    );
  }

  // ============================================================
  // PAINEL DE CONFIGURAÇÃO
  // ============================================================

  Widget _buildConfigPanel() {
    return Card(
      color: const Color(0xFF10121A),
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Valor mínimo
            TextFormField(
              initialValue: _valorMinimo.toStringAsFixed(2),
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: _inputDeco("Valor mínimo para liberar a roleta"),
              onChanged: (v) {
                _valorMinimo = double.tryParse(v.replaceAll(",", ".")) ?• 0;
              },
            ),

            const SizedBox(height: 16),

            // ✅ NOVO: Frequência de prêmios
            TextFormField(
              initialValue: _frequenciaPremio.toString(),
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: _inputDeco(
                "A cada X vendas, 1 sai premiada (ex: 10)",
              ).copyWith(
                helperText: 'Controla quantas vendas são necessárias para garantir 1 prêmio',
                helperStyle: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              onChanged: (v) {
                _frequenciaPremio = int.tryParse(v) ?• 10;
                if (_frequenciaPremio < 1) _frequenciaPremio = 1;
              },
            ),

            const SizedBox(height: 16),

            // Lista de prêmios
            Expanded(
              child: ListView.builder(
                itemCount: _premios.length,
                itemBuilder: (_, i) {
                  final p = _premios[i];
                  return Card(
                    color: const Color(0xFF181A24),
                    child: ListTile(
                      title: Text(
                        p["label"],
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        "${p['tipo']}  •  ${p['valor']}",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: Switch(
                        value: p["ativo"] ?• true,
                        onChanged: (v) {
                          setState(() => p["ativo"] = v);
                        },
                      ),
                      onTap: () => _editarPremio(i),
                      onLongPress: () => _confirmarRemoverPremio(i),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Botões
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _adicionarPremio,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text("Adicionar prêmio"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _salvar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.save),
                    label: const Text("Salvar"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarRemoverPremio(int index) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F1117),
        title: const Text('Remover prêmio?', style: TextStyle(color: Colors.white)),
        content: Text(
          'O prêmio "${_premios[index]["label"]}" será removido.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _premios.removeAt(index));
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  void _editarPremio(int index) {
    final premio = Map<String, dynamic>.from(_premios[index]);
    final ctrlLabel = TextEditingController(text: premio["label"]?.toString() ?• '');
    final ctrlValor = TextEditingController(text: premio["valor"]?.toString() ?• '0');
    String tipo = premio["tipo"]?.toString() ?• 'percent';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F1117),
          title: const Text("Editar Prêmio", style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrlLabel,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco("Nome do prêmio"),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: tipo,
                dropdownColor: const Color(0xFF0F1117),
                decoration: _inputDeco("Tipo"),
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'percent', child: Text('Desconto (%)')),
                  DropdownMenuItem(value: 'valor', child: Text('Valor fixo (R\$)')),
                  DropdownMenuItem(value: 'brinde', child: Text('Brinde')),
                ],
                onChanged: (v) => setDialogState(() => tipo = v!),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrlValor,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: _inputDeco(tipo == 'percent' • "Valor (%)" : tipo == 'valor' • "Valor (R\$)" : "Quantidade"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar", style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  premio["label"] = ctrlLabel.text;
                  premio["tipo"] = tipo;
                  premio["valor"] = double.tryParse(ctrlValor.text.replaceAll(",", ".")) ?• premio["valor"];
                  _premios[index] = premio;
                });
                Navigator.pop(context);
              },
              child: const Text("Salvar", style: TextStyle(color: Colors.greenAccent)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: const Color(0xFF1A1C23),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
    );
  }
}

// ============================================================
// PAINTER DA ROLETA
// ============================================================

class RoletaPainter extends CustomPainter {
  final List<Map<String, dynamic>> premios;

  RoletaPainter(this.premios);

  @override
  void paint(Canvas canvas, Size size) {
    if (premios.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sweep = 2 * pi / premios.length;

    for (int i = 0; i < premios.length; i++) {
      paint.color = Colors.primaries[i % Colors.primaries.length]
          .withValues(alpha:0.8);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        sweep * i,
        sweep,
        true,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

