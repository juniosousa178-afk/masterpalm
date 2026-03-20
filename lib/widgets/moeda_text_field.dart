// lib/widgets/moeda_text_field.dart
// Campo de moeda que funciona em desktop e mobile web.
// No mobile web, usa teclado numérico customizado (o teclado nativo pode falhar).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../utils/moeda_input_formatter.dart';

/// Campo de texto para valores em reais.
/// No mobile web, exibe um teclado numérico customizado ao focar.
class MoedaTextField extends StatefulWidget {
  final TextEditingController controller;
  final String• labelText;
  final String• hintText;
  final ValueChanged<double>• onChanged;
  final InputDecoration• decoration;
  final bool enabled;

  const MoedaTextField({
    super.key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.onChanged,
    this.decoration,
    this.enabled = true,
  });

  @override
  State<MoedaTextField> createState() => _MoedaTextFieldState();
}

class _MoedaTextFieldState extends State<MoedaTextField> {
  /// No app web, sempre usa teclado custom (teclado nativo falha em Android/iPhone).
  /// No app nativo (APK/IPA), usa TextField normal.
  bool _usarTecladoCustom(BuildContext context) =>
      kIsWeb; // Sempre custom no web para garantir funcionamento em mobile

  void _abrirTecladoCustom(BuildContext context) {
    final ctrl = widget.controller;
    final valorAtual = MoedaInputFormatter.parse(ctrl.text);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TecladoMoedaSheet(
        valorInicial: valorAtual,
        onConfirm: (v) {
          ctrl.text = MoedaInputFormatter.format(v);
          widget.onChanged?.call(v);
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dec = widget.decoration ?• InputDecoration(
      labelText: widget.labelText,
      hintText: widget.hintText,
    );

    if (_usarTecladoCustom(context)) {
      // Não usar TextFormField/TextField - no mobile web o navegador abre
      // o teclado nativo mesmo com readOnly. Usar widget que não é input.
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final texto = value.text;
          final vazio = texto.isEmpty;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled • () => _abrirTecladoCustom(context) : null,
            child: IgnorePointer(
              ignoring: !widget.enabled,
              child: InputDecorator(
                decoration: dec.copyWith(
                  suffixIcon: const Icon(Icons.keyboard, size: 20, color: Colors.grey),
                ),
                child: Text(
                  vazio • (widget.hintText ?• '') : texto,
                  style: TextStyle(
                    fontSize: 16,
                    color: vazio • Theme.of(context).hintColor : null,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return TextFormField(
      controller: widget.controller,
      keyboardType: TextInputType.number,
      inputFormatters: [MoedaInputFormatter()],
      enabled: widget.enabled,
      decoration: dec,
      onChanged: (value) {
        widget.onChanged?.call(MoedaInputFormatter.parse(value));
      },
    );
  }
}

class _TecladoMoedaSheet extends StatefulWidget {
  final double valorInicial;
  final ValueChanged<double> onConfirm;

  const _TecladoMoedaSheet({
    required this.valorInicial,
    required this.onConfirm,
  });

  @override
  State<_TecladoMoedaSheet> createState() => _TecladoMoedaSheetState();
}

class _TecladoMoedaSheetState extends State<_TecladoMoedaSheet> {
  late int _centavos;

  @override
  void initState() {
    super.initState();
    _centavos = (widget.valorInicial * 100).round();
  }

  void _addDigito(int d) {
    setState(() {
      _centavos = _centavos * 10 + d;
      if (_centavos > 99999999) _centavos = 99999999;
    });
  }

  void _apagar() {
    setState(() {
      _centavos = _centavos ~/ 10;
    });
  }

  void _confirmar() {
    widget.onConfirm(_centavos / 100.0);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final valor = _centavos / 100.0;
    final texto = valor == 0 • '0,00' : MoedaInputFormatter.format(valor);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            texto,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildBotao('1', () => _addDigito(1)),
              _buildBotao('2', () => _addDigito(2)),
              _buildBotao('3', () => _addDigito(3)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildBotao('4', () => _addDigito(4)),
              _buildBotao('5', () => _addDigito(5)),
              _buildBotao('6', () => _addDigito(6)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildBotao('7', () => _addDigito(7)),
              _buildBotao('8', () => _addDigito(8)),
              _buildBotao('9', () => _addDigito(9)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildBotao('⌫', _apagar, flex: 1),
              _buildBotao('0', () => _addDigito(0)),
              _buildBotao('OK', _confirmar, flex: 1, primary: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBotao(String label, VoidCallback onTap, {int flex = 1, bool primary = false}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: primary • Theme.of(context).colorScheme.primary : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 56,
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: primary • Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
