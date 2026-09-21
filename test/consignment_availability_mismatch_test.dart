import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_eligibility.dart';

void main() {
  test('simple qty maps to availableQty', () {
    final item = evaluateConsignmentPickerItem(
      productId: 'p',
      lojaId: 'mirjoias',
      stock: {
        'stockKind': 'simple',
        'stockRevision': 1,
        'quantidade': 3,
        'variacoes': {},
      },
      draft: {'nome': 'Anel', 'preco': 10},
      dependency: {'comboIds': []},
    );
    expect(item.eligible, isTrue);
    expect(item.availableQty, 3);
  });

  test('zero stock reason is consignacao-specific', () {
    final item = evaluateConsignmentPickerItem(
      productId: 'p',
      lojaId: 'mirjoias',
      stock: {
        'stockKind': 'simple',
        'stockRevision': 1,
        'quantidade': 0,
        'variacoes': {},
      },
      draft: {'nome': 'Anel', 'preco': 10},
      dependency: {'comboIds': []},
    );
    expect(item.eligible, isFalse);
    expect(item.unavailableReason, '0 disponíveis para consignação');
  });

  test('variation availableQty capped to cell sum', () {
    final item = evaluateConsignmentPickerItem(
      productId: 'v',
      lojaId: 'mirjoias',
      stock: {
        'stockKind': 'variation',
        'stockRevision': 1,
        'quantidade': 4,
        'variacoes': {
          'P': {'sem-cor': 1},
          'M': {'sem-cor': 0},
          'G': {'sem-cor': 2},
        },
      },
      draft: {'nome': 'Var', 'preco': 10},
      dependency: {'comboIds': []},
    );
    expect(item.eligible, isTrue);
    expect(item.availableQty, 3);
  });

  test('AN15SM-style simple remains available', () {
    final item = evaluateConsignmentPickerItem(
      productId: 'mirjoias-anel-solit-rio-cravejado-pedra-fina-t-19-semijoia-3',
      lojaId: 'mirjoias',
      stock: {
        'stockKind': 'simple',
        'stockRevision': 6,
        'quantidade': 1,
        'codigoBarras': 'AN15SM',
        'variacoes': {},
      },
      draft: {
        'nome': 'Anel Solitário Cravejado Pedra Fina T.19 Semijoia',
        'preco': 10,
        'codigoBarras': 'AN15SM',
      },
      dependency: {'comboIds': []},
    );
    expect(item.eligible, isTrue);
    expect(item.availableQty, 1);
    expect(item.productCode, 'AN15SM');
  });
}
