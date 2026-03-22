// lib/widgets/selecionar_cupom_modal.dart
// Modal para selecionar cupom de desconto (igual ao modelo da imagem)
// Inclui cupons de indicação (exclusivos do remetente/destinatário) quando o cliente está logado.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/cupom.dart';
import '../models/cupom_cliente.dart';
import '../services/cupom_desconto_service.dart';
import '../services/cupons_service.dart';
import '../utils/platform_adaptive.dart';

class SelecionarCupomModal extends StatefulWidget {
  final String lojaId;
  final String clienteId;
  final double valorPedido;
  final Cupom? cupomAtual;

  const SelecionarCupomModal({
    super.key,
    required this.lojaId,
    required this.clienteId,
    required this.valorPedido,
    this.cupomAtual,
  });

  @override
  State<SelecionarCupomModal> createState() => _SelecionarCupomModalState();
}

class _SelecionarCupomModalState extends State<SelecionarCupomModal> {
  final _cupomService = CupomDescontoService();
  /// Cupom da loja (Cupom) ou cupom de indicação (Map com origem 'cupom_cliente')
  dynamic _cupomSelecionado;
  List<CupomCliente>? _cuponsIndicacao;

  @override
  void initState() {
    super.initState();
    _cupomSelecionado = widget.cupomAtual;
    _carregarCuponsIndicacao();
  }

  Future<void> _carregarCuponsIndicacao() async {
    final clienteId = widget.clienteId.toString().trim();
    if (clienteId.isEmpty) return;
    try {
      final list = await CuponsService.buscarCuponsValidos(
        lojaId: widget.lojaId,
        clienteId: clienteId,
      );
      if (mounted) setState(() => _cuponsIndicacao = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BCD4).withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.local_offer,
                    color: Color(0xFF00BCD4),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Cupom',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Subtitle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Escolha um cupom disponível',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ),
          ),

          // Lista de cupons
          Expanded(
            child: StreamBuilder<List<Cupom>>(
              stream: _cupomService.listarDisponiveis(
                widget.lojaId,
                widget.clienteId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF00BCD4),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Erro ao carregar cupons: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final cupons = snapshot.data ?? [];
                final indicacao = _cuponsIndicacao ?? [];
                final temIndicacao = indicacao.isNotEmpty;

                if (cupons.isEmpty && !temIndicacao) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum cupom disponível',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    ...cupons.map((cupom) {
                      final isSelecionado = _cupomSelecionado is Cupom &&
                          (_cupomSelecionado as Cupom).id == cupom.id;
                      final podeUsar = cupom.podeSerUsado(
                        widget.clienteId,
                        widget.valorPedido,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildCupomCard(cupom, isSelecionado, podeUsar),
                      );
                    }),
                    if (temIndicacao) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Meus cupons (indicação)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      ...indicacao.map((c) {
                        final isSelecionado = _cupomSelecionado is Map &&
                            (_cupomSelecionado as Map)['id'] == c.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildCupomClienteCard(c, isSelecionado),
                        );
                      }),
                    ],
                  ],
                );
              },
            ),
          ),

          // Botão Salvar
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                top: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _cupomSelecionado != null
                    ? () => Navigator.pop(context, _cupomSelecionado)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BCD4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: Colors.grey[300],
                ),
                child: const Text(
                  'Salvar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mapa no formato usado pelo carrinho para cupom de indicação (origem cupom_cliente).
  Map<String, dynamic> _mapFromCupomCliente(CupomCliente c) {
    final tipo = c.tipo == TipoCupom.freteGratis
        ? 'frete_gratis'
        : (c.tipo == TipoCupom.descontoFixo ? 'valor' : 'percent');
    return {
      'id': c.id,
      'codigo': c.codigo,
      'code': c.codigo,
      'tipo': tipo,
      'valor': c.valorDesconto ?? 0.0,
      'aplicarEm': 'total',
      'freteGratis': c.tipo == TipoCupom.freteGratis,
      'dataValidade': c.dataValidade,
      'origem': 'cupom_cliente',
    };
  }

  Widget _buildCupomClienteCard(CupomCliente c, bool isSelecionado) {
    final podeUsar = c.isValido;
    final desconto = c.tipo == TipoCupom.descontoFixo
        ? 'R\$ ${(c.valorDesconto ?? 0).toStringAsFixed(2)}'
        : '${(c.valorDesconto ?? 0).toStringAsFixed(0)}%';
    return InkWell(
      onTap: podeUsar
          ? () {
              setState(() {
                if (isSelecionado) {
                  _cupomSelecionado = null;
                } else {
                  _cupomSelecionado = _mapFromCupomCliente(c);
                }
              });
            }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: podeUsar ? Colors.white : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelecionado
                ? const Color(0xFF00BCD4)
                : podeUsar
                    ? Colors.grey[300]!
                    : Colors.grey[200]!,
            width: isSelecionado ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelecionado
                    ? const Color(0xFF00BCD4)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelecionado
                      ? const Color(0xFF00BCD4)
                      : Colors.grey[400]!,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: isSelecionado
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.codigo,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: podeUsar ? Colors.black : Colors.grey,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9C27B0).withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'INDICAÇÃO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF9C27B0),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.titulo,
                    style: TextStyle(
                      fontSize: 14,
                      color: podeUsar ? Colors.grey[700] : Colors.grey,
                    ),
                  ),
                  if (!podeUsar) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline, size: 14,
                              color: Colors.orange[700]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              c.usado
                                  ? 'Já utilizado'
                                  : c.isExpirado
                                      ? 'Expirado'
                                      : 'Aguardando confirmação',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.orange[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: podeUsar
                    ? const Color(0xFF00BCD4).withValues(alpha:0.1)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                desconto,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: podeUsar ? const Color(0xFF00BCD4) : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCupomCard(Cupom cupom, bool isSelecionado, bool podeUsar) {
    // Calcular desconto
    final desconto = cupom.tipo == 'percentual'
        ? '${cupom.valor.toStringAsFixed(0)}%'
        : 'R\$ ${cupom.valor.toStringAsFixed(2)}';

    // Tag do cupom
    String? tag;
    Color? tagColor;
    if (cupom.clienteId != null) {
      tag = 'VALE-COMPRA';
      tagColor = const Color(0xFF9C27B0); // Purple
    } else if (cupom.freteGratis) {
      tag = 'FRETE GRÁTIS';
      tagColor = const Color(0xFF4CAF50); // Green
    } else if (cupom.usoUnicoGlobal) {
      tag = 'EXCLUSIVO';
      tagColor = const Color(0xFFFF9800); // Orange
    }

    return InkWell(
      onTap: podeUsar
          ? () {
              setState(() {
                if (isSelecionado) {
                  _cupomSelecionado = null;
                } else {
                  _cupomSelecionado = cupom;
                }
              });
            }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: podeUsar ? Colors.white : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelecionado
                ? const Color(0xFF00BCD4)
                : podeUsar
                    ? Colors.grey[300]!
                    : Colors.grey[200]!,
            width: isSelecionado ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Checkbox (store cupom)
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelecionado
                    ? const Color(0xFF00BCD4)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelecionado
                      ? const Color(0xFF00BCD4)
                      : Colors.grey[400]!,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: isSelecionado
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),

            const SizedBox(width: 12),

            // Info do cupom
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Código + Tag
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          cupom.codigo,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: podeUsar ? Colors.black : Colors.grey,
                          ),
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: tagColor!.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: tagColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Nome/descrição
                  Text(
                    cupom.nome,
                    style: TextStyle(
                      fontSize: 14,
                      color: podeUsar ? Colors.grey[700] : Colors.grey,
                    ),
                  ),

                  // Restrições
                  if (!podeUsar) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _getMensagemRestricao(cupom),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Valor do desconto
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: podeUsar
                    ? const Color(0xFF00BCD4).withValues(alpha:0.1)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                desconto,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: podeUsar ? const Color(0xFF00BCD4) : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMensagemRestricao(Cupom cupom) {
    if (cupom.valorMinimo != null && widget.valorPedido < cupom.valorMinimo!) {
      return 'Mínimo: R\$ ${cupom.valorMinimo!.toStringAsFixed(2)}';
    }
    if (cupom.usoUnico && cupom.usadosPor.contains(widget.clienteId)) {
      return 'Você já usou este cupom';
    }
    if (cupom.usoUnicoGlobal && cupom.qtdUsosAtuais > 0) {
      return 'Cupom já foi utilizado';
    }
    return 'Não disponível';
  }
}

/// Função helper para exibir o modal.
/// Retorna [Cupom] (cupom da loja) ou [Map] (cupom de indicação, origem 'cupom_cliente').
Future<dynamic> mostrarModalSelecionarCupom({
  required BuildContext context,
  required String lojaId,
  required String clienteId,
  required double valorPedido,
  Cupom? cupomAtual,
}) async {
  if (!context.mounted) return null;
  final wideChrome = usePointerFirstChrome(context);

  Widget cupomSheetBody(BuildContext modalContext) {
    return SizedBox(
      height: MediaQuery.of(modalContext).size.height * 0.75,
      child: SelecionarCupomModal(
        lojaId: lojaId,
        clienteId: clienteId,
        valorPedido: valorPedido,
        cupomAtual: cupomAtual,
      ),
    );
  }

  if (wideChrome) {
    return showDialog<dynamic>(
      context: context,
      barrierDismissible: true,
      builder: (modalContext) {
        final mq = MediaQuery.of(modalContext);
        final maxW = math.min(kMaxContentWidth, mq.size.width - 40);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxW,
              maxHeight: mq.size.height * 0.85,
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: cupomSheetBody(modalContext),
            ),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<dynamic>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) => cupomSheetBody(modalContext),
  );
}

