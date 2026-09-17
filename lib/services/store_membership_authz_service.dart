// Loads lojas/{storeId}/members/{uid} for the CURRENT store only.
// Client UX authority; Rules remain the data security boundary.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/store_membership_authz.dart';

/// In-memory membership authz for the active store + signed-in uid.
///
/// - One fetch/listen key: `storeId|uid`
/// - Store switch / logout clears prior authorization (not sticky)
/// - Fail-closed on error / missing doc
class StoreMembershipAuthzService extends ChangeNotifier {
  StoreMembershipAuthzService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  StoreMembershipSnapshot? _snapshot;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<User?>? _authSub;
  String? _activeKey;
  bool _started = false;

  StoreMembershipSnapshot? get snapshot => _snapshot;

  StoreMembershipLoadState get loadState =>
      _snapshot?.loadState ?? StoreMembershipLoadState.idle;

  bool get grantsProductManagement =>
      StoreMembershipAuthz.snapshotGrantsProductManagement(_snapshot);

  /// Start listening to Auth so logout clears capability.
  void ensureAuthListener() {
    if (_started) return;
    _started = true;
    _authSub = _auth.authStateChanges().listen((user) {
      if (user == null) {
        clear();
      }
    });
  }

  /// Bind to [storeId] for the current Auth uid. No-op if same key already active.
  Future<void> bindCurrentStore(String? storeId) async {
    ensureAuthListener();
    final uid = (_auth.currentUser?.uid ?? '').trim();
    final store = (storeId ?? '').trim();
    if (uid.isEmpty || store.isEmpty) {
      clear();
      return;
    }
    final key = '$store|$uid';
    if (_activeKey == key &&
        _snapshot != null &&
        _snapshot!.loadState != StoreMembershipLoadState.idle) {
      return;
    }
    await _bind(storeId: store, uid: uid, key: key);
  }

  Future<void> _bind({
    required String storeId,
    required String uid,
    required String key,
  }) async {
    await _sub?.cancel();
    _sub = null;
    _activeKey = key;
    _snapshot = StoreMembershipSnapshot(
      storeId: storeId,
      uid: uid,
      loadState: StoreMembershipLoadState.loading,
    );
    notifyListeners();

    final ref = _db.collection('lojas').doc(storeId).collection('members').doc(uid);
    try {
      _sub = ref.snapshots().listen(
        (snap) {
          if (_activeKey != key) return;
          if (!snap.exists) {
            _snapshot = StoreMembershipSnapshot(
              storeId: storeId,
              uid: uid,
              loadState: StoreMembershipLoadState.ready,
              exists: false,
            );
          } else {
            final data = snap.data() ?? const <String, dynamic>{};
            final role = (data['role'] ?? '').toString();
            _snapshot = StoreMembershipSnapshot(
              storeId: storeId,
              uid: uid,
              loadState: StoreMembershipLoadState.ready,
              exists: true,
              role: role,
            );
          }
          notifyListeners();
        },
        onError: (Object e, StackTrace st) {
          if (_activeKey != key) return;
          debugPrint(
            '[StoreMembershipAuthz] listen error type=${e.runtimeType}',
          );
          _snapshot = StoreMembershipSnapshot(
            storeId: storeId,
            uid: uid,
            loadState: StoreMembershipLoadState.error,
          );
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('[StoreMembershipAuthz] bind failed type=${e.runtimeType}');
      _snapshot = StoreMembershipSnapshot(
        storeId: storeId,
        uid: uid,
        loadState: StoreMembershipLoadState.error,
      );
      notifyListeners();
    }
  }

  /// One-shot read (tests / gates that must await readiness).
  Future<StoreMembershipSnapshot> fetchOnce({
    required String storeId,
    required String uid,
  }) async {
    final store = storeId.trim();
    final id = uid.trim();
    if (store.isEmpty || id.isEmpty) {
      return StoreMembershipSnapshot(
        storeId: store,
        uid: id,
        loadState: StoreMembershipLoadState.ready,
        exists: false,
      );
    }
    try {
      final snap = await _db
          .collection('lojas')
          .doc(store)
          .collection('members')
          .doc(id)
          .get()
          .timeout(const Duration(seconds: 8));
      if (!snap.exists) {
        return StoreMembershipSnapshot(
          storeId: store,
          uid: id,
          loadState: StoreMembershipLoadState.ready,
          exists: false,
        );
      }
      final data = snap.data() ?? const <String, dynamic>{};
      return StoreMembershipSnapshot(
        storeId: store,
        uid: id,
        loadState: StoreMembershipLoadState.ready,
        exists: true,
        role: (data['role'] ?? '').toString(),
      );
    } catch (e) {
      debugPrint('[StoreMembershipAuthz] fetchOnce error type=${e.runtimeType}');
      return StoreMembershipSnapshot(
        storeId: store,
        uid: id,
        loadState: StoreMembershipLoadState.error,
      );
    }
  }

  /// Wait until not loading (or timeout → error fail-closed).
  Future<StoreMembershipSnapshot> resolveForCurrentStore(
    String? storeId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await bindCurrentStore(storeId);
    final started = DateTime.now();
    while (loadState == StoreMembershipLoadState.loading ||
        loadState == StoreMembershipLoadState.idle) {
      if (DateTime.now().difference(started) > timeout) {
        final uid = (_auth.currentUser?.uid ?? '').trim();
        final store = (storeId ?? '').trim();
        return StoreMembershipSnapshot(
          storeId: store,
          uid: uid,
          loadState: StoreMembershipLoadState.error,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _snapshot ??
        StoreMembershipSnapshot(
          storeId: (storeId ?? '').trim(),
          uid: (_auth.currentUser?.uid ?? '').trim(),
          loadState: StoreMembershipLoadState.error,
        );
  }

  void clear() {
    _sub?.cancel();
    _sub = null;
    _activeKey = null;
    _snapshot = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}

/// Process-wide default (optional). Screens may also construct their own.
StoreMembershipAuthzService? _sharedStoreMembershipAuthz;

StoreMembershipAuthzService sharedStoreMembershipAuthz() {
  return _sharedStoreMembershipAuthz ??= StoreMembershipAuthzService();
}

@visibleForTesting
void debugResetSharedStoreMembershipAuthz() {
  _sharedStoreMembershipAuthz?.dispose();
  _sharedStoreMembershipAuthz = null;
}
