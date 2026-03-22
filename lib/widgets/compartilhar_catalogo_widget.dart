// lib/widgets/compartilhar_catalogo_widget.dart
// Widget para vendedores compartilharem catálogo com tracking

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/tracking_service.dart';
import '../utils/platform_adaptive.dart';

/// Widget de botão para compartilhar catálogo com tracking
class CompartilharCatalogoButton extends StatefulWidget {
  /// Telefone do cliente (opcional)
  final String? clienteTelefone;

  /// Nome do cliente (opcional)
  final String? clienteNome;

  /// Mensagem personalizada (opcional)
  final String? mensagemPersonalizada;

  /// Callback após compartilhar
  final VoidCallback? onCompartilhado;

  /// Se mostra opções expandidas
  final bool expandido;

  /// Cor do botão
  final Color? cor;

  const CompartilharCatalogoButton({
    super.key,
    this.clienteTelefone,
    this.clienteNome,
    this.mensagemPersonalizada,
    this.onCompartilhado,
    this.expandido = false,
    this.cor,
  });

  @override
  State<CompartilharCatalogoButton> createState() => _CompartilharCatalogoButtonState();
}

class _CompartilharCatalogoButtonState extends State<CompartilharCatalogoButton> {
  bool _carregando = false;
  String? _linkGerado;
  String? _erro;

  Future<void> _gerarLink() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    final resultado = await TrackingService.gerarLinkCatalogoComTracking(
      clienteTelefone: widget.clienteTelefone,
      clienteNome: widget.clienteNome,
      origem: 'app',
    );

    if (!mounted) return;

    setState(() {
      _carregando = false;
      if (resultado.sucesso) {
        _linkGerado = resultado.link;
      } else {
        _erro = resultado.mensagemErro;
      }
    });
  }

  Future<void> _compartilharWhatsApp() async {
    if (_linkGerado == null) {
      await _gerarLink();
      if (_linkGerado == null) return;
    }

    final sucesso = await TrackingService.compartilharNoWhatsApp(
      link: _linkGerado!,
      mensagemPersonalizada: widget.mensagemPersonalizada,
      telefoneDestino: widget.clienteTelefone,
    );

    if (sucesso) {
      widget.onCompartilhado?.call();
    }
  }

  Future<void> _compartilharOutros() async {
    if (_linkGerado == null) {
      await _gerarLink();
      if (_linkGerado == null) return;
    }

    await TrackingService.compartilharNativo(
      link: _linkGerado!,
      mensagemPersonalizada: widget.mensagemPersonalizada,
    );

    widget.onCompartilhado?.call();
  }

  Future<void> _copiarLink() async {
    if (_linkGerado == null) {
      await _gerarLink();
      if (_linkGerado == null) return;
    }

    await Clipboard.setData(ClipboardData(text: _linkGerado!));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copiado!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final corPrimaria = widget.cor ?? Theme.of(context).colorScheme.primary;

    if (widget.expandido) {
      return _buildExpandido(corPrimaria);
    }

    return _buildCompacto(corPrimaria);
  }

  Widget _buildCompacto(Color corPrimaria) {
    return ElevatedButton.icon(
      onPressed: _carregando ? null : _compartilharWhatsApp,
      icon: _carregando
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.share, color: Colors.white),
      label: const Text(
        'Enviar Catálogo',
        style: TextStyle(color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: corPrimaria,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildExpandido(Color corPrimaria) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.send, color: corPrimaria),
                const SizedBox(width: 8),
                const Text(
                  'Compartilhar Catálogo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Envie o catálogo para seus clientes e ganhe comissão nas vendas!',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 8),
              Text(
                _erro!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _carregando ? null : _compartilharWhatsApp,
                    icon: _carregando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.message, size: 18),
                    label: const Text('WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _carregando ? null : _compartilharOutros,
                  icon: const Icon(Icons.share),
                  tooltip: 'Outras opções',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _carregando ? null : _copiarLink,
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copiar link',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                  ),
                ),
              ],
            ),
            if (_linkGerado != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _linkGerado!,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dialog para compartilhar catálogo
class CompartilharCatalogoDialog extends StatefulWidget {
  final String? clienteTelefone;
  final String? clienteNome;

  const CompartilharCatalogoDialog({
    super.key,
    this.clienteTelefone,
    this.clienteNome,
  });

  static Future<void> show(
    BuildContext context, {
    String? clienteTelefone,
    String? clienteNome,
  }) {
    return showDialog(
      context: context,
      builder: (context) => CompartilharCatalogoDialog(
        clienteTelefone: clienteTelefone,
        clienteNome: clienteNome,
      ),
    );
  }

  @override
  State<CompartilharCatalogoDialog> createState() => _CompartilharCatalogoDialogState();
}

class _CompartilharCatalogoDialogState extends State<CompartilharCatalogoDialog> {
  final _telefoneController = TextEditingController();
  final _nomeController = TextEditingController();
  final _mensagemController = TextEditingController();
  bool _carregando = false;
  String? _linkGerado;

  @override
  void initState() {
    super.initState();
    _telefoneController.text = widget.clienteTelefone ?? '';
    _nomeController.text = widget.clienteNome ?? '';
    _mensagemController.text =
        'Olá! Confira nosso catálogo de produtos com ofertas especiais:';
  }

  @override
  void dispose() {
    _telefoneController.dispose();
    _nomeController.dispose();
    _mensagemController.dispose();
    super.dispose();
  }

  Future<void> _gerarECompartilhar() async {
    setState(() => _carregando = true);

    final resultado = await TrackingService.gerarLinkCatalogoComTracking(
      clienteTelefone: _telefoneController.text.trim(),
      clienteNome: _nomeController.text.trim(),
      origem: 'whatsapp',
    );

    if (!mounted) return;

    if (resultado.sucesso) {
      _linkGerado = resultado.link;

      final mensagem = '${_mensagemController.text}\n\n$_linkGerado';

      await TrackingService.compartilharNoWhatsApp(
        link: _linkGerado!,
        mensagemPersonalizada: mensagem,
        telefoneDestino: _telefoneController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      setState(() => _carregando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resultado.mensagemErro ?? 'Erro ao gerar link'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxW = math.min(
      kMaxContentWidth,
      MediaQuery.sizeOf(context).width - 40,
    );
    return AlertDialog(
      constraints: BoxConstraints(maxWidth: maxW),
      title: const Row(
        children: [
          Icon(Icons.send, color: Colors.green),
          SizedBox(width: 8),
          Text('Enviar Catálogo'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Preencha os dados do cliente (opcional) para enviar o catálogo via WhatsApp.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(
                labelText: 'Nome do cliente',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _telefoneController,
              decoration: const InputDecoration(
                labelText: 'Telefone (com DDD)',
                prefixIcon: Icon(Icons.phone),
                hintText: '5533999999999',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mensagemController,
              decoration: const InputDecoration(
                labelText: 'Mensagem',
                prefixIcon: Icon(Icons.message),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Você receberá comissão nas vendas feitas através deste link!',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _carregando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _carregando ? null : _gerarECompartilhar,
          icon: _carregando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send),
          label: Text(_carregando ? 'Gerando...' : 'Enviar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF25D366),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
