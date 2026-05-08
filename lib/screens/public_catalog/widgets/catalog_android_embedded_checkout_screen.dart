import 'package:flutter/material.dart';

import '../../../web/native_checkout_input_stub.dart'
    if (dart.library.html) '../../../web/native_checkout_input_web.dart';
import '../catalog_helpers.dart'
    show catalogIsPlausibleMpBuyerEmail, catalogIsValidCpfForMpPayer;
import 'catalog_checkout_external_browser_gate.dart';

class CatalogAndroidEmbeddedCheckoutScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> fretes;
  final Map<String, dynamic>? initialFormData;
  final Color primary;
  final Color cardColor;
  final Color textColor;
  final String catalogUrl;

  const CatalogAndroidEmbeddedCheckoutScreen({
    super.key,
    required this.items,
    required this.fretes,
    required this.initialFormData,
    required this.primary,
    required this.cardColor,
    required this.textColor,
    required this.catalogUrl,
  });

  @override
  State<CatalogAndroidEmbeddedCheckoutScreen> createState() =>
      _CatalogAndroidEmbeddedCheckoutScreenState();
}

class _CatalogAndroidEmbeddedCheckoutScreenState
    extends State<CatalogAndroidEmbeddedCheckoutScreen> {
  final Map<String, String> _data = <String, String>{};
  final Set<String> _errorKeys = <String>{};
  String? _errorMessage;
  String _pagamento = 'PIX';
  int _freteIndex = 0;

  @override
  void initState() {
    super.initState();
    final init = widget.initialFormData ?? const <String, dynamic>{};
    for (final key in const <String>[
      'nome',
      'cpf',
      'email',
      'tel',
      'cep',
      'rua',
      'numero',
      'bairro',
      'cidade',
      'estado',
      'complemento',
      'obs',
      'cupomCodigo',
    ]) {
      _data[key] = (init[key] ?? '').toString();
    }
    _pagamento = (init['pagamento'] ?? 'PIX').toString();
    final rawFrete = init['freteIndex'];
    if (rawFrete is int) {
      _freteIndex = rawFrete;
    } else if (rawFrete is num) {
      _freteIndex = rawFrete.toInt();
    } else if (rawFrete is String) {
      _freteIndex = int.tryParse(rawFrete) ?? 0;
    }
  }

  void _setValue(String key, String value) {
    _data[key] = value;
    if (_errorKeys.contains(key)) {
      setState(() {
        _errorKeys.remove(key);
        if (_errorKeys.isEmpty) _errorMessage = null;
      });
    }
  }

  String _value(String key) => _data[key] ?? '';

  bool get _requiresAddress {
    if (_freteIndex >= 0 && _freteIndex < widget.fretes.length) {
      final tipo = (widget.fretes[_freteIndex]['tipo'] ?? '')
          .toString()
          .toLowerCase();
      return tipo != 'retirada';
    }
    return true;
  }

  bool _validate() {
    _errorKeys.clear();
    _errorMessage = null;

    final requiredLabels = <String, String>{
      'nome': 'Nome',
      'cpf': 'CPF',
      'email': 'E-mail',
      'tel': 'Telefone',
      if (_requiresAddress) ...{
        'cep': 'CEP',
        'rua': 'Rua',
        'numero': 'Número',
        'bairro': 'Bairro',
        'cidade': 'Cidade',
        'estado': 'UF',
      },
    };

    for (final entry in requiredLabels.entries) {
      if (_value(entry.key).trim().isEmpty) {
        _errorKeys.add(entry.key);
      }
    }

    final cpf = _value('cpf').replaceAll(RegExp(r'[^0-9]'), '');
    final tel = _value('tel').replaceAll(RegExp(r'[^0-9]'), '');
    final cep = _value('cep').replaceAll(RegExp(r'[^0-9]'), '');

    if (!_errorKeys.contains('cpf')) {
      if (cpf.length != 11 || !catalogIsValidCpfForMpPayer(_value('cpf'))) {
        _errorKeys.add('cpf');
        _errorMessage = 'CPF inválido. Confira os 11 dígitos.';
      }
    }
    if (!_errorKeys.contains('email') &&
        !catalogIsPlausibleMpBuyerEmail(_value('email'))) {
      _errorKeys.add('email');
      _errorMessage = 'Digite um e-mail válido.';
    }
    if (!_errorKeys.contains('tel') && tel.length < 10) {
      _errorKeys.add('tel');
      _errorMessage = 'Telefone deve ter DDD e número.';
    }
    if (_requiresAddress && !_errorKeys.contains('cep') && cep.length != 8) {
      _errorKeys.add('cep');
      _errorMessage = 'CEP deve ter 8 dígitos.';
    }

    if (_errorKeys.isNotEmpty) {
      _errorMessage ??= 'Preencha os campos obrigatórios para continuar.';
      setState(() {});
      return false;
    }
    return true;
  }

  Map<String, dynamic> _formData() {
    return <String, dynamic>{
      ..._data,
      'email': _value('email').trim().toLowerCase(),
      'freteIndex': _freteIndex,
      'pagamento': _pagamento,
    };
  }

  void _continueCheckout() {
    if (!_validate()) return;
    Navigator.of(context).pop<Map<String, dynamic>>(_formData());
  }

  double get _subtotal {
    var total = 0.0;
    for (final item in widget.items) {
      final price = _itemPrice(item);
      final qtyRaw = item['quantidade'] ?? item['qty'] ?? 1;
      final qty = qtyRaw is num
          ? qtyRaw.toInt()
          : int.tryParse(qtyRaw.toString()) ?? 1;
      total += price * (qty <= 0 ? 1 : qty);
    }
    return total;
  }

  double _itemPrice(Map<String, dynamic> item) {
    final raw = item['preco'] ?? item['price'] ?? 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString().replaceAll(',', '.')) ?? 0.0;
  }

  int get _itemCount {
    var total = 0;
    for (final item in widget.items) {
      final qtyRaw = item['quantidade'] ?? item['qty'] ?? 1;
      final qty = qtyRaw is num
          ? qtyRaw.toInt()
          : int.tryParse(qtyRaw.toString()) ?? 1;
      total += qty <= 0 ? 1 : qty;
    }
    return total;
  }

  String _money(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

  TextStyle _safeTextStyle(
    TextStyle? base, {
    Color? color,
    FontWeight? fontWeight,
    double? height,
  }) {
    return (base ?? const TextStyle()).copyWith(
      color: color,
      fontFamily: 'Arial',
      fontFamilyFallback: const <String>['Roboto', 'sans-serif'],
      fontWeight: fontWeight,
      height: height,
      wordSpacing: 1.5,
    );
  }

  Widget _field(
    String key,
    String label, {
    NativeCheckoutInputKind kind = NativeCheckoutInputKind.text,
    String? hintText,
    bool requiredField = false,
  }) {
    return NativeCheckoutInput(
      label: label,
      value: _value(key),
      onChanged: (value) => _setValue(key, value),
      kind: kind,
      hintText: hintText,
      requiredField: requiredField,
      hasError: _errorKeys.contains(key),
    );
  }

  Widget _sectionCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outline.withOpacity(0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: _safeTextStyle(
                theme.textTheme.titleMedium,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _cartSummary(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleItems = widget.items.take(3).toList();
    final remaining = widget.items.length - visibleItems.length;

    return _sectionCard(
      context: context,
      title: 'Resumo do carrinho',
      children: [
        Text(
          'Seu carrinho será mantido. Confira os dados e continue para escolher frete e finalizar.',
          style: _safeTextStyle(
            theme.textTheme.bodyMedium,
            color: colorScheme.onSurface.withOpacity(0.75),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        for (final item in visibleItems) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  (item['nome'] ?? item['name'] ?? 'Produto').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _safeTextStyle(theme.textTheme.bodyMedium),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'R\$ ${_money(_itemPrice(item))}',
                style: _safeTextStyle(
                  theme.textTheme.bodyMedium,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (remaining > 0)
          Text(
            '+ $remaining ${remaining == 1 ? 'item' : 'itens'} no carrinho',
            style: _safeTextStyle(
              theme.textTheme.bodySmall,
              color: colorScheme.onSurface.withOpacity(0.62),
            ),
          ),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '$_itemCount ${_itemCount == 1 ? 'item' : 'itens'}',
                style: _safeTextStyle(theme.textTheme.bodyMedium),
              ),
            ),
            Text(
              'Subtotal R\$ ${_money(_subtotal)}',
              style: _safeTextStyle(
                theme.textTheme.titleSmall,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _paymentSelector(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Forma de pagamento',
          style: _safeTextStyle(
            theme.textTheme.labelMedium,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outline.withOpacity(0.32)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _pagamento,
              isExpanded: true,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              items: const [
                DropdownMenuItem(value: 'PIX', child: Text('PIX')),
                DropdownMenuItem(
                  value: 'CARTAO',
                  child: Text('Cartão de crédito / débito'),
                ),
                DropdownMenuItem(value: 'DINHEIRO', child: Text('Dinheiro')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _pagamento = value);
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(
          'Checkout',
          style: _safeTextStyle(
            theme.textTheme.titleLarge,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cartSummary(context),
                  const SizedBox(height: 16),
                  _sectionCard(
                    context: context,
                    title: 'Dados para finalizar',
                    children: [
                      Text(
                        'Use os campos abaixo para abrir o teclado nativo do Android dentro do Instagram.',
                        style: _safeTextStyle(
                          theme.textTheme.bodyMedium,
                          color: colorScheme.onSurface.withOpacity(0.75),
                          height: 1.35,
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _errorMessage!,
                              style: _safeTextStyle(
                                theme.textTheme.bodyMedium,
                                color: colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _field('nome', 'Nome completo', requiredField: true),
                      const SizedBox(height: 12),
                      _field(
                        'cpf',
                        'CPF',
                        kind: NativeCheckoutInputKind.number,
                        requiredField: true,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        'email',
                        'E-mail',
                        kind: NativeCheckoutInputKind.email,
                        requiredField: true,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        'tel',
                        'Telefone / WhatsApp',
                        kind: NativeCheckoutInputKind.phone,
                        requiredField: true,
                      ),
                      const SizedBox(height: 16),
                      _field(
                        'cep',
                        'CEP',
                        kind: NativeCheckoutInputKind.number,
                        requiredField: true,
                      ),
                      const SizedBox(height: 12),
                      _field('rua', 'Rua', requiredField: true),
                      const SizedBox(height: 12),
                      _field(
                        'numero',
                        'Número',
                        kind: NativeCheckoutInputKind.number,
                        requiredField: true,
                      ),
                      const SizedBox(height: 12),
                      _field('bairro', 'Bairro', requiredField: true),
                      const SizedBox(height: 12),
                      _field('cidade', 'Cidade', requiredField: true),
                      const SizedBox(height: 12),
                      _field('estado', 'UF', requiredField: true),
                      const SizedBox(height: 12),
                      _field('complemento', 'Complemento'),
                      const SizedBox(height: 12),
                      _field(
                        'obs',
                        'Observações',
                        kind: NativeCheckoutInputKind.multiline,
                      ),
                      const SizedBox(height: 12),
                      _field('cupomCodigo', 'Cupom de desconto'),
                      const SizedBox(height: 16),
                      _paymentSelector(context),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _continueCheckout,
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('Continuar checkout'),
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => CatalogCheckoutExternalBrowserGate(
                            catalogUrl: widget.catalogUrl,
                          ),
                        ),
                      );
                    },
                    child: const Text('Problemas? Abrir no navegador externo'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
