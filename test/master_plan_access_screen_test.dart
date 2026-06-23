import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/master_plan_access_models.dart';
import 'package:master_palm/services/master_plan_admin_service.dart';
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

  group('Detalhe por card da lista', () {
    test('payload do detalhe usa somente targetUid', () {
      const row = MasterPlanUserRow(
        uid: 'user_abc',
        emailMasked: 'c***@test.com',
        renewal: MasterPlanRenewalSummary(active: false, cancelAtPeriodEnd: false),
        courtesy: MasterPlanCourtesySummary(active: false),
      );
      final payload = MasterPlanAdminService.buildUserLookupPayload(
        targetUid: row.uid,
      );
      expect(payload, {'targetUid': 'user_abc'});
      expect(payload.containsKey('targetEmail'), isFalse);
    });

    test('usuário legado sem e-mail abre por UID', () {
      const row = MasterPlanUserRow(
        uid: 'legacy_uid',
        renewal: MasterPlanRenewalSummary(active: false, cancelAtPeriodEnd: false),
        courtesy: MasterPlanCourtesySummary(active: false),
      );
      final payload = MasterPlanAdminService.buildUserLookupPayload(
        targetUid: row.uid,
      );
      expect(payload['targetUid'], 'legacy_uid');
    });
  });
}
