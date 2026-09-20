import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/home_module_registry.dart';
import 'package:master_palm/core/plan_matrix.dart';
import 'package:master_palm/features/consignments/consignment_errors.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/consignment_validation.dart';
import 'package:master_palm/services/permissao_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('consignment frontend MVP', () {
    test('feature flag default hides module', () {
      final ctx = HomeModuleAccessContext(
        tipoUsuario: 'admin',
        permissoes: {for (final k in PermissaoService.todasAsChaves) k: true},
        planTier: PlanAccessTier.lifetime,
        applyPlanGate: false,
      );
      expect(ctx.consignmentModuleEnabled, isFalse);
      expect(
        HomeModuleRegistry.visibleForHome(ctx).any((m) => m.id == 'consignados'),
        isFalse,
      );
    });

    test('feature flag on shows consignados', () {
      final ctx = HomeModuleAccessContext(
        tipoUsuario: 'admin',
        permissoes: {for (final k in PermissaoService.todasAsChaves) k: true},
        planTier: PlanAccessTier.lifetime,
        applyPlanGate: false,
        consignmentModuleEnabled: true,
      );
      expect(
        HomeModuleRegistry.visibleForHome(ctx).any((m) => m.id == 'consignados'),
        isTrue,
      );
    });

    test('create draft add simple, variation, remove, edit qty', () {
      final lines = <ConsignmentDraftLine>[
        ConsignmentDraftLine(
          productId: 's1',
          productName: 'Anel',
          productType: 'simple',
          qtySent: 1,
          unitSalePrice: 50,
        ),
      ];
      lines.add(ConsignmentDraftLine(
        productId: 'v1',
        productName: 'Pulseira',
        productType: 'variation',
        qtySent: 2,
        unitSalePrice: 40,
        variationKey: const ConsignmentVariationKey(size: 'P', color: 'sem-cor'),
      ));
      expect(lines, hasLength(2));
      lines.removeAt(0);
      expect(lines, hasLength(1));
      lines.first.qtySent = 5;
      expect(consignmentDraftTotalQty(lines), 5);
    });

    test('settlement validation sold+returned = sent', () {
      final line = ConsignmentSettlementLineInput(
        line: {'qtySent': 3, 'productId': 's1'},
        qtySold: 2,
      );
      expect(line.qtyReturned, 1);
      expect(line.isValid, isTrue);
      line.qtySold = 4;
      expect(line.isValid, isFalse);
      expect(consignmentSettlementIsValid([line]), isFalse);
    });

    test('commission and price freeze use snapshots', () {
      final a = consignmentLineAmounts(
        qty: 2,
        unitPrice: 100,
        commissionType: 'PERCENTUAL',
        commissionValue: 10,
      );
      expect(a.gross, 200);
      expect(a.commission, 20);
      expect(a.net, 180);
      final b = consignmentLineAmounts(
        qty: 2,
        unitPrice: 100,
        commissionType: 'PERCENTUAL',
        commissionValue: 50,
      );
      expect(b.commission, isNot(20));
    });

    test('error mapping does not collapse to connection', () {
      expect(ConsignmentException.userMessage('INSUFFICIENT_STOCK'), contains('Estoque'));
      expect(ConsignmentException.userMessage('CONSIGNMENT_ALREADY_SETTLED'), contains('acertada'));
      expect(ConsignmentException.fromCallable('unavailable', 'x', null).code, 'NETWORK');
      expect(
        ConsignmentException.fromCallable(
          'failed-precondition',
          'x',
          {'consignmentCode': 'PRODUCT_STATE_UNSAFE'},
        ).code,
        'PRODUCT_STATE_UNSAFE',
      );
    });

    test('double click protection on issue/settle', () async {
      var calls = 0;
      ConsignmentService.debugConnectivity =
          () async => [ConnectivityResult.wifi];
      ConsignmentService.debugTransport = (name, data) async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return {'ok': true, 'operationId': data['operationId']};
      };
      final first = ConsignmentService.issue(lojaId: 'loja', consignmentId: 'c1');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(ConsignmentService.issueInFlight, isTrue);
      await expectLater(
        ConsignmentService.issue(lojaId: 'loja', consignmentId: 'c1'),
        throwsA(isA<ConsignmentException>()),
      );
      await first;
      expect(calls, 1);
      ConsignmentService.debugTransport = null;
      ConsignmentService.debugConnectivity = null;
    });

    test('network error mapped before issue', () async {
      ConsignmentService.debugConnectivity =
          () async => [ConnectivityResult.none];
      await expectLater(
        ConsignmentService.issue(lojaId: 'loja', consignmentId: 'c1'),
        throwsA(predicate((e) => e is ConsignmentException && e.code == 'NETWORK')),
      );
      ConsignmentService.debugConnectivity = null;
    });

    test('already-settled refresh message', () {
      expect(
        ConsignmentException.userMessage('CONSIGNMENT_ALREADY_SETTLED'),
        contains('já foi acertada'),
      );
    });

    test('grade helper', () {
      expect(
        consignmentProductIsGrade(_FakeProduct(grade: true)),
        isTrue,
      );
      expect(
        consignmentProductIsCombo(_FakeProduct(combo: true)),
        isTrue,
      );
    });
  });
}

class _FakeProduct {
  _FakeProduct({this.grade = false, this.combo = false});
  final bool grade;
  final bool combo;
  bool get temVariacaoTamanhoECor => grade;
  bool get ehCombo => combo;
  String get tipoProduto => combo ? 'combo' : 'simples';
  Map<String, dynamic>? get variacoesExtraTipo => null;
}
