// lib/widgets/shipping_automation_card.dart
// Envio automático do frete ao carrinho do provedor (Melhor Envio/SuperFrete):
// flags por loja e dados do remetente, gravados via Callable no backend.

import 'package:flutter/material.dart';

import '../services/shipping_export_service.dart';

class ShippingAutomationCard extends StatefulWidget {
  const ShippingAutomationCard({super.key, required this.lojaId});

  final String lojaId;

  @override
  State<ShippingAutomationCard> createState() => _ShippingAutomationCardState();
}

class _ShippingAutomationCardState extends State<ShippingAutomationCard> {
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);

  bool _loading = true;
  bool _saving = false;
  bool _autoMelhorEnvio = false;
  bool _autoSuperFrete = false;
  bool _senderComplete = false;
  String _documentMasked = '';
  String _companyDocumentMasked = '';
  String _shippingDocument = 'declaracao_conteudo';

  final _nameCtrl = TextEditingController();
  final _documentCtrl = TextEditingController();
  final _companyDocumentCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _complementCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _documentCtrl,
      _companyDocumentCtrl,
      _phoneCtrl,
      _postalCodeCtrl,
      _addressCtrl,
      _numberCtrl,
      _complementCtrl,
      _districtCtrl,
      _cityCtrl,
      _stateCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final cfg =
        await ShippingExportService.getAutomationConfig(lojaId: widget.lojaId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (cfg == null) return;
      final flags = cfg['flags'] is Map ? cfg['flags'] as Map : const {};
      final sender = cfg['sender'] is Map ? cfg['sender'] as Map : const {};
      _autoMelhorEnvio = flags['melhorEnvio'] == true;
      _autoSuperFrete = flags['superFrete'] == true;
      _senderComplete = cfg['senderComplete'] == true;
      _documentMasked = (sender['documentMasked'] ?? '').toString();
      _companyDocumentMasked =
          (sender['companyDocumentMasked'] ?? '').toString();
      _shippingDocument =
          sender['shippingDocument'] == 'nota_fiscal'
              ? 'nota_fiscal'
              : 'declaracao_conteudo';
      _nameCtrl.text = (sender['name'] ?? '').toString();
      _phoneCtrl.text = (sender['phone'] ?? '').toString();
      _postalCodeCtrl.text = (sender['postalCode'] ?? '').toString();
      _addressCtrl.text = (sender['address'] ?? '').toString();
      _numberCtrl.text = (sender['number'] ?? '').toString();
      _complementCtrl.text = (sender['complement'] ?? '').toString();
      _districtCtrl.text = (sender['district'] ?? '').toString();
      _cityCtrl.text = (sender['city'] ?? '').toString();
      _stateCtrl.text = (sender['state'] ?? '').toString();
    });
  }

  Map<String, dynamic> _senderPayload() {
    final document = _documentCtrl.text.trim();
    final companyDocument = _companyDocumentCtrl.text.trim();
    return {
      'name': _nameCtrl.text.trim(),
      if (document.isNotEmpty) 'document': document,
      if (companyDocument.isNotEmpty) 'companyDocument': companyDocument,
      'phone': _phoneCtrl.text.trim(),
      'postalCode': _postalCodeCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'number': _numberCtrl.text.trim(),
      'complement': _complementCtrl.text.trim(),
      'district': _districtCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'state': _stateCtrl.text.trim().toUpperCase(),
      'shippingDocument': _shippingDocument,
    };
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final hasSenderInput = [
      _nameCtrl,
      _documentCtrl,
      _companyDocumentCtrl,
      _postalCodeCtrl,
      _addressCtrl,
      _cityCtrl,
    ].any((c) => c.text.trim().isNotEmpty);
    final res = await ShippingExportService.saveAutomationConfig(
      lojaId: widget.lojaId,
      sender: hasSenderInput ? _senderPayload() : null,
      flags: {'melhorEnvio': _autoMelhorEnvio, 'superFrete': _autoSuperFrete},
    );
    if (!mounted) return;
    setState(() => _saving = false);
    final ok = res['ok'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Envio automático salvo.'
            : (res['message'] ?? 'Não foi possível salvar a configuração.')
                .toString()),
      ),
    );
    if (ok) {
      _documentCtrl.clear();
      _companyDocumentCtrl.clear();
      await _load();
    }
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.outbox, color: _primaryColor),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Envio automático do frete',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quando o pagamento for aprovado (ou quando você confirmar o pedido), '
                    'o frete escolhido pelo cliente é enviado ao carrinho da sua conta no provedor. '
                    'A etiqueta não é comprada automaticamente.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enviar automaticamente ao Melhor Envio'),
                    value: _autoMelhorEnvio,
                    onChanged: (v) => setState(() => _autoMelhorEnvio = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enviar automaticamente à SuperFrete'),
                    subtitle: const Text(
                      'Disponível apenas em modo de testes (sandbox) da SuperFrete.',
                    ),
                    value: _autoSuperFrete,
                    onChanged: (v) => setState(() => _autoSuperFrete = v),
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Remetente',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_senderComplete)
                        const Icon(Icons.check_circle,
                            color: _successColor, size: 18),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _field(_nameCtrl, 'Nome ou razão social'),
                  _field(
                    _documentCtrl,
                    'CPF',
                    hint: _documentMasked.isNotEmpty
                        ? 'Cadastrado: $_documentMasked'
                        : null,
                    keyboardType: TextInputType.number,
                  ),
                  _field(
                    _companyDocumentCtrl,
                    'CNPJ',
                    hint: _companyDocumentMasked.isNotEmpty
                        ? 'Cadastrado: $_companyDocumentMasked'
                        : null,
                    keyboardType: TextInputType.number,
                  ),
                  _field(_phoneCtrl, 'Telefone',
                      keyboardType: TextInputType.phone),
                  _field(_postalCodeCtrl, 'CEP',
                      keyboardType: TextInputType.number),
                  _field(_addressCtrl, 'Endereço'),
                  _field(_numberCtrl, 'Número'),
                  _field(_complementCtrl, 'Complemento'),
                  _field(_districtCtrl, 'Bairro'),
                  _field(_cityCtrl, 'Cidade'),
                  _field(_stateCtrl, 'UF'),
                  DropdownButtonFormField<String>(
                    value: _shippingDocument,
                    decoration: InputDecoration(
                      labelText: 'Documento do envio',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'declaracao_conteudo',
                        child: Text('Declaração de conteúdo'),
                      ),
                      DropdownMenuItem(
                        value: 'nota_fiscal',
                        child: Text('Nota fiscal'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _shippingDocument = v);
                    },
                  ),
                  if (_shippingDocument == 'nota_fiscal')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Com nota fiscal, o pedido só é enviado quando tiver a chave da nota.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Salvar envio automático'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _successColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
