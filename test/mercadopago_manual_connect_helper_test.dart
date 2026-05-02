import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/mercadopago_manual_connect_helper.dart';

void main() {
  test('persiste token e faz merge quando fetchProfile retorna dados',
      () async {
    String? persistedLoja;
    String? persistedToken;
    Map<String, dynamic>? merged;

    final deps = MercadoPagoManualConnectDeps(
      validateRemote: (_) async => true,
      fetchProfile: (_) async => {
        'email': 'loja@example.com',
        'id': 123,
        'nickname': 'nick',
      },
      clearMpIdentityBeforeToken: (_) async {},
      persistAccessToken: (lojaId, accessToken, {catalogTokenValidated}) async {
        persistedLoja = lojaId;
        persistedToken = accessToken;
        expect(catalogTokenValidated, isTrue);
      },
      mergeMpProfile: (_, info) async {
        merged = Map<String, dynamic>.from(info);
      },
    );

    final r = await MercadoPagoManualConnectHelper.connect(
      lojaId: 'loja-1',
      rawToken: '  APP_USR-xxxxxxxxxxxxxxxxxxxx  ',
      deps: deps,
    );

    expect(r.success, isTrue);
    expect(r.tokenPersisted, isTrue);
    expect(r.profileMerged, isTrue);
    expect(r.profileEmail, 'loja@example.com');
    expect(persistedLoja, 'loja-1');
    expect(persistedToken, 'APP_USR-xxxxxxxxxxxxxxxxxxxx');
    expect(merged!['email'], 'loja@example.com');
    expect(merged!['id'], 123);
  });

  test('sem perfil: ainda persiste token e não chama merge', () async {
    var persistCount = 0;
    var mergeCount = 0;

    final deps = MercadoPagoManualConnectDeps(
      validateRemote: (_) async => true,
      fetchProfile: (_) async => null,
      clearMpIdentityBeforeToken: (_) async {},
      persistAccessToken: (_, __, {catalogTokenValidated}) async {
        persistCount++;
        expect(catalogTokenValidated, isTrue);
      },
      mergeMpProfile: (_, __) async {
        mergeCount++;
      },
    );

    final r = await MercadoPagoManualConnectHelper.connect(
      lojaId: 'loja-1',
      rawToken: 'APP_USR-12345678901234567890',
      deps: deps,
    );

    expect(r.success, isTrue);
    expect(persistCount, 1);
    expect(mergeCount, 0);
    expect(r.profileMerged, isFalse);
  });

  test('snackbarMessage não inclui o token', () {
    final r = MercadoPagoManualConnectResult(
      success: true,
      normalizedToken: 'APP_USR-SECRET_SHOULD_NOT_APPEAR',
      remoteValidationOk: true,
      tokenPersisted: true,
    );
    final msg = MercadoPagoManualConnectHelper.snackbarMessage(r);
    expect(msg.contains('SECRET'), isFalse);
    expect(msg.contains('APP_USR'), isFalse);
  });

  test('limpa identidade antes de persistir o token', () async {
    final order = <String>[];

    final deps = MercadoPagoManualConnectDeps(
      validateRemote: (_) async => true,
      fetchProfile: (_) async => null,
      clearMpIdentityBeforeToken: (_) async {
        order.add('clear');
      },
      persistAccessToken: (_, __, {catalogTokenValidated}) async {
        order.add('persist');
        expect(catalogTokenValidated, isTrue);
      },
      mergeMpProfile: (_, __) async {},
    );

    await MercadoPagoManualConnectHelper.connect(
      lojaId: 'loja-1',
      rawToken: 'APP_USR-12345678901234567890',
      deps: deps,
    );

    expect(order, ['clear', 'persist']);
  });

  test('snackbarMessage com e-mail de perfil', () {
    final r = MercadoPagoManualConnectResult(
      success: true,
      normalizedToken: 'x',
      remoteValidationOk: true,
      tokenPersisted: true,
      profileMerged: true,
      profileEmail: 'a@b.com',
    );
    expect(
      MercadoPagoManualConnectHelper.snackbarMessage(r),
      'Mercado Pago conectado! a@b.com',
    );
  });
}
