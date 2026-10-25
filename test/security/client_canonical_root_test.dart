import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/subscription_service.dart';
import 'package:master_palm/utils/role_utils.dart';

/// sha256 (16 hex) do UID root legado do cliente: o teste detecta o valor sem tê-lo no source.
const _legacyRootUidSha16 = 'e0922588eef1cda8';
const _rootEmail = 'masterpalm26@gmail.com';
const _oldRootEmails = ['masterpalm@gmail.com', 'admin@masterpalm.com'];

class _FakeUser implements User {
  _FakeUser({required this.uid, this.email, this.emailVerified = false});

  @override
  final String uid;
  @override
  final String? email;
  @override
  final bool emailVerified;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Iterable<File> _dartSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

String _sha16(String s) =>
    sha256.convert(utf8.encode(s)).toString().substring(0, 16);

void _signIn(User? user) => RoleUtils.currentUserOverride = () => user;

/// Ex-root: conta antiga com marcadores `programador`/`is_root`, sem e-mail root verificado.
final _exRoot = _FakeUser(
  uid: 'ex_root_uid_fixture',
  email: 'ex-root@example.com',
  emailVerified: false,
);

final _verifiedRoot =
    _FakeUser(uid: 'root_uid_fixture', email: _rootEmail, emailVerified: true);

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('client_root_test_');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    RoleUtils.currentUserOverride = null;
    if (Hive.isBoxOpen('sessao')) await Hive.box('sessao').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  group('Ex-root (AUTH_CASE_031) não é root no cliente', () {
    test('sem root de plataforma nem SubscriptionService.isRoot', () {
      _signIn(_exRoot);
      expect(RoleUtils.isCurrentUserVerifiedRoot(), isFalse);
      expect(SubscriptionService.isRoot, isFalse);
    });

    test('role programador do Firestore/Hive vale admin', () {
      _signIn(_exRoot);
      final role = RoleUtils.resolveRole(
        isVerifiedRoot: RoleUtils.isCurrentUserVerifiedRoot(),
        firestoreRole: 'programador',
        localRole: 'programador',
      );
      expect(role, UserRole.admin);
      expect(role.isRoot, isFalse);
      expect(
        RoleUtils.platformSafeTipo('programador', isVerifiedRoot: false),
        'admin',
      );
    });

    test('sessão Hive com programador/is_root não destrava UI de root',
        () async {
      _signIn(_exRoot);
      final sessao = await Hive.openBox('sessao');
      await sessao.put('tipo_usuario', 'programador');
      await sessao.put('role', 'programador');
      await sessao.put('is_root', true);

      final role = await RoleUtils.loadFromSession();
      expect(role, UserRole.admin);
      expect(role.isRoot, isFalse);
    });

    test('saveToSession não grava is_root para o ex-root', () async {
      _signIn(_exRoot);
      await RoleUtils.saveToSession(
        email: _exRoot.email!,
        role: UserRole.programador,
      );
      final sessao = Hive.box('sessao');
      expect(sessao.get('is_root'), isFalse);
      expect(sessao.get('tipo_usuario'), 'admin');
    });

    test('tipos não-root ficam inalterados', () {
      expect(RoleUtils.platformSafeTipo('admin', isVerifiedRoot: false), 'admin');
      expect(
        RoleUtils.platformSafeTipo('vendedor', isVerifiedRoot: false),
        'vendedor',
      );
      expect(RoleUtils.platformSafeTipo('', isVerifiedRoot: false), '');
    });
  });

  group('UID root legado', () {
    test('não existe mais em lib/ (comparação por hash)', () {
      final literal = RegExp(r'''['"]([A-Za-z0-9]{28})['"]''');
      final hits = <String>[];
      for (final f in _dartSources()) {
        for (final m in literal.allMatches(f.readAsStringSync())) {
          if (_sha16(m.group(1)!) == _legacyRootUidSha16) hits.add(f.path);
        }
      }
      expect(hits, isEmpty);
    });

    test('nenhum UID destrava root sem e-mail root verificado', () {
      _signIn(_FakeUser(uid: 'qualquer_uid', email: null, emailVerified: true));
      expect(RoleUtils.isCurrentUserVerifiedRoot(), isFalse);
      expect(SubscriptionService.isRoot, isFalse);
    });

    test('SubscriptionService não expõe rootUid/rootEmail', () {
      final src =
          File('lib/services/subscription_service.dart').readAsStringSync();
      expect(src.contains('rootUid'), isFalse);
      expect(src.contains('rootEmail'), isFalse);
    });
  });

  group('Root canônico verificado', () {
    test('mantém root e UI Master', () async {
      _signIn(_verifiedRoot);
      expect(RoleUtils.isCurrentUserVerifiedRoot(), isTrue);
      expect(SubscriptionService.isRoot, isTrue);
      expect(
        RoleUtils.resolveRole(isVerifiedRoot: true, firestoreRole: 'vendedor'),
        UserRole.programador,
      );
      expect(
        RoleUtils.platformSafeTipo('admin', isVerifiedRoot: true),
        'programador',
      );

      final sessao = await Hive.openBox('sessao');
      await sessao.put('tipo_usuario', 'admin');
      expect(await RoleUtils.loadFromSession(), UserRole.programador);
    });

    test('e-mail canônico não verificado não qualifica', () {
      _signIn(_FakeUser(uid: 'root_uid_fixture', email: _rootEmail));
      expect(RoleUtils.isCurrentUserVerifiedRoot(), isFalse);
      expect(SubscriptionService.isRoot, isFalse);
    });

    test('e-mails root antigos não qualificam, mesmo verificados', () {
      for (final email in _oldRootEmails) {
        _signIn(_FakeUser(uid: 'old_$email', email: email, emailVerified: true));
        expect(RoleUtils.isRootEmail(email), isFalse, reason: email);
        expect(RoleUtils.isCurrentUserVerifiedRoot(), isFalse, reason: email);
        expect(SubscriptionService.isRoot, isFalse, reason: email);
      }
    });

    test('sem usuário autenticado não há root', () {
      _signIn(null);
      expect(RoleUtils.isCurrentUserVerifiedRoot(), isFalse);
    });
  });

  group('Sem listas de root no cliente', () {
    test('Remote Config não define admins root dinâmicos', () {
      final src = File('lib/core/remote_config_keys.dart').readAsStringSync();
      expect(src.contains('rcRootAdminEmailsJson'), isFalse);
      expect(src.contains('rcEnableDynamicRootAdmins'), isFalse);
    });

    test('rootEmails contém só o e-mail canônico', () {
      expect(rootEmails, {_rootEmail});
    });
  });
}
