// H13B — não consegue selecionar cliente ao criar cupom pessoal

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/cupom_pessoal_cliente_busca.dart';

void main() {
  group('H13B — busca de cliente para cupom pessoal', () {
    final clientes = [
      {
        'id': 'cli-1',
        'nome': 'Maria Silva',
        'email': 'Maria@Email.COM',
        'telefone': '11999990000',
      },
      {
        'id': 'cli-2',
        'nome': 'João Pereira',
        'email': 'joao@loja.com',
        'telefone': '11888880000',
      },
    ];

    test(
      'RED: prefixo Firestore lowercased NÃO encontra nome Title Case',
      () {
        // Reproduz a semântica quebrada de searchClientes (query.toLowerCase
        // + where nome >= queryLower), que impede listar/selecionar cliente.
        expect(
          cupomPessoalFirestorePrefixMatchBroken(
            nomeArmazenado: 'Maria Silva',
            queryDigitada: 'maria',
          ),
          isFalse,
        );
        expect(
          cupomPessoalFirestorePrefixMatchBroken(
            nomeArmazenado: 'Maria Silva',
            queryDigitada: 'Maria',
          ),
          isFalse,
        );
      },
    );

    test('GREEN: filtro case-insensitive encontra por nome', () {
      final r = filtrarClientesCupomPessoal(
        clientes: clientes,
        query: 'maria',
      );
      expect(r, hasLength(1));
      expect(r.single['id'], 'cli-1');
      expect(r.single['nome'], 'Maria Silva');
    });

    test('GREEN: encontra por e-mail normalizado', () {
      final r = filtrarClientesCupomPessoal(
        clientes: clientes,
        query: 'maria@email',
      );
      expect(r.single['id'], 'cli-1');
    });

    test('GREEN: encontra por telefone', () {
      final r = filtrarClientesCupomPessoal(
        clientes: clientes,
        query: '1199999',
      );
      expect(r.single['id'], 'cli-1');
    });

    test('GREEN: query curta não lista (evita lista infinita)', () {
      expect(
        filtrarClientesCupomPessoal(clientes: clientes, query: 'm'),
        isEmpty,
      );
    });

    test('GREEN: seleção normaliza id e e-mail para o cupom', () {
      final sel = normalizarClienteSelecionadoCupom(clientes.first);
      expect(sel['id'], 'cli-1');
      expect(sel['clienteId'], 'cli-1');
      expect(sel['email'], 'maria@email.com');
    });

    test('H13B-fluxo: após filtrar, onSelected grava no state usável', () {
      Map<String, dynamic>? clienteSelecionado;
      final lista = filtrarClientesCupomPessoal(
        clientes: clientes,
        query: 'silva',
      );
      expect(lista, isNotEmpty);
      // Espelha onTap do ListTile no dialog
      clienteSelecionado = normalizarClienteSelecionadoCupom(lista.first);
      expect(clienteSelecionado, isNotNull);
      expect(clienteSelecionado!['clienteId'], isNotEmpty);
      // Validator lê o mesmo state
      final exigeCliente = clienteSelecionado == null;
      expect(exigeCliente, isFalse);
    });
  });
}
