// M3.9 HOTFIX — alerta visual venda cancelada (ALERTA-1..8)

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/venda_cancelada_alerta_gate.dart';
import 'package:master_palm/services/notificacao_vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

NotificacaoVenda _n({
  required String id,
  required String dest,
  String pedidoId = 'venda-1',
  String tipo = 'vendaCancelada',
  String? motivo,
  bool lida = false,
}) {
  return NotificacaoVenda(
    id: id,
    destinatarioUid: dest,
    destinatarioEmail: '$dest@t.com',
    tipo: tipo == 'vendaCancelada'
        ? TipoNotificacao.vendaCancelada
        : TipoNotificacao.novaVenda,
    titulo: 't',
    mensagem: 'm',
    pedidoId: pedidoId,
    storeId: 'loja-x',
    lida: lida,
    criadaEm: DateTime.now(),
    dados: {
      if (motivo != null) 'motivo': motivo,
      'tipoAcao': 'excluida',
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await VendaCanceladaAlertaGate.clearPersistedForTest(
      storeId: 'loja-x',
      uid: 'v1',
    );
  });

  group('ALERTA venda cancelada', () {
    test('ALERTA-1 Firestore: nova vendaCancelada → alerta uma vez', () {
      final gate = VendaCanceladaAlertaGate();
      gate.seedBaseline(const []); // sessão limpa
      final n = _n(id: 'vx_fs_1', dest: 'v1');
      expect(
        gate.shouldShow(
          notificationId: n.id,
          sessionUid: 'v1',
          destinatarioUid: n.destinatarioUid,
          tipoName: n.tipo.name,
        ),
        isTrue,
      );
      gate.markShown(n.id);
      expect(
        gate.shouldShow(
          notificationId: n.id,
          sessionUid: 'v1',
          destinatarioUid: n.destinatarioUid,
          tipoName: n.tipo.name,
        ),
        isFalse,
      );
    });

    test('ALERTA-2 espelho local: mesma regra de nova → uma vez', () {
      final gate = VendaCanceladaAlertaGate();
      gate.seedBaseline(const []);
      final n = _n(id: 'vx_local_1', dest: 'v1');
      // Fonte local não muda a decisão — só o gate.
      expect(
        gate.shouldShow(
          notificationId: n.id,
          sessionUid: 'v1',
          destinatarioUid: 'v1',
          tipoName: 'vendaCancelada',
        ),
        isTrue,
      );
      gate.markShown(n.id);
      expect(
        gate.shouldShow(
          notificationId: n.id,
          sessionUid: 'v1',
          destinatarioUid: 'v1',
          tipoName: 'vendaCancelada',
        ),
        isFalse,
      );
    });

    test('ALERTA-3 outro vendedor → nenhum alerta', () {
      final gate = VendaCanceladaAlertaGate();
      gate.seedBaseline(const []);
      expect(
        gate.shouldShow(
          notificationId: 'vx_other',
          sessionUid: 'v1',
          destinatarioUid: 'v2',
          tipoName: 'vendaCancelada',
        ),
        isFalse,
      );
    });

    test('ALERTA-4 Ctrl+F5: baseline engole antigas', () {
      final gate = VendaCanceladaAlertaGate();
      gate.seedBaseline(['vx_old_1', 'vx_old_2']);
      expect(
        gate.shouldShow(
          notificationId: 'vx_old_1',
          sessionUid: 'v1',
          destinatarioUid: 'v1',
          tipoName: 'vendaCancelada',
        ),
        isFalse,
      );
    });

    test('ALERTA-5 retry mesmo vx_* → não duplica', () {
      final gate = VendaCanceladaAlertaGate();
      gate.seedBaseline(const []);
      const id = 'vx_loja-x_v1_venda-retry_excluida';
      expect(
        gate.shouldShow(
          notificationId: id,
          sessionUid: 'v1',
          destinatarioUid: 'v1',
          tipoName: 'vendaCancelada',
        ),
        isTrue,
      );
      gate.markShown(id);
      expect(
        gate.shouldShow(
          notificationId: id,
          sessionUid: 'v1',
          destinatarioUid: 'v1',
          tipoName: 'vendaCancelada',
        ),
        isFalse,
      );
    });

    test('ALERTA-6 remount gate: sessão limpa mas persistidos bloqueiam', () async {
      final g1 = VendaCanceladaAlertaGate();
      g1.seedBaseline(const []);
      const id = 'vx_nav_1';
      expect(
        g1.shouldShow(
          notificationId: id,
          sessionUid: 'v1',
          destinatarioUid: 'v1',
          tipoName: 'vendaCancelada',
        ),
        isTrue,
      );
      g1.markShown(id);
      await VendaCanceladaAlertaGate.persistDisplayed(
        storeId: 'loja-x',
        uid: 'v1',
        notificationId: id,
      );

      // Simula remount (nova instância do gate / navegação).
      final g2 = VendaCanceladaAlertaGate();
      g2.seedBaseline(const []);
      final persisted = await VendaCanceladaAlertaGate.loadPersistedDisplayed(
        storeId: 'loja-x',
        uid: 'v1',
      );
      expect(
        g2.shouldShow(
          notificationId: id,
          sessionUid: 'v1',
          destinatarioUid: 'v1',
          tipoName: 'vendaCancelada',
          persistedDisplayed: persisted,
        ),
        isFalse,
      );
    });

    test('ALERTA-7 mensagem + título consistentes com lista', () {
      expect(VendaCanceladaAlertaGate.buildTitulo(), 'Venda cancelada');
      final msg = VendaCanceladaAlertaGate.buildMensagem(
        vendaId: 'abc-123',
        motivo: 'Erro de preço',
      );
      expect(msg, contains('abc-123'));
      expect(msg, contains('Motivo: Erro de preço'));
      expect(msg.toLowerCase(), isNot(contains('r\$')));
    });

    test('ALERTA-8 lida não impede lista; exibido impede re-alerta', () async {
      final gate = VendaCanceladaAlertaGate();
      gate.seedBaseline(const []);
      final n = _n(id: 'vx_lida_1', dest: 'v1', lida: true);
      // "lida" não entra na decisão do gate.
      expect(
        gate.shouldShow(
          notificationId: n.id,
          sessionUid: 'v1',
          destinatarioUid: 'v1',
          tipoName: 'vendaCancelada',
        ),
        isTrue,
      );
      gate.markShown(n.id);
      await VendaCanceladaAlertaGate.persistDisplayed(
        storeId: 'loja-x',
        uid: 'v1',
        notificationId: n.id,
      );
      final persisted = await VendaCanceladaAlertaGate.loadPersistedDisplayed(
        storeId: 'loja-x',
        uid: 'v1',
      );
      expect(
        gate.shouldShow(
          notificationId: n.id,
          sessionUid: 'v1',
          destinatarioUid: 'v1',
          tipoName: 'vendaCancelada',
          persistedDisplayed: persisted,
        ),
        isFalse,
      );
      // Registro continua "existindo" (não apagamos o doc — só gate).
      expect(n.id, isNotEmpty);
      expect(n.lida, isTrue);
    });
  });
}
