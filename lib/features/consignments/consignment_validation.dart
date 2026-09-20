import 'consignment_models.dart';

class ConsignmentLineAmounts {
  const ConsignmentLineAmounts({
    required this.gross,
    required this.commission,
    required this.net,
  });
  final double gross;
  final double commission;
  final double net;
}

double _money(num value) => (value * 100).round() / 100;

ConsignmentLineAmounts consignmentLineAmounts({
  required int qty,
  required double unitPrice,
  required String commissionType,
  required double commissionValue,
}) {
  final q = qty < 0 ? 0 : qty;
  final gross = _money(q * unitPrice);
  var commission = 0.0;
  if (commissionType == 'PERCENTUAL') {
    commission = _money(gross * commissionValue / 100);
  } else if (commissionType == 'VALOR_FIXO_POR_UNIDADE') {
    commission = _money(q * commissionValue);
  }
  if (commission > gross) commission = gross;
  return ConsignmentLineAmounts(
    gross: gross,
    commission: commission,
    net: _money(gross - commission),
  );
}

class ConsignmentSettlementLineInput {
  ConsignmentSettlementLineInput({
    required this.line,
    required this.qtySold,
  });

  final Map<String, dynamic> line;
  int qtySold;

  int get qtySent {
    final v = line['qtySent'];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  int get qtyReturned {
    final r = qtySent - qtySold;
    return r < 0 ? 0 : r;
  }

  bool get isValid => qtySold >= 0 && qtyReturned >= 0 && qtySold + qtyReturned == qtySent;
}

bool consignmentSettlementIsValid(List<ConsignmentSettlementLineInput> lines) {
  if (lines.isEmpty) return false;
  return lines.every((l) => l.isValid);
}

int consignmentDraftTotalQty(List<ConsignmentDraftLine> lines) =>
    lines.fold(0, (s, l) => s + l.qtySent);

ConsignmentLineAmounts consignmentDraftPotential(List<ConsignmentDraftLine> lines) {
  var gross = 0.0, commission = 0.0, net = 0.0;
  for (final line in lines) {
    final a = consignmentLineAmounts(
      qty: line.qtySent,
      unitPrice: line.unitSalePrice,
      commissionType: line.commissionType,
      commissionValue: line.commissionValue,
    );
    gross += a.gross;
    commission += a.commission;
    net += a.net;
  }
  return ConsignmentLineAmounts(
    gross: _money(gross),
    commission: _money(commission),
    net: _money(net),
  );
}

bool consignmentProductIsGrade(dynamic produto) {
  try {
    final extra = produto.variacoesExtraTipo;
    if (extra is Map && extra.isNotEmpty) return true;
  } catch (_) {}
  try {
    if (produto.temVariacaoTamanhoECor == true) return true;
  } catch (_) {}
  return false;
}

bool consignmentProductIsCombo(dynamic produto) {
  try {
    if (produto.ehCombo == true) return true;
    if ((produto.tipoProduto ?? '').toString() == 'combo') return true;
  } catch (_) {}
  return false;
}
