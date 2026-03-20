// lib/screens/compartilhar_whatsapp_screen.dart
// Catálogo WhatsApp simplificado: compartilhar catálogo completo ou campanha.
// Usa apenas CatalogShareService; não duplica lógica de mensagem/URL.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/catalog_share_service.dart';
import '../services/public_store_link_helper.dart';
import '../services/loja_id_service.dart';

class CompartilharWhatsAppScreen extends StatefulWidget {
  const CompartilharWhatsAppScreen({super.key});

  @override
  State<CompartilharWhatsAppScreen> createState() => _CompartilharWhatsAppScreenState();
}

class _CompartilharWhatsAppScreenState extends State<CompartilharWhatsAppScreen> {
  String• _lojaId;
  String• _erro;
  bool _loading = true;

  final _campanhaNomeCtrl = TextEditingController();
  final _campanhaDescricaoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarLoja();
  }

  @override
  void dispose() {
    _campanhaNomeCtrl.dispose();
    _campanhaDescricaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarLoja() async {
    final lojaId = await LojaIdService.get();
    setState(() {
      _lojaId = lojaId;
      _loading = false;
      if (lojaId == null || lojaId.isEmpty) _erro = 'Loja não identificada.';
    });
  }

  String get _urlCatalogo {
    final url = buildPublicCatalogUrl(_lojaId);
    if (url == null) return '';
    return CatalogShareService.buildUrlWithParams(url);
  }

  void _copiar(String texto) {
    if (texto.isEmpty) return;
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mensagem copiada para a área de transferência')),
    );
  }

  Future<void> _abrirWhatsApp(String texto) async {
    if (texto.isEmpty) return;
    final uri = Uri.parse('https://wa.me/?text=${CatalogShareService.encodeForWhatsApp(texto)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Compartilhar no WhatsApp')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_erro != null && _lojaId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Compartilhar no WhatsApp')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_erro!, style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final urlCatalogo = _urlCatalogo;
    final msgCatalogo = CatalogShareService.buildCatalogShareMessage(url: urlCatalogo);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compartilhar no WhatsApp'),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(16),
        children: [
          // Catálogo completo
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.store, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Catálogo completo', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Compartilhe o link do seu catálogo com clientes.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha:0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(msgCatalogo, style: const TextStyle(height: 1.4)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: urlCatalogo.isEmpty • null : () => _copiar(msgCatalogo),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: urlCatalogo.isEmpty • null : () => _abrirWhatsApp(msgCatalogo),
                        icon: const Icon(Icons.chat, size: 18),
                        label: const Text('Abrir no WhatsApp'),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Campanha
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.campaign_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Campanha', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _campanhaNomeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome da campanha',
                      hintText: 'Ex: Black Friday',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _campanhaDescricaoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descrição (opcional)',
                      hintText: 'Ex: Descontos até 50%',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final nome = _campanhaNomeCtrl.text.trim();
                      final desc = _campanhaDescricaoCtrl.text.trim();
                      final msgCampanha = nome.isEmpty
                          • null
                          : CatalogShareService.buildCampaignShareMessage(
                              nomeCampanha: nome,
                              descricao: desc.isEmpty • null : desc,
                              url: urlCatalogo,
                            );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (msgCampanha != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha:0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SelectableText(msgCampanha, style: const TextStyle(height: 1.4)),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: () => _copiar(msgCampanha),
                                  icon: const Icon(Icons.copy, size: 18),
                                  label: const Text('Copiar'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: () => _abrirWhatsApp(msgCampanha),
                                  icon: const Icon(Icons.chat, size: 18),
                                  label: const Text('Abrir no WhatsApp'),
                                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                                ),
                              ],
                            ),
                          ] else
                            Text(
                              'Digite o nome da campanha para gerar a mensagem.',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Produto
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Produto', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Para compartilhar um produto específico, abra o catálogo no navegador (ou envie o link do catálogo acima) e use o botão compartilhar em cada produto.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
