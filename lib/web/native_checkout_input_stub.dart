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
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant NativeCheckoutInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  TextInputType get _keyboardType {
    switch (widget.kind) {
      case NativeCheckoutInputKind.email:
        return TextInputType.emailAddress;
      case NativeCheckoutInputKind.phone:
        return TextInputType.phone;
      case NativeCheckoutInputKind.number:
        return TextInputType.number;
      case NativeCheckoutInputKind.multiline:
        return TextInputType.multiline;
      case NativeCheckoutInputKind.text:
        return TextInputType.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = widget.hasError
        ? colorScheme.error
        : colorScheme.outline.withOpacity(0.45);

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
        TextField(
          controller: _controller,
          keyboardType: _keyboardType,
          maxLines: widget.kind == NativeCheckoutInputKind.multiline ? 3 : 1,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            hintText: widget.hintText,
            filled: true,
            fillColor: colorScheme.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
