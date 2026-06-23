import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/utils/role_utils.dart';

void main() {
  group('Acesso Mestre — menu e rota', () {
    test('1. menu Mestre somente para masterpalm26@gmail.com', () {
      expect(RoleUtils.isMasterPlanAdminEmail('masterpalm26@gmail.com'), isTrue);
    });

    test('2. outros roots não veem entrada Mestre de planos', () {
      expect(RoleUtils.isMasterPlanAdminEmail('masterpalm@gmail.com'), isFalse);
      expect(RoleUtils.isMasterPlanAdminEmail('admin@masterpalm.com'), isFalse);
      expect(RoleUtils.isRootEmail('masterpalm@gmail.com'), isTrue);
    });

    test('3. rota direta bloqueia usuário não autorizado', () {
      expect(RoleUtils.isMasterPlanAdminEmail('cliente@loja.com'), isFalse);
      expect(RoleUtils.isMasterPlanAdminEmail(null), isFalse);
    });
  });
}
