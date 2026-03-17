// lib/screens/historico_cliente_detalhe_screen.dart
// Tela que mostra TODAS as compras de um cliente com data/hora e todos os produtos
// Produtos exatamente como vendidos (itens separados, sem misturar)

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/venda.dart';
import '../models/venda_item.dart';
import '../utils/text_utils.dart';

// Cores alinhadas com vendas_screen
const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF22C55E);
const Color _cardColor = Color(0xFFFFFFFF);
const Color _backgroundColor = Color(0xFFF8FAFC);
const Color _surfaceColor = Color(0xFF1E293B);

class HistoricoClienteDetalheScreen extends StatefulWidget {
  final String clienteNome;
  final String? clienteTelefone;
  final Box<Venda> vendasBox;
  final String lojaId;

  const HistoricoClienteDetalheScreen({
    super.key,
    required this.clienteNome,
    this.clienteTelefone,
    required this.vendasBox,
    required this.lojaId,
  });

  @override
  State<HistoricoClienteDetalheScreen> createState() => _HistoricoClienteDetalheScreenState();
}

class _HistoricoClienteDetalheScreenState extends State<HistoricoClienteDetalheScreen> {
  String ordenacaoCompras = 'data_desc'; // data_desc | data_asc

  List<Venda> _vendasDoCliente() {
    final nomeNorm = normalizeText(widget.clienteNome);
    var lista = widget.vendasBox.values.where((v) {
      if (v.lojaId != null && v.lojaId!.isNotEmpty && v.lojaId != widget.lojaId) {
        return false;
      }
      return normalizeText(v.clienteNome) == nomeNorm;
    }).toList();

    if (ordenacaoCompras == 'data_asc') {
      lista.sort((a, b) => a.data.compareTo(b.data));
    } else {
      lista.sort((a, b) => b.data.compareTo(a.data));
    }
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final vendas = _vendasDoCliente();

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Compras de ${widget.clienteNome}',
              style: const TextStyle(color: _surfaceColor),
            ),
            if (vendas.isNotEmpty)
              Text(
                '${vendas.length} compra(s)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey[600]),
              ),
          ],
        ),
        backgroundColor: _cardColor,
        foregroundColor: _surfaceColor,
        elevation: 0,
        actions: [
          if (widget.clienteTelefone != null &&
              widget.clienteTelefone!.replaceAll(RegExp(r'\D'), '').length >= 10) ...[
            IconButton(
              icon: const Icon(Icons.phone),
              tooltip: 'Ligar',
              onPressed: () async {
                final tel = widget.clienteTelefone!.replaceAll(RegExp(r'\D'), '');
                final e164 = tel.startsWith('55') ? tel : '55$tel';
                try {
                  await launchUrl(Uri.parse('tel:+$e164'));
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Não foi possível abrir o discador.')),
                    );
                  }
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.chat),
              tooltip: 'WhatsApp',
              onPressed: () async {
                final tel = widget.clienteTelefone!.replaceAll(RegExp(r'\D'), '');
                final e164 = tel.startsWith('55') ? tel : '55$tel';
                try {
                  await launchUrl(Uri.parse('https://wa.me/$e164'));
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
                    );
                  }
                }
              },
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (vendas.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: _cardColor,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: ordenacaoCompras,
                    icon: const Icon(Icons.sort, color: _primaryColor, size: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    onChanged: (value) {
                      if (value != null) setState(() => ordenacaoCompras = value);
                    },
                    items: const [
                      DropdownMenuItem(value: 'data_desc', child: Text('Ordenar: Data (mais recente)')),
                      DropdownMenuItem(value: 'data_asc', child: Text('Ordenar: Data (mais antiga)')),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: vendas.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhuma compra encontrada para este cliente.',
                          style: TextStyle(fontSize: 18, color: Colors.grey[500]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: vendas.length,
                    itemBuilder: (context, index) {
                      final venda = vendas[index];
                      return _CompraCard(venda: venda);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CompraCard extends StatelessWidget {
  final Venda venda;

  const _CompraCard({required this.venda});

  @override
  Widget build(BuildContext context) {
    final itens = venda.itensOuVazio;
    final temItens = itens.isNotEmpty;
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header da compra
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _successColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.receipt_long, color: _successColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('dd/MM/yyyy - HH:mm').format(venda.data),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _surfaceColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        venda.formasPagamentoDiscriminado,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  currencyFormat.format(venda.total),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _successColor,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Seções (igual vendas_screen)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailSection('Cliente', [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha:0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _primaryColor.withValues(alpha:0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha:0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.person, size: 20, color: _primaryColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SelectableText(
                            venda.clienteNome,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _surfaceColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _buildDetailSection('Produtos', [
                  if (temItens) ...[
                    ...itens.map((item) => _buildProdutoItem(item)),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: SelectableText(
                        venda.produtosDescricao,
                        style: const TextStyle(
                          fontSize: 14,
                          color: _surfaceColor,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  if (venda.frete > 0 || venda.desconto > 0) ...[
                    const Divider(height: 24),
                    if (venda.frete > 0)
                      _buildDetailRow(Icons.local_shipping, 'Frete', currencyFormat.format(venda.frete)),
                    if (venda.desconto > 0)
                      _buildDetailRow(Icons.discount, 'Desconto', '${venda.desconto.toStringAsFixed(1)}%'),
                  ],
                ]),
                if (venda.observacao.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildDetailSection('Observação', [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: SelectableText(
                        venda.observacao,
                        style: TextStyle(fontSize: 14, color: Colors.orange[800]),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey[500],
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _backgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _primaryColor),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _surfaceColor),
          ),
        ],
      ),
    );
  }

  Widget _buildProdutoItem(VendaItem item) {
    final subtotal = item.precoUnitario * item.quantidade;
    final variacao = [
      if (item.tamanho.isNotEmpty) item.tamanho,
      if (item.cor.isNotEmpty) item.cor,
    ].join(' / ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _successColor.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2_outlined, size: 18, color: _successColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.quantidade}x ${item.produtoNome}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _surfaceColor,
                  ),
                ),
                if (variacao.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      variacao,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            'R\$ ${subtotal.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _successColor,
            ),
          ),
        ],
      ),
    );
  }
}

