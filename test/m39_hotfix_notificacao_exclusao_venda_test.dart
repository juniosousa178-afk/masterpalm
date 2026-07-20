// M3.9 HOTFIX — notificação de exclusão de venda (NOTIFICACAO-1..7)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/notificacao_vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    NotificacaoVendasService.debugFirestoreOverride = db;
    NotificacaoVendasService.exclusaoBadgeTick.value = 0;
    await NotificacaoVendasService.clearEspelhoExclusaoForTest(
      storeId: 'loja-x',
      uid: 'v1',
    );
    await NotificacaoVendasService.clearEspelhoExclusaoForTest(
      storeId: 'loja-x',
      uid: 'v2',
    );
  });

  tearDown(() {
    NotificacaoVendasService.debugFirestoreOverride = null;
  });

  group('NOTIFICACAO exclusão venda', () {
    test('NOTIFICACAO-1 cria exatamente 1 documento', () async {
      final svc = NotificacaoVendasService();
      final ok = await svc.notificarVendedorVendaCancelada(
        storeId: 'loja-x',
        vendedorUid: 'v1',
        vendedorEmail: 'v1@t.com',
        pedidoId: 'venda-abc',
        clienteNome: 'Cliente',
        motivo: 'Erro de preço',
        tipoAcao: 'excluida',
        adminUid: 'admin-1',
      );
      expect(ok, isTrue);

      final snap = await db
          .collection('lojas')
          .doc('loja-x')
          .collection('notificacoes')
          .get();
      expect(snap.docs.length, 1);
      expect(snap.docs.first.id.startsWith('vx_'), isTrue);
    });

    test('NOTIFICACAO-2 documento contém campos obrigatórios', () async {
      final svc = NotificacaoVendasService();
      await svc.notificarVendedorVendaCancelada(
        storeId: 'loja-x',
        vendedorUid: 'v1',
        vendedorEmail: 'v1@t.com',
        pedidoId: 'venda-abc',
        clienteNome: 'Cliente',
        motivo: 'Duplicada',
        tipoAcao: 'excluida',
        adminUid: 'admin-1',
      );
      final docs = await db
          .collection('lojas')
          .doc('loja-x')
          .collection('notificacoes')
          .get();
      final data = docs.docs.single.data();
      expect(data['storeId'], 'loja-x');
      expect(data['destinatarioUid'], 'v1');
      expect(data['pedidoId'], 'venda-abc');
      expect(data['tipo'], 'vendaCancelada');
      expect((data['dados'] as Map)['motivo'], 'Duplicada');
      expect((data['dados'] as Map)['tipoAcao'], 'excluida');
      expect((data['dados'] as Map)['adminUid'], 'admin-1');
      expect(data['criadaEm'], isNotNull);
    });

    test('NOTIFICACAO-3 tela (getUltimas) mostra exatamente um registro', () async {
      final svc = NotificacaoVendasService();
      await svc.notificarVendedorVendaCancelada(
        storeId: 'loja-x',
        vendedorUid: 'v1',
        vendedorEmail: 'v1@t.com',
        pedidoId: 'venda-tela',
        clienteNome: 'C',
        motivo: 'M',
      );
      final list = await svc.getUltimasNotificacoes('v1', 'loja-x');
      final canceladas =
          list.where((n) => n.tipo == TipoNotificacao.vendaCancelada).toList();
      expect(canceladas.length, 1);
      expect(canceladas.first.pedidoId, 'venda-tela');
    });

    test('NOTIFICACAO-4 badge aumenta', () async {
      final before = NotificacaoVendasService.exclusaoBadgeTick.value;
      await NotificacaoVendasService().notificarVendedorVendaCancelada(
        storeId: 'loja-x',
        vendedorUid: 'v1',
        vendedorEmail: 'v1@t.com',
        pedidoId: 'venda-badge',
        clienteNome: 'C',
      );
      expect(
        NotificacaoVendasService.exclusaoBadgeTick.value,
        before + 1,
      );
      final unread =
          await NotificacaoVendasService().contarNaoLidas('v1', 'loja-x');
      expect(unread, greaterThanOrEqualTo(1));
    });

    test('NOTIFICACAO-5 Ctrl+F5 — espelho local persiste', () async {
      final svc = NotificacaoVendasService();
      await svc.notificarVendedorVendaCancelada(
        storeId: 'loja-x',
        vendedorUid: 'v1',
        vendedorEmail: 'v1@t.com',
        pedidoId: 'venda-persist',
        clienteNome: 'C',
        motivo: 'X',
      );
      // Simula nova sessão: novo service + Firestore vazio, prefs mantidas.
      NotificacaoVendasService.debugFirestoreOverride = FakeFirebaseFirestore();
      final list = await NotificacaoVendasService()
          .getUltimasNotificacoes('v1', 'loja-x');
      final hit = list.where((n) => n.pedidoId == 'venda-persist').toList();
      expect(hit.length, 1);
      expect(hit.first.dados?['motivo'], 'X');
    });

    test('NOTIFICACAO-6 retry não duplica', () async {
      final svc = NotificacaoVendasService();
      final tick0 = NotificacaoVendasService.exclusaoBadgeTick.value;
      await svc.notificarVendedorVendaCancelada(
        storeId: 'loja-x',
        vendedorUid: 'v1',
        vendedorEmail: 'v1@t.com',
        pedidoId: 'venda-retry',
        clienteNome: 'C',
      );
      await svc.notificarVendedorVendaCancelada(
        storeId: 'loja-x',
        vendedorUid: 'v1',
        vendedorEmail: 'v1@t.com',
        pedidoId: 'venda-retry',
        clienteNome: 'C',
      );
      final snap = await db
          .collection('lojas')
          .doc('loja-x')
          .collection('notificacoes')
          .get();
      expect(snap.docs.length, 1);
      final list = await svc.getUltimasNotificacoes('v1', 'loja-x');
      expect(
        list.where((n) => n.pedidoId == 'venda-retry').length,
        1,
      );
      // Badge pode incrementar 2× (2 chamadas OK), mas documento único.
      expect(
        NotificacaoVendasService.exclusaoBadgeTick.value,
        greaterThanOrEqualTo(tick0 + 1),
      );
    });

    test('NOTIFICACAO-7 outro vendedor não recebe', () async {
      final svc = NotificacaoVendasService();
      await svc.notificarVendedorVendaCancelada(
        storeId: 'loja-x',
        vendedorUid: 'v1',
        vendedorEmail: 'v1@t.com',
        pedidoId: 'venda-iso',
        clienteNome: 'C',
        motivo: 'Só v1',
      );
      final v1 = await svc.getUltimasNotificacoes('v1', 'loja-x');
      final v2 = await svc.getUltimasNotificacoes('v2', 'loja-x');
      expect(v1.where((n) => n.pedidoId == 'venda-iso').length, 1);
      expect(v2.where((n) => n.pedidoId == 'venda-iso').length, 0);
    });
  });
}
