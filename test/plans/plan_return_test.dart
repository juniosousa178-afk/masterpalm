import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/app_routes.dart' as app_routes;
import 'package:master_palm/catalog/public_order_link.dart';
import 'package:master_palm/core/master_plan_access_models.dart';
import 'package:master_palm/features/plans/plan_return_link.dart';
import 'package:master_palm/features/plans/plan_return_screen.dart';
import 'package:master_palm/features/plans/plan_return_web_app.dart';
import 'package:master_palm/services/checkout_service.dart';
import 'package:master_palm/services/planos_service.dart';

const _mpApprovedQuery = 'collection_id=123&collection_status=approved'
    '&payment_id=123&status=approved&external_reference=po_abc'
    '&payment_type=credit_card&merchant_order_id=9&preference_id=1-2'
    '&site_id=MLB&processing_mode=aggregator&merchant_account_id=null';

const _oneTimePath = '/assinatura/intermediate_monthly/retorno';
const _recurringPath = '/planos/retorno';
const _changePath = '/assinatura/troca/chg_A1-b2/retorno';

EffectivePlanAccessDto _access({
  String? contracted,
  String accessSource = 'paid_subscription',
  String status = 'active',
  String? maskedSubscriptionId,
}) {
  return EffectivePlanAccessDto.fromMap({
    'contractedPlanId': contracted,
    'effectivePlanId': contracted,
    'accessSource': accessSource,
    'effectiveStatus': status,
    if (maskedSubscriptionId != null)
      'subscription': {'maskedProviderSubscriptionId': maskedSubscriptionId},
  });
}

PlanInfo _plan({String? pendingTo, String? pendingStatus}) => PlanInfo(
      planId: 'pro_monthly',
      status: 'active',
      trialing: false,
      currentPeriodEnd: DateTime.now().add(const Duration(days: 20)),
      trialUsed: true,
      manualOverride: false,
      pendingPlanChangeToPlanId: pendingTo,
      pendingPlanChangeStatus: pendingStatus,
    );

class _LoaderSpy {
  _LoaderSpy(this.result);
  PlanReturnStatus result;
  final calls = <PlanReturnRef>[];

  Future<PlanReturnStatus> call(PlanReturnRef ref) async {
    calls.add(ref);
    return result;
  }
}

List<String> _captureAnnouncedUrls(WidgetTester tester) {
  final announced = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
    if (call.method == 'routeInformationUpdated') {
      announced.add((call.arguments as Map)['uri'].toString());
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.navigation, null));
  return announced;
}

Future<void> _pumpWebApp(
  WidgetTester tester,
  String pathAndQuery, {
  PlanReturnStatusLoader? loader,
}) async {
  final uri = Uri.parse('https://app.mastepalm.com.br$pathAndQuery');
  await tester.pumpWidget(PlanReturnWebApp(
    key: UniqueKey(),
    ref: PlanReturnLink.parse(uri),
    routeName: PlanReturnLink.routeName(uri),
    loader: loader ??
        _LoaderSpy(const PlanReturnStatus(PlanReturnState.awaitingConfirmation))
            .call,
    onOpenApp: (_) {},
    autoRefreshInterval: null,
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('PlanReturnLink — rotas', () {
    test('reconhece os três formatos de retorno', () {
      expect(PlanReturnLink.parse(Uri.parse(_oneTimePath)),
          const PlanReturnRef(
              kind: PlanReturnKind.oneTime, planId: 'intermediate_monthly'));
      expect(PlanReturnLink.parse(Uri.parse(_recurringPath)),
          const PlanReturnRef(kind: PlanReturnKind.recurring));
      expect(PlanReturnLink.parse(Uri.parse(_changePath)),
          const PlanReturnRef(
              kind: PlanReturnKind.planChange, changeId: 'chg_A1-b2'));
      expect(PlanReturnLink.parse(Uri.parse('/planos/retorno/')),
          const PlanReturnRef(kind: PlanReturnKind.recurring));
    });

    test('prioridade: `?loja=` / `?slug=` não desviam o retorno para o catálogo',
        () {
      for (final q in ['loja=nathy', 'slug=x', 'store_id=y']) {
        final uri = Uri.parse('https://app.mastepalm.com.br$_recurringPath?$q');
        expect(PlanReturnLink.isPlanReturnPath(uri), isTrue, reason: q);
        expect(PublicOrderLink.isPublicOrderPath(uri), isFalse, reason: q);
      }
    });

    test('paths que não são retorno de plano', () {
      for (final p in [
        '/',
        '/planos',
        '/planos/retorno/x',
        '/assinatura',
        '/assinatura/pro_monthly',
        '/assinatura/pro_monthly/retorno/x',
        '/assinatura/troca/a/b/retorno',
        '/loja/assinatura',
        '/pedido/abc',
        '/pagamento/sucesso',
      ]) {
        expect(PlanReturnLink.isPlanReturnPath(Uri.parse(p)), isFalse,
            reason: p);
        expect(PlanReturnLink.parse(Uri.parse(p)), isNull, reason: p);
      }
    });

    test('I. plano/troca malformados viram referência inválida (sem exceção)',
        () {
      for (final p in [
        '/assinatura/PRO_MONTHLY/retorno',
        '/assinatura/pro%2Fmonthly/retorno',
        '/assinatura/%3Cscript%3E/retorno',
        '/assinatura/pro%20monthly/retorno',
        '/assinatura/..%2F..%2Fadmin/retorno',
        '/assinatura/${'x' * 65}/retorno',
        '/assinatura/troca/retorno',
        '/assinatura/troca/a%2Fb/retorno',
        '/assinatura/troca/${'c' * 129}/retorno',
      ]) {
        final ref = PlanReturnLink.parse(Uri.parse(p));
        expect(ref, isNotNull, reason: p);
        expect(ref!.isValid, isFalse, reason: p);
      }
    });

    test('routeName preserva path e a query devolvida pelo Mercado Pago', () {
      final uri = Uri.parse(
          'https://app.mastepalm.com.br$_oneTimePath?$_mpApprovedQuery');
      expect(PlanReturnLink.routeName(uri), '$_oneTimePath?$_mpApprovedQuery');
      expect(PlanReturnLink.routeName(Uri.parse(
              'https://app.mastepalm.com.br$_recurringPath?preapproval_id=2c9')),
          '$_recurringPath?preapproval_id=2c9');
      expect(
          PlanReturnLink.parse(uri),
          const PlanReturnRef(
              kind: PlanReturnKind.oneTime, planId: 'intermediate_monthly'));
    });
  });

  group('returnUrl explícito do checkout avulso', () {
    test('G/H. payload de planCreatePreferenceCall envia returnUrl no app canônico',
        () {
      final payload = planCreatePreferencePayload(
        plan: 'intermediate_monthly',
        canonicalPlanId: 'intermediate_monthly',
        installationId: 'inst-1',
      );
      expect(payload['plan'], 'intermediate_monthly');
      expect(payload['installationId'], 'inst-1');
      expect(payload['returnUrl'],
          'https://app.mastepalm.com.br/assinatura/intermediate_monthly/retorno');
      final url = Uri.parse(payload['returnUrl'] as String);
      expect(url.origin, 'https://app.mastepalm.com.br');
      expect(url.hasQuery, isFalse);
      expect(PlanReturnLink.parse(url)!.isValid, isTrue);
    });

    test('H. aliases legados (mensal/anual) usam o id canônico no retorno', () {
      final mensal = planCreatePreferencePayload(
          plan: 'mensal', canonicalPlanId: 'pro_monthly', installationId: '');
      expect(mensal['plan'], 'mensal');
      expect(mensal['returnUrl'],
          'https://app.mastepalm.com.br/assinatura/pro_monthly/retorno');
      expect(mensal.containsKey('installationId'), isFalse);
    });

    test('encoding: ids com hífen/underscore são aceitos; o resto é rejeitado',
        () {
      expect(
          PlanReturnLink.buildOneTimeReturnUrl(planId: 'pro-monthly_2')
              .toString(),
          'https://app.mastepalm.com.br/assinatura/pro-monthly_2/retorno');
      for (final bad in [
        '',
        ' ',
        'Pro',
        'a/b',
        'a b',
        '../x',
        'a?b',
        'a#b',
        'https://evil.com',
        'x' * 65,
      ]) {
        expect(() => PlanReturnLink.buildOneTimeReturnUrl(planId: bad),
            throwsArgumentError,
            reason: bad);
      }
    });

    test('nunca usa o domínio apex do site de marketing', () {
      for (final id in [
        'basic_monthly',
        'intermediate_monthly',
        'pro_monthly',
        'pro_yearly'
      ]) {
        final url = PlanReturnLink.buildOneTimeReturnUrl(planId: id);
        expect(url.host, 'app.mastepalm.com.br');
        expect(url.scheme, 'https');
      }
    });
  });

  group('evaluatePlanReturn — webhook/backend é a autoridade', () {
    const oneTime = PlanReturnRef(
        kind: PlanReturnKind.oneTime, planId: 'intermediate_monthly');
    const recurring = PlanReturnRef(kind: PlanReturnKind.recurring);
    const change =
        PlanReturnRef(kind: PlanReturnKind.planChange, changeId: 'chg1');

    test('sem resposta do servidor: indisponível (nunca confirma)', () {
      expect(evaluatePlanReturn(ref: oneTime, access: null).state,
          PlanReturnState.unavailable);
    });

    test('F. plano ainda não ativado pelo webhook: aguardando confirmação', () {
      for (final a in [
        _access(contracted: 'free_limited', accessSource: 'free_limited',
            status: 'free_limited'),
        _access(contracted: 'free_trial_30d', accessSource: 'trial'),
        _access(contracted: 'intermediate_monthly', status: 'expired'),
        _access(contracted: 'basic_monthly'),
      ]) {
        expect(evaluatePlanReturn(ref: oneTime, access: a).state,
            PlanReturnState.awaitingConfirmation);
      }
    });

    test('avulso confirmado só com o plano pago ativo no servidor', () {
      final s = evaluatePlanReturn(
          ref: oneTime, access: _access(contracted: 'intermediate_monthly'));
      expect(s.state, PlanReturnState.confirmed);
      expect(s.planLabel, 'Intermediário');
      expect(
          evaluatePlanReturn(
                  ref: const PlanReturnRef(
                      kind: PlanReturnKind.oneTime, planId: 'mensal'),
                  access: _access(contracted: 'pro_monthly'))
              .state,
          PlanReturnState.confirmed);
    });

    test('recorrente exige assinatura MP registrada pelo backend', () {
      expect(
          evaluatePlanReturn(
                  ref: recurring, access: _access(contracted: 'pro_monthly'))
              .state,
          PlanReturnState.awaitingConfirmation);
      expect(
          evaluatePlanReturn(
                  ref: recurring,
                  access: _access(
                      contracted: 'pro_monthly',
                      maskedSubscriptionId: '2c9***abc'))
              .state,
          PlanReturnState.confirmed);
    });

    test('troca de plano pendente continua aguardando', () {
      final active = _access(contracted: 'pro_monthly');
      expect(evaluatePlanReturn(ref: change, access: active).state,
          PlanReturnState.awaitingConfirmation);
      expect(
          evaluatePlanReturn(
                  ref: change,
                  access: active,
                  plan: _plan(pendingTo: 'pro_yearly', pendingStatus: 'pending'))
              .state,
          PlanReturnState.awaitingConfirmation);
      expect(
          evaluatePlanReturn(ref: change, access: active, plan: _plan()).state,
          PlanReturnState.confirmed);
    });
  });

  group('PlanReturnWebApp — URL preservada', () {
    for (final entry in {
      'A. /assinatura/<plano>/retorno': '$_oneTimePath?$_mpApprovedQuery',
      'C. /planos/retorno': '$_recurringPath?preapproval_id=2c93808',
      'E. /assinatura/troca/<id>/retorno': _changePath,
    }.entries) {
      testWidgets('${entry.key}: abertura direta mantém a URL real',
          (tester) async {
        final announced = _captureAnnouncedUrls(tester);
        await _pumpWebApp(tester, entry.value);
        expect(find.byType(PlanReturnScreen), findsOneWidget);
        expect(find.byKey(const Key('plan-return-awaiting')), findsOneWidget);
        expect(announced, isNotEmpty);
        expect(announced.last, entry.value);
        expect(announced, isNot(contains('/')));
      });
    }

    for (final entry in {
      'B. /assinatura/<plano>/retorno': '$_oneTimePath?$_mpApprovedQuery',
      'D. /planos/retorno': _recurringPath,
      'E. /assinatura/troca/<id>/retorno': _changePath,
    }.entries) {
      testWidgets('${entry.key}: refresh (nova instância) mantém a URL',
          (tester) async {
        final announced = _captureAnnouncedUrls(tester);
        await _pumpWebApp(tester, entry.value);
        announced.clear();
        await _pumpWebApp(tester, entry.value);
        expect(find.byType(PlanReturnScreen), findsOneWidget);
        expect(announced, isNotEmpty);
        expect(announced.last, entry.value);
        expect(announced, isNot(contains('/')));
      });
    }

    testWidgets('voltar/avançar do browser reabre a mesma rota', (tester) async {
      final announced = _captureAnnouncedUrls(tester);
      await _pumpWebApp(tester, _recurringPath);
      await tester.binding.handlePushRoute('$_recurringPath?preapproval_id=9');
      await tester.pumpAndSettle();
      expect(find.byType(PlanReturnScreen), findsWidgets);
      expect(announced.last, '$_recurringPath?preapproval_id=9');
      expect(announced, isNot(contains('/')));
    });
  });

  group('PlanReturnScreen — estados', () {
    Future<_LoaderSpy> pumpScreen(
      WidgetTester tester, {
      required PlanReturnRef? ref,
      required PlanReturnStatus result,
    }) async {
      final spy = _LoaderSpy(result);
      await tester.pumpWidget(MaterialApp(
        home: PlanReturnScreen(
          ref: ref,
          loader: spy.call,
          onOpenApp: (_) {},
          autoRefreshInterval: null,
        ),
      ));
      await tester.pumpAndSettle();
      return spy;
    }

    testWidgets(
        'F. query "approved" do Mercado Pago não confirma pagamento: estado vem do loader',
        (tester) async {
      final uri = Uri.parse(
          'https://app.mastepalm.com.br$_oneTimePath?$_mpApprovedQuery');
      final spy = await pumpScreen(tester,
          ref: PlanReturnLink.parse(uri),
          result:
              const PlanReturnStatus(PlanReturnState.awaitingConfirmation));
      expect(spy.calls, [
        const PlanReturnRef(
            kind: PlanReturnKind.oneTime, planId: 'intermediate_monthly')
      ]);
      expect(find.byKey(const Key('plan-return-awaiting')), findsOneWidget);
      expect(find.textContaining('ativa'), findsNothing);
      expect(find.textContaining('confirmado'), findsNothing);
      expect(find.textContaining('aprovado'), findsNothing);
    });

    testWidgets('confirmado mostra apenas o nome do plano', (tester) async {
      await pumpScreen(tester,
          ref: const PlanReturnRef(kind: PlanReturnKind.recurring),
          result: const PlanReturnStatus(PlanReturnState.confirmed,
              planLabel: 'Pro mensal'));
      expect(find.text('Sua assinatura está ativa'), findsOneWidget);
      expect(find.text('Plano atual: Pro mensal.'), findsOneWidget);
    });

    testWidgets('aguardando permite atualizar e relê o servidor',
        (tester) async {
      final spy = await pumpScreen(tester,
          ref: const PlanReturnRef(kind: PlanReturnKind.recurring),
          result:
              const PlanReturnStatus(PlanReturnState.awaitingConfirmation));
      expect(spy.calls, hasLength(1));
      spy.result = const PlanReturnStatus(PlanReturnState.confirmed,
          planLabel: 'Pro mensal');
      await tester.tap(find.text('Atualizar'));
      await tester.pumpAndSettle();
      expect(spy.calls, hasLength(2));
      expect(find.byKey(const Key('plan-return-confirmed')), findsOneWidget);
    });

    testWidgets('releitura automática enquanto o webhook não chega',
        (tester) async {
      final spy = _LoaderSpy(
          const PlanReturnStatus(PlanReturnState.awaitingConfirmation));
      await tester.pumpWidget(MaterialApp(
        home: PlanReturnScreen(
          ref: const PlanReturnRef(kind: PlanReturnKind.recurring),
          loader: spy.call,
          onOpenApp: (_) {},
          autoRefreshInterval: const Duration(seconds: 5),
          maxAutoRefreshes: 2,
        ),
      ));
      await tester.pump();
      expect(spy.calls, hasLength(1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(spy.calls, hasLength(3));
    });

    testWidgets('falha do loader vira estado indisponível com nova tentativa',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PlanReturnScreen(
          ref: const PlanReturnRef(kind: PlanReturnKind.recurring),
          loader: (_) async => throw Exception('rede'),
          onOpenApp: (_) {},
          autoRefreshInterval: null,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan-return-unavailable')), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('I. plano malformado: aviso de link inválido, sem consultar conta',
        (tester) async {
      final spy = await pumpScreen(tester,
          ref: PlanReturnLink.parse(
              Uri.parse('/assinatura/%3Cscript%3E/retorno')),
          result: const PlanReturnStatus(PlanReturnState.confirmed,
              planLabel: 'Pro mensal'));
      expect(spy.calls, isEmpty);
      expect(find.byKey(const Key('plan-return-invalid')), findsOneWidget);
      expect(find.textContaining('<script>'), findsNothing);
    });

    testWidgets('J. sem login: página genérica, sem dados de assinatura',
        (tester) async {
      await pumpScreen(tester,
          ref: const PlanReturnRef(kind: PlanReturnKind.recurring),
          result: const PlanReturnStatus(PlanReturnState.signedOut));
      expect(find.byKey(const Key('plan-return-signed-out')), findsOneWidget);
      expect(find.text('Entrar no MasterPalm'), findsOneWidget);
      expect(find.textContaining('Plano atual'), findsNothing);
      expect(find.textContaining('ativa'), findsNothing);
      expect(find.textContaining('@'), findsNothing);
    });
  });

  group('app_routes — prioridade sobre rotas genéricas', () {
    test('onGenerateRoute resolve os retornos de plano mantendo o nome', () {
      for (final name in [
        '$_oneTimePath?$_mpApprovedQuery',
        '$_recurringPath?loja=nathy',
        _changePath,
      ]) {
        final route =
            app_routes.onGenerateRoute(RouteSettings(name: name));
        expect(route, isA<MaterialPageRoute>(), reason: name);
        expect(route!.settings.name, name);
      }
    });
  });
}
