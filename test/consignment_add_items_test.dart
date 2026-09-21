import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/consignment_errors.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_actions.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_data.dart';

void main() {
  group('ConsignmentDoc add-items model', () {
    test('canAddItems only for DRAFT and ISSUED', () {
      ConsignmentDoc doc(String status) => ConsignmentDoc(
            id: 'c1',
            storeId: 's',
            resellerId: 'joao',
            resellerName: 'João',
            status: status,
            lines: const [],
            totalItemsSent: 0,
            totalItemsSold: 0,
            totalItemsReturned: 0,
            grossSoldAmount: 0,
            commissionAmount: 0,
            netAmount: 0,
            potentialGrossAmount: 0,
          );
      expect(doc('DRAFT').canAddItems, isTrue);
      expect(doc('ISSUED').canAddItems, isTrue);
      expect(doc('SETTLED').canAddItems, isFalse);
      expect(doc('CANCELLED').canAddItems, isFalse);
    });

    test('consolidatedLines merges same product lots (João B 2+3=5)', () {
      final doc = ConsignmentDoc(
        id: 'c1',
        storeId: 's',
        resellerId: 'joao',
        resellerName: 'João',
        status: 'ISSUED',
        lines: [
          {
            'productId': 'A',
            'productNameSnapshot': 'A',
            'qtySent': 1,
            'unitSalePriceSnapshot': 100,
            'variationKey': {'size': '', 'color': '', 'extra': ''},
          },
          {
            'productId': 'B',
            'productNameSnapshot': 'B',
            'qtySent': 2,
            'unitSalePriceSnapshot': 100,
            'variationKey': {'size': '', 'color': '', 'extra': ''},
          },
          {
            'productId': 'C',
            'productNameSnapshot': 'C',
            'qtySent': 1,
            'unitSalePriceSnapshot': 100,
            'variationKey': {'size': '', 'color': '', 'extra': ''},
          },
          {
            'productId': 'B',
            'productNameSnapshot': 'B',
            'qtySent': 3,
            'unitSalePriceSnapshot': 110,
            'variationKey': {'size': '', 'color': '', 'extra': ''},
            'additionId': 'add2',
          },
          {
            'productId': 'F',
            'productNameSnapshot': 'F',
            'qtySent': 1,
            'unitSalePriceSnapshot': 50,
            'variationKey': {'size': '', 'color': '', 'extra': ''},
            'additionId': 'add2',
          },
          {
            'productId': 'G',
            'productNameSnapshot': 'G',
            'qtySent': 2,
            'unitSalePriceSnapshot': 60,
            'variationKey': {'size': '', 'color': '', 'extra': ''},
            'additionId': 'add2',
          },
        ],
        totalItemsSent: 10,
        totalItemsSold: 0,
        totalItemsReturned: 0,
        grossSoldAmount: 0,
        commissionAmount: 0,
        netAmount: 0,
        potentialGrossAmount: 900,
        additions: [
          {
            'additionId': 'initial',
            'kind': 'INITIAL',
            'lines': [
              {'productId': 'A', 'qtyAdded': 1},
              {'productId': 'B', 'qtyAdded': 2},
              {'productId': 'C', 'qtyAdded': 1},
            ],
          },
          {
            'additionId': 'add2',
            'kind': 'ADDITION',
            'lines': [
              {'productId': 'B', 'qtyAdded': 3, 'unitSalePriceSnapshot': 110},
              {'productId': 'F', 'qtyAdded': 1},
              {'productId': 'G', 'qtyAdded': 2},
            ],
          },
        ],
      );

      final consolidated = {
        for (final l in doc.consolidatedLines)
          '${l['productId']}': (l['qtySent'] as num).toInt(),
      };
      expect(consolidated, {'A': 1, 'B': 5, 'C': 1, 'F': 1, 'G': 2});
      expect(doc.totalItemsSent, 10);
      expect(doc.additions.length, 2);
      expect(doc.additions[0]['kind'], 'INITIAL');
      expect(doc.additions[1]['kind'], 'ADDITION');
    });

    test('draft line payload includes expectedStockRevision', () {
      final line = ConsignmentDraftLine(
        productId: 'B',
        productName: 'B',
        productType: 'simple',
        qtySent: 3,
        unitSalePrice: 110,
        expectedStockRevision: 2,
      );
      expect(line.toPayload()['expectedStockRevision'], 2);
    });
  });

  group('add-items error copy', () {
    test('SETTLED / CANCELLED / STOCK_CONFLICT / NETWORK', () {
      expect(
        ConsignmentException.userMessage('CONSIGNMENT_ALREADY_SETTLED'),
        contains('acertada'),
      );
      expect(
        ConsignmentException.userMessage('CONSIGNMENT_CANCELLED'),
        contains('cancelada'),
      );
      expect(
        ConsignmentException.userMessage('STOCK_CONFLICT'),
        contains('alterado'),
      );
      expect(
        ConsignmentException.userMessage('NETWORK'),
        contains('conectado'),
      );
    });
  });

  group('addition report aggregator', () {
    test('additionLinesOf uses qtyAdded and price snapshot', () {
      final lines = ConsignmentReportAggregator.additionLinesOf([
        {
          'productId': 'B',
          'productNameSnapshot': 'Produto B',
          'qtyAdded': 3,
          'unitSalePriceSnapshot': 110,
          'commissionType': 'SEM_COMISSAO',
          'commissionValueSnapshot': 0,
        },
      ]);
      expect(lines.single.qtySent, 3);
      expect(lines.single.unitPrice, 110);
      expect(lines.single.lineConsignedValue, 330);
    });

    test('report kind includes addition', () {
      expect(ConsignmentReportKind.values, contains(ConsignmentReportKind.addition));
    });
  });
}
