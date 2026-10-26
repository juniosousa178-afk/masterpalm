import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../design_system/mp_tokens.dart';
import 'consignment_models.dart';
import 'consignment_variation_price.dart';

final NumberFormat consignmentMoney = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
);

/// "Anel — Tam. 15" (product name alone for simple products).
String consignmentDraftLineTitle(ConsignmentDraftLine line) {
  final variation = consignmentVariationShortLabel(line.variationKey);
  return variation.isEmpty ? line.productName : '${line.productName} — $variation';
}

/// "1 × R$ 25,90 = R$ 25,90", always with the line's own unit price.
String consignmentDraftLineSummary(ConsignmentDraftLine line) =>
    '${line.qtySent} × ${consignmentMoney.format(line.unitSalePrice)} = '
    '${consignmentMoney.format(line.lineSubtotal)}';

Color consignmentStatusColor(String status) {
  switch (status) {
    case 'DRAFT':
      return MpColors.inkMuted;
    case 'ISSUED':
      return MpColors.warning;
    case 'SETTLED':
      return MpColors.success;
    case 'CANCELLED':
      return MpColors.danger;
    default:
      return MpColors.inkMuted;
  }
}

String consignmentStatusLabel(String status) {
  switch (status) {
    case 'DRAFT':
      return 'Rascunho';
    case 'ISSUED':
      return 'Em consignação';
    case 'SETTLED':
      return 'Acertado';
    case 'CANCELLED':
      return 'Cancelado';
    default:
      return status;
  }
}

class ConsignmentStatusChip extends StatelessWidget {
  const ConsignmentStatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = consignmentStatusColor(status);
    return Chip(
      label: Text(consignmentStatusLabel(status)),
      backgroundColor: color.withOpacity(0.12),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      visualDensity: VisualDensity.compact,
    );
  }
}
