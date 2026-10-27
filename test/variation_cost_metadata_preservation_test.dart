import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_effective_stock.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_stock_catalog_cadastro_sync.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _loja = 'loja-variation-cost';

/// Documento remoto do "Teste 1" (cópia sintética, sem dados de produção).
Map<String, dynamic> _remoteTeste1({
  int rev = 0,
  String? op,
  int q1 = 4,
  int q2 = 5,
}) =>
    {
      'nome': 'Teste 1',
      'lojaId': _loja,
      'tipoProduto': 'simples',
      'quantidade': q1 + q2,
      'preco': 2.99,
      'custoReal': 1.99,
      'custoEditadoNoCadastro': true,
      'stockKind': 'variation',
      'stockRevision': rev,
      if (op != null) 'stockOperationId': op,
      'tamanhos': ['1', '2'],
      'cores': <String>[],
      'estoquePorTamanho': {'1': q1, '2': q2},
      'precoPorTamanho': {'1': 5.99, '2': 6.99},
      'variacoes': {
        '1': {
          'sem-cor': {'_sem_extra': q1, '__custoUnitario': 2.99},
        },
        '2': {
          'sem-cor': {'_sem_extra': q2, '__custoUnitario': 3.99},
        },
      },
    };

Produto _produto({
  required String id,
  String nome = 'Produto',
  required double custoReal,
  required int qtd,
  double preco = 10,
  Map<String, dynamic>? variacoes,
  Map<String, int>? ept,
  List<String>? tamanhos,
  String lojaId = _loja,
}) {
  return Produto(
    nome: nome,
    custoReal: custoReal,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: preco,
    precoFinal: preco,
    quantidade: qtd,
    precoUnitario: preco,
    categoria: 'Teste',
    dataEntrada: DateTime(2026, 1, 1),
    idFirebase: id,
    slug: id,
    lojaId: lojaId,
    variacoes: variacoes,
    estoquePorTamanho: ept ?? const {},
    tamanhos: tamanhos ?? const [],
    publicadoNoCatalogo: false,
  );
}

/// Teste 1 como fica no Hive após o FullSync da Home (meta preservada).
Produto _teste1AposFullSync() {
  final p = _produto(
    id: 'teste-1',
    nome: 'Teste 1',
    custoReal: 1.99,
    qtd: 9,
    preco: 2.99,
  );
  ProdutosFirestoreService.applyRemoteVariationFieldsToExistingOnPull(
    local: p,
    data: _remoteTeste1(),
  );
  return p;
}

/// Teste 1 com Hive já sem `__custoUnitario` (estado deixado pelo bug).
Produto _teste1HiveSemMeta() => _produto(
      id: 'teste-1',
      nome: 'Teste 1',
      custoReal: 1.99,
      qtd: 9,
      preco: 2.99,
      variacoes: {
        '1': {'sem-cor': 4},
        '2': {'sem-cor': 5},
      },
      ept: {'1': 4, '2': 5},
      tamanhos: ['1', '2'],
    );

/// Mesmo trecho do `syncFirestoreToHive` (ramo sem preserve) do Estoque.
void _pullDaTelaEstoque(Produto p, Map<String, dynamic> remote) {
  ProdutosFirestoreService.applyRemoteVariationFieldsToExistingOnPull(
    local: p,
    data: remote,
  );
  if (tryConfirmStockFromRemote(p, remote)) {
    applyAuthoritativeRemoteStockToProduto(p, remote: remote);
  }
  p.recalcularQuantidadeTotal();
}

/// Só o passo autoritativo (hidratação de venda / reconciliação).
void _authoritative(Produto p, Map<String, dynamic> remote) {
  if (tryConfirmStockFromRemote(p, remote)) {
    applyAuthoritativeRemoteStockToProduto(p, remote: remote);
  }
  p.recalcularQuantidadeTotal();
}

double _custoTotalHeader(Iterable<Produto> ps) => ps
    .where((p) => !p.ehCombo)
    .fold(0.0, (acc, p) => acc + p.custoTotalEstoque());

double _r2(double v) => (v * 100).roundToDouble() / 100;

List<Produto> _lojaSmoke(Produto teste1) => [
      _produto(
        id: 'anel-teste',
        custoReal: 10,
        qtd: 3,
        variacoes: {
          '13': {'sem-cor': 1},
          '15': {'sem-cor': 1},
          '17': {'sem-cor': 1},
        },
        ept: {'13': 1, '15': 1, '17': 1},
        tamanhos: ['13', '15', '17'],
      ),
      _produto(id: 'colar', custoReal: 20, qtd: 3),
      _produto(id: 'qa', custoReal: 1, qtd: 1),
      teste1,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Teste 1 / loja — pull do Estoque preserva custo por variação', () {
    test('Teste 1: 31,91 antes e depois do pull', () {
      final p = _teste1AposFullSync();
      expect(_r2(p.custoTotalEstoque()), 31.91);

      _pullDaTelaEstoque(p, _remoteTeste1());

      expect(p.quantidade, 9);
      expect(_r2(p.custoTotalEstoque()), 31.91);
      expect(p.custoUnitarioVariacao('1', ''), 2.99);
      expect(p.custoUnitarioVariacao('2', ''), 3.99);
      expect(p.variacoes!['1']['sem-cor'], {
        ProdutoVariacaoExtra.kSemExtraKey: 4,
        ProdutoVariacaoExtra.kMetaCustoUnitarioKey: 2.99,
      });
      expect(p.variacoes!['2']['sem-cor'], {
        ProdutoVariacaoExtra.kSemExtraKey: 5,
        ProdutoVariacaoExtra.kMetaCustoUnitarioKey: 3.99,
      });
    });

    test('loja de smoke: 122,91 -> 122,91, qtd e valor de venda inalterados',
        () {
      final teste1 = _teste1AposFullSync();
      final loja = _lojaSmoke(teste1);
      final qtdAntes = loja.fold<int>(0, (a, p) => a + p.quantidade);
      expect(_r2(_custoTotalHeader(loja)), 122.91);

      _pullDaTelaEstoque(teste1, _remoteTeste1());

      expect(_r2(_custoTotalHeader(loja)), 122.91);
      expect(loja.fold<int>(0, (a, p) => a + p.quantidade), qtdAntes);
    });

    test('Hive já sem meta é curado pelo pull (remoto é a autoridade)', () {
      final p = _teste1HiveSemMeta();
      expect(_r2(p.custoTotalEstoque()), 17.91);

      _authoritative(p, _remoteTeste1());

      expect(_r2(p.custoTotalEstoque()), 31.91);
    });

    test('célula com letras mantém __custoUnitario', () {
      final remote = <String, dynamic>{
        'lojaId': _loja,
        'quantidade': 3,
        'custoReal': 1.0,
        'stockKind': 'variation',
        'stockRevision': 0,
        'tamanhos': ['P'],
        'estoquePorTamanho': {'P': 3},
        'variacoes': {
          'P': {
            'sem-cor': {'A': 1, 'B': 2, '__custoUnitario': 5.0},
          },
        },
      };
      final p = _produto(id: 'letras', custoReal: 1, qtd: 3);
      _pullDaTelaEstoque(p, remote);
      expect(p.custoTotalEstoque(), 15.0);
      expect(p.custoUnitarioVariacao('P', '', 'A'), 5.0);
    });
  });

  group('controles do pull autoritativo', () {
    test('produto simples sem variações: custoReal * quantidade', () {
      final p = _produto(id: 'simples', custoReal: 4, qtd: 3);
      _authoritative(p, {
        'lojaId': _loja,
        'quantidade': 5,
        'stockKind': 'simple',
        'stockRevision': 1,
      });
      expect(p.variacoes, isNull);
      expect(p.quantidade, 5);
      expect(p.custoTotalEstoque(), 20.0);
    });

    test('variação sem custo próprio usa custoReal e não cria meta', () {
      final p = _produto(id: 'sem-custo', custoReal: 2, qtd: 0);
      _authoritative(p, {
        'lojaId': _loja,
        'quantidade': 5,
        'stockKind': 'variation',
        'stockRevision': 1,
        'variacoes': {
          'P': {'sem-cor': 2},
          'M': {'sem-cor': 3},
        },
      });
      expect(p.variacoes!['P']['sem-cor'], 2);
      expect(p.variacoes!['M']['sem-cor'], 3);
      expect(p.custoTotalEstoque(), 10.0);
    });

    test('custo da variação = 0 cai em custoReal (0 não é custo válido)', () {
      final p = _produto(id: 'custo-zero', custoReal: 2, qtd: 0);
      _authoritative(p, {
        'lojaId': _loja,
        'quantidade': 3,
        'stockKind': 'variation',
        'stockRevision': 1,
        'variacoes': {
          'P': {
            'sem-cor': {'_sem_extra': 3, '__custoUnitario': 0},
          },
        },
      });
      expect(p.variacoes!['P']['sem-cor'], 3);
      expect(p.custoUnitarioVariacao('P', ''), 2.0);
      expect(p.custoTotalEstoque(), 6.0);
    });

    test('múltiplas cores (sem tamanho): cada cor mantém o próprio custo', () {
      final p = _produto(id: 'cores', custoReal: 1, qtd: 0);
      _authoritative(p, {
        'lojaId': _loja,
        'quantidade': 3,
        'stockKind': 'variation',
        'stockRevision': 1,
        'variacoes': {
          'sem-tamanho': {
            'Azul': {'_sem_extra': 1, '__custoUnitario': 5.0},
            'Rosa': {'_sem_extra': 2, '__custoUnitario': 7.0},
          },
        },
      });
      expect(p.custoUnitarioVariacao('', 'Azul'), 5.0);
      expect(p.custoUnitarioVariacao('', 'Rosa'), 7.0);
      expect(p.custoTotalEstoque(), 19.0);
    });

    test('cor + tamanho: custo nunca é copiado entre variações', () {
      final p = _produto(id: 'grade', custoReal: 1, qtd: 0);
      _authoritative(p, {
        'lojaId': _loja,
        'quantidade': 6,
        'stockKind': 'grade',
        'stockRevision': 1,
        'variacoes': {
          'P': {
            'Azul': {'_sem_extra': 1, '__custoUnitario': 5.0},
            'Rosa': 2,
          },
          'M': {
            'Azul': {'_sem_extra': 3, '__custoUnitario': 9.0},
          },
        },
      });
      expect(p.custoUnitarioVariacao('P', 'Azul'), 5.0);
      expect(p.custoUnitarioVariacao('P', 'Rosa'), 1.0);
      expect(p.custoUnitarioVariacao('M', 'Azul'), 9.0);
      expect(p.variacoes!['P']['Rosa'], 2);
      expect(p.custoTotalEstoque(), 5.0 + 2.0 + 27.0);
    });

    test('identidade ambígua (duas células -> mesmo id canônico) = sem custo',
        () {
      final source = {
        '': {
          'Azul': {'_sem_extra': 1, '__custoUnitario': 5.0},
        },
        'sem-tamanho': {
          'Azul': {'_sem_extra': 1, '__custoUnitario': 8.0},
        },
      };
      expect(custoUnitarioDaCelulaCanonica(source, 'sem-tamanho|Azul'), isNull);
      expect(
        custoUnitarioDaCelulaCanonica({
          'P': {
            'Azul': {'_sem_extra': 1, '__custoUnitario': 5.0},
          },
        }, 'P|Azul'),
        5.0,
      );
    });

    test('qty remota mudou + qty local stale: remoto vence, custo preservado',
        () {
      final p = _teste1AposFullSync();
      p.variacoes = {
        '1': {
          'sem-cor': {'_sem_extra': 10, '__custoUnitario': 2.99},
        },
        '2': {
          'sem-cor': {'_sem_extra': 10, '__custoUnitario': 3.99},
        },
      };
      p.estoquePorTamanho = {'1': 10, '2': 10};
      p.quantidade = 20;
      p.stockRevision = 2;

      _authoritative(p, _remoteTeste1(rev: 3, op: 'op-3', q1: 1, q2: 2));

      expect(p.quantidade, 3);
      expect(p.estoquePorTamanho, {'1': 1, '2': 2});
      expect(ProdutoVariacaoExtra.somarCelula(p.variacoes!['1']['sem-cor']), 1);
      expect(ProdutoVariacaoExtra.somarCelula(p.variacoes!['2']['sem-cor']), 2);
      expect(p.custoUnitarioVariacao('1', ''), 2.99);
      expect(p.custoUnitarioVariacao('2', ''), 3.99);
      expect(_r2(p.custoTotalEstoque()), _r2(2.99 + 2 * 3.99));
      expect(p.stockRevision, 3);
      expect(p.confirmedStockOperationId, 'op-3');
    });

    test('remoto com variacoes é a autoridade do custo (não ressuscita local)',
        () {
      final p = _produto(
        id: 'auth',
        custoReal: 1,
        qtd: 2,
        variacoes: {
          'P': {
            'sem-cor': {'_sem_extra': 2, '__custoUnitario': 9.99},
          },
        },
        ept: {'P': 2},
      );
      _authoritative(p, {
        'lojaId': _loja,
        'quantidade': 2,
        'stockKind': 'variation',
        'stockRevision': 1,
        'variacoes': {
          'P': {'sem-cor': 2},
        },
      });
      expect(p.variacoes!['P']['sem-cor'], 2);
      expect(p.custoUnitarioVariacao('P', ''), 1.0);
    });

    test('pending local: pull não toca grade nem custo', () {
      final p = _teste1AposFullSync();
      markPendingStockMutation(p, operationId: 'op-local', baseRevision: 0);
      final antes = Map<String, dynamic>.from(p.variacoes!);
      final aplicou = applyAuthoritativeRemoteStockToProduto(
        p,
        remote: _remoteTeste1(rev: 1, op: 'op-remoto', q1: 0, q2: 0),
      );
      expect(aplicou, isFalse);
      expect(p.variacoes, antes);
      expect(p.quantidade, 9);
    });

    test('sem variacoes remotas: meta local só da mesma loja', () {
      Produto local(String loja) => _produto(
            id: 'tenant',
            custoReal: 1,
            qtd: 2,
            lojaId: loja,
            variacoes: {
              'P': {
                'sem-cor': {'_sem_extra': 2, '__custoUnitario': 6.0},
              },
            },
            ept: {'P': 2},
            tamanhos: ['P'],
          );
      Map<String, dynamic> remote(String loja) => {
            'lojaId': loja,
            'quantidade': 2,
            'stockKind': 'variation',
            'stockRevision': 1,
            'tamanhos': ['P'],
            'estoquePorTamanho': {'P': 2},
          };

      final mesma = local(_loja);
      _authoritative(mesma, remote(_loja));
      expect(mesma.custoUnitarioVariacao('P', ''), 6.0);

      final outra = local(_loja);
      _authoritative(outra, remote('outra-loja'));
      expect(outra.custoUnitarioVariacao('P', ''), 1.0);
    });
  });

  group('regra única de custo', () {
    test('custoUnitarioValido rejeita 0, negativo, NaN, infinito e texto', () {
      expect(ProdutoVariacaoExtra.custoUnitarioValido(2.99), 2.99);
      expect(ProdutoVariacaoExtra.custoUnitarioValido('3.5'), 3.5);
      expect(ProdutoVariacaoExtra.custoUnitarioValido(0), isNull);
      expect(ProdutoVariacaoExtra.custoUnitarioValido(-1), isNull);
      expect(ProdutoVariacaoExtra.custoUnitarioValido(double.nan), isNull);
      expect(ProdutoVariacaoExtra.custoUnitarioValido(double.infinity), isNull);
      expect(ProdutoVariacaoExtra.custoUnitarioValido('abc'), isNull);
      expect(ProdutoVariacaoExtra.custoUnitarioValido(null), isNull);
    });

    test('custoRealValido: negativo/NaN viram 0', () {
      expect(_produto(id: 'a', custoReal: -5, qtd: 2).custoTotalEstoque(), 0);
      expect(
        _produto(id: 'b', custoReal: double.nan, qtd: 2).custoTotalEstoque(),
        0,
      );
    });

    test('custo de célula inválido cai em custoReal no total e na venda', () {
      final p = _produto(
        id: 'invalido',
        custoReal: 2,
        qtd: 4,
        variacoes: {
          'P': {
            'sem-cor': {'_sem_extra': 2, '__custoUnitario': -3},
          },
          'M': {
            'sem-cor': {'_sem_extra': 2, '__custoUnitario': double.nan},
          },
        },
      );
      expect(p.custoTotalEstoque(), 8.0);
      expect(p.custoUnitarioVariacao('P', ''), 2.0);
      expect(p.custoUnitarioVariacao('M', ''), 2.0);
    });

    test('total e venda usam a mesma regra por célula', () {
      final p = _teste1AposFullSync();
      final porCelula = 4 * p.custoUnitarioVariacao('1', '') +
          5 * p.custoUnitarioVariacao('2', '');
      expect(_r2(p.custoTotalEstoque()), _r2(porCelula));
    });
  });

  group('custo de venda nova', () {
    test('após hidratação autoritativa (pré-venda) custo = custo da variação',
        () {
      final p = _teste1AposFullSync();
      _authoritative(p, _remoteTeste1());
      expect(p.custoUnitarioVariacao('1', ''), 2.99);
      expect(p.custoUnitarioVariacao('2', ''), 3.99);
    });

    test('estrutura de variação para UI de venda preserva custo', () {
      final p = _teste1HiveSemMeta();
      applyRemoteVariationStructureForSaleUi(p, remote: _remoteTeste1());
      expect(p.custoUnitarioVariacao('1', ''), 2.99);
      expect(p.custoUnitarioVariacao('2', ''), 3.99);
    });
  });

  group('push Hive -> Firestore não apaga custo remoto', () {
    final remoteVars = {
      '1': {
        'sem-cor': {'_sem_extra': 4, '__custoUnitario': 2.99},
      },
      '2': {
        'sem-cor': {'_sem_extra': 5, '__custoUnitario': 3.99},
      },
    };

    test('célula sem meta herda custo da mesma célula remota; qty do push', () {
      final out = preserveRemoteVariationCostOnPush(
        push: {
          '1': {'sem-cor': 3},
          '2': {'sem-cor': 5},
        },
        remoteVariacoes: remoteVars,
      );
      expect(out, {
        '1': {
          'sem-cor': {'_sem_extra': 3, '__custoUnitario': 2.99},
        },
        '2': {
          'sem-cor': {'_sem_extra': 5, '__custoUnitario': 3.99},
        },
      });
    });

    test('custo próprio do push vence o remoto', () {
      final out = preserveRemoteVariationCostOnPush(
        push: {
          '1': {
            'sem-cor': {'_sem_extra': 4, '__custoUnitario': 4.5},
          },
        },
        remoteVariacoes: remoteVars,
      );
      expect(out['1']['sem-cor']['__custoUnitario'], 4.5);
    });

    test('remoção explícita no cadastro (baseline tinha custo) é respeitada',
        () {
      final out = preserveRemoteVariationCostOnPush(
        push: {
          '1': {'sem-cor': 4},
          '2': {'sem-cor': 5},
        },
        remoteVariacoes: remoteVars,
        baselineVariacoes: {
          '1': {
            'sem-cor': {'_sem_extra': 4, '__custoUnitario': 2.99},
          },
          '2': {'sem-cor': 5},
        },
      );
      expect(out['1']['sem-cor'], 4);
      expect(out['2']['sem-cor']['__custoUnitario'], 3.99);
    });

    test('não copia custo para variação nova / diferente', () {
      final out = preserveRemoteVariationCostOnPush(
        push: {
          '3': {'sem-cor': 2},
          '1': {'Azul': 1},
        },
        remoteVariacoes: remoteVars,
      );
      expect(out['3']['sem-cor'], 2);
      expect(out['1']['Azul'], 1);
    });

    test('remoto ambíguo não restaura custo', () {
      final out = preserveRemoteVariationCostOnPush(
        push: {
          'sem-tamanho': {'Azul': 1},
        },
        remoteVariacoes: {
          '': {
            'Azul': {'_sem_extra': 1, '__custoUnitario': 5.0},
          },
          'sem-tamanho': {
            'Azul': {'_sem_extra': 1, '__custoUnitario': 8.0},
          },
        },
      );
      expect(out['sem-tamanho']['Azul'], 1);
    });

    test('cadastro replace (backend): Hive sem meta não apaga custo remoto',
        () async {
      final p = _teste1HiveSemMeta();
      final baseline = ProdutoFormGradeBaseline.capture(p);
      p
        ..variacoes = {
          '1': {'sem-cor': 3},
          '2': {'sem-cor': 5},
        }
        ..estoquePorTamanho = {'1': 3, '2': 5}
        ..quantidade = 8;

      final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
        produto: p,
        produtoId: 'teste-1',
        documentExists: true,
        forcePushFromCadastro: true,
        gradeBaseline: baseline,
        remoteRevisionAtSaveTime: 0,
        remoteVariacoesAtSaveTime: Map<String, dynamic>.from(remoteVars),
      );

      expect(intent.kind, 'replace');
      final vars = intent.definition!['variacoes'] as Map;
      expect(vars['1']['sem-cor'], {'_sem_extra': 3, '__custoUnitario': 2.99});
      expect(vars['2']['sem-cor'], {'_sem_extra': 5, '__custoUnitario': 3.99});
    });

    test('cadastro replace: custo removido explicitamente no formulário', () async {
      final p = _teste1AposFullSync();
      final baseline = ProdutoFormGradeBaseline.capture(p);
      p
        ..variacoes = {
          '1': {'sem-cor': 3},
          '2': {
            'sem-cor': {'_sem_extra': 5, '__custoUnitario': 3.99},
          },
        }
        ..estoquePorTamanho = {'1': 3, '2': 5}
        ..quantidade = 8;

      final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
        produto: p,
        produtoId: 'teste-1',
        documentExists: true,
        forcePushFromCadastro: true,
        gradeBaseline: baseline,
        remoteRevisionAtSaveTime: 0,
        remoteVariacoesAtSaveTime: Map<String, dynamic>.from(remoteVars),
      );

      final vars = intent.definition!['variacoes'] as Map;
      expect(vars['1']['sem-cor'], 3);
      expect(vars['2']['sem-cor']['__custoUnitario'], 3.99);
    });

    test('célula com letras recebe meta sem perder letras', () {
      final out = preserveRemoteVariationCostOnPush(
        push: {
          'P': {
            'sem-cor': {'A': 1, 'B': 2},
          },
        },
        remoteVariacoes: {
          'P': {
            'sem-cor': {'A': 1, 'B': 2, '__custoUnitario': 5.0},
          },
        },
      );
      expect(out['P']['sem-cor'], {'A': 1, 'B': 2, '__custoUnitario': 5.0});
    });
  });

  group('Firestore fake — pull e push reais', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_var_cost_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      final s = DateTime.now().microsecondsSinceEpoch;
      produtosBox = await Hive.openBox<Produto>('p_var_cost_$s');
    });

    tearDown(() async {
      ProdutosFirestoreService.debugFirestoreOverride = null;
      await produtosBox.close();
    });

    DocumentRefHelper doc(String id) => DocumentRefHelper(firestore, id);

    test('syncFirestoreToHive mantém Teste 1 em 31,91', () async {
      await doc('teste-1').set({
        'slug': 'teste-1',
        'id': 'teste-1',
        ..._remoteTeste1(),
      });
      await produtosBox.add(_teste1AposFullSync());

      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: _loja,
        produtosBox: produtosBox,
      );

      final p = produtosBox.values.singleWhere((x) => x.idFirebase == 'teste-1');
      expect(p.quantidade, 9);
      expect(_r2(p.custoTotalEstoque()), 31.91);
      expect(p.custoUnitarioVariacao('1', ''), 2.99);
      expect(p.custoUnitarioVariacao('2', ''), 3.99);
    });

    test('syncFirestoreToHive cura Hive que já tinha perdido o custo', () async {
      await doc('teste-1').set({
        'slug': 'teste-1',
        'id': 'teste-1',
        ..._remoteTeste1(),
      });
      await produtosBox.add(_teste1HiveSemMeta());

      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: _loja,
        produtosBox: produtosBox,
      );

      final p = produtosBox.values.singleWhere((x) => x.idFirebase == 'teste-1');
      expect(_r2(p.custoTotalEstoque()), 31.91);
    });

    test('push de Hive sem meta não apaga __custoUnitario remoto', () async {
      await doc('teste-1').set({
        'slug': 'teste-1',
        'id': 'teste-1',
        ..._remoteTeste1(),
      });

      // Grade igual ao remoto não gera push; baixa local na mesma revisão gera.
      final local = _teste1HiveSemMeta()
        ..variacoes = {
          '1': {'sem-cor': 3},
          '2': {'sem-cor': 5},
        }
        ..estoquePorTamanho = {'1': 3, '2': 5}
        ..quantidade = 8;

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        local,
        lojaId: _loja,
        bumpHiveTimestamp: false,
        enqueueOnFailure: false,
      );

      expect(status, ProdutoSyncRemotoStatus.confirmado);
      final remoto = await doc('teste-1').get();
      final vars = remoto!['variacoes'] as Map;
      expect(
        ProdutoVariacaoExtra.custoUnitarioNaCelula(vars['1']['sem-cor']),
        2.99,
      );
      expect(
        ProdutoVariacaoExtra.custoUnitarioNaCelula(vars['2']['sem-cor']),
        3.99,
      );
      expect(ProdutoVariacaoExtra.somarCelula(vars['1']['sem-cor']), 3);
      expect(ProdutoVariacaoExtra.somarCelula(vars['2']['sem-cor']), 5);
    });
  });
}

class DocumentRefHelper {
  DocumentRefHelper(this.db, this.id);
  final FakeFirebaseFirestore db;
  final String id;

  Future<void> set(Map<String, dynamic> data) => db
      .collection('lojas')
      .doc(_loja)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(id)
      .set(data);

  Future<Map<String, dynamic>?> get() async => (await db
          .collection('lojas')
          .doc(_loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .get())
      .data();
}
