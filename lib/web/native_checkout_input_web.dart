// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

enum NativeCheckoutInputKind {
  text,
  email,
  phone,
  number,
  multiline,
}

class NativeCheckoutInput extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final NativeCheckoutInputKind kind;
  final String? hintText;
  final bool requiredField;
  final bool hasError;

  const NativeCheckoutInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.kind = NativeCheckoutInputKind.text,
    this.hintText,
    this.requiredField = false,
    this.hasError = false,
  });

  @override
  State<NativeCheckoutInput> createState() => _NativeCheckoutInputState();
}

class _NativeCheckoutInputState extends State<NativeCheckoutInput> {
  late final String _viewType =
      'native-checkout-input-${DateTime.now().microsecondsSinceEpoch}-$hashCode';
  html.HtmlElement? _element;
  StreamSubscription<html.Event>? _inputSubscription;

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final element = _createElement();
      _element = element;
      _syncElementValue();
      return element;
    });
  }

  @override
  void didUpdateWidget(covariant NativeCheckoutInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncElementValue();
    _syncElementStyle();
  }

  @override
  void dispose() {
    _inputSubscription?.cancel();
    _element = null;
    super.dispose();
  }

  html.HtmlElement _createElement() {
    _inputSubscription?.cancel();

    final element = widget.kind == NativeCheckoutInputKind.multiline
        ? html.TextAreaElement()
        : html.InputElement();

    if (element is html.InputElement) {
      element
        ..type = _htmlType
        ..inputMode = _inputMode;
    }
    if (element is html.TextAreaElement) {
      element.rows = 3;
    }

    element
      ..id = _viewType
      ..setAttribute('aria-label', widget.label)
      ..setAttribute('autocomplete', _autocomplete)
      ..setAttribute('placeholder', widget.hintText ?? '')
      ..style.width = '100%'
      ..style.height = widget.kind == NativeCheckoutInputKind.multiline
          ? '88px'
          : '48px'
      ..style.boxSizing = 'border-box'
      ..style.borderRadius = '12px'
      ..style.padding = '12px 14px'
      ..style.fontFamily = 'Arial, Roboto, sans-serif'
      ..style.fontSize = '16px'
      ..style.lineHeight = '22px'
      ..style.outline = 'none'
      ..style.resize = 'none'
      ..style.appearance = 'none';

    _syncElementStyle(element);
    _inputSubscription = element.onInput.listen((_) {
      widget.onChanged(_elementValue(element));
    });
    return element;
  }

  String get _htmlType {
    switch (widget.kind) {
      case NativeCheckoutInputKind.email:
        return 'email';
      case NativeCheckoutInputKind.phone:
      case NativeCheckoutInputKind.number:
        return 'tel';
      case NativeCheckoutInputKind.multiline:
      case NativeCheckoutInputKind.text:
        return 'text';
    }
  }

  String get _inputMode {
    switch (widget.kind) {
      case NativeCheckoutInputKind.phone:
      case NativeCheckoutInputKind.number:
        return 'numeric';
      case NativeCheckoutInputKind.email:
        return 'email';
      case NativeCheckoutInputKind.multiline:
      case NativeCheckoutInputKind.text:
        return 'text';
    }
  }

  String get _autocomplete {
    final lower = widget.label.toLowerCase();
    if (lower.contains('nome')) return 'name';
    if (lower.contains('e-mail')) return 'email';
    if (lower.contains('telefone')) return 'tel';
    if (lower.contains('cep')) return 'postal-code';
    if (lower.contains('rua')) return 'address-line1';
    if (lower.contains('número')) return 'address-line2';
    if (lower.contains('cidade')) return 'address-level2';
    if (lower.contains('estado')) return 'address-level1';
    return 'on';
  }

  String _elementValue(html.HtmlElement element) {
    if (element is html.InputElement) return element.value ?? '';
    if (element is html.TextAreaElement) return element.value ?? '';
    return '';
  }

  void _setElementValue(html.HtmlElement element, String value) {
    if (element is html.InputElement) {
      element.value = value;
    } else if (element is html.TextAreaElement) {
      element.value = value;
    }
  }

  void _syncElementValue() {
    final element = _element;
    if (element == null) return;
    if (html.document.activeElement == element) return;
    if (_elementValue(element) != widget.value) {
      _setElementValue(element, widget.value);
    }
    element.setAttribute('placeholder', widget.hintText ?? '');
  }

  void _syncElementStyle([html.HtmlElement? target]) {
    final element = target ?? _element;
    if (element == null) return;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    element
      ..style.backgroundColor =
          isDark ? 'rgba(255,255,255,0.06)' : 'rgba(255,255,255,0.96)'
      ..style.color = isDark ? '#FFFFFF' : '#111827'
      ..style.border =
          '1px solid ${widget.hasError ? _hex(colorScheme.error) : (isDark ? 'rgba(255,255,255,0.24)' : 'rgba(15,23,42,0.22)')}';
  }

  String _hex(Color color) {
    final value = color.value.toRadixString(16).padLeft(8, '0');
    return '#${value.substring(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.requiredField ? '${widget.label} *' : widget.label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: widget.hasError ? colorScheme.error : colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: widget.kind == NativeCheckoutInputKind.multiline ? 88 : 48,
          child: HtmlElementView(viewType: _viewType),
        ),
      ],
    );
  }
}
