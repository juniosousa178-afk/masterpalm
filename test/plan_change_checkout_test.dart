import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/checkout_service.dart';

void main() {
  test('PlanChangeCallOutcome distingue aberto vs já ativo', () {
    expect(PlanChangeCallOutcome.opened, isNot(PlanChangeCallOutcome.alreadyActive));
    expect(PlanChangeCallOutcome.values, hasLength(2));
  });
}
