// Painel somente leitura do snapshot de cliente do pedido / pré-pedido.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/pedido_cliente_snapshot_helpers.dart';
import '../services/customer_metrics_service.dart';

class PedidoClienteSnapshotPanel extends StatefulWidget {
  const PedidoClienteSnapshotPanel({
    super.key,
    required this.cliente,
    this.lojaId,
  });

  /// Mapa `cliente` gravado no pré-pedido/pedido (snapshot).
  final Map<String, dynamic>? cliente;
  final String? lojaId;

  @override
  State<PedidoClienteSnapshotPanel> createState() =>
      _PedidoClienteSnapshotPanelState();
}

class _PedidoClienteSnapshotPanelState extends State<PedidoClienteSnapshotPanel> {
  CustomerMetrics _metrics = CustomerMetrics.empty;
  bool _loadingMetrics = false;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  @override
  void didUpdateWidget(covariant PedidoClienteSnapshotPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cliente != widget.cliente ||
        oldWidget.lojaId != widget.lojaId) {
      _loadMetrics();
    }
  }

  Future<void> _loadMetrics() async {
    final c = widget.cliente;
    final lojaId = widget.lojaId;
    if (c == null || lojaId == null || lojaId.isEmpty) return;
    setState(() => _loadingMetrics = true);
    final m = await CustomerMetricsService.loadForCliente(
      lojaId: lojaId,
      clienteNome: pedidoClienteCampo(c, ['nome', 'name']),
      clienteTelefone: pedidoClienteCampo(c, ['telefone', 'whatsapp', 'phone']),
      clienteId: pedidoClienteCampo(c, ['clienteId', 'id']),
    );
    if (!mounted) return;
    setState(() {
      _metrics = m;
      _loadingMetrics = false;
    });
  }

  Future<void> _copy(String label, String value) async {
    if (value.trim().isEmpty) {
      _snack('$label vazio');
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    _snack('$label copiado');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) {
      _snack('Link indisponível');
      return;
    }
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      _snack('Não foi possível abrir');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;
    if (c == null || c.isEmpty) {
      return _box(child: const Text('Cliente não informado'));
    }

    final nome = pedidoClienteCampo(c, ['nome', 'name']);
    final cpf = pedidoClienteCampo(c, ['cpf', 'documento']);
    final tel = pedidoClienteCampo(c, ['telefone', 'phone']);
    final wa = pedidoClienteCampo(c, ['whatsapp', 'telefone', 'phone']);
    final email = pedidoClienteCampo(c, ['email']);
    final end = pedidoClienteEnderecoMap(c);
    String endField(List<String> keys) => pedidoClienteCampo(
          {...c, ...end},
          keys,
        );

    final rua = endField(['rua', 'logradouro', 'endereco', 'street']);
    final numero = endField(['numero', 'number', 'n']);
    final bairro = endField(['bairro', 'district']);
    final cidade = endField(['cidade', 'city']);
    final estado = endField(['estado', 'uf', 'state']);
    final cep = endField(['cep', 'zip']);
    final complemento = endField(['complemento', 'complement']);
    final referencia = endField(['referencia', 'referência', 'reference']);
    final enderecoTexto = formatarEnderecoSnapshotCompleto(c);
    final df = DateFormat('dd/MM/yyyy');

    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Identificação',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          _row('Nome', nome),
          _row('CPF', cpf),
          _row('Telefone', tel),
          _row('WhatsApp', wa),
          _row('Email', email),
          const SizedBox(height: 12),
          const Text(
            'Endereço (snapshot do pedido)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          _row('Rua', rua),
          _row('Número', numero),
          _row('Bairro', bairro),
          _row('Cidade', cidade),
          _row('Estado', estado),
          _row('CEP', cep),
          _row('Complemento', complemento),
          _row('Referência', referencia),
          if (enderecoTexto.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              enderecoTexto,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _action(
                Icons.copy,
                'Copiar CPF',
                () => _copy('CPF', cpf),
              ),
              _action(
                Icons.copy_all,
                'Copiar endereço',
                () => _copy('Endereço', enderecoTexto.replaceAll('\n', ', ')),
              ),
              _action(
                Icons.phone,
                'Copiar telefone',
                () => _copy('Telefone', tel),
              ),
              _action(
                Icons.chat,
                'WhatsApp',
                () => _openUrl(whatsappUrlFromTelefone(wa.isNotEmpty ? wa : tel)),
              ),
              _action(
                Icons.map,
                'Google Maps',
                () => _openUrl(googleMapsUrlFromClienteSnapshot(c)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Histórico do cliente',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (_loadingMetrics)
            const LinearProgressIndicator(minHeight: 2)
          else ...[
            _row(
              'Cliente desde',
              _metrics.clienteDesde == null
                  ? '—'
                  : df.format(_metrics.clienteDesde!),
            ),
            _row('Pedidos', '${_metrics.quantidadePedidos}'),
            _row(
              'Total comprado',
              'R\$ ${_metrics.valorTotalComprado.toStringAsFixed(2)}',
            ),
            _row(
              'Ticket médio',
              'R\$ ${_metrics.ticketMedio.toStringAsFixed(2)}',
            ),
            _row(
              'Última compra',
              _metrics.ultimaCompra == null
                  ? '—'
                  : df.format(_metrics.ultimaCompra!),
            ),
            if (_metrics.vip || _metrics.recorrente)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    if (_metrics.vip)
                      const Chip(
                        label: Text('VIP'),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (_metrics.recorrente)
                      const Chip(
                        label: Text('Recorrente'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _box({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _row(String label, String value) {
    final v = value.trim().isEmpty ? '—' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }
}
