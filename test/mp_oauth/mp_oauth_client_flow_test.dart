import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/mp_oauth_callback_screen.dart';
import 'package:master_palm/screens/mp_oauth_start_screen.dart';
import 'package:master_palm/services/pagamentos_service.dart';

const _lojaA = 'loja-a';
const _opaqueState = 'Zk3_opaque-STATE-value_0123456789abcdefghijk';
const _code = 'TG-AUTHCODE-123456';
const _authUrl =
    'https://auth.mercadopago.com/authorization?client_id=1&response_type=code&platform_id=mp&state=$_opaqueState&redirect_uri=https%3A%2F%2Fapp.mastepalm.com.br%2Fmp-oauth-callback';

Uri _startUri([String? lojaId = _lojaA]) => Uri.parse(
    'https://app.mastepalm.com.br/mp-oauth-start${lojaId == null ? '' : '?lojaId=$lojaId'}');

class _StartHarness {
  _StartHarness({
    this.session = true,
    Future<String> Function(String lojaId)? createAuthUrl,
    this.launchResult = true,
  }) : createAuthUrlImpl = createAuthUrl ?? ((_) async => _authUrl);

  final bool session;
  final Future<String> Function(String lojaId) createAuthUrlImpl;
  final bool launchResult;
  final createCalls = <String>[];
  final launched = <Uri>[];
  int signOuts = 0;

  MpOAuthStartScreen screen(Uri uri) => MpOAuthStartScreen(
        uri: uri,
        hasRealSession: () async => session,
        createAuthUrl: (lojaId) {
          createCalls.add(lojaId);
          return createAuthUrlImpl(lojaId);
        },
        launchAuthUrl: (url) async {
          launched.add(url);
          return launchResult;
        },
        signOut: () async => signOuts++,
      );
}

class _CallbackHarness {
  _CallbackHarness({
    this.session = true,
    Future<void> Function()? exchange,
    this.firstAttempt = true,
  }) : exchangeImpl = exchange ?? (() async {});

  final bool session;
  final Future<void> Function() exchangeImpl;
  final bool firstAttempt;
  final exchanges = <List<String>>[];
  final guardKeys = <String>[];

  MpOAuthCallbackScreen screen(Map<String, String> params) =>
      MpOAuthCallbackScreen(
        params: params,
        hasRealSession: () async => session,
        exchange: ({required String code, required String state}) {
          exchanges.add([code, state]);
          return exchangeImpl();
        },
        markAttemptOnce: (state) {
          guardKeys.add(state);
          return firstAttempt;
        },
      );
}

FirebaseFunctionsException _fnError(String code, [String? message]) =>
    FirebaseFunctionsException(code: code, message: message ?? code);

/// Nenhum texto visível nem log pode conter code/state.
void _expectNoSecretsVisible(WidgetTester tester, List<String> logs) {
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    final s = t.data ?? t.textSpan?.toPlainText() ?? '';
    expect(s.contains(_code), isFalse, reason: 'code visível: $s');
    expect(s.contains(_opaqueState), isFalse, reason: 'state visível: $s');
  }
  for (final l in logs) {
    expect(l.contains(_code) || l.contains(_opaqueState), isFalse,
        reason: 'segredo em log: $l');
  }
}

/// testWidgets com captura de debugPrint (restaurado antes das verificações do binding).
void testWidgetsLogged(String description,
    Future<void> Function(WidgetTester, List<String>) body) {
  testWidgets(description, (tester) async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      await body(tester, logs);
    } finally {
      debugPrint = original;
    }
  });
}

void main() {
  group('MpOAuthStartScreen', () {
    testWidgetsLogged(
        'merchant autorizado: pede o state ao servidor e abre a URL tal como veio',
        (tester, logs) async {
      final h = _StartHarness();
      await tester.pumpWidget(h.screen(_startUri()));
      await tester.pumpAndSettle();

      expect(h.createCalls, [_lojaA]);
      expect(h.launched, [Uri.parse(_authUrl)]);
      expect(h.launched.single.queryParameters['state'], _opaqueState);
      expect(find.textContaining('Abrindo o Mercado Pago'), findsOneWidget);
      _expectNoSecretsVisible(tester, logs);
    });

    testWidgets('anónimo/sem sessão: não inicia OAuth e mostra login',
        (tester) async {
      final h = _StartHarness(session: false);
      await tester.pumpWidget(h.screen(_startUri()));
      await tester.pumpAndSettle();

      expect(h.createCalls, isEmpty);
      expect(h.launched, isEmpty);
      expect(find.byType(MpOAuthSignInPanel), findsOneWidget);
    });

    testWidgets(
        'sessão expirada no servidor (unauthenticated) → volta ao login, sem redirect',
        (tester) async {
      final h = _StartHarness(
          createAuthUrl: (_) async => throw _fnError('unauthenticated'));
      await tester.pumpWidget(h.screen(_startUri()));
      await tester.pumpAndSettle();

      expect(h.launched, isEmpty);
      expect(find.byType(MpOAuthSignInPanel), findsOneWidget);
    });

    testWidgets(
        'loja de outro tenant (permission-denied) → mensagem clara, sem redirect',
        (tester) async {
      final h = _StartHarness(
          createAuthUrl: (_) async => throw _fnError('permission-denied',
              'Sem permissão para conectar o Mercado Pago desta loja.'));
      await tester.pumpWidget(h.screen(_startUri('loja-b')));
      await tester.pumpAndSettle();

      expect(h.createCalls, ['loja-b']);
      expect(h.launched, isEmpty);
      expect(find.textContaining('não administra a loja "loja-b"'),
          findsOneWidget);
      expect(
          find.textContaining('Nenhuma alteração foi feita'), findsOneWidget);
      expect(find.text('Entrar com outra conta'), findsOneWidget);
    });

    testWidgets('falha de rede → mensagem, sem redirect', (tester) async {
      final h = _StartHarness(
          createAuthUrl: (_) async => throw _fnError('unavailable'));
      await tester.pumpWidget(h.screen(_startUri()));
      await tester.pumpAndSettle();

      expect(h.launched, isEmpty);
      expect(find.textContaining('Sem resposta do servidor'), findsOneWidget);
    });

    testWidgets('resposta inválida do servidor → erro genérico, sem redirect',
        (tester) async {
      final h = _StartHarness(
          createAuthUrl: (_) async =>
              throw Exception('Resposta inválida do servidor.'));
      await tester.pumpWidget(h.screen(_startUri()));
      await tester.pumpAndSettle();

      expect(h.launched, isEmpty);
      expect(find.textContaining('Não foi possível iniciar a conexão'),
          findsOneWidget);
    });

    testWidgets(
        'launch recusado pelo browser → erro, não fica preso a carregar',
        (tester) async {
      final h = _StartHarness(launchResult: false);
      await tester.pumpWidget(h.screen(_startUri()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Não foi possível abrir o Mercado Pago'),
          findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('sem lojaId → não chama o servidor', (tester) async {
      final h = _StartHarness();
      await tester.pumpWidget(h.screen(_startUri(null)));
      await tester.pumpAndSettle();

      expect(h.createCalls, isEmpty);
      expect(find.textContaining('Loja não informada'), findsOneWidget);
    });

    testWidgets('duplo início: um único pedido de state em voo',
        (tester) async {
      var pending = Completer<String>();
      final h = _StartHarness(createAuthUrl: (_) => pending.future);
      await tester.pumpWidget(h.screen(_startUri()));
      await tester.pump();

      final panelTitle = find.text('Tentar novamente');
      expect(panelTitle, findsNothing);
      expect(h.createCalls.length, 1);

      pending.complete(_authUrl);
      await tester.pumpAndSettle();
      expect(h.launched.length, 1);

      pending = Completer<String>();
      await tester.tap(find.text('Tentar novamente'));
      await tester.tap(find.text('Tentar novamente'), warnIfMissed: false);
      await tester.pump();
      expect(h.createCalls.length, 2);

      pending.complete(_authUrl);
      await tester.pumpAndSettle();
      expect(h.launched.length, 2);
    });
  });

  group('MpOAuthCallbackScreen', () {
    Map<String, String> ok() => {'code': _code, 'state': _opaqueState};

    testWidgetsLogged('sucesso: reenvia code/state sem alterar e confirma',
        (tester, logs) async {
      final h = _CallbackHarness();
      await tester.pumpWidget(h.screen(ok()));
      await tester.pumpAndSettle();

      expect(h.exchanges, [
        [_code, _opaqueState]
      ]);
      expect(find.text('Conexão concluída'), findsOneWidget);
      _expectNoSecretsVisible(tester, logs);
    });

    testWidgets('cancelado no Mercado Pago: não chama o backend',
        (tester) async {
      final h = _CallbackHarness();
      await tester.pumpWidget(h.screen({
        'error': 'access_denied',
        'error_description': 'Ligue para 0800 e informe o seu código',
        'state': _opaqueState,
      }));
      await tester.pumpAndSettle();

      expect(h.exchanges, isEmpty);
      expect(find.text('Conexão cancelada'), findsOneWidget);
      expect(
          find.textContaining('Nenhuma alteração foi feita'), findsOneWidget);
      expect(find.textContaining('0800'), findsNothing);
    });

    testWidgets('erro arbitrário do MP: texto da URL não é mostrado',
        (tester) async {
      final h = _CallbackHarness();
      await tester.pumpWidget(h.screen(
          {'error': 'server_error', 'error_description': 'texto injetado'}));
      await tester.pumpAndSettle();

      expect(h.exchanges, isEmpty);
      expect(find.text('Falha na conexão'), findsOneWidget);
      expect(find.textContaining('texto injetado'), findsNothing);
    });

    for (final c in const [
      [
        'state expirado',
        400,
        'State inválido ou expirado. Refaça a conexão pelo botão de pagamentos.'
      ],
      [
        'state inválido',
        400,
        'State inválido ou expirado. Refaça a conexão pelo botão de pagamentos.'
      ],
      [
        'state já consumido',
        400,
        'State inválido ou expirado. Refaça a conexão pelo botão de pagamentos.'
      ],
      [
        'state de outro utilizador',
        403,
        'State inválido ou expirado. Refaça a conexão pelo botão de pagamentos.'
      ],
      [
        'sem permissão na loja',
        403,
        'Sem permissão para conectar o Mercado Pago desta loja.'
      ],
      ['code reutilizado', 400, 'Código de autorização já utilizado.'],
    ]) {
      testWidgetsLogged('${c[0]} → mensagem do servidor, sem sucesso',
          (tester, logs) async {
        final h = _CallbackHarness(
            exchange: () async =>
                throw MpOAuthExchangeException(c[1] as int, c[2] as String));
        await tester.pumpWidget(h.screen(ok()));
        await tester.pumpAndSettle();

        expect(find.text('Falha na conexão'), findsOneWidget);
        expect(find.text(c[2] as String), findsOneWidget);
        expect(find.text('Conexão concluída'), findsNothing);
        _expectNoSecretsVisible(tester, logs);
      });
    }

    testWidgets('erro 5xx do backend → mensagem genérica', (tester) async {
      final h = _CallbackHarness(
          exchange: () async => throw const MpOAuthExchangeException(
              502, 'Falha de comunicação com o Mercado Pago.'));
      await tester.pumpWidget(h.screen(ok()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Falha de comunicação com o Mercado Pago'),
          findsOneWidget);
    });

    testWidgets('falha de rede → orienta conferir o status', (tester) async {
      final h = _CallbackHarness(
          exchange: () async => throw const MpOAuthExchangeException(
              null, 'Sem resposta do servidor.'));
      await tester.pumpWidget(h.screen(ok()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sem resposta do servidor'), findsOneWidget);
    });

    testWidgets('sem sessão: pede login e não troca o code', (tester) async {
      final h = _CallbackHarness(session: false);
      await tester.pumpWidget(h.screen(ok()));
      await tester.pumpAndSettle();

      expect(h.exchanges, isEmpty);
      expect(find.byType(MpOAuthSignInPanel), findsOneWidget);
    });

    testWidgets('sessão expirada no servidor (401) → volta ao login',
        (tester) async {
      final h = _CallbackHarness(
          exchange: () async => throw const MpOAuthExchangeException(
              401, 'Faça login para concluir a conexão.'));
      await tester.pumpWidget(h.screen(ok()));
      await tester.pumpAndSettle();

      expect(find.byType(MpOAuthSignInPanel), findsOneWidget);
      expect(find.textContaining('Sua sessão expirou'), findsOneWidget);
    });

    testWidgets('retorno repetido na mesma aba → não troca de novo',
        (tester) async {
      final h = _CallbackHarness(firstAttempt: false);
      await tester.pumpWidget(h.screen(ok()));
      await tester.pumpAndSettle();

      expect(h.exchanges, isEmpty);
      expect(find.textContaining('já foi processado'), findsOneWidget);
    });

    testWidgets('refresh (sem parâmetros) → nada a concluir', (tester) async {
      final h = _CallbackHarness();
      await tester.pumpWidget(h.screen(const {}));
      await tester.pumpAndSettle();

      expect(h.exchanges, isEmpty);
      expect(h.guardKeys, isEmpty);
      expect(find.text('Nada a concluir'), findsOneWidget);
    });

    testWidgets('retorno incompleto (sem state) → não troca', (tester) async {
      final h = _CallbackHarness();
      await tester.pumpWidget(h.screen(const {'code': _code}));
      await tester.pumpAndSettle();

      expect(h.exchanges, isEmpty);
      expect(find.textContaining('Retorno incompleto'), findsOneWidget);
    });

    testWidgets('login concluído duas vezes → uma única troca', (tester) async {
      final pending = Completer<void>();
      final h =
          _CallbackHarness(session: false, exchange: () => pending.future);
      await tester.pumpWidget(h.screen(ok()));
      await tester.pumpAndSettle();

      final panel =
          tester.widget<MpOAuthSignInPanel>(find.byType(MpOAuthSignInPanel));
      panel.onSignedIn();
      panel.onSignedIn();
      await tester.pump();
      expect(h.exchanges.length, 1);

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Conexão concluída'), findsOneWidget);
    });
  });

  group('PagamentosService.abrirConexaoOAuth', () {
    late Future<bool> Function(Uri) originalLauncher;

    setUp(() {
      originalLauncher = PagamentosService.oauthPageLauncher;
      PagamentosService.resetOAuthAberturaCooldown();
    });

    tearDown(() {
      PagamentosService.oauthPageLauncher = originalLauncher;
      PagamentosService.resetOAuthAberturaCooldown();
    });

    test(
        'abre /mp-oauth-start (não o /mp-oauth legado) e ignora clique repetido',
        () async {
      final opened = <Uri>[];
      PagamentosService.oauthPageLauncher = (u) async {
        opened.add(u);
        return true;
      };

      expect(await PagamentosService.abrirConexaoOAuth(_lojaA), isTrue);
      expect(await PagamentosService.abrirConexaoOAuth(_lojaA), isFalse);

      expect(opened, hasLength(1));
      final u = opened.single;
      expect(u.host, 'app.mastepalm.com.br');
      expect(u.path, '/mp-oauth-start');
      expect(u.queryParameters, {'lojaId': _lojaA});
    });

    test('falha ao abrir libera novo clique', () async {
      var calls = 0;
      PagamentosService.oauthPageLauncher = (u) async {
        calls++;
        if (calls == 1) throw StateError('launcher indisponível');
        return true;
      };

      await expectLater(
          PagamentosService.abrirConexaoOAuth(_lojaA), throwsStateError);
      expect(await PagamentosService.abrirConexaoOAuth(_lojaA), isTrue);
      expect(calls, 2);
    });
  });

  group('layout mobile', () {
    const sizes = [
      Size(320, 568),
      Size(360, 640),
      Size(390, 844),
      Size(412, 915),
    ];

    Future<void> pumpAt(WidgetTester tester, Size size, Widget w) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(w);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow em $size');
    }

    for (final size in sizes) {
      testWidgets(
          'start: login, erro e redirect sem overflow em ${size.width.toInt()}px',
          (tester) async {
        await pumpAt(
            tester, size, _StartHarness(session: false).screen(_startUri()));
        await pumpAt(
            tester,
            size,
            _StartHarness(
                createAuthUrl: (_) async =>
                    throw _fnError('permission-denied')).screen(_startUri(
                'loja-com-um-identificador-bem-comprido-para-testar')));
        await pumpAt(tester, size, _StartHarness().screen(_startUri()));
      });

      testWidgets(
          'callback: login, sucesso, cancelado e erro sem overflow em ${size.width.toInt()}px',
          (tester) async {
        final p = {'code': _code, 'state': _opaqueState};
        await pumpAt(tester, size, _CallbackHarness(session: false).screen(p));
        await pumpAt(tester, size, _CallbackHarness().screen(p));
        await pumpAt(tester, size,
            _CallbackHarness().screen(const {'error': 'access_denied'}));
        await pumpAt(
            tester,
            size,
            _CallbackHarness(
                    exchange: () async => throw const MpOAuthExchangeException(
                        403,
                        'Sem permissão para conectar o Mercado Pago desta loja.'))
                .screen(p));
      });
    }
  });
}
