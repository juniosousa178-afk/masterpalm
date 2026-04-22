// lib/screens/pagamento_resultado_screen.dart
// Tela exibida após retorno do Mercado Pago (sucesso, falha ou pendente)

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_routes.dart' as app_routes;
import '../services/catalog_cart_persistence.dart';

class PagamentoResultadoScreen extends StatefulWidget {
  final String status; // 'sucesso' | 'falha' | 'pendente'
  final String? orderId;
  final String? lojaId;
  final String? planoId;

  /// Query do MP (quando presente): approved / pending / etc.
  final String? collectionStatus;

  /// Query genérica `status` do retorno (ex.: approved).
  final String? paymentStatusQuery;

  /// `external_reference` do pagamento (ex.: id do pré-pedido).
  final String? externalReference;

  const PagamentoResultadoScreen({
    super.key,
    required this.status,
    this.orderId,
    this.lojaId,
    this.planoId,
    this.collectionStatus,
    this.paymentStatusQuery,
    this.externalReference,
  });

  @override
  State<PagamentoResultadoScreen> createState() =>
      _PagamentoResultadoScreenState();
}

class _PagamentoResultadoScreenState extends State<PagamentoResultadoScreen> {
  Timer? _redirectTimer;

  @override
  void dispose() {
    _redirectTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scheduleAutoReturnToCatalog();
  }

  bool _pagamentoCatalogoAprovadoMp() {
    final isPlano =
        widget.planoId != null && widget.planoId!.trim().isNotEmpty;
    if (isPlano) return false;
    if (widget.status != 'sucesso') return false;
    final cs = widget.collectionStatus?.toLowerCase().trim();
    final ps = widget.paymentStatusQuery?.toLowerCase().trim();
    return cs == 'approved' || ps == 'approved';
  }

  Future<void> _maybeClearCartSePagamentoCatalogoAprovado() async {
    if (!_pagamentoCatalogoAprovadoMp()) return;
    final loja = widget.lojaId?.trim();
    if (loja == null || loja.isEmpty) return;
    await CatalogCartPersistence.clearAfterSuccessfulCatalogPayment(loja);
  }

  void _navegarAoCatalogoWeb() {
    final loja = widget.lojaId?.trim();
    if (loja == null || loja.isEmpty) return;
    _redirectTimer?.cancel();
    final path = '/loja/${Uri.encodeComponent(loja)}';
    final generated =
        app_routes.onGenerateRoute(RouteSettings(name: path));
    if (!mounted) return;
    if (generated != null) {
      Navigator.of(context).pushAndRemoveUntil(generated, (_) => false);
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil(path, (_) => false);
    }
  }

  void _scheduleAutoReturnToCatalog() {
    final loja = widget.lojaId?.trim();
    if (loja == null || loja.isEmpty) return;
    final isPlano =
        widget.planoId != null && widget.planoId!.trim().isNotEmpty;
    if (isPlano) return;
    if (widget.status != 'sucesso' && widget.status != 'pendente') return;

    _redirectTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await _maybeClearCartSePagamentoCatalogoAprovado();
      if (!mounted) return;
      _navegarAoCatalogoWeb();
    });
  }

  void _voltarAoCatalogoAgora() {
    final loja = widget.lojaId?.trim();
    if (loja == null || loja.isEmpty) return;
    _redirectTimer?.cancel();
    unawaited(_maybeClearCartSePagamentoCatalogoAprovado().then((_) {
      if (!mounted) return;
      _navegarAoCatalogoWeb();
    }));
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = widget.status == 'sucesso';
    final isPending = widget.status == 'pendente';
    final isPlano = widget.planoId != null && widget.planoId!.isNotEmpty;

    final cs = widget.collectionStatus?.toLowerCase().trim();
    final ps = widget.paymentStatusQuery?.toLowerCase().trim();
    final mpApproved = cs == 'approved' || ps == 'approved';
    final mpPending = cs == 'pending' ||
        cs == 'in_process' ||
        cs == 'in_mediation' ||
        ps == 'pending';

    final successExplicitPending = isSuccess && mpPending;
    final successExplicitApproved = isSuccess && mpApproved;

    final refPedido = (widget.externalReference?.trim().isNotEmpty == true)
        ? widget.externalReference!.trim()
        : (widget.orderId?.trim().isNotEmpty == true)
            ? widget.orderId!.trim()
            : null;

    final icon = isSuccess
        ? (successExplicitPending ? Icons.schedule : Icons.check_circle)
        : isPending
            ? Icons.schedule
            : Icons.error;
    final color = isSuccess
        ? (successExplicitPending ? Colors.orange : Colors.green)
        : isPending
            ? Colors.orange
            : Colors.red;

    final String title;
    if (isPlano) {
      title = isSuccess
          ? (mpPending || !mpApproved
              ? 'Aguardando confirmação'
              : 'Pagamento recebido')
          : isPending
              ? 'Pagamento pendente'
              : 'Pagamento não realizado';
    } else if (isSuccess) {
      if (successExplicitPending) {
        title = 'Pagamento pendente';
      } else if (successExplicitApproved) {
        title = 'Pagamento aprovado!';
      } else {
        title = 'Pagamento recebido';
      }
    } else if (isPending) {
      title = 'Pagamento pendente';
    } else {
      title = 'Pagamento não realizado';
    }

    final String message;
    if (isPlano) {
      message = isSuccess
          ? (mpPending || !mpApproved
              ? 'O retorno do Mercado Pago não significa liberação imediata. O plano só fica ativo após o servidor confirmar o pagamento (webhook + consulta à API). Volte ao app e use «Atualizar» na tela de planos, se precisar.'
              : 'Recebemos o retorno do checkout. A confirmação final ainda vem do servidor; se o pagamento foi aprovado, o plano liberará em instantes. Use «Atualizar» em Planos se não mudar sozinho.')
          : isPending
              ? 'Seu pagamento está em análise. O plano será ativado somente quando o servidor confirmar a aprovação no Mercado Pago.'
              : 'O prazo para pagar pode ter expirado, o pagamento pode ter sido recusado ou reembolsado. Tente novamente ou escolha outra forma de pagamento.';
    } else if (isSuccess) {
      if (successExplicitPending) {
        message =
            'Seu pagamento está em análise. Você receberá a confirmação quando for aprovado. Com cadastro no catálogo, você pode acompanhar pedidos no menu.';
      } else if (successExplicitApproved) {
        message =
            'Obrigado pela sua compra! Seu pagamento foi confirmado. Você receberá a confirmação por e-mail ou WhatsApp. Com cadastro no catálogo, use o menu para ver seus pedidos.';
      } else {
        message =
            'Obrigado! Recebemos o retorno do pagamento. Se a cobrança foi aprovada, você receberá a confirmação em instantes. Você voltará ao catálogo da loja em alguns segundos.';
      }
    } else if (isPending) {
      message =
          'Seu pagamento está em análise. Você receberá a confirmação quando for aprovado.';
    } else {
      message =
          'O prazo para pagar pode ter expirado, o pagamento pode ter sido recusado ou reembolsado. Tente novamente ou escolha outra forma de pagamento.';
    }

    final lojaTrim = widget.lojaId?.trim();
    final mostrarVoltarCatalogo =
        !isPlano && lojaTrim != null && lojaTrim.isNotEmpty;
    final autoRedirectCatalogo =
        mostrarVoltarCatalogo && (isSuccess || isPending);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 80, color: color),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                if (refPedido != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Referência: $refPedido',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (autoRedirectCatalogo) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Redirecionando ao catálogo em instantes…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                if (isPlano)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                      '/home',
                      (route) => false,
                    ),
                    icon: const Icon(Icons.home),
                    label: const Text('Ir para o app'),
                  )
                else if (mostrarVoltarCatalogo)
                  TextButton.icon(
                    onPressed: _voltarAoCatalogoAgora,
                    icon: const Icon(Icons.storefront),
                    label: const Text('Voltar ao catálogo agora'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
