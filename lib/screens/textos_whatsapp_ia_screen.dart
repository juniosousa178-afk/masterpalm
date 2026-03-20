// lib/screens/textos_whatsapp_ia_screen.dart
// Gera mensagens prontas para WhatsApp: pós-venda, recuperação de carrinho, promoção, novidade.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/loja_id_service.dart';

const List<Map<String, String>> _tipos = [
  {'id': 'posVenda', 'label': 'Pós-venda', 'hint': 'Agradecimento e pedido de avaliação'},
  {'id': 'recuperacaoCarrinho', 'label': 'Recuperação de carrinho', 'hint': 'Lembrete para finalizar compra'},
  {'id': 'promocao', 'label': 'Promoção', 'hint': 'Anúncio de oferta'},
  {'id': 'novidade', 'label': 'Novidade', 'hint': 'Lançamento ou novo produto'},
];

class TextosWhatsAppIaScreen extends StatefulWidget {
  const TextosWhatsAppIaScreen({super.key});

  @override
  State<TextosWhatsAppIaScreen> createState() => _TextosWhatsAppIaScreenState();
}

class _TextosWhatsAppIaScreenState extends State<TextosWhatsAppIaScreen> {
  final _contextoCtrl = TextEditingController();
  String _tipoSelecionado = _tipos.first['id']!;
  String? _mensagemGerada;
  bool _gerando = false;

  @override
  void dispose() {
    _contextoCtrl.dispose();
    super.dispose();
  }

  Future<void> _gerar() async {
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    setState(() {
      _gerando = true;
      _mensagemGerada = null;
    });
    try {
      final msg = await AiLojaService.sugerirMensagemWhatsApp(
        tipo: _tipoSelecionado,
        contexto: _contextoCtrl.text.trim().isEmpty ? null : _contextoCtrl.text.trim(),
      );
      if (mounted) {
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        setState(() {
          _mensagemGerada = msg;
          _gerando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _gerando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AiLojaService.messageForUser(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _copiar() {
    if (_mensagemGerada == null) return;
    Clipboard.setData(ClipboardData(text: _mensagemGerada!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mensagem copiada para a área de transferência')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Textos para WhatsApp'),
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
                  Text('Tipo de mensagem', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._tipos.map((t) {
                    final id = t['id']!;
                    return RadioListTile<String>(
                      title: Text(t['label']!),
                      subtitle: Text(t['hint']!, style: theme.textTheme.bodySmall),
                      value: id,
                      // ignore: deprecated_member_use
                      groupValue: _tipoSelecionado,
                      // ignore: deprecated_member_use
                      onChanged: (v) => setState(() => _tipoSelecionado = v!),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contextoCtrl,
            decoration: const InputDecoration(
              labelText: 'Contexto (opcional)',
              hintText: 'Ex: nome do produto, promoção relâmpago, desconto 10%',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _gerando ? null : _gerar,
            icon: _gerando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_gerando ? 'Gerando…' : 'Gerar mensagem'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          if (_mensagemGerada != null) ...[
            const SizedBox(height: 20),
            Card(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha:0.5),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Mensagem gerada', style: theme.textTheme.titleMedium),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: _copiar,
                          tooltip: 'Copiar',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(_mensagemGerada!, style: const TextStyle(height: 1.4)),
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

