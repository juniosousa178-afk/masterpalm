// lib/widgets/vendedor_aguarde_widget.dart
// Widget exibido quando vendedor não tem nenhuma permissão liberada

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/public_store_link_helper.dart';
import '../services/store_resolver_facade.dart';

/// Widget exibido para vendedor sem permissões liberadas
class VendedorAguardeWidget extends StatefulWidget {
  final String vendedorNome;
  final String lojaId;
  final VoidCallback? onLogout;

  const VendedorAguardeWidget({
    super.key,
    required this.vendedorNome,
    required this.lojaId,
    this.onLogout,
  });

  @override
  State<VendedorAguardeWidget> createState() => _VendedorAguardeWidgetState();
}

class _VendedorAguardeWidgetState extends State<VendedorAguardeWidget> {
  String? _linkCatalogo;
  bool _copiado = false;

  @override
  void initState() {
    super.initState();
    _carregarLink();
  }

  Future<void> _carregarLink() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Usar widget.lojaId se válido, senão StoreResolverFacade (mesma lógica da loja modelo)
      String storeId = widget.lojaId.trim();
      if (storeId.isEmpty) {
        storeId = (await StoreResolverFacade.resolveForAdminApp())?.trim() ?? '';
      }

      if (storeId.isEmpty) {
        debugPrint('⚠️ [VENDEDOR] storeId não encontrado');
        return;
      }

      // Buscar slug da loja para o link
      String lojaSlug = storeId;
      try {
        final lojaDoc = await FirebaseFirestore.instance
            .collection('lojas')
            .doc(storeId)
            .get();
        if (lojaDoc.exists) {
          final lojaData = lojaDoc.data() ?? {};
          lojaSlug = (lojaData['slug'] ?? lojaData['id'] ?? storeId).toString();
        }
      } catch (e) {
        debugPrint('⚠️ [VENDEDOR] Erro ao buscar slug da loja (type=${e.runtimeType})');
      }

      // Gerar link com ref do vendedor (só se slug for válido, sem placeholder)
      if (!isValidForPublicLink(lojaSlug)) {
        if (mounted) setState(() => _linkCatalogo = null);
        return;
      }
      final link = '/loja/$lojaSlug?ref=${user.uid}';

      if (mounted) {
        setState(() => _linkCatalogo = link);
      }

      debugPrint('✅ [VENDEDOR] Link gerado: $link');
    } catch (e) {
      debugPrint('❌ [VENDEDOR] Erro ao carregar link (type=${e.runtimeType})');
    }
  }

  void _copiarLink() {
    if (_linkCatalogo == null) return;

    // Montar URL completa (usar URL base do app)
    final urlCompleta = 'https://app.mastepalm.com.br$_linkCatalogo';

    Clipboard.setData(ClipboardData(text: urlCompleta));
    setState(() => _copiado = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copiado!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiado = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('MasterPalm'),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (widget.onLogout != null)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: widget.onLogout,
              tooltip: 'Sair',
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Ícone
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.hourglass_empty,
                    size: 64,
                    color: Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 32),

                // Saudação
                Text(
                  'Olá, ${widget.vendedorNome}!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Mensagem principal
                const Text(
                  'Aguarde a liberação do administrador',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Submensagem
                Text(
                  'O administrador da loja ainda não liberou suas permissões de acesso.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Card com link do catálogo
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.link,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Seu link do catálogo',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Enquanto aguarda, você já pode compartilhar seu link de vendas:',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_linkCatalogo != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              'app.mastepalm.com.br$_linkCatalogo',
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _linkCatalogo != null ? _copiarLink : null,
                            icon: Icon(_copiado ? Icons.check : Icons.copy),
                            label: Text(_copiado ? 'Copiado!' : 'Copiar link'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _copiado ? Colors.green : Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Dica
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Vendas realizadas pelo seu link geram comissão automaticamente!',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
