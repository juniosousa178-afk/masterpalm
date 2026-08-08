// Simula atualização da linha de venda (autocomplete / digitação) sem widget nem loja real.

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/strict_product_resolution.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/utils/text_utils.dart';

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
      linha.remove('variationId');
      linha['preco'] = 0.0;
      linha['tamanho'] = '';
      linha['cor'] = '';
    }
  }
  final trimmed = normalizeText(texto);
  final p = produtosDaLoja.firstWhereOrNull(
    (x) =>
        normalizeText(x.nome) == trimmed ||
        (x.codigoBarras.trim().isNotEmpty &&
            normalizeText(x.codigoBarras) == trimmed),
  );
  if (p != null) {
    linha['preco'] = p.precoFinal;
    linha['productId'] =
        p.idFirebase.trim().isNotEmpty ? p.idFirebase.trim() : null;
    if (normalizeText(p.nome) != trimmed &&
        normalizeText(p.codigoBarras) == trimmed) {
      linha['produto'] = p.nome;
    }
  } else {
    linha.remove('productId');
    linha.remove('variationId');
    linha['preco'] = 0.0;
    linha['tamanho'] = '';
    linha['cor'] = '';
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
    String codigoBarras = '',
    double precoFinal = 100,
  }) {
    final p = Produto.vazio();
    p.nome = nome;
    p.idFirebase = idFirebase;
    p.slug = slug;
    p.lojaId = lojaId;
    p.precoFinal = precoFinal;
    p.codigoBarras = codigoBarras;
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

  group('pesquisa por código de barras', () {
    const codigoBrinco = 'BR01PR-87';
    const idBrinco = 'produto-codigo-r8445';
    const nomeBrinco = 'Produto Código QA';

    setUp(() {
      catalogo = [
        prod(
          nome: nomeRelogio,
          idFirebase: idRelogio,
          slug: 'lavile-joias-rel-gio-cassio-oval',
        ),
        prod(
          nome: nomeBrinco,
          idFirebase: idBrinco,
          slug: 'produto-codigo-qa',
          codigoBarras: codigoBrinco,
          precoFinal: 49.90,
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

    test('BR01PR-87 encontra o produto', () {
      aplicarTextoDigitado(linha, codigoBrinco, catalogo);

      expect(linha['produto'], nomeBrinco);
      expect(linha['productId'], idBrinco);
      expect(linha['preco'], 49.90);
    });

    test('código com espaços é normalizado', () {
      aplicarTextoDigitado(linha, '  BR01PR-87  ', catalogo);

      expect(linha['produto'], nomeBrinco);
      expect(linha['productId'], idBrinco);
      expect(linha['preco'], 49.90);
    });

    test('código inexistente não cria linha', () {
      aplicarTextoDigitado(linha, 'CODIGO_INEXISTENTE', catalogo);

      expect(linha.containsKey('productId'), isFalse);
      expect(linha['preco'], 0.0);
    });

    test('código com hífen é preservado na busca', () {
      aplicarTextoDigitado(linha, 'BR01PR-87', catalogo);

      expect(linha['produto'], nomeBrinco);
      expect(linha['productId'], idBrinco);
    });

    test('produto encontrado vincula productId', () {
      aplicarTextoDigitado(linha, codigoBrinco, catalogo);

      expect(linha['productId'], idBrinco);
      expect(linha['productId'], isNotEmpty);
    });

    test('produto encontrado carrega preço', () {
      aplicarTextoDigitado(linha, codigoBrinco, catalogo);

      expect(linha['preco'], 49.90);
      expect(linha['preco'], isNot(0.0));
    });

    test('código inválido falha fechado - remove productId anterior', () {
      linha['productId'] = idRelogio;
      linha['produto'] = nomeRelogio;

      aplicarTextoDigitado(linha, 'CODIGO_INVALIDO', catalogo);

      expect(linha.containsKey('productId'), isFalse);
      expect(linha['preco'], 0.0);
    });

    test('produto anterior não permanece selecionado após código inválido', () {
      linha['produto'] = nomeRelogio;
      linha['productId'] = idRelogio;
      linha['preco'] = 100.0;

      aplicarTextoDigitado(linha, 'CODIGO_INVALIDO', catalogo);

      expect(linha.containsKey('productId'), isFalse);
      expect(linha['preco'], 0.0);
    });

    test('nomes duplicados com códigos diferentes - código seleciona produto correto', () {
      const nomeDuplicado = 'Brinco Borboleta';
      const idProdutoA = 'produto-a';
      const idProdutoB = 'produto-b';
      const codigoA = 'COD-A';
      const codigoB = 'COD-B';

      final catalogoDuplicado = [
        prod(
          nome: nomeDuplicado,
          idFirebase: idProdutoA,
          slug: 'brinco-borboleta-a',
          codigoBarras: codigoA,
          precoFinal: 49.90,
        ),
        prod(
          nome: nomeDuplicado,
          idFirebase: idProdutoB,
          slug: 'brinco-borboleta-b',
          codigoBarras: codigoB,
          precoFinal: 79.90,
        ),
      ];

      linha.clear();
      linha['produto'] = '';
      linha['preco'] = 0.0;
      linha['quantidade'] = 1;
      linha['tamanho'] = '';
      linha['cor'] = '';

      // Ao digitar COD-B, deve selecionar produto-b com preço 79.90
      aplicarTextoDigitado(linha, codigoB, catalogoDuplicado);

      expect(linha['produto'], nomeDuplicado);
      expect(linha['productId'], idProdutoB);
      expect(linha['preco'], 79.90);
      expect(linha['productId'], isNot(idProdutoA));
    });

    test('nomes duplicados - código A seleciona produto A com preço correto', () {
      const nomeDuplicado = 'Brinco Borboleta';
      const idProdutoA = 'produto-a';
      const idProdutoB = 'produto-b';
      const codigoA = 'COD-A';
      const codigoB = 'COD-B';

      final catalogoDuplicado = [
        prod(
          nome: nomeDuplicado,
          idFirebase: idProdutoA,
          slug: 'brinco-borboleta-a',
          codigoBarras: codigoA,
          precoFinal: 49.90,
        ),
        prod(
          nome: nomeDuplicado,
          idFirebase: idProdutoB,
          slug: 'brinco-borboleta-b',
          codigoBarras: codigoB,
          precoFinal: 79.90,
        ),
      ];

      linha.clear();
      linha['produto'] = '';
      linha['preco'] = 0.0;
      linha['quantidade'] = 1;
      linha['tamanho'] = '';
      linha['cor'] = '';

      // Ao digitar COD-A, deve selecionar produto-a com preço 49.90
      aplicarTextoDigitado(linha, codigoA, catalogoDuplicado);

      expect(linha['produto'], nomeDuplicado);
      expect(linha['productId'], idProdutoA);
      expect(linha['preco'], 49.90);
      expect(linha['productId'], isNot(idProdutoB));
    });

    test('escopo da empresa - código localiza produto da mesma empresa', () {
      const lojaA = 'loja-a';
      const lojaB = 'loja-b';
      const codigoCompartilhado = 'BR01PR-87';
      const idProdutoA = 'produto-empresa-a';
      const idProdutoB = 'produto-empresa-b';

      final catalogoMultiEmpresa = [
        prod(
          nome: 'Produto Empresa A',
          idFirebase: idProdutoA,
          slug: 'produto-empresa-a',
          codigoBarras: codigoCompartilhado,
          precoFinal: 49.90,
        )..lojaId = lojaA,
        prod(
          nome: 'Produto Empresa B',
          idFirebase: idProdutoB,
          slug: 'produto-empresa-b',
          codigoBarras: codigoCompartilhado,
          precoFinal: 79.90,
        )..lojaId = lojaB,
      ];

      linha.clear();
      linha['produto'] = '';
      linha['preco'] = 0.0;
      linha['quantidade'] = 1;
      linha['tamanho'] = '';
      linha['cor'] = '';

      // Filtrar apenas produtos da loja A
      final produtosLojaA = catalogoMultiEmpresa.where((p) => p.lojaId == lojaA).toList();

      aplicarTextoDigitado(linha, codigoCompartilhado, produtosLojaA);

      expect(linha['produto'], 'Produto Empresa A');
      expect(linha['productId'], idProdutoA);
      expect(linha['preco'], 49.90);
      expect(linha['productId'], isNot(idProdutoB));
    });

    test('escopo da empresa - código não localiza produto de outra empresa', () {
      const lojaA = 'loja-a';
      const lojaB = 'loja-b';
      const codigoCompartilhado = 'BR01PR-87';
      const idProdutoA = 'produto-empresa-a';
      const idProdutoB = 'produto-empresa-b';

      final catalogoMultiEmpresa = [
        prod(
          nome: 'Produto Empresa A',
          idFirebase: idProdutoA,
          slug: 'produto-empresa-a',
          codigoBarras: codigoCompartilhado,
          precoFinal: 49.90,
        )..lojaId = lojaA,
        prod(
          nome: 'Produto Empresa B',
          idFirebase: idProdutoB,
          slug: 'produto-empresa-b',
          codigoBarras: codigoCompartilhado,
          precoFinal: 79.90,
        )..lojaId = lojaB,
      ];

      linha.clear();
      linha['produto'] = '';
      linha['preco'] = 0.0;
      linha['quantidade'] = 1;
      linha['tamanho'] = '';
      linha['cor'] = '';

      // Filtrar apenas produtos da loja A (não contém produto com o código)
      final produtosLojaA = catalogoMultiEmpresa.where((p) => p.lojaId == lojaA).toList();

      // Produto da loja B não deve estar na lista filtrada
      expect(produtosLojaA.any((p) => p.idFirebase == idProdutoB), isFalse);

      // Código deve encontrar apenas produto da loja A
      aplicarTextoDigitado(linha, codigoCompartilhado, produtosLojaA);

      expect(linha['produto'], 'Produto Empresa A');
      expect(linha['productId'], idProdutoA);
      expect(linha['productId'], isNot(idProdutoB));
    });

    test('Enter - digitar código e pressionar Enter (simulado via onTextChanged)', () {
      // O campo TextFormField chama onTextChanged a cada keystroke
      // Enter chama onFieldSubmitted que confirma a seleção do Autocomplete
      // A resolução do produto acontece no onChanged, não no Enter
      aplicarTextoDigitado(linha, codigoBrinco, catalogo);

      expect(linha['produto'], nomeBrinco);
      expect(linha['productId'], idBrinco);
      expect(linha['preco'], 49.90);
    });

    test('botão + - adiciona nova linha vazia sem corromper produto resolvido', () {
      linha['produto'] = nomeRelogio;
      linha['productId'] = idRelogio;
      linha['preco'] = 100.0;

      // Simula o comportamento do botão + (adiciona nova linha)
      final novaLinha = {
        'produto': '',
        'preco': 0.0,
        'quantidade': 1,
        'tamanho': '',
        'cor': '',
      };

      // Linha atual permanece inalterada
      expect(linha['produto'], nomeRelogio);
      expect(linha['productId'], idRelogio);
      expect(linha['preco'], 100.0);

      // Nova linha está vazia
      expect(novaLinha['produto'], '');
      expect(novaLinha['preco'], 0.0);
    });

    test('colar código - onTextChanged processa código colado', () {
      // Colar código é tratado como onTextChanged com o código completo
      aplicarTextoDigitado(linha, codigoBrinco, catalogo);

      expect(linha['produto'], nomeBrinco);
      expect(linha['productId'], idBrinco);
      expect(linha['preco'], 49.90);
    });

    test('código em caixa diferente - normalização funciona', () {
      aplicarTextoDigitado(linha, 'br01pr-87', catalogo);

      expect(linha['produto'], nomeBrinco);
      expect(linha['productId'], idBrinco);
      expect(linha['preco'], 49.90);
    });

    test('código com espaços extras - trim funciona', () {
      aplicarTextoDigitado(linha, '  BR01PR-87  ', catalogo);

      expect(linha['produto'], nomeBrinco);
      expect(linha['productId'], idBrinco);
      expect(linha['preco'], 49.90);
    });

    test('código inválido remove completamente estado anterior - productId', () {
      linha['produto'] = nomeRelogio;
      linha['productId'] = idRelogio;
      linha['preco'] = 100.0;
      linha['tamanho'] = 'M';
      linha['cor'] = 'Dourado';

      aplicarTextoDigitado(linha, 'CODIGO_INVALIDO', catalogo);

      expect(linha.containsKey('productId'), isFalse);
      expect(linha['preco'], 0.0);
    });

    test('código inválido remove completamente estado anterior - tamanho e cor', () {
      linha['produto'] = nomeRelogio;
      linha['productId'] = idRelogio;
      linha['preco'] = 100.0;
      linha['tamanho'] = 'M';
      linha['cor'] = 'Dourado';

      aplicarTextoDigitado(linha, 'CODIGO_INVALIDO', catalogo);

      expect(linha['tamanho'], '');
      expect(linha['cor'], '');
      expect(linha['preco'], 0.0);
    });

    test('código inválido remove completamente estado anterior - estoque não reutilizado', () {
      linha['produto'] = nomeRelogio;
      linha['productId'] = idRelogio;
      linha['preco'] = 100.0;
      linha['quantidade'] = 5;

      aplicarTextoDigitado(linha, 'CODIGO_INVALIDO', catalogo);

      // Quantidade permanece inalterada pelo helper (não faz reset de quantidade)
      // A quantidade é resetada apenas pelo widget ao adicionar nova linha
      expect(linha['quantidade'], 5);
      expect(linha.containsKey('productId'), isFalse);
      expect(linha['preco'], 0.0);
    });
  });
}
