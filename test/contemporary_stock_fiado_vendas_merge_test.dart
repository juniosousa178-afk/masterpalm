import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regressão contemporânea: o merge de [VendasService] deve preservar
/// Fiado LIVE (040) e o protocolo Stock LOCAL_GREEN no mesmo ficheiro.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/services/vendas_service.dart').readAsStringSync();
  });

  test('preserva settlement remoto PAID / edição quitada (Fiado)', () {
    expect(source.contains('encerrarAbertasPorEdicaoVendaQuitada'), isTrue);
    expect(source.contains('debugAtualizarContasReceberAposEdicaoVenda'), isTrue);
    expect(
      source.contains('mensagemNaoPodeRemoverFiadoComRecebimentosParciais'),
      isTrue,
    );
    expect(source.contains('normalizarCamposFinanceiros'), isTrue);
  });

  test('preserva baixa stock backend / operationId (Estoque)', () {
    expect(source.contains('_pedidoIdPersistidoFromPrePedidoIntent'), isTrue);
    expect(source.contains('usaPedidoPersistidoBackend'), isTrue);
    expect(source.contains('orderSaleOperationId'), isTrue);
    expect(source.contains('baixarEstoquePedidoIdempotente'), isTrue);
    expect(source.contains('montarItensParaBackend'), isTrue);
    expect(source.contains('usaBackendConfiavel'), isTrue);
  });

  test('não contém marcadores de conflito de merge', () {
    expect(source.contains('<<<<<<<'), isFalse);
    expect(source.contains('>>>>>>>'), isFalse);
  });
}
