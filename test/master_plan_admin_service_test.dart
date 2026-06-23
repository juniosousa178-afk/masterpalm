import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/master_plan_admin_messages.dart';
import 'package:master_palm/services/master_plan_admin_service.dart';
import 'package:master_palm/utils/role_utils.dart';

void main() {
  group('RoleUtils.isMasterPlanAdminEmail', () {
    test('1. menu Mestre somente masterpalm26@gmail.com', () {
      expect(RoleUtils.isMasterPlanAdminEmail('masterpalm26@gmail.com'), isTrue);
    });
    test('2. outros roots não são Mestre de planos', () {
      expect(RoleUtils.isMasterPlanAdminEmail('masterpalm@gmail.com'), isFalse);
      expect(RoleUtils.isMasterPlanAdminEmail('admin@masterpalm.com'), isFalse);
    });
  });

  group('masterPlanAdminErrorMessage', () {
    test('11. não expõe permission-denied cru', () {
      final msg = masterPlanAdminErrorMessage(Exception('permission-denied'));
      expect(msg, contains('administração Mestre'));
      expect(msg.toLowerCase(), isNot(contains('permission-denied')));
    });
    test('4. unavailable vira mensagem amigável', () {
      final msg = masterPlanAdminErrorMessage(Exception('unavailable network'));
      expect(msg.toLowerCase(), contains('conectar'));
    });
  });

  group('MasterPlanAdminService.newRequestId', () {
    test('5. requestId usa apenas caracteres permitidos', () {
      final id = MasterPlanAdminService.newRequestId();
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id), isTrue);
    });

    test('busca ambígua por e-mail mostra mensagem amigável', () {
      final msg = masterPlanAdminErrorMessage(
        Exception('failed-precondition: Há mais de um cadastro com este e-mail'),
      );
      expect(msg, 'Há mais de um cadastro com este e-mail. Consulte pelo UID.');
    });
  });
}
