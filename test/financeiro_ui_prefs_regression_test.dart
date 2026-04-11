// Regressão: filtros escopados usuário+loja; mês não é persistido neste serviço.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/services/financeiro_ui_prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FinanceiroUiPrefsService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('prefs diferentes por userKey na mesma loja', () async {
      await FinanceiroUiPrefsService.save(
        visaoCompetencia: true,
        filtroStatus: FinanceiroStatusLancamento.pago,
        lojaId: 'loja-x',
        userKey: 'fb_user_a',
      );
      await FinanceiroUiPrefsService.save(
        visaoCompetencia: false,
        filtroStatus: null,
        lojaId: 'loja-x',
        userKey: 'fb_user_b',
      );

      final a = await FinanceiroUiPrefsService.load(
        lojaId: 'loja-x',
        userKey: 'fb_user_a',
      );
      final b = await FinanceiroUiPrefsService.load(
        lojaId: 'loja-x',
        userKey: 'fb_user_b',
      );

      expect(a.visaoCompetencia, isTrue);
      expect(a.filtroStatus, FinanceiroStatusLancamento.pago);
      expect(b.visaoCompetencia, isFalse);
      expect(b.filtroStatus, isNull);
    });

    test('valor de status inválido no storage vira null ao carregar', () async {
      await FinanceiroUiPrefsService.save(
        visaoCompetencia: false,
        filtroStatus: FinanceiroStatusLancamento.pendente,
        lojaId: 'loja-x',
        userKey: 'fb_u1',
      );
      final p = await SharedPreferences.getInstance();
      await p.setString(
        'fin_ui_v2_fb_u1_loja-xstatus',
        'invalid_status_xyz',
      );

      final d = await FinanceiroUiPrefsService.load(
        lojaId: 'loja-x',
        userKey: 'fb_u1',
      );
      expect(d.filtroStatus, isNull);
    });

    test('lojaId vazio não persiste (prefix null)', () async {
      await FinanceiroUiPrefsService.save(
        visaoCompetencia: true,
        lojaId: '',
        userKey: 'fb_u',
      );
      final d = await FinanceiroUiPrefsService.load(lojaId: '', userKey: 'fb_u');
      expect(d.visaoCompetencia, isFalse);
    });
  });
}
