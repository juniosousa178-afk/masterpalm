import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/master_config.dart';
import 'package:master_palm/screens/master_config_screen.dart';
import 'package:master_palm/services/master_config_service.dart';
import 'package:master_palm/utils/role_utils.dart';

/// sha256 (16 hex) da antiga senha master padrão: o teste detecta o valor sem tê-lo no source.
const _legacyDefaultPasswordSha16 = 'f1f64410d6fe3212';
const _legacyFields = [
  'masterPassword',
  'mercadoPagoAccessToken',
  'mercadoPagoPublicKey',
];
const _rootEmail = 'masterpalm26@gmail.com';

Iterable<File> _dartSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

String _sha16(String s) => sha256.convert(utf8.encode(s)).toString().substring(0, 16);

Map<String, dynamic> _legacyCachedDoc() => {
      'masterPassword': 'legacy-cached-value',
      'mercadoPagoAccessToken': 'APP_USR-legacy-cached',
      'mercadoPagoPublicKey': 'APP_USR-legacy-public',
      'campoDesconhecido': 'x',
      'requirePlanForNewUsers': false,
      'usersWithUnlimitedAccess': ['a@b.com'],
      'globalSettings': {'supportPhone': '5511999999999'},
      'lastUpdated': '2026-04-12T00:04:31.886',
      'updatedBy': _rootEmail,
    };

void main() {
  group('Source: sem senha master nem credenciais legadas', () {
    test('a senha master padrão não aparece em nenhum literal de lib/', () {
      final literals = [RegExp(r"'([^'\\\r\n]*)'"), RegExp(r'"([^"\\\r\n]*)"')];
      final hits = <String>[];
      for (final f in _dartSources()) {
        final text = f.readAsStringSync();
        for (final re in literals) {
          for (final m in re.allMatches(text)) {
            final value = m.group(1) ?? '';
            if (value.isNotEmpty && _sha16(value) == _legacyDefaultPasswordSha16) hits.add(f.path);
          }
        }
      }
      expect(hits, isEmpty);
    });

    test('nenhum serializador/validador de senha master ou credencial MP legada em lib/', () {
      final forbidden = RegExp(
        r'masterPassword|validateMasterPassword|updateMasterPassword|'
        r'mercadoPagoAccessToken|mercadoPagoPublicKey|updateMercadoPagoKeys|MasterLoginScreen',
      );
      final hits = [
        for (final f in _dartSources())
          if (forbidden.hasMatch(f.readAsStringSync())) f.path,
      ];
      expect(hits, isEmpty);
    });
  });

  group('MasterConfig: allowlist', () {
    test('toMap grava somente os campos permitidos', () {
      expect(MasterConfig().toMap().keys.toSet(), MasterConfig.allowedFields.toSet());
    });

    test('documento sem masterPassword carrega sem erro e sem senha padrão', () {
      final c = MasterConfig.fromMap({});
      expect(c.requirePlanForNewUsers, isTrue);
      expect(c.toMap().keys.any(_legacyFields.contains), isFalse);
    });

    test('objeto legado em cache não ressuscita campos removidos', () {
      final c = MasterConfig.fromMap(_legacyCachedDoc());
      final payload = MasterConfigService.buildWritePayload(c);
      for (final f in [..._legacyFields, 'campoDesconhecido']) {
        expect(payload.containsKey(f), isFalse, reason: f);
      }
      expect(payload['requirePlanForNewUsers'], isFalse);
      expect(payload['usersWithUnlimitedAccess'], ['a@b.com']);
    });

    test('tipos inesperados no documento não quebram a leitura', () {
      final c = MasterConfig.fromMap({
        'requirePlanForNewUsers': 'sim',
        'usersWithUnlimitedAccess': 'x',
        'globalSettings': 3,
        'lastUpdated': 'não é data',
      });
      expect(c.requirePlanForNewUsers, isTrue);
      expect(c.usersWithUnlimitedAccess, isEmpty);
      expect(c.globalSettings, isEmpty);
      expect(c.lastUpdated, isNull);
    });
  });

  group('MasterConfigService.saveMasterConfig', () {
    late FakeFirebaseFirestore db;
    DocumentReferenceLike doc() => DocumentReferenceLike(db);

    setUp(() {
      db = FakeFirebaseFirestore();
      MasterConfigService.firestoreForTesting = db;
    });
    tearDown(() => MasterConfigService.firestoreForTesting = null);

    test('descarta campos legados/desconhecidos e não restaura credenciais MP', () async {
      await doc().set({'requirePlanForNewUsers': true, 'globalSettings': {}});
      await MasterConfigService.saveMasterConfig(
        MasterConfig.fromMap(_legacyCachedDoc()),
        updatedBy: _rootEmail,
      );
      final data = await doc().data();
      for (final f in [..._legacyFields, 'campoDesconhecido']) {
        expect(data.containsKey(f), isFalse, reason: f);
      }
      expect(data['requirePlanForNewUsers'], isFalse);
      expect(data.keys.every(MasterConfig.allowedFields.contains), isTrue);
    });

    test('documento antigo com masterPassword: lê sem erro e nunca regrava senha padrão', () async {
      await doc().set({'masterPassword': 'valor-antigo', 'requirePlanForNewUsers': true});
      final loaded = await MasterConfigService.loadMasterConfig();
      expect(loaded.requirePlanForNewUsers, isTrue);
      await MasterConfigService.saveMasterConfig(
        loaded.copyWith(requirePlanForNewUsers: false),
        updatedBy: _rootEmail,
      );
      final data = await doc().data();
      expect(data['masterPassword'], 'valor-antigo');
      expect(data['requirePlanForNewUsers'], isFalse);
    });

    test('documento ausente: carrega padrão sem gravar nada', () async {
      final loaded = await MasterConfigService.loadMasterConfig();
      expect(loaded.usersWithUnlimitedAccess, isEmpty);
      expect((await db.collection('app_config').doc('master_config').get()).exists, isFalse);
    });

    test('exportação não contém campos legados', () async {
      await doc().set(_legacyCachedDoc());
      final exported = jsonDecode(await MasterConfigService.exportConfigJson()) as Map;
      expect(exported.keys.any(_legacyFields.contains), isFalse);
    });
  });

  group('Autoridade root canônica', () {
    test('root verificado tem acesso', () {
      expect(RoleUtils.isVerifiedRootAccount(email: _rootEmail, emailVerified: true), isTrue);
    });

    test('root não verificado, outros e-mails e sessão vazia não têm acesso', () {
      expect(RoleUtils.isVerifiedRootAccount(email: _rootEmail, emailVerified: false), isFalse);
      expect(RoleUtils.isVerifiedRootAccount(email: 'admin@masterpalm.com', emailVerified: true), isFalse);
      expect(RoleUtils.isVerifiedRootAccount(email: 'cliente@loja.com', emailVerified: true), isFalse);
      expect(RoleUtils.isVerifiedRootAccount(email: null, emailVerified: true), isFalse);
    });
  });

  group('MasterConfigScreen', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      db = FakeFirebaseFirestore();
      MasterConfigService.firestoreForTesting = db;
    });
    tearDown(() => MasterConfigService.firestoreForTesting = null);

    Future<void> openFromHome(WidgetTester tester, {required bool allowed}) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MasterConfigScreen(accessCheck: () => allowed),
              )),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('não-root é bloqueado antes de carregar a configuração', (tester) async {
      await openFromHome(tester, allowed: false);
      expect(find.byType(MasterConfigScreen), findsNothing);
      expect(find.text('Acesso restrito ao root. Você não tem permissão.'), findsOneWidget);
    });

    testWidgets('root abre o painel sem masterPassword no documento e sem campos legados', (tester) async {
      await db.collection('app_config').doc('master_config').set({
        'requirePlanForNewUsers': true,
        'usersWithUnlimitedAccess': <String>[],
        'globalSettings': <String, dynamic>{},
      });
      await openFromHome(tester, allowed: true);
      expect(find.text('Painel de Controle Master'), findsOneWidget);
      expect(find.textContaining('Senha Master'), findsNothing);
      expect(find.textContaining('Access Token'), findsNothing);
      // Desmonta para cancelar o timer de sessão da tela.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// Acesso curto ao documento `app_config/master_config` no Firestore falso.
class DocumentReferenceLike {
  DocumentReferenceLike(this.db);
  final FakeFirebaseFirestore db;

  Future<void> set(Map<String, dynamic> data) =>
      db.collection('app_config').doc('master_config').set(data);

  Future<Map<String, dynamic>> data() async =>
      (await db.collection('app_config').doc('master_config').get()).data() ?? {};
}
