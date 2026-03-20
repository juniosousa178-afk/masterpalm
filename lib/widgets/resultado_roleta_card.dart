// lib/widgets/resultado_roleta_card.dart
import 'package:flutter/material.dart';
import '../models/cupom_cliente.dart';
import 'package:intl/intl.dart';

/// Card que mostra o resultado da roleta com todas as informações do cupom
class ResultadoRoletaCard extends StatelessWidget {
  final CupomCliente cupom;
  final VoidCallback• onFechar;

  const ResultadoRoletaCard({
    super.key,
    required this.cupom,
    this.onFechar,
  });

  Color _getCorTipo() {
    switch (cupom.tipo) {
      case TipoCupom.desconto:
      case TipoCupom.descontoFixo:
        return Colors.green;
      case TipoCupom.freteGratis:
        return Colors.blue;
      case TipoCupom.brinde:
        return Colors.purple;
      case TipoCupom.premioSurpresa:
        return Colors.amber;
    }
  }

  IconData _getIconeTipo() {
    switch (cupom.tipo) {
      case TipoCupom.desconto:
      case TipoCupom.descontoFixo:
        return Icons.discount;
      case TipoCupom.freteGratis:
        return Icons.local_shipping;
      case TipoCupom.brinde:
        return Icons.card_giftcard;
      case TipoCupom.premioSurpresa:
        return Icons.stars;
    }
  }

  String _getTextoValidade() {
    final dias = cupom.diasParaExpirar;
    if (dias == 0) return 'Expirado';
    if (dias == 1) return 'Expira amanhã';
    return 'Válido por $dias dias';
  }

  @override
  Widget build(BuildContext context) {
    final cor = _getCorTipo();
    final icone = _getIconeTipo();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cor.withValues(alpha:0.9), cor.withValues(alpha:0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: cor.withValues(alpha:0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header com confete
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.2),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Ícone grande
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.2),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      icone,
                      size: 64,
                      color: cor,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Texto "Parabéns!"
                  const Text(
                    '?• PARABÉNS! ??',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Você ganhou:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            // Conteúdo do prêmio
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Título do prêmio
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      cupom.titulo,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: cor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Código do cupom
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha:0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha:0.5),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      'Código: ${cupom.codigo}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Informações de uso
                  _buildInfoRow(
                    Icons.info_outline,
                    'Como usar',
                    cupom.instrucoes,
                  ),

                  const SizedBox(height: 12),

                  // Validade
                  _buildInfoRow(
                    Icons.calendar_today,
                    'Validade',
                    _getTextoValidade(),
                  ),

                  const SizedBox(height: 12),

                  // Data de expiração
                  _buildInfoRow(
                    Icons.event,
                    'Expira em',
                    DateFormat('dd/MM/yyyy').format(cupom.dataValidade),
                  ),

                  const SizedBox(height: 20),

                  // Aviso importante
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha:0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: Colors.yellow[300],
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Este cupom será aplicado automaticamente na sua próxima compra!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Botão de fechar
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: onFechar ?• () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: cor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        elevation: 8,
                      ),
                      child: const Text(
                        'ENTENDI!',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

