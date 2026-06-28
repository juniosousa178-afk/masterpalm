// Contexto imutável de uma tentativa de sync de catálogo (um save de produto).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/loja_ativa_resolver.dart';
import 'catalogo_sync_diagnostic_mask_util.dart';
import 'store_resolver_facade.dart';

/// Intenção da mutação Firestore (sem afirmar create/update de Rules).
enum CatalogoSyncMutationIntent {
  set,
  update,
  transaction,
  unknown,
}

/// Dica de existência do doc — somente quando já havia leitura no fluxo existente.
enum CatalogoSyncDocumentStateHint {
  unknown,
  knownPresentFromExistingState,
  knownAbsentFromExistingState,
}

class CatalogoSyncAttemptContext {
  const CatalogoSyncAttemptContext({
    required this.attemptId,
    required this.origin,
    required this.startedAtUtc,
    required this.buildId,
    required this.firebaseProjectId,
    required this.firebaseAppName,
    required this.firestoreAppName,
    required this.host,
    required this.sessionStoreIdMasked,
    required this.resolvedStoreIdMasked,
    required this.authUidMasked,
    required this.authState,
    required this.isAnonymous,
    required this.tokenMetadataState,
    this.authTimeUtc,
    this.issuedAtUtc,
    this.expirationTimeUtc,
    this.claimKeysOnly = const [],
  });

  final String attemptId;
  final String origin;
  final DateTime startedAtUtc;
  final String buildId;
  final String firebaseProjectId;
  final String firebaseAppName;
  final String firestoreAppName;
  final String host;
  final String sessionStoreIdMasked;
  final String resolvedStoreIdMasked;
  final String authUidMasked;
  final String authState;
  final bool isAnonymous;
  final String tokenMetadataState;
  final String? authTimeUtc;
  final String? issuedAtUtc;
  final String? expirationTimeUtc;
  final List<String> claimKeysOnly;

  String get attemptIdCurto =>
      CatalogoSyncDiagnosticMaskUtil.attemptIdCurto(attemptId);

  /// Captura contexto sanitizado uma vez por save de produto.
  static Future<CatalogoSyncAttemptContext> capture({
    required String origin,
    String? sessionStoreIdHint,
  }) async {
    final attemptId = const Uuid().v4();
    final startedAtUtc = DateTime.now().toUtc();

    String firebaseProjectId = '—';
    String firebaseAppName = '—';
    String firestoreAppName = '—';
    try {
      final app = Firebase.app();
      firebaseProjectId = app.options.projectId;
      firebaseAppName = app.name;
      firestoreAppName = FirebaseFirestore.instance.app.name;
    } catch (_) {}

    final host = kIsWeb
        ? (Uri.base.host.isEmpty ? 'web' : Uri.base.host)
        : defaultTargetPlatform.name;

    const buildId = String.fromEnvironment(
      'CATALOG_BUILD_ID',
      defaultValue: 'dev',
    );

    String sessionStoreId = sessionStoreIdHint?.trim() ?? '';
    if (sessionStoreId.isEmpty) {
      try {
        final sessao = Hive.isBoxOpen('sessao')
            ? Hive.box('sessao')
            : await Hive.openBox('sessao');
        sessionStoreId = (sessao.get('store_id') ?? '').toString().trim();
      } catch (_) {}
    }

    String? resolvedStoreId;
    try {
      resolvedStoreId = await StoreResolverFacade.resolveForAdminApp();
    } catch (_) {}
    if (resolvedStoreId == null || resolvedStoreId.isEmpty) {
      try {
        resolvedStoreId = await LojaAtivaResolver.resolve(origem: origin);
      } catch (_) {}
    }

    final user = FirebaseAuth.instance.currentUser;
    final authState = user == null
        ? 'signed_out'
        : (user.isAnonymous ? 'anonymous' : 'signed_in');

    var tokenMetadataState = 'unavailable';
    String? authTimeUtc;
    String? issuedAtUtc;
    String? expirationTimeUtc;
    List<String> claimKeysOnly = [];

    if (user != null && !user.isAnonymous) {
      try {
        final tokenResult = await user.getIdTokenResult(false);
        tokenMetadataState = 'available';
        authTimeUtc = tokenResult.authTime?.toUtc().toIso8601String();
        issuedAtUtc = tokenResult.issuedAtTime?.toUtc().toIso8601String();
        expirationTimeUtc =
            tokenResult.expirationTime?.toUtc().toIso8601String();
        claimKeysOnly = tokenResult.claims?.keys
                .map((k) => k.toString())
                .toList(growable: false) ??
            const [];
      } catch (_) {
        tokenMetadataState = 'unavailable';
      }
    }

    return CatalogoSyncAttemptContext(
      attemptId: attemptId,
      origin: origin,
      startedAtUtc: startedAtUtc,
      buildId: buildId,
      firebaseProjectId: firebaseProjectId,
      firebaseAppName: firebaseAppName,
      firestoreAppName: firestoreAppName,
      host: host,
      sessionStoreIdMasked:
          CatalogoSyncDiagnosticMaskUtil.mascararLojaId(sessionStoreId),
      resolvedStoreIdMasked:
          CatalogoSyncDiagnosticMaskUtil.mascararLojaId(resolvedStoreId),
      authUidMasked: CatalogoSyncDiagnosticMaskUtil.mascararUid(user?.uid),
      authState: authState,
      isAnonymous: user?.isAnonymous ?? false,
      tokenMetadataState: tokenMetadataState,
      authTimeUtc: authTimeUtc,
      issuedAtUtc: issuedAtUtc,
      expirationTimeUtc: expirationTimeUtc,
      claimKeysOnly: List<String>.unmodifiable(claimKeysOnly),
    );
  }

  @visibleForTesting
  static CatalogoSyncAttemptContext synthetic({
    required String attemptId,
    String origin = 'test',
    DateTime? startedAtUtc,
    String buildId = 'test-build',
    String firebaseProjectId = 'test-project',
    String firebaseAppName = '[DEFAULT]',
    String firestoreAppName = '[DEFAULT]',
    String host = 'test',
    String sessionStoreIdMasked = 'lo…',
    String resolvedStoreIdMasked = 'lo…',
    String authUidMasked = '57Yh…Ow1',
    String authState = 'signed_in',
    bool isAnonymous = false,
    String tokenMetadataState = 'unavailable',
  }) {
    return CatalogoSyncAttemptContext(
      attemptId: attemptId,
      origin: origin,
      startedAtUtc: startedAtUtc ?? DateTime.utc(2026, 6, 26, 12),
      buildId: buildId,
      firebaseProjectId: firebaseProjectId,
      firebaseAppName: firebaseAppName,
      firestoreAppName: firestoreAppName,
      host: host,
      sessionStoreIdMasked: sessionStoreIdMasked,
      resolvedStoreIdMasked: resolvedStoreIdMasked,
      authUidMasked: authUidMasked,
      authState: authState,
      isAnonymous: isAnonymous,
      tokenMetadataState: tokenMetadataState,
    );
  }

  /// Contexto sanitizado para retry da fila (novo attemptId a cada processamento).
  /// Não reutiliza attemptId do save offline original.
  static Future<CatalogoSyncAttemptContext> captureForQueueRetry({
    required String lojaId,
  }) async {
    try {
      return await capture(
        origin: 'sync_queue.canonical_catalog_publish',
        sessionStoreIdHint: lojaId,
      );
    } catch (_) {
      return CatalogoSyncAttemptContext(
        attemptId: const Uuid().v4(),
        origin: 'sync_queue.canonical_catalog_publish',
        startedAtUtc: DateTime.now().toUtc(),
        buildId: const String.fromEnvironment(
          'CATALOG_BUILD_ID',
          defaultValue: 'dev',
        ),
        firebaseProjectId: '—',
        firebaseAppName: '—',
        firestoreAppName: '—',
        host: kIsWeb ? 'web' : defaultTargetPlatform.name,
        sessionStoreIdMasked:
            CatalogoSyncDiagnosticMaskUtil.mascararLojaId(lojaId),
        resolvedStoreIdMasked:
            CatalogoSyncDiagnosticMaskUtil.mascararLojaId(lojaId),
        authUidMasked: '—',
        authState: 'unknown',
        isAnonymous: false,
        tokenMetadataState: 'unavailable',
      );
    }
  }

  Map<String, dynamic> toSanitizedMap() => {
        'attemptIdCurto': attemptIdCurto,
        'origin': origin,
        'startedAtUtc': startedAtUtc.toIso8601String(),
        'buildId': buildId,
        'firebaseProjectId': firebaseProjectId,
        'firebaseAppName': firebaseAppName,
        'firestoreAppName': firestoreAppName,
        'host': host,
        'sessionStoreIdMasked': sessionStoreIdMasked,
        'resolvedStoreIdMasked': resolvedStoreIdMasked,
        'authUidMasked': authUidMasked,
        'authState': authState,
        'isAnonymous': isAnonymous,
        'tokenMetadataState': tokenMetadataState,
        if (authTimeUtc != null) 'authTimeUtc': authTimeUtc,
        if (issuedAtUtc != null) 'issuedAtUtc': issuedAtUtc,
        if (expirationTimeUtc != null) 'expirationTimeUtc': expirationTimeUtc,
        'claimKeysOnly': claimKeysOnly,
      };
}
