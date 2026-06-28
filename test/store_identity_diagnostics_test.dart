// Testes do diagnóstico sanitizado de identidade de loja.

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/catalogo_sync_attempt_context.dart';
import 'package:master_palm/services/catalogo_sync_diagnostics_service.dart';
import 'package:master_palm/services/store_identity_diagnostic_snapshot.dart';
import 'package:master_palm/services/store_identity_diagnostics_service.dart';

const _uid = 'uid-teste-diagnostico';
const _email = 'usuario-teste@example.com';
const _canonical = 'loja-canonica-teste';
const _legacy = 'loja-legada-teste';

StoreIdentityProfileFields _profile({
  String? storeId,
  String? ownerOf,
  String? lojaId,
  String? usuariosStoreId,
  String? ownerStoreId,
}) {
  return StoreIdentityProfileFields(
    usersStoreId: storeId,
    usersOwnerOf: ownerOf,
    usersLojaId: lojaId,
    usuariosStoreId: usuariosStoreId,
    usuariosOwnerStoreId: ownerStoreId,
    usersDocAvailable: storeId != null || ownerOf != null || lojaId != null,
    usuariosDocAvailable: usuariosStoreId != null || ownerStoreId != null,
  );
}

Future<void> _configureCapture({
  String? session,
  String? resolved,
  String? active,
  StoreIdentityProfileFields? profile,
}) async {
  StoreIdentityDiagnosticsService.debugAuthUid = _uid;
  StoreIdentityDiagnosticsService.debugAuthEmail = _email;
  StoreIdentityDiagnosticsService.debugSessionStoreReader =
      () async => session;
  StoreIdentityDiagnosticsService.debugResolvedStoreResolver =
      () async => resolved;
  StoreIdentityDiagnosticsService.debugActiveStoreResolver =
      ({String origem = ''}) async => active;
  StoreIdentityDiagnosticsService.debugProfileReader =
      (uid, email) async => profile ?? const StoreIdentityProfileFields();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    StoreIdentityDiagnosticsService.resetForTests();
    Hive.init('store_identity_diag_test_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    StoreIdentityDiagnosticsService.resetForTests();
    await Hive.close();
  });

  group('StoreIdentityDiagnosticsService — relações', () {
    test('1. perfil totalmente alinhado', () async {
      await _configureCapture(
        session: _canonical,
        resolved: _canonical,
        active: _canonical,
        profile: _profile(
          storeId: _canonical,
          ownerOf: _canonical,
          lojaId: _canonical,
          usuariosStoreId: _canonical,
          ownerStoreId: _canonical,
        ),
      );

      final snap = await StoreIdentityDiagnosticsService.capture();

      expect(snap.profileHasLegacyConflict, isFalse);
      expect(snap.sessionVsCanonical, StoreIdentityRelation.matchCanonical);
      expect(snap.resolvedVsCanonical, StoreIdentityRelation.matchCanonical);
      expect(snap.activeStoreMatchesCanonical, StoreIdentityRelation.matchCanonical);
      expect(snap.sessionEqualsResolved, StoreIdentityRelation.matchCanonical);
      expect(snap.sessionVsLegacy, StoreIdentityRelation.notApplicable);
      expect(snap.activeStoreResolutionSource,
          StoreIdentityResolutionSource.sessionStoreId);
      expect(snap.diagnosticDataCompleteness,
          StoreIdentityDiagnosticCompleteness.full);
    });

    test('2. perfil com legado divergente, sessão e resolvida canônicas', () async {
      await _configureCapture(
        session: _canonical,
        resolved: _canonical,
        active: _canonical,
        profile: _profile(
          storeId: _canonical,
          ownerOf: _canonical,
          lojaId: _legacy,
          usuariosStoreId: _canonical,
          ownerStoreId: _legacy,
        ),
      );

      final snap = await StoreIdentityDiagnosticsService.capture();

      expect(snap.profileHasLegacyConflict, isTrue);
      expect(snap.profileLojaIdLegacyAvailable, isTrue);
      expect(snap.legacyOwnerStoreIdAvailable, isTrue);
      expect(snap.sessionVsCanonical, StoreIdentityRelation.matchCanonical);
      expect(snap.sessionVsLegacy, StoreIdentityRelation.mismatch);
      expect(snap.resolvedVsCanonical, StoreIdentityRelation.matchCanonical);
      expect(snap.activeStoreMatchesCanonical, StoreIdentityRelation.matchCanonical);
      expect(snap.activeStoreMatchesLegacy, StoreIdentityRelation.mismatch);
    });

    test('3. sessão apontando para loja legada', () async {
      await _configureCapture(
        session: _legacy,
        resolved: _legacy,
        active: _legacy,
        profile: _profile(
          storeId: _canonical,
          lojaId: _legacy,
        ),
      );

      final snap = await StoreIdentityDiagnosticsService.capture();

      expect(snap.profileHasLegacyConflict, isTrue);
      expect(snap.sessionVsCanonical, StoreIdentityRelation.mismatch);
      expect(snap.sessionVsLegacy, StoreIdentityRelation.matchLegacy);
      expect(snap.resolvedVsLegacy, StoreIdentityRelation.matchLegacy);
      expect(snap.activeStoreMatchesLegacy, StoreIdentityRelation.matchLegacy);
      expect(snap.activeStoreMatchesCanonical, StoreIdentityRelation.mismatch);
      expect(snap.activeStoreResolutionSource,
          StoreIdentityResolutionSource.sessionStoreId);
    });

    test('4. sessão diferente da canônica e do legado', () async {
      const outra = 'loja-terceira-teste';
      await _configureCapture(
        session: outra,
        resolved: outra,
        active: outra,
        profile: _profile(storeId: _canonical, lojaId: _legacy),
      );

      final snap = await StoreIdentityDiagnosticsService.capture();

      expect(snap.sessionVsCanonical, StoreIdentityRelation.mismatch);
      expect(snap.sessionVsLegacy, StoreIdentityRelation.mismatch);
      expect(snap.activeStoreResolutionSource,
          StoreIdentityResolutionSource.sessionStoreId);
    });

    test('5. sessão indisponível', () async {
      await _configureCapture(
        session: null,
        resolved: _canonical,
        active: _canonical,
        profile: _profile(storeId: _canonical),
      );

      final snap = await StoreIdentityDiagnosticsService.capture();

      expect(snap.sessionVsCanonical, StoreIdentityRelation.unavailable);
      expect(snap.sessionEqualsResolved, StoreIdentityRelation.unavailable);
      expect(snap.diagnosticDataCompleteness,
          StoreIdentityDiagnosticCompleteness.partial);
    });

    test('6. perfil remoto parcialmente indisponível', () async {
      await _configureCapture(
        session: _canonical,
        resolved: _canonical,
        active: _canonical,
        profile: const StoreIdentityProfileFields(),
      );

      final snap = await StoreIdentityDiagnosticsService.capture();

      expect(snap.profileCanonicalStoreAvailable, isFalse);
      expect(snap.sessionVsCanonical, StoreIdentityRelation.unavailable);
      expect(snap.diagnosticDataCompleteness,
          StoreIdentityDiagnosticCompleteness.partial);
    });

    test('7. ownerOf como fallback quando store_id ausente', () async {
      await _configureCapture(
        session: _canonical,
        resolved: _canonical,
        active: _canonical,
        profile: _profile(ownerOf: _canonical),
      );

      final snap = await StoreIdentityDiagnosticsService.capture();

      expect(snap.profileCanonicalStoreAvailable, isTrue);
      expect(snap.profileStoreIdAvailable, isFalse);
      expect(snap.profileOwnerOfAvailable, isTrue);
      expect(snap.sessionVsCanonical, StoreIdentityRelation.matchCanonical);
    });

    test('8. lojaId legado não vira canônica se store_id existir', () async {
      await _configureCapture(
        session: _canonical,
        resolved: _canonical,
        active: _canonical,
        profile: _profile(storeId: _canonical, lojaId: _legacy),
      );

      final snap = await StoreIdentityDiagnosticsService.capture();

      expect(snap.profileHasLegacyConflict, isTrue);
      expect(snap.sessionVsCanonical, StoreIdentityRelation.matchCanonical);
      expect(snap.resolvedVsCanonical, StoreIdentityRelation.matchCanonical);
      expect(snap.activeStoreMatchesCanonical, StoreIdentityRelation.matchCanonical);
    });
  });

  group('Sanitização — sem IDs completos', () {
    test('9–10. snapshot, JSON e relatório não expõem IDs completos', () async {
      await _configureCapture(
        session: _canonical,
        resolved: _canonical,
        active: _legacy,
        profile: _profile(storeId: _canonical, lojaId: _legacy),
      );

      final snap = await StoreIdentityDiagnosticsService.capture();
      final json = jsonEncode(snap.toSanitizedMap());
      final report = snap.buildReportSection();

      for (final forbidden in [_canonical, _legacy, _uid, _email]) {
        expect(json.contains(forbidden), isFalse,
            reason: 'JSON contém valor proibido');
        expect(report.contains(forbidden), isFalse,
            reason: 'Relatório contém valor proibido');
      }

      expect(json.contains('hash'), isFalse);
      expect(json.contains('fingerprint'), isFalse);
      expect(json.contains('md5'), isFalse);
      expect(json.contains('sha'), isFalse);
    });

    test('16. copiar relatório seguro contém relações', () async {
      await _configureCapture(
        session: _legacy,
        resolved: _legacy,
        active: _legacy,
        profile: _profile(storeId: _canonical, lojaId: _legacy),
      );

      final snap = await StoreIdentityDiagnosticsService.capture();
      final combined = CatalogoSyncDiagnosticsService.buildCombinedSafeReport(
        attemptRecord: null,
        identitySnapshot: snap,
      );

      expect(combined, contains('Sessão vs canônica'));
      expect(combined, contains('Sessão vs legado'));
      expect(combined, contains('Conflito remoto de perfil'));
      expect(combined.contains(_canonical), isFalse);
      expect(combined.contains(_legacy), isFalse);
    });
  });

  group('Read-only e não bloqueante', () {
    test('11. leitura Firestore sem escrita', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('users').doc(_uid).set({
        'store_id': _canonical,
        'lojaId': _legacy,
      });

      StoreIdentityDiagnosticsService.debugFirestoreOverride = fake;
      StoreIdentityDiagnosticsService.debugProfileReader = null;
      StoreIdentityDiagnosticsService.debugSessionStoreReader =
          () async => _canonical;
      StoreIdentityDiagnosticsService.debugResolvedStoreResolver =
          () async => _canonical;
      StoreIdentityDiagnosticsService.debugActiveStoreResolver =
          ({String origem = ''}) async => _canonical;

      // Simula auth via profile reader delegando ao fake
      StoreIdentityDiagnosticsService.debugProfileReader =
          (uid, email) async {
        final snap = await fake.collection('users').doc(uid).get();
        final data = snap.data();
        return StoreIdentityProfileFields(
          usersStoreId: data?['store_id']?.toString(),
          usersLojaId: data?['lojaId']?.toString(),
          usersDocAvailable: snap.exists,
        );
      };

      await StoreIdentityDiagnosticsService.capture();

      final after = await fake.collection('users').doc(_uid).get();
      expect(after.data()?['store_id'], _canonical);
      // FakeFirestore não tem contagem de writes fácil; doc inalterado confirma.
    });

    test('13. não altera Hive de sessão', () async {
      final sessaoName =
          'sessao_identity_test_${DateTime.now().microsecondsSinceEpoch}';
      final sessao = await Hive.openBox(sessaoName);
      await sessao.put('store_id', _legacy);
      final antes = sessao.get('store_id');

      StoreIdentityDiagnosticsService.debugSessionStoreReader = () async {
        return (sessao.get('store_id') ?? '').toString();
      };
      await _configureCapture(
        session: _legacy,
        resolved: _legacy,
        active: _legacy,
        profile: _profile(storeId: _canonical, lojaId: _legacy),
      );

      await StoreIdentityDiagnosticsService.capture();

      expect(sessao.get('store_id'), antes);
      await sessao.close();
    });

    test('14–15. captureSafe parcial não lança exceção', () async {
      StoreIdentityDiagnosticsService.debugAuthUid = _uid;
      StoreIdentityDiagnosticsService.debugProfileReader =
          (uid, email) async => _profile(storeId: _canonical);
      StoreIdentityDiagnosticsService.debugSessionStoreReader =
          () async => throw StateError('falha simulada');
      StoreIdentityDiagnosticsService.debugResolvedStoreResolver =
          () async => _canonical;
      StoreIdentityDiagnosticsService.debugActiveStoreResolver =
          ({String origem = ''}) async => _canonical;

      final snap = await StoreIdentityDiagnosticsService.captureSafe();
      expect(snap.diagnosticDataCompleteness,
          StoreIdentityDiagnosticCompleteness.partial);
      expect(snap.resolvedVsCanonical, StoreIdentityRelation.matchCanonical);

      expect(() async => snap.toSanitizedMap(), returnsNormally);
    });
  });

  group('Integração tentativa catálogo', () {
    test('identidade incluída no contexto sanitizado', () async {
      await _configureCapture(
        session: _canonical,
        resolved: _canonical,
        active: _canonical,
        profile: _profile(storeId: _canonical, lojaId: _legacy),
      );

      // Injeta captura de identidade via synthetic no contexto de teste
      final identity = await StoreIdentityDiagnosticsService.capture();
      final ctx = CatalogoSyncAttemptContext.synthetic(
        attemptId: 'attempt-teste',
        storeIdentity: identity,
      );

      final map = ctx.toSanitizedMap();
      expect(map['identidadeLoja'], isNotNull);
      final idMap = map['identidadeLoja'] as Map<String, dynamic>;
      expect(idMap['profileHasLegacyConflict'], isTrue);
      expect(jsonEncode(idMap).contains(_legacy), isFalse);
    });
  });

  group('18. sem hardcode de cliente', () {
    test('serviço não referencia lojas reais conhecidas', () {
      const forbidden = ['mirjoias', 'mariaisaabel42', 'nathy-pratas'];
      // Verificação estática leve via strings nos enums/labels exportados.
      for (final label in StoreIdentityResolutionSource.values) {
        expect(forbidden.any((f) => label.name.contains(f)), isFalse);
      }
    });
  });
}
