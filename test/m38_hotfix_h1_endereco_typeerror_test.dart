// M3.8-HOTFIX-H1-FIX — coerção endereco Map → String?

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/endereco_legacy_string_coercion.dart';
import 'package:master_palm/core/pedido_cliente_snapshot_helpers.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/cliente_web.dart';
import 'package:master_palm/services/pre_pedido_confirmacao_eligibility.dart';

Map<String, dynamic> _enderecoMapCompleto() => <String, dynamic>{
      'rua': 'Rua das Flores',
      'numero': '123',
      'complemento': 'Apto 4',
      'bairro': 'Centro',
      'cidade': 'São Paulo',
      'estado': 'SP',
      'cep': '01000-000',
    };

Map<String, dynamic> _clientePrePedidoSnapshot() => <String, dynamic>{
      'nome': 'Lara',
      'email': 'lara@test.com',
      'telefone': '11999998888',
      'cpf': '12345678901',
      'endereco': _enderecoMapCompleto(),
      'enderecoFormatado':
          'Rua das Flores, 123, Apto 4, Centro, São Paulo - SP, 01000-000',
    };

void main() {
  group('M3.8-HOTFIX-H1-FIX coerceEnderecoLegacyString', () {
    test('H1ADDR-1 String legado permanece igual', () {
      final out = coerceEnderecoLegacyString(
        enderecoRaw: '  Rua Antiga, 10  ',
        enderecoFormatado: 'não deve usar se raw é String',
      );
      expect(out, 'Rua Antiga, 10');
    });

    test('H1ADDR-2 Map estruturado usa enderecoFormatado', () {
      final out = coerceEnderecoLegacyString(
        enderecoRaw: _enderecoMapCompleto(),
        enderecoFormatado: 'Linha formatada preferida',
      );
      expect(out, 'Linha formatada preferida');
    });

    test('H1ADDR-3 Map sem enderecoFormatado monta linha legível', () {
      final out = coerceEnderecoLegacyString(
        enderecoRaw: _enderecoMapCompleto(),
        enderecoFormatado: '',
      );
      expect(out, isNotNull);
      expect(out, contains('Rua das Flores'));
      expect(out, contains('123'));
      expect(out, contains('Apto 4'));
      expect(out, contains('Centro'));
      expect(out, contains('São Paulo'));
      expect(out, contains('SP'));
      expect(out, contains('01000-000'));
    });

    test('H1ADDR-4 String vazia retorna null', () {
      expect(
        coerceEnderecoLegacyString(enderecoRaw: '   ', enderecoFormatado: null),
        isNull,
      );
    });

    test('H1ADDR-5 Map vazio retorna null', () {
      expect(
        coerceEnderecoLegacyString(
          enderecoRaw: <String, dynamic>{},
          enderecoFormatado: '  ',
        ),
        isNull,
      );
    });

    test('H1ADDR-9 endereço completo preserva número/complemento', () {
      final out = coerceEnderecoLegacyString(
        enderecoRaw: _enderecoMapCompleto(),
      );
      expect(out, contains('123'));
      expect(out, contains('Apto 4'));
    });

    test('H1ADDR-10 nenhum "null" aparece na String final', () {
      final out = coerceEnderecoLegacyString(
        enderecoRaw: <String, dynamic>{
          'rua': 'Rua X',
          'numero': null,
          'complemento': 'null',
          'bairro': '',
          'cidade': 'Campinas',
          'estado': null,
        },
      );
      expect(out, isNotNull);
      expect(out!.toLowerCase().contains('null'), isFalse);
      expect(out, contains('Rua X'));
      expect(out, contains('Campinas'));
    });
  });

  group('M3.8-HOTFIX-H1-FIX modelos String?', () {
    test('H1ADDR-6 Cliente (sync path) não lança TypeError com Map', () {
      final data = <String, dynamic>{
        'nome': 'Lara',
        'telefone': '11999998888',
        'email': 'lara@test.com',
        'endereco': _enderecoMapCompleto(),
        'enderecoFormatado': 'Rua das Flores, 123 — São Paulo',
        'instagram': '',
        'cep': '01000-000',
        'cidade': 'São Paulo',
      };

      Cliente? cliente;
      expect(
        () {
          cliente = Cliente(
            nome: data['nome'] ?? '',
            telefone: data['telefone'] ?? '',
            email: data['email'],
            endereco: coerceEnderecoLegacyString(
              enderecoRaw: data['endereco'],
              enderecoFormatado: data['enderecoFormatado'],
            ),
            instagram: data['instagram'] ?? '',
            cep: data['cep'] ?? '',
            cidade: data['cidade'] ?? '',
            lojaId: 'loja-h1',
          );
        },
        returnsNormally,
      );
      expect(cliente!.endereco, 'Rua das Flores, 123 — São Paulo');
      expect(cliente!.endereco, isA<String>());
    });

    test('H1ADDR-7 ClienteWeb.fromMap não lança TypeError', () {
      final map = <String, dynamic>{
        'nome': 'Lara',
        'email': 'lara@test.com',
        'telefone': '11999998888',
        'cpf': '12345678901',
        'endereco': _enderecoMapCompleto(),
        'enderecoFormatado': 'Formatado Web',
      };

      late ClienteWeb web;
      expect(() => web = ClienteWeb.fromMap(map, 'web-1'), returnsNormally);
      expect(web.endereco, 'Formatado Web');
    });

    test('H1ADDR-8 telefone/email/cpf não são alterados', () {
      final map = <String, dynamic>{
        'nome': 'Lara',
        'email': 'lara@test.com',
        'telefone': '11999998888',
        'cpf': '12345678901',
        'endereco': _enderecoMapCompleto(),
        'enderecoFormatado': 'Fmt',
      };
      final web = ClienteWeb.fromMap(map, 'web-2');
      expect(web.telefone, '11999998888');
      expect(web.email, 'lara@test.com');
      expect(web.cpf, '12345678901');
      expect(web.endereco, 'Fmt');
    });
  });

  group('M3.8-HOTFIX-H1-FIX confirmação pré-pedido + snapshot', () {
    test(
      'pre-pedido com endereco Map + formatado String: elegível e snapshot intacto',
      () {
        final prePedido = <String, dynamic>{
          'id': 'ped-h1-lara',
          'status': 'pendente',
          'pagamento': 'PIX',
          'statusPagamento': 'pendente',
          'total': 151.91,
          'cliente': _clientePrePedidoSnapshot(),
          'itens': [
            {
              'nome': 'Conjunto Borboleta',
              'quantidade': 1,
              'precoUnitario': 151.91,
            },
          ],
        };

        final eligibility =
            PrePedidoConfirmacaoEligibility.evaluateMap(prePedido);
        expect(eligibility.isEligible, isTrue);

        final cliente = Map<String, dynamic>.from(
          prePedido['cliente'] as Map,
        );
        // Snapshot estruturado do pedido permanece Map (não convertido).
        expect(cliente['endereco'], isA<Map>());
        expect(cliente['enderecoFormatado'], isA<String>());
        expect(pedidoClienteEnderecoMap(cliente)['rua'], 'Rua das Flores');
        expect(
          formatarEnderecoSnapshotCompleto(cliente),
          contains('Rua das Flores'),
        );

        // Hive/admin recebe só String? coerida.
        final hiveEndereco = coerceEnderecoLegacyString(
          enderecoRaw: cliente['endereco'],
          enderecoFormatado: cliente['enderecoFormatado'],
        );
        expect(hiveEndereco, isA<String>());
        expect(hiveEndereco, isNot(contains('Instance of')));
        expect(() {
          // ignore: unnecessary_nullable_for_final_variable_declarations
          final String? s = hiveEndereco;
          return s;
        }, returnsNormally);
      },
    );

    test('RED legado: assign Map cru a String? ainda rebenta', () {
      final dynamic raw = _enderecoMapCompleto();
      expect(
        () {
          // ignore: unnecessary_nullable_for_final_variable_declarations
          final String? endereco = raw;
          return endereco;
        },
        throwsA(isA<TypeError>()),
      );
    });
  });
}
