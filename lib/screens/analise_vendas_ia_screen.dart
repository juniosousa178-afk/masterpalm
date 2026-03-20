// lib/screens/analise_vendas_ia_screen.dart
// Pergunte sobre suas vendas em linguagem natural; a IA responde com base em um resumo local.

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/hive_box_names.dart';
import '../models/venda.dart';
import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/loja_id_service.dart';
import '../services/store_resolver_facade.dart';

class AnaliseVendasIaScreen extends StatefulWidget {
  const AnaliseVendasIaScreen({super.key});

  @override
  State<AnaliseVendasIaScreen> createState() => _AnaliseVendasIaScreenState();
}

class _AnaliseVendasIaScreenState extends State<AnaliseVendasIaScreen> {
  final _perguntaCtrl = TextEditingController();
  String• _resposta;
  String• _resumoUsado;
  bool _carregando = false;
  bool _enviando = false;

  @override
  void dispose() {
    _perguntaCtrl.dispose();
    super.dispose();
  }

  Future<String> _montarResumoVendas() async {
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null) return 'Nenhuma loja ativa.';
    try {
      final box = Hive.box<Venda>(HiveBoxNames.vendas(lojaId));
      final agora = DateTime.now();
      final inicio = agora.subtract(const Duration(days: 30));
      final vendas = box.values.where((v) => v.data.isAfter(inicio)).toList();
      if (vendas.isEmpty) {
        return 'Últimos 30 dias: nenhuma venda registrada.';
      }
      final total = vendas.fold<double>(0, (s, v) => s + v.total);
      final ticketMedio = total / vendas.length;
      final porProduto = <String, int>{};
      for (final v in vendas) {
        if (v.itens != null) {
          for (final item in v.itens!) {
            porProduto[item.produtoNome] = (porProduto[item.produtoNome] ?• 0) + item.quantidade;
          }
        }
      }
      final top = porProduto.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top5 = top.take(5).map((e) => '${e.key}: ${e.value} un').join('; ');
      return 'Últimos 30 dias: ${vendas.length} vendas; total R\$ ${total.toStringAsFixed(2)}; '
          'ticket médio R\$ ${ticketMedio.toStringAsFixed(2)}. '
          'Top produtos (quantidade): $top5.';
    } catch (_) {
      return 'Erro ao carregar dados de vendas.';
    }
  }

  Future<void> _enviar() async {
    final pergunta = _perguntaCtrl.text.trim();
    if (pergunta.isEmpty || _enviando) return;
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    setState(() {
      _enviando = true;
      _resposta = null;
    });
    try {
      if (_resumoUsado == null) {
        _carregando = true;
        if (mounted) setState(() {});
        _resumoUsado = await _montarResumoVendas();
        _carregando = false;
      }
      final resposta = await AiLojaService.analiseVendasNatural(
        pergunta: pergunta,
        resumoVendas: _resumoUsado,
      );
      if (mounted) {
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        setState(() {
          _resposta = resposta;
          _enviando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AiLojaService.messageForUser(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pergunte sobre vendas'),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Faça perguntas em linguagem natural sobre seus últimos 30 dias de vendas.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (_resumoUsado != null) ...[
                    const SizedBox(height: 12),
                    Text('Dados usados:', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    SelectableText(
                      _resumoUsado!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _perguntaCtrl,
            decoration: const InputDecoration(
              labelText: 'Sua pergunta',
              hintText: 'Ex: Qual meu produto mais vendido• Quanto vendi na última semana?',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (_carregando || _enviando) • null : _enviar,
            icon: _enviando || _carregando
                • const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_carregando • 'Carregando…' : _enviando • 'Analisando…' : 'Perguntar'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          if (_resposta != null) ...[
            const SizedBox(height: 20),
            Card(
              color: theme.colorScheme.primaryContainer.withValues(alpha:0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resposta', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          child: SelectableText(_resposta!, style: const TextStyle(height: 1.4)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

