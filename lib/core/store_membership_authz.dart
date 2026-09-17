// Store-scoped product/stock management authorization (client UX).
// Aligns with Firestore Rules isLojaMemberElevated: members.role in [owner, admin].
// Does NOT grant Rules isAdminOrSystem / cross-store privilege.

import 'package:flutter/foundation.dart';

/// Explicit load lifecycle for current-store membership.
enum StoreMembershipLoadState {
  /// Not started / cleared (logout, store cleared).
  idle,

  /// Fetch in flight for the requested store+uid.
  loading,

  /// Membership document resolved for the requested store+uid.
  ready,

  /// Fetch failed; store-scoped path must fail closed.
  error,
}

/// Immutable snapshot of membership for one store + uid.
@immutable
class StoreMembershipSnapshot {
  const StoreMembershipSnapshot({
    required this.storeId,
    required this.uid,
    required this.loadState,
    this.role,
    this.exists = false,
  });

  final String storeId;
  final String uid;
  final StoreMembershipLoadState loadState;

  /// Raw `role` field when the membership doc exists.
  final String? role;
  final bool exists;

  static const elevatedRoles = <String>{'owner', 'admin'};

  /// Rules `isLojaMemberElevated` equivalent (store-local only).
  bool get grantsProductManagement {
    if (loadState != StoreMembershipLoadState.ready) return false;
    if (!exists) return false;
    final r = (role ?? '').trim().toLowerCase();
    return elevatedRoles.contains(r);
  }

  bool get isLoading => loadState == StoreMembershipLoadState.loading;
  bool get isError => loadState == StoreMembershipLoadState.error;
  bool get isReady => loadState == StoreMembershipLoadState.ready;

  StoreMembershipSnapshot copyWith({
    String? storeId,
    String? uid,
    StoreMembershipLoadState? loadState,
    String? role,
    bool? exists,
    bool clearRole = false,
  }) {
    return StoreMembershipSnapshot(
      storeId: storeId ?? this.storeId,
      uid: uid ?? this.uid,
      loadState: loadState ?? this.loadState,
      role: clearRole ? null : (role ?? this.role),
      exists: exists ?? this.exists,
    );
  }
}

/// Pure helpers (unit-testable without Firebase).
abstract final class StoreMembershipAuthz {
  StoreMembershipAuthz._();

  static bool roleGrantsProductManagement(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return StoreMembershipSnapshot.elevatedRoles.contains(r);
  }

  /// Fail-closed: only [ready] + elevated role grants; loading/error/idle → false.
  static bool snapshotGrantsProductManagement(StoreMembershipSnapshot? snap) {
    if (snap == null) return false;
    return snap.grantsProductManagement;
  }

  /// Wrong-store snapshot must never authorize the current store.
  static bool snapshotMatchesCurrentStore({
    required StoreMembershipSnapshot? snap,
    required String? currentStoreId,
  }) {
    final store = (currentStoreId ?? '').trim();
    if (store.isEmpty || snap == null) return false;
    return snap.storeId.trim() == store;
  }
}
