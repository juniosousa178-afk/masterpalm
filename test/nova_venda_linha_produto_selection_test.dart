// Simula atualização da linha de venda (autocomplete / digitação) sem widget nem loja real.

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/strict_product_resolution.dart';
import 'package:master_palm/models/produto.dart';

/// Espelha [NovaVendaModal] onChanged após seleção no autocomplete.
void aplicarSelecaoAutocomplete(
  Map<String, dynamic> linha, {
  required String nome,
  required double preco,
  String? productId,
}) {
  linha['produto'] = nome;
  linha['preco'] = preco;
  linha['tamanho'] = '';
  linha['cor'] = '';
  linha.remove('itensComboComSelecao');
  linha['quantidade'] = 1;
  if (productId != null && productId.isNotEmpty) {
    linha['productId'] = productId;
  } else {
    linha.remove('productId');
  }
}

/// Espelha [NovaVendaModal] onTextChanged (linha avulsa, não combo).
void aplicarTextoDigitado(
  Map<String, dynamic> linha,
  String texto,
  List<Produto> produtosDaLoja,
) {
  linha['produto'] = texto;
  final pidAtual = (linha['productId'] as String?)?.trim();
  if (pidAtual != null && pidAtual.isNotEmpty) {
    final pPorId = produtosDaLoja.firstWhereOrNull(
      (x) => x.idFirebase.trim() == pidAtual,
    );
    if (pPorId != null &&
        productIdIncoerenteComNomeExibido(
          nomeProdutoResolvido: pPorId.nome,
          nomeExibido: texto,
        )) {
      linha.remove('productId');
    }
  }
  final p = produtosDaLoja.firstWhereOrNull(
    (x) => x.nome.toLowerCase() == texto.trim().toLowerCase(),
  );
  if (p != null) {
    linha['preco'] = p.precoFinal;
    linha['productId'] =
        p.idFirebase.trim().isNotEmpty ? p.idFirebase.trim() : null;
  } else {
    linha.remove('productId');
  }
}

void main() {
  const lojaId = 'loja-teste-preview';
  const nomeRelogio = 'Relógio Cássio Oval';
  const nomeAnel = 'Anel Shine Regulável';
  const idRelogio = 'produto-relogio';
  const idAnel = 'produto-anel';

  Produto prod({
    required String nome,
    required String idFirebase,
    String slug = '',
  }) {
    final p = Produto.vazio();
    p.nome = nome;
    p.idFirebase = idFirebase;
    p.slug = slug;
    p.lojaId = lojaId;
    p.precoFinal = 100;
    return p;
  }

  late List<Produto> catalogo;
  late Map<String, dynamic> linha;

  setUp(() {
    catalogo = [
      prod(
        nome: nomeRelogio,
        idFirebase: idRelogio,
        slug: 'lavile-joias-rel-gio-cassio-oval',
      ),
      prod(
        nome: nomeAnel,
        idFirebase: idAnel,
        slug: 'anel-shine-regulavel',
      ),
    ];
    linha = {
      'produto': '',
      'preco': 0.0,
      'quantidade': 1,
      'tamanho': '',
      'cor': '',
    };
  });

  group('fluxo autocomplete — trocar Relógio por Anel', () {
    test('selecionar Relógio depois Anel deixa productId do Anel', () {
      aplicarSelecaoAutocomplete(
        linha,
        nome: nomeRelogio,
        preco: 200,
        productId: idRelogio,
      );
      expect(linha['productId'], idRelogio);

      aplicarSelecaoAutocomplete(
        linha,
        nome: nomeAnel,
        preco: 99,
        productId: idAnel,
      );

      expect(linha['produto'], nomeAnel);
      expect(linha['productId'], idAnel);
      expect(linha['productId'], isNot(idRelogio));
    });

    test('bug antigo: trocar só nome sem productId mantinha id stale', () {
      aplicarSelecaoAutocomplete(
        linha,
        nome: nomeRelogio,
        preco: 200,
        productId: idRelogio,
      );

      // Simula callback antigo (sem atualizar productId).
      linha['produto'] = nomeAnel;
      linha['preco'] = 99.0;
      // productId permanece idRelogio — estado bugado.

      expect(linha['produto'], nomeAnel);
      expect(linha['productId'], idRelogio);

      expect(
        productIdIncoerenteComNomeExibido(
          nomeProdutoResolvido: nomeRelogio,
          nomeExibido: linha['produto'] as String,
        ),
        isTrue,
      );
    });
  });

  group('digitação manual limpa productId stale', () {
    test('texto diferente do produto do productId remove id antigo', () {
      linha['produto'] = nomeAnel;
      linha['productId'] = idRelogio;

      aplicarTextoDigitado(linha, nomeAnel, catalogo);

      expect(linha['productId'], idAnel);
    });

    test('texto parcial sem match remove productId', () {
      linha['productId'] = idRelogio;
      aplicarTextoDigitado(linha, 'Anel Shine', catalogo);
      expect(linha.containsKey('productId'), isFalse);
    });

    test('texto arbitrário sem produto cadastrado remove productId', () {
      linha['productId'] = idRelogio;
      aplicarTextoDigitado(linha, 'Colar Fantasia', catalogo);
      expect(linha.containsKey('productId'), isFalse);
    });
  });
}
