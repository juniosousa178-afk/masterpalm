// lib/screens/campanha_sorteio_form_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/campanhas_sorteio_service.dart';
import '../utils/moeda_input_formatter.dart';
import 'globo_sorteio_screen.dart';

class CampanhaSorteioFormScreen extends StatefulWidget {
  final String lojaId;
  final String? campanhaId; // null = nova

  const CampanhaSorteioFormScreen({
    super.key,
    required this.lojaId,
    this.campanhaId,
  });

  @override
  State<CampanhaSorteioFormScreen> createState() =>
      _CampanhaSorteioFormScreenState();
}

class _CampanhaSorteioFormScreenState
    extends State<CampanhaSorteioFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nomeController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _premioController = TextEditingController();
  final _valorMinimoController = TextEditingController();
  final _valorXController = TextEditingController(); // ?? R$ X = 1 número

  DateTime? _dataInicio;
  DateTime? _dataFim;
  DateTime? _dataSorteio;
  bool _ativa = true;
  String? _statusAtual;

  bool _carregando = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    if (widget.campanhaId != null) {
      _carregarCampanha();
    } else {
      final hoje = DateTime.now();
      _dataInicio = hoje;
      _dataFim = hoje.add(const Duration(days: 7));
      _dataSorteio = _dataFim!.add(const Duration(days: 1));
      _valorMinimoController.text = '0,00';
      _valorXController.text = '50,00';
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _premioController.dispose();
    _valorMinimoController.dispose();
    _valorXController.dispose();
    super.dispose();
  }

  Future<void> _carregarCampanha() async {
    setState(() => _carregando = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('campanhas_sorteio')
          .doc(widget.campanhaId)
          .get();

      if (!snap.exists) {
        if (!mounted) return;
        _showSnackBar('Campanha não encontrada.', isError: true);
        Navigator.of(context).pop();
        return;
      }

      final data = snap.data() ?? {};

      _nomeController.text = data['nome'] ?? '';
      _descricaoController.text = data['descricao'] ?? '';
      _premioController.text = data['premioDescricao'] ?? '';

      final valorMinimo =
          (data['valorMinimo'] as num?)?.toDouble() ?? 0.0;
      final valorX = (data['valorX'] as num?)?.toDouble() ?? 50.0;

      _valorMinimoController.text = MoedaInputFormatter.format(valorMinimo);
      _valorXController.text = MoedaInputFormatter.format(valorX);

      final tsInicio = data['dataInicio'] as Timestamp?;
      final tsFim = data['dataFim'] as Timestamp?;
      final tsSorteio = data['dataSorteio'] as Timestamp?;

      _dataInicio = tsInicio?.toDate();
      _dataFim = tsFim?.toDate();
      _dataSorteio = tsSorteio?.toDate();

      _ativa = data['ativa'] as bool? ?? true;
      _statusAtual = data['status'] as String?;

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Erro ao carregar campanha: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  Future<void> _selecionarData({
    required DateTime? atual,
    required ValueChanged<DateTime> onSelected,
  }) async {
    final agora = DateTime.now();
    final inicial = atual ?? agora;

    final picked = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Selecione a data',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );

    if (picked != null) {
      onSelected(picked);
      setState(() {});
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    if (_dataInicio == null || _dataFim == null || _dataSorteio == null) {
      _showSnackBar('Defina as datas de início, fim e data do sorteio.', isError: true);
      return;
    }

    if (_dataFim!.isBefore(_dataInicio!)) {
      _showSnackBar('A data de fim deve ser igual ou posterior ? data de início.', isError: true);
      return;
    }
    if (_dataSorteio!.isBefore(_dataFim!)) {
      _showSnackBar('A data do sorteio deve ser igual ou posterior ? data de fim.', isError: true);
      return;
    }

    // ? Só permite uma campanha ativa por vez: ao criar/ativar, verifica se já existe
    if (_ativa) {
      final ativas = await CampanhasSorteioService.listarCampanhasAtivas(
        lojaId: widget.lojaId,
        excluirId: widget.campanhaId,
      );
      if (ativas.isNotEmpty) {
        final nome = ativas.first['nome'] ?? 'Campanha ativa';
        _showSnackBar(
          'Já existe uma campanha ativa: "$nome". '
          'Encerre ou desative a campanha atual antes de criar outra.',
          isError: true,
        );
        return;
      }
    }

    final valorMinimo = MoedaInputFormatter.parse(_valorMinimoController.text);
    final valorX = MoedaInputFormatter.parse(_valorXController.text);

    setState(() => _salvando = true);

    try {
      await CampanhasSorteioService.salvarCampanha(
        lojaId: widget.lojaId,
        campanhaId: widget.campanhaId,
        nome: _nomeController.text.trim(),
        descricao: _descricaoController.text.trim(),
        dataInicio: _dataInicio!,
        dataFim: _dataFim!,
        dataSorteio: _dataSorteio!,
        premioDescricao: _premioController.text.trim(),
        valorMinimo: valorMinimo,
        valorXPorNumero: valorX, // ?? agora casa com o service
        ativa: _ativa,
      );

      if (!mounted) return;

      _showSnackBar(
        widget.campanhaId == null
            ? 'Campanha criada com sucesso!'
            : 'Campanha atualizada com sucesso!',
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Erro ao salvar campanha: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _abrirGlobo() {
    if (widget.campanhaId == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GloboSorteioScreen(
          lojaId: widget.lojaId,
          campanhaId: widget.campanhaId!,
        ),
      ),
    );
  }

  // ? REMOVIDO: Configurar Roleta agora tem aba própria em Sorteios e Campanhas
  // void _abrirRoleta() {
  //   Navigator.of(context).push(
  //     MaterialPageRoute(
  //       builder: (_) => RoletaSorteScreen(lojaId: widget.lojaId),
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.campanhaId != null;

    return Scaffold(
      backgroundColor: const Color(0xFF05060A),
      appBar: AppBar(
        title: Text(isEdit ? 'Editar Campanha' : 'Nova Campanha'),
        backgroundColor: Colors.black,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Card(
                    color: const Color(0xFF10121A),
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título
                            Row(
                              children: [
                                const Icon(Icons.celebration,
                                    color: Colors.orange),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isEdit
                                        ? 'Campanha de Sorteio'
                                        : 'Nova Campanha de Sorteio',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_statusAtual != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade800,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _statusAtual!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Nome
                            TextFormField(
                              controller: _nomeController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDeco('Nome da campanha'),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Informe o nome da campanha';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Descrição
                            TextFormField(
                              controller: _descricaoController,
                              maxLines: 3,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDeco(
                                'Descrição da campanha',
                                hint:
                                    'Ex: Nas compras acima de R\$ 100 concorra a uma cesta...',
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Prêmio
                            TextFormField(
                              controller: _premioController,
                              maxLines: 2,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDeco(
                                'Prêmio',
                                hint: 'Ex: Cesta com R\$ 300 em produtos',
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Valor mínimo + valorX + ativa
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _valorMinimoController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [MoedaInputFormatter()],
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration: _inputDeco(
                                      'Valor mínimo para participar',
                                      prefixText: 'R\$ ',
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Informe o valor mínimo';
                                      }
                                      final valor = MoedaInputFormatter.parse(v);
                                      if (valor < 0) {
                                        return 'Valor inválido';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Tooltip(
                                    message: 'Cada R\$ X em compras gera 1 número da sorte. Ex: R\$ 50 = compra de R\$ 100 gera 2 números.',
                                    child: TextFormField(
                                    controller: _valorXController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [MoedaInputFormatter()],
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration: _inputDeco(
                                      'R\$ em compras = 1 número',
                                      prefixText: 'R\$ ',
                                      helperText: 'Ex: R\$ 50 = cada R\$ 50 em compras gera 1 número',
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Informe o valor X';
                                      }
                                      final valor = MoedaInputFormatter.parse(v);
                                      if (valor <= 0) {
                                        return 'Valor inválido';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Ativa?',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Switch(
                                      value: _ativa,
                                      onChanged: (v) =>
                                          setState(() => _ativa = v),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            const Text(
                              'Período da campanha',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),

                            Row(
                              children: [
                                Expanded(
                                  child: _DateChip(
                                    label: 'Início',
                                    date: _dataInicio,
                                    onTap: () => _selecionarData(
                                      atual: _dataInicio,
                                      onSelected: (d) {
                                        _dataInicio = d;
                                        if (_dataFim != null &&
                                            _dataFim!.isBefore(d)) {
                                          _dataFim = d;
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _DateChip(
                                    label: 'Fim',
                                    date: _dataFim,
                                    onTap: () => _selecionarData(
                                      atual: _dataFim,
                                      onSelected: (d) => _dataFim = d,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            const Text(
                              'Data do sorteio',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _DateChip(
                              label: 'Sorteio',
                              date: _dataSorteio,
                              onTap: () => _selecionarData(
                                atual: _dataSorteio,
                                onSelected: (d) => _dataSorteio = d,
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Info
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withValues(alpha:0.25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.deepPurpleAccent
                                      .withValues(alpha:0.5),
                                ),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline,
                                      color: Colors.deepPurpleAccent),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'O sistema gera números de 5 dígitos automaticamente '
                                      'para cada compra que atingir o valor mínimo. '
                                      'No dia do sorteio, use o Globo para sortear o número vencedor.',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Botões principais
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _salvando ? null : _salvar,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.greenAccent,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    icon: _salvando
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<
                                                      Color>(Colors.black),
                                            ),
                                          )
                                        : const Icon(Icons.save),
                                    label: Text(
                                      _salvando
                                          ? 'Salvando...'
                                          : (isEdit
                                              ? 'Salvar alterações'
                                              : 'Criar campanha'),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // ? Botão Globo (Configurar Roleta foi movido para aba própria)
                            if (isEdit)
                              ElevatedButton.icon(
                                onPressed: _abrirGlobo,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orangeAccent,
                                  foregroundColor: Colors.black,
                                ),
                                icon: const Icon(Icons.casino),
                                label: const Text('Abrir Globo'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  InputDecoration _inputDeco(
    String label, {
    String? hint,
    String? prefixText,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      helperText: helperText,
      helperStyle: const TextStyle(color: Colors.white54, fontSize: 11),
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF181A24),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.greenAccent),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DateChip({
    required this.label,
    required this.date,
    required this.onTap,
  });

  String _format(DateTime? dt) {
    if (dt == null) return 'Selecione';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF181A24),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month,
                size: 18, color: Colors.white.withValues(alpha:0.8)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _format(date),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

