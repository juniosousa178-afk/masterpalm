// Diagnóstico local read-only de identidade de loja (relações sanitizadas).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/firestore_access_guard.dart';
import '../core/loja_ativa_resolver.dart';
import '../core/loja_id_adapter.dart';
import 'store_identity_diagnostic_snapshot.dart';
import 'store_resolver_facade.dart';

/// Campos de perfil lidos em memória — nunca persistidos nem expostos.
@visibleForTesting
class StoreIdentityProfileFields {
  const StoreIdentityProfileFields({
    this.usersStoreId,
    this.usersOwnerOf,
    this.usersLojaId,
    this.usuariosStoreId,
    this.usuariosOwnerStoreId,
    this.usersDocAvailable = false,
    this.usuariosDocAvailable = false,
  });

  final String? usersStoreId;
  final String? usersOwnerOf;
  final String? usersLojaId;
  final String? usuariosStoreId;
  final String? usuariosOwnerStoreId;
  final bool usersDocAvailable;
  final bool usuariosDocAvailable;
}

class StoreIdentityDiagnosticsService {
  StoreIdentityDiagnosticsService._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  @visibleForTesting
  static Future<String?> Function({String origem})? debugActiveStoreResolver;

  @visibleForTesting
  static Future<String?> Function()? debugResolvedStoreResolver;

  @visibleForTesting
  static Future<StoreIdentityProfileFields> Function(String uid, String? email)?
      debugProfileReader;

  @visibleForTesting
  static Future<String?> Function()? debugSessionStoreReader;

  @visibleForTesting
  static String? debugAuthUid;

  @visibleForTesting
  static String? debugAuthEmail;

  static FirebaseFirestore get _db => FirestoreAccessGuard.resolve(
        override: debugFirestoreOverride,
      );

  @visibleForTesting
  static void resetForTests() {
    debugFirestoreOverride = null;
    debugActiveStoreResolver = null;
    debugResolvedStoreResolver = null;
    debugProfileReader = null;
    debugSessionStoreReader = null;
    debugAuthUid = null;
    debugAuthEmail = null;
    FirestoreAccessGuard.resetForTests();
  }

  /// Captura relações de identidade sem expor IDs nem escrever dados.
  static Future<StoreIdentityDiagnosticSnapshot> capture() async {
    final capturedAtUtc = DateTime.now().toUtc();
    var completeness = StoreIdentityDiagnosticCompleteness.full;

    String? sessionStore;
    try {
      sessionStore = debugSessionStoreReader != null
          ? await debugSessionStoreReader!()
          : await _readSessionStoreLocal();
    } catch (_) {
      completeness = StoreIdentityDiagnosticCompleteness.partial;
    }

    String? resolvedStore;
    try {
      resolvedStore = debugResolvedStoreResolver != null
          ? await debugResolvedStoreResolver!()
          : await StoreResolverFacade.resolveForAdminApp();
    } catch (_) {
      completeness = StoreIdentityDiagnosticCompleteness.partial;
    }

    String? activeStore;
    try {
      activeStore = debugActiveStoreResolver != null
          ? await debugActiveStoreResolver!(origem: 'StoreIdentityDiagnostics')
          : await LojaAtivaResolver.resolve(
              origem: 'StoreIdentityDiagnostics',
            );
    } catch (_) {
      completeness = StoreIdentityDiagnosticCompleteness.partial;
    }

    StoreIdentityProfileFields profile = const StoreIdentityProfileFields();
    final authUid = _resolveAuthUid();
    final authEmail = _resolveAuthEmail();
    try {
      if (authUid != null && authUid.isNotEmpty) {
        profile = debugProfileReader != null
            ? await debugProfileReader!(authUid, authEmail)
            : await _readProfileFieldsReadOnly(authUid, authEmail);
      } else {
        completeness = StoreIdentityDiagnosticCompleteness.partial;
      }
    } catch (_) {
      completeness = StoreIdentityDiagnosticCompleteness.partial;
    }

    final canonical = _deriveCanonical(profile);
    final legacy = _deriveLegacy(profile, canonical);

    final profileStoreIdAvailable =
        _nonEmpty(profile.usersStoreId);
    final profileOwnerOfAvailable =
        _nonEmpty(profile.usersOwnerOf);
    final profileLojaIdLegacyAvailable = canonical != null &&
        _nonEmpty(profile.usersLojaId) &&
        profile.usersLojaId!.trim() != canonical;
    final legacyOwnerStoreIdAvailable = canonical != null &&
        _nonEmpty(profile.usuariosOwnerStoreId) &&
        profile.usuariosOwnerStoreId!.trim() != canonical;

    final profileHasLegacyConflict =
        profileLojaIdLegacyAvailable || legacyOwnerStoreIdAvailable;

    final profileCanonicalStoreAvailable = canonical != null;

    if (!profile.usersDocAvailable && !profile.usuariosDocAvailable) {
      if (completeness == StoreIdentityDiagnosticCompleteness.full) {
        completeness = StoreIdentityDiagnosticCompleteness.partial;
      }
    }

    if (sessionStore == null &&
        resolvedStore == null &&
        activeStore == null &&
        canonical == null) {
      completeness = StoreIdentityDiagnosticCompleteness.unavailable;
    } else if (completeness == StoreIdentityDiagnosticCompleteness.full &&
        (sessionStore == null || canonical == null)) {
      completeness = StoreIdentityDiagnosticCompleteness.partial;
    }

    final activeSource = _inferActiveSource(
      activeStore: activeStore,
      sessionStore: sessionStore,
      profile: profile,
      canonical: canonical,
      legacy: legacy,
    );

    return StoreIdentityDiagnosticSnapshot(
      capturedAtUtc: capturedAtUtc,
      activeStoreResolutionSource: activeSource,
      profileCanonicalStoreAvailable: profileCanonicalStoreAvailable,
      profileHasLegacyConflict: profileHasLegacyConflict,
      sessionVsCanonical: _compareToCanonical(sessionStore, canonical),
      sessionVsLegacy: legacy == null
          ? StoreIdentityRelation.notApplicable
          : _compareToLegacy(sessionStore, legacy),
      resolvedVsCanonical: _compareToCanonical(resolvedStore, canonical),
      resolvedVsLegacy: legacy == null
          ? StoreIdentityRelation.notApplicable
          : _compareToLegacy(resolvedStore, legacy),
      sessionEqualsResolved: _sessionEqualsResolved(sessionStore, resolvedStore),
      activeStoreMatchesCanonical: _compareToCanonical(activeStore, canonical),
      activeStoreMatchesLegacy: legacy == null
          ? StoreIdentityRelation.notApplicable
          : _compareToLegacy(activeStore, legacy),
      profileStoreIdAvailable: profileStoreIdAvailable,
      profileOwnerOfAvailable: profileOwnerOfAvailable,
      profileLojaIdLegacyAvailable: profileLojaIdLegacyAvailable,
      legacyOwnerStoreIdAvailable: legacyOwnerStoreIdAvailable,
      diagnosticDataCompleteness: completeness,
    );
  }

  /// Snapshot parcial seguro quando a captura falha — não interrompe fluxos.
  static StoreIdentityDiagnosticSnapshot unavailableSnapshot() {
    const unavailable = StoreIdentityRelation.unavailable;
    return StoreIdentityDiagnosticSnapshot(
      capturedAtUtc: DateTime.now().toUtc(),
      activeStoreResolutionSource: StoreIdentityResolutionSource.unavailable,
      profileCanonicalStoreAvailable: false,
      profileHasLegacyConflict: false,
      sessionVsCanonical: unavailable,
      sessionVsLegacy: unavailable,
      resolvedVsCanonical: unavailable,
      resolvedVsLegacy: unavailable,
      sessionEqualsResolved: unavailable,
      activeStoreMatchesCanonical: unavailable,
      activeStoreMatchesLegacy: unavailable,
      profileStoreIdAvailable: false,
      profileOwnerOfAvailable: false,
      profileLojaIdLegacyAvailable: false,
      legacyOwnerStoreIdAvailable: false,
      diagnosticDataCompleteness: StoreIdentityDiagnosticCompleteness.unavailable,
    );
  }

  static Future<StoreIdentityDiagnosticSnapshot> captureSafe() async {
    try {
      return await capture();
    } catch (_) {
      return StoreIdentityDiagnosticSnapshot(
        capturedAtUtc: DateTime.now().toUtc(),
        activeStoreResolutionSource: StoreIdentityResolutionSource.unavailable,
        profileCanonicalStoreAvailable: false,
        profileHasLegacyConflict: false,
        sessionVsCanonical: StoreIdentityRelation.unavailable,
        sessionVsLegacy: StoreIdentityRelation.unavailable,
        resolvedVsCanonical: StoreIdentityRelation.unavailable,
        resolvedVsLegacy: StoreIdentityRelation.unavailable,
        sessionEqualsResolved: StoreIdentityRelation.unavailable,
        activeStoreMatchesCanonical: StoreIdentityRelation.unavailable,
        activeStoreMatchesLegacy: StoreIdentityRelation.unavailable,
        profileStoreIdAvailable: false,
        profileOwnerOfAvailable: false,
        profileLojaIdLegacyAvailable: false,
        legacyOwnerStoreIdAvailable: false,
        diagnosticDataCompleteness: StoreIdentityDiagnosticCompleteness.partial,
      );
    }
  }

  static String? _deriveCanonical(StoreIdentityProfileFields profile) {
    final storeId = profile.usersStoreId?.trim();
    if (_nonEmpty(storeId)) return storeId;

    // ownerOf só como fallback quando store_id ausente — nunca lojaId legado.
    final ownerOf = profile.usersOwnerOf?.trim();
    if (_nonEmpty(ownerOf)) return ownerOf;

    final usuariosStoreId = profile.usuariosStoreId?.trim();
    if (_nonEmpty(usuariosStoreId)) return usuariosStoreId;

    return null;
  }

  static String? _deriveLegacy(
    StoreIdentityProfileFields profile,
    String? canonical,
  ) {
    if (canonical == null || canonical.isEmpty) return null;

    final lojaId = profile.usersLojaId?.trim();
    if (_nonEmpty(lojaId) && lojaId != canonical) return lojaId;

    final ownerStoreId = profile.usuariosOwnerStoreId?.trim();
    if (_nonEmpty(ownerStoreId) && ownerStoreId != canonical) {
      return ownerStoreId;
    }

    return null;
  }

  static StoreIdentityRelation _compareToCanonical(
    String? value,
    String? canonical,
  ) {
    if (!_nonEmpty(value)) return StoreIdentityRelation.unavailable;
    if (!_nonEmpty(canonical)) return StoreIdentityRelation.unavailable;
    return value!.trim() == canonical!.trim()
        ? StoreIdentityRelation.matchCanonical
        : StoreIdentityRelation.mismatch;
  }

  static StoreIdentityRelation _compareToLegacy(String? value, String legacy) {
    if (!_nonEmpty(value)) return StoreIdentityRelation.unavailable;
    return value!.trim() == legacy.trim()
        ? StoreIdentityRelation.matchLegacy
        : StoreIdentityRelation.mismatch;
  }

  static StoreIdentityRelation _sessionEqualsResolved(
    String? session,
    String? resolved,
  ) {
    if (!_nonEmpty(session) || !_nonEmpty(resolved)) {
      return StoreIdentityRelation.unavailable;
    }
    return session!.trim() == resolved!.trim()
        ? StoreIdentityRelation.matchCanonical
        : StoreIdentityRelation.mismatch;
  }

  static StoreIdentityResolutionSource _inferActiveSource({
    required String? activeStore,
    required String? sessionStore,
    required StoreIdentityProfileFields profile,
    required String? canonical,
    required String? legacy,
  }) {
    if (!_nonEmpty(activeStore)) {
      return StoreIdentityResolutionSource.unavailable;
    }
    final active = activeStore!.trim();

    if (_nonEmpty(sessionStore) && active == sessionStore!.trim()) {
      return StoreIdentityResolutionSource.sessionStoreId;
    }
    if (_nonEmpty(canonical) && active == canonical!.trim()) {
      if (_nonEmpty(profile.usersStoreId) &&
          active == profile.usersStoreId!.trim()) {
        return StoreIdentityResolutionSource.profileStoreId;
      }
      if (_nonEmpty(profile.usersOwnerOf) &&
          active == profile.usersOwnerOf!.trim()) {
        return StoreIdentityResolutionSource.profileOwnerOf;
      }
      return StoreIdentityResolutionSource.profileStoreId;
    }
    if (_nonEmpty(legacy) && active == legacy!.trim()) {
      if (_nonEmpty(profile.usersLojaId) &&
          active == profile.usersLojaId!.trim()) {
        return StoreIdentityResolutionSource.legacyLojaId;
      }
      return StoreIdentityResolutionSource.legacyOwnerStoreId;
    }
    return StoreIdentityResolutionSource.fallback;
  }

  static bool _nonEmpty(String? value) =>
      value != null && value.trim().isNotEmpty;

  static String? _resolveAuthUid() {
    if (_nonEmpty(debugAuthUid)) return debugAuthUid!.trim();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  static String? _resolveAuthEmail() {
    if (_nonEmpty(debugAuthEmail)) return debugAuthEmail!.trim();
    try {
      return FirebaseAuth.instance.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _readSessionStoreLocal() async {
    final user = _resolveAuthUid();
    if (user == null) return null;

    String? authEmail;
    try {
      authEmail = _resolveAuthEmail()?.trim().toLowerCase();
    } catch (_) {
      return null;
    }
    if (authEmail == null || authEmail.isEmpty) return null;

    try {
      final sessao =
          Hive.isBoxOpen('sessao') ? Hive.box('sessao') : await Hive.openBox('sessao');
      final cfg =
          Hive.isBoxOpen('config') ? Hive.box('config') : await Hive.openBox('config');

      final principalEmail = (sessao.get('usuario_logado_email') ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final principalLegacy = (sessao.get('usuario_logado') ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final principal =
          principalEmail.isNotEmpty ? principalEmail : principalLegacy;

      return LojaAtivaResolver.sessionStoreIfValid(
        storeIdFromSessao: normalizeFromBox(sessao),
        storeIdFromConfig: normalizeFromBox(cfg),
        lastLojaIdFromConfig: (cfg.get('last_loja_id') ?? '').toString().trim(),
        principalSessao: principal,
        authEmail: authEmail,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<StoreIdentityProfileFields> _readProfileFieldsReadOnly(
    String uid,
    String? email,
  ) async {
    String? usersStoreId;
    String? usersOwnerOf;
    String? usersLojaId;
    var usersDocAvailable = false;

    try {
      final snap = await _db.collection('users').doc(uid).get();
      if (snap.exists) {
        usersDocAvailable = true;
        final data = snap.data();
        usersStoreId = data?['store_id']?.toString().trim();
        usersOwnerOf = data?['ownerOf']?.toString().trim();
        usersLojaId = data?['lojaId']?.toString().trim();
      }
    } catch (_) {}

    String? usuariosStoreId;
    String? usuariosOwnerStoreId;
    var usuariosDocAvailable = false;

    final normalizedEmail = (email ?? '').trim().toLowerCase();
    if (normalizedEmail.isNotEmpty) {
      try {
        final snap = await _db.collection('usuarios').doc(normalizedEmail).get();
        if (snap.exists) {
          usuariosDocAvailable = true;
          final data = snap.data();
          usuariosStoreId = data?['store_id']?.toString().trim();
          usuariosOwnerStoreId = data?['ownerStoreId']?.toString().trim();
        }
      } catch (_) {}
    }

    return StoreIdentityProfileFields(
      usersStoreId: usersStoreId,
      usersOwnerOf: usersOwnerOf,
      usersLojaId: usersLojaId,
      usuariosStoreId: usuariosStoreId,
      usuariosOwnerStoreId: usuariosOwnerStoreId,
      usersDocAvailable: usersDocAvailable,
      usuariosDocAvailable: usuariosDocAvailable,
    );
  }
}
