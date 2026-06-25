// Compatibilidade Hive: produtos gravados antes de @HiveField(47) sku.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive/src/binary/binary_reader_impl.dart';
import 'package:hive/src/binary/binary_writer_impl.dart';
import 'package:master_palm/models/produto.dart';

/// Serializa [Produto] no formato legado (47 campos, sem HiveField 47 / sku).
Uint8List writeLegacyProdutoBinary(Produto obj) {
  final writer = BinaryWriterImpl(Hive);
  writer
    ..writeByte(47)
    ..writeByte(0)
    ..write(obj.nome)
    ..writeByte(1)
    ..write(obj.custoReal)
    ..writeByte(2)
    ..write(obj.frete)
    ..writeByte(3)
    ..write(obj.gastosFixos)
    ..writeByte(4)
    ..write(obj.gastosVariaveis)
    ..writeByte(5)
    ..write(obj.precoSugerido)
    ..writeByte(6)
    ..write(obj.precoFinal)
    ..writeByte(7)
    ..write(obj.quantidade)
    ..writeByte(8)
    ..write(obj.precoUnitario)
    ..writeByte(9)
    ..write(obj.categoria)
    ..writeByte(10)
    ..write(obj.dataEntrada)
    ..writeByte(11)
    ..write(obj.descricao)
    ..writeByte(12)
    ..write(obj.imagens)
    ..writeByte(13)
    ..write(obj.publicadoNoCatalogo)
    ..writeByte(14)
    ..write(obj.slug)
    ..writeByte(15)
    ..write(obj.tamanhos)
    ..writeByte(16)
    ..write(obj.subcategoria)
    ..writeByte(17)
    ..write(obj.estoquePorTamanho)
    ..writeByte(28)
    ..write(obj.cores)
    ..writeByte(18)
    ..write(obj.ativoNoRascunho)
    ..writeByte(19)
    ..write(obj.idFirebase)
    ..writeByte(20)
    ..write(obj.lojaId)
    ..writeByte(21)
    ..write(obj.emPromocao)
    ..writeByte(22)
    ..write(obj.percentualPromo)
    ..writeByte(23)
    ..write(obj.valorPromo)
    ..writeByte(24)
    ..write(obj.dataInicioPromo)
    ..writeByte(25)
    ..write(obj.dataFimPromo)
    ..writeByte(26)
    ..write(obj.peso)
    ..writeByte(27)
    ..write(obj.tipoEmbalagem)
    ..writeByte(29)
    ..write(obj.marketplaces)
    ..writeByte(30)
    ..write(obj.variacoes)
    ..writeByte(43)
    ..write(obj.variacoesExtraTipo)
    ..writeByte(31)
    ..write(obj.divideSemJuros)
    ..writeByte(32)
    ..write(obj.percentualDescontoPix)
    ..writeByte(33)
    ..write(obj.maxParcelasSemJuros)
    ..writeByte(34)
    ..write(obj.videoUrl)
    ..writeByte(35)
    ..write(obj.codigoBarras)
    ..writeByte(36)
    ..write(obj.estoqueMinimo)
    ..writeByte(37)
    ..write(obj.precoPorTamanho)
    ..writeByte(38)
    ..write(obj.tipoProduto)
    ..writeByte(39)
    ..write(obj.itensCombo)
    ..writeByte(44)
    ..write(obj.comboConfig)
    ..writeByte(40)
    ..write(obj.updatedAt)
    ..writeByte(41)
    ..write(obj.custoEditadoNoCadastro)
    ..writeByte(42)
    ..write(obj.fornecedor)
    ..writeByte(45)
    ..write(obj.categoriasExtras)
    ..writeByte(46)
    ..write(obj.subcategoriasExtras);
  return Uint8List.fromList(writer.toBytes());
}

void main() {
  late String hivePath;
  late Box<Produto> box;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_legacy_sku_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    final s = DateTime.now().microsecondsSinceEpoch;
    box = await Hive.openBox<Produto>('legacy_sku_$s');
  });

  tearDown(() async {
    await box.close();
  });

  test('fixture legada (sem HiveField 47) abre com adapter atual', () async {
    const lojaId = 'loja-legacy-hive';
    final entrada = DateTime(2024, 3, 15, 10, 30);
    final legacy = Produto(
      nome: 'Anel Coração Legado',
      custoReal: 12.5,
      frete: 1.0,
      gastosFixos: 0.5,
      gastosVariaveis: 0.25,
      precoSugerido: 30,
      precoFinal: 35.9,
      quantidade: 7,
      precoUnitario: 35.9,
      categoria: 'Anéis',
      subcategoria: 'Prata',
      dataEntrada: entrada,
      descricao: 'Produto gravado antes do campo sku',
      imagens: ['https://cdn.example.com/anel.jpg'],
      slug: '$lojaId-anel-coracao-legado',
      idFirebase: '$lojaId-anel-coracao-legado',
      lojaId: lojaId,
      codigoBarras: '7890123456789',
      tamanhos: ['16', '18'],
      estoquePorTamanho: {'16': 3, '18': 4},
      cores: ['rose'],
      variacoes: {
        'T::16': {'cor': 'rose', 'estoque': 3},
        'T::18': {'cor': 'rose', 'estoque': 4},
      },
      fornecedor: 'Fornecedor Legado',
      custoEditadoNoCadastro: true,
    );
    // sku permanece default '' — simula app antigo.

    final bytes = writeLegacyProdutoBinary(legacy);
    final adapter = ProdutoAdapter();
    final lido = adapter.read(BinaryReaderImpl(bytes, Hive));

    expect(lido.nome, legacy.nome);
    expect(lido.custoReal, legacy.custoReal);
    expect(lido.quantidade, 7);
    expect(lido.categoria, 'Anéis');
    expect(lido.subcategoria, 'Prata');
    expect(lido.codigoBarras, '7890123456789');
    expect(lido.slug, '$lojaId-anel-coracao-legado');
    expect(lido.idFirebase, '$lojaId-anel-coracao-legado');
    expect(lido.lojaId, lojaId);
    expect(lido.estoquePorTamanho['16'], 3);
    expect(lido.estoquePorTamanho['18'], 4);
    expect(lido.variacoes?['T::16'], isNotNull);
    expect(lido.sku, '');
    expect(lido.imagens, ['https://cdn.example.com/anel.jpg']);
    expect(lido.fornecedor, 'Fornecedor Legado');

    await box.put('legacy-key', lido);
    final roundTrip = box.get('legacy-key')!;
    expect(roundTrip.sku, '');
    expect(roundTrip.nome, legacy.nome);
    expect(roundTrip.codigoBarras, legacy.codigoBarras);
    expect(roundTrip.quantidade, legacy.quantidade);
    expect(roundTrip.slug, legacy.slug);
    expect(roundTrip.idFirebase, legacy.idFirebase);

    await roundTrip.save();
    final afterSave = box.get('legacy-key')!;
    expect(afterSave.nome, legacy.nome);
    expect(afterSave.sku, '');
    expect(afterSave.estoquePorTamanho['18'], 4);
  });
}
