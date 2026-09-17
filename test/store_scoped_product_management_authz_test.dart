// Store-scoped product management capability — pure authz tests.
// No Firebase / no hardcoded production UIDs or store IDs in production logic.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/access_scope_service.dart';
import 'package:master_palm/core/produto_cadastro_gate.dart';
import 'package:master_palm/core/store_membership_authz.dart';
import 'package:master_palm/utils/role_utils.dart';

AccessScopeIdentity _seller({String uid = 'uid-seller'}) => AccessScopeIdentity(
      role: UserRole.vendedor,
      uid: uid,
      email: 'seller@example.test',
      displayName: 'Seller',
    );

AccessScopeIdentity _admin() => const AccessScopeIdentity(
      role: UserRole.admin,
      uid: 'uid-admin',
      email: 'admin@example.test',
      displayName: 'Admin',
    );

AccessScopeIdentity _programador() => const AccessScopeIdentity(
      role: UserRole.programador,
      uid: 'uid-prog',
      email: 'prog@example.test',
      displayName: 'Prog',
    );

StoreMembershipSnapshot _snap({
  required String storeId,
  required String uid,
  required StoreMembershipLoadState state,
  String? role,
  bool exists = true,
}) =>
    StoreMembershipSnapshot(
      storeId: storeId,
      uid: uid,
      loadState: state,
      role: role,
      exists: exists,
    );

void main() {
  group('StoreMembershipAuthz roles', () {
    test('owner and admin grant product management', () {
      expect(StoreMembershipAuthz.roleGrantsProductManagement('owner'), isTrue);
      expect(StoreMembershipAuthz.roleGrantsProductManagement('admin'), isTrue);
      expect(StoreMembershipAuthz.roleGrantsProductManagement('Admin'), isTrue);
    });

    test('non-managing roles do not grant', () {
      expect(StoreMembershipAuthz.roleGrantsProductManagement('vendedor'), isFalse);
      expect(StoreMembershipAuthz.roleGrantsProductManagement('seller'), isFalse);
      expect(StoreMembershipAuthz.roleGrantsProductManagement(''), isFalse);
      expect(StoreMembershipAuthz.roleGrantsProductManagement(null), isFalse);
    });
  });

  group('canManageStock store-scoped', () {
    test('vendedor + current-store membership admin → true', () {
      final id = _seller(uid: 'u1');
      final mem = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        role: 'admin',
      );
      expect(
        AccessScopeService.canManageStock(
          id,
          storeMembership: mem,
          currentStoreId: 'store-a',
        ),
        isTrue,
      );
      expect(
        podeAbrirCadastroProduto(
          id,
          storeMembership: mem,
          currentStoreId: 'store-a',
        ),
        isTrue,
      );
    });

    test('vendedor + membership owner → true', () {
      final id = _seller(uid: 'u1');
      final mem = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        role: 'owner',
      );
      expect(
        AccessScopeService.canManageStock(
          id,
          storeMembership: mem,
          currentStoreId: 'store-a',
        ),
        isTrue,
      );
    });

    test('vendedor + non-managing membership → false', () {
      final id = _seller(uid: 'u1');
      final mem = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        role: 'vendedor',
      );
      expect(
        AccessScopeService.canManageStock(
          id,
          storeMembership: mem,
          currentStoreId: 'store-a',
        ),
        isFalse,
      );
    });

    test('vendedor + no membership doc → false', () {
      final id = _seller(uid: 'u1');
      final mem = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        exists: false,
      );
      expect(
        AccessScopeService.canManageStock(
          id,
          storeMembership: mem,
          currentStoreId: 'store-a',
        ),
        isFalse,
      );
    });

    test('membership admin of store A does not grant store B', () {
      final id = _seller(uid: 'u1');
      final memA = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        role: 'admin',
      );
      expect(
        AccessScopeService.canManageStock(
          id,
          storeMembership: memA,
          currentStoreId: 'store-b',
        ),
        isFalse,
      );
      expect(
        StoreMembershipAuthz.snapshotMatchesCurrentStore(
          snap: memA,
          currentStoreId: 'store-b',
        ),
        isFalse,
      );
    });

    test('store switch: A authorized then B unauthorized', () {
      final id = _seller(uid: 'u1');
      final memA = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        role: 'admin',
      );
      final memB = _snap(
        storeId: 'store-b',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        role: 'vendedor',
      );
      expect(
        AccessScopeService.canManageStock(
          id,
          storeMembership: memA,
          currentStoreId: 'store-a',
        ),
        isTrue,
      );
      expect(
        AccessScopeService.canManageStock(
          id,
          storeMembership: memB,
          currentStoreId: 'store-b',
        ),
        isFalse,
      );
    });

    test('reverse store switch: unauthorized then authorized', () {
      final id = _seller(uid: 'u1');
      final memB = _snap(
        storeId: 'store-b',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        exists: false,
      );
      final memA = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        role: 'admin',
      );
      expect(
        AccessScopeService.canManageStock(
          id,
          storeMembership: memB,
          currentStoreId: 'store-b',
        ),
        isFalse,
      );
      expect(
        AccessScopeService.canManageStock(
          id,
          storeMembership: memA,
          currentStoreId: 'store-a',
        ),
        isTrue,
      );
    });

    test('loading membership does not expose create capability', () {
      final id = _seller(uid: 'u1');
      final mem = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.loading,
        role: 'admin',
      );
      expect(
        AccessScopeService.canManageStock(
          id,
          storeMembership: mem,
          currentStoreId: 'store-a',
        ),
        isFalse,
      );
    });

    test('error membership fails closed', () {
      final id = _seller(uid: 'u1');
      final mem = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.error,
        role: 'admin',
      );
      expect(
        AccessScopeService.canManageStock(
          id,
          storeMembership: mem,
          currentStoreId: 'store-a',
        ),
        isFalse,
      );
    });

    test('null membership (omitted) fails closed for vendedor', () {
      expect(AccessScopeService.canManageStock(_seller()), isFalse);
      expect(podeAbrirCadastroProduto(_seller()), isFalse);
    });

    test('auth session leak: prior membership snapshot not reused for other uid', () {
      final seller1 = _seller(uid: 'u1');
      final seller2 = _seller(uid: 'u2');
      final memU1 = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        role: 'admin',
      );
      expect(
        AccessScopeService.canManageStock(
          seller1,
          storeMembership: memU1,
          currentStoreId: 'store-a',
        ),
        isTrue,
      );
      expect(
        AccessScopeService.canManageStock(
          seller2,
          storeMembership: memU1,
          currentStoreId: 'store-a',
        ),
        isFalse,
      );
    });
  });

  group('global compatibility', () {
    test('global admin manages stock without membership', () {
      expect(AccessScopeService.canManageStock(_admin()), isTrue);
      expect(podeAbrirCadastroProduto(_admin()), isTrue);
    });

    test('global programador manages stock without membership', () {
      expect(AccessScopeService.canManageStock(_programador()), isTrue);
      expect(podeAbrirCadastroProduto(_programador()), isTrue);
    });
  });

  group('UI capability flags', () {
    test('store admin product create/edit UI flags true', () {
      final id = _seller(uid: 'u1');
      final mem = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        role: 'admin',
      );
      final can = AccessScopeService.canEditStock(
        id,
        storeMembership: mem,
        currentStoreId: 'store-a',
      );
      expect(can, isTrue);
      expect(podeAbrirCadastroProduto(id, storeMembership: mem, currentStoreId: 'store-a'), isTrue);
    });

    test('other store product management UI flags false', () {
      final id = _seller(uid: 'u1');
      final mem = _snap(
        storeId: 'store-a',
        uid: 'u1',
        state: StoreMembershipLoadState.ready,
        role: 'admin',
      );
      expect(
        AccessScopeService.canEditStock(
          id,
          storeMembership: mem,
          currentStoreId: 'store-other',
        ),
        isFalse,
      );
    });
  });
}
