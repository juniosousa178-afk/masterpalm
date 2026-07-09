// M3.7-HOMOLOG-CAMPANHA-TYPEERROR — mapas Firestore web no confirm admin.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/firestore_dynamic_map.dart';
import 'package:master_palm/services/campaign_engine_service.dart';
import 'package:master_palm/services/pre_pedido_confirmacao_eligibility.dart';

const _lojaId = 'loja-camp-typeerror';
const _campDocId = 'campanha-borboleta-ativa';

/// Payload Lara + Conjunto Borboleta Cristal (45cm / cristal / pagamento pendente).
Map<String, Object?> _prePedidoLaraWebLike() => <String, Object?>{
      'id': 'pre-pedido-lara-borboleta',
      'status': 'pendente',
      'pagamento': 'PIX',
      'statusPagamento': 'pendente',
      'total': 151.91,
      'subtotal': 151.91,
      'cliente': <String, Object?>{
        'nome': 'Lara',
        'email': 'lara@test.com',
        'telefone': '11999998888',
        'endereco': <String, Object?>{
          'rua': 'Rua Teste',
          'numero': '10',
          'cidade': 'São Paulo',
        },
      },
      'frete': <String, Object?>{
        'nome': 'Entrega',
        'valor': 0.0,
        'gratis': true,
      },
      'itens': <Object?>[
        <String, Object?>{
          'nome': 'Conjunto Borboleta Cristal',
          'quantidade': 1,
          'precoUnitario': 151.91,
          'tamanho': '45cm',
          'cor': 'cristal',
          'productId': 'prod-borboleta-cristal',
        },
      ],
      'premioRoleta': <String, Object?>{
        'codigo': 'ROLETA10',
        'valor': 10.0,
        'tipo': 'desconto',
        'descricao': '10% desconto',
        'status': 'pendente',
      },
    };

Future<void> _seedCampanhaAtiva(
  FakeFirebaseFirestore fs, {
  Map<String, Object?>? idLegadoMap,
}) async {
  final now = DateTime.now();
  await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection('campanhas_sorteio')
      .doc(_campDocId)
      .set({
    'ativa': true,
    'status': 'aberta',
    'valorMinimo': 50.0,
    'dataInicio': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
    'dataFim': Timestamp.fromDate(now.add(const Duration(days: 30))),
    'nome': 'Campanha Borboleta',
    if (idLegadoMap != null) 'id': idLegadoMap,
  });
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    CampaignEngineService.debugFirestoreOverride = firestore;
  });

  tearDown(() {
    CampaignEngineService.debugFirestoreOverride = null;
  });

  group('M3.7 TYPE-CAMP — expressão exata e normalização', () {
    test('RED-R1: spread legado sobrescreve id canônico com Map (cast String?)', () {
      final data = <String, dynamic>{
        'ativa': true,
        'id': <String, Object?>{'legacy': 'nested'},
      };

      final legado = <String, dynamic>{'id': _campDocId, ...data};
      expect(
        () => legado['id'] as String?,
        throwsA(isA<TypeError>()),
      );

      final corrigido = <String, dynamic>{...data, 'id': _campDocId};
      expect(corrigido['id'] as String?, _campDocId);
    });

    test('RED-R2: premioRoleta Map<dynamic,dynamic> quebra cast direto (web)', () {
      final raw = Map<dynamic, dynamic>.from({
        'codigo': 'ROLETA10',
        'valor': 10.0,
        'tipo': 'desconto',
      });
      expect(
        () => raw as Map<String, dynamic>?,
        throwsA(isA<TypeError>()),
      );
      expect(
        firestoreStringDynamicMapOrNull(raw)?['codigo'],
        'ROLETA10',
      );
    });

    test('GREEN-C1: CampaignEngine registra participação com id legado Map no doc', () async {
      await _seedCampanhaAtiva(
        firestore,
        idLegadoMap: <String, Object?>{'nested': 'bad'},
      );

      final resultado = await CampaignEngineService.onVendaConcluida(
        lojaId: _lojaId,
        vendaId: 'venda-lara-151',
        clienteNome: 'Lara',
        telefone: '11999998888',
        email: 'lara@test.com',
        valorTotal: 151.91,
        origem: 'catalogo',
      );

      expect(resultado.sucesso, isTrue, reason: resultado.erro);
      expect(resultado.numero, isNotEmpty);

      final participantes = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('campanhas_sorteio')
          .doc(_campDocId)
          .collection('participantes')
          .get();
      expect(participantes.docs.length, 1);
    });

    test('GREEN-C2: loadAndEvaluate preserva id canônico com campo id Map no doc', () async {
      final fs = FakeFirebaseFirestore();
      final body = Map<String, dynamic>.from(
        _prePedidoLaraWebLike().map((k, v) => MapEntry(k.toString(), v)),
      )..remove('id');
      body['id'] = <String, Object?>{'bad': true};

      await fs
          .collection('lojas')
          .doc(_lojaId)
          .collection('pre_pedidos')
          .doc('ped-lara')
          .set(body);

      final service = PrePedidoConfirmacaoEligibilityService(firestore: fs);
      final result = await service.loadAndEvaluate(
        lojaId: _lojaId,
        prePedidoId: 'ped-lara',
      );

      expect(result.isEligible, isTrue);
      expect(result.data?['id'], 'ped-lara');
    });

    test('GREEN-C3: payload Lara normaliza cliente/frete/premio para confirm', () {
      final raw = _prePedidoLaraWebLike();

      final cliente = firestoreStringDynamicMapOrEmpty(raw['cliente']);
      final frete = firestoreStringDynamicMapOrEmpty(raw['frete']);
      final premio = firestoreStringDynamicMapOrNull(raw['premioRoleta']);

      expect(cliente['nome'], 'Lara');
      expect(frete['gratis'], isTrue);
      expect(premio?['codigo'], 'ROLETA10');
      expect((raw['itens'] as List).first, isA<Map>());
    });
  });
}
