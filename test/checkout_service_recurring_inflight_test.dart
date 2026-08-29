import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/checkout_service.dart';

void main() {
  group('recurring CREATE in-flight guard', () {
    test('suppresses duplicate in-flight recurring create', () async {
      CheckoutService.resetRecurringCreateInFlightForTest();
      var calls = 0;

      final first = CheckoutService.runRecurringCreateWithInFlightGuard(() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return const CheckoutLaunchResult(
          flowType: CheckoutFlowType.recurringCreate,
          opened: true,
        );
      });

      final second = CheckoutService.runRecurringCreateWithInFlightGuard(() async {
        calls++;
        return const CheckoutLaunchResult(
          flowType: CheckoutFlowType.recurringCreate,
          opened: true,
        );
      });

      final results = await Future.wait([first, second]);
      expect(calls, 1);
      expect(results.length, 2);
      expect(results.every((r) => r.flowType == CheckoutFlowType.recurringCreate), isTrue);
      CheckoutService.resetRecurringCreateInFlightForTest();
    });

    test('releases guard after successful completion', () async {
      CheckoutService.resetRecurringCreateInFlightForTest();
      var calls = 0;

      await CheckoutService.runRecurringCreateWithInFlightGuard(() async {
        calls++;
        return const CheckoutLaunchResult(flowType: CheckoutFlowType.recurringCreate);
      });

      await CheckoutService.runRecurringCreateWithInFlightGuard(() async {
        calls++;
        return const CheckoutLaunchResult(flowType: CheckoutFlowType.recurringCreate);
      });

      expect(calls, 2);
      CheckoutService.resetRecurringCreateInFlightForTest();
    });

    test('releases guard after error without implicit second CREATE', () async {
      CheckoutService.resetRecurringCreateInFlightForTest();
      var calls = 0;

      await expectLater(
        CheckoutService.runRecurringCreateWithInFlightGuard(() async {
          calls++;
          throw Exception('provider failure');
        }),
        throwsA(isA<Exception>()),
      );

      await CheckoutService.runRecurringCreateWithInFlightGuard(() async {
        calls++;
        return const CheckoutLaunchResult(flowType: CheckoutFlowType.recurringCreate);
      });

      expect(calls, 2);
      CheckoutService.resetRecurringCreateInFlightForTest();
    });
  });
}
