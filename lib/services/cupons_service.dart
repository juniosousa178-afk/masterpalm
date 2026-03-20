// lib/services/cupons_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/cupom_cliente.dart';
import 'dart:math';

class CuponsService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Gera um código único para o cupom
  static String _gerarCodigo() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    final code = List.generate(
      6,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
    return 'ROLETA-$code';
  }

  static String _gerarCodigoIndicacao() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    final code = List.generate(6, (i) => chars[random.nextInt(chars.length)]).join();
    return 'INDIC-$code';
  }

  /// Cria um cupom para o cliente após ganhar na roleta
  static Future<CupomCliente?> criarCupomRoleta({
    required String lojaId,
    required String clienteId,
    String• clienteNome,
    String• clienteEmail,
    String• clienteWhatsApp,
    required Map<String, dynamic> premio,
    String• campanhaId,
    String• roletaId,
  }) async {
    try {
      // Parse do tipo de prêmio
      final tipoStr = premio['tipo'] as String• ?• 'desconto';
      TipoCupom tipo;
      double• valorDesconto;
      String• brindeDescricao;
      String• premioSurpresaDescricao;
      String titulo;
      String descricao;

      switch (tipoStr) {
        case 'percent':
        case 'desconto':
          tipo = TipoCupom.desconto;
          valorDesconto = (premio['valor'] as num?)?.toDouble() ?• 5.0;
          titulo = '${valorDesconto.toStringAsFixed(0)}% de Desconto';
          descricao = 'Desconto aplicado automaticamente na próxima compra';
          break;

        case 'valor':
        case 'descontoFixo':
          tipo = TipoCupom.descontoFixo;
          valorDesconto = (premio['valor'] as num?)?.toDouble() ?• 10.0;
          titulo = 'R\$ ${valorDesconto.toStringAsFixed(2)} de Desconto';
          descricao = 'Desconto aplicado automaticamente na próxima compra';
          break;

        case 'freteGratis':
          tipo = TipoCupom.freteGratis;
          titulo = 'Frete Grátis';
          descricao = 'Frete zerado na próxima compra';
          break;

        case 'brinde':
          tipo = TipoCupom.brinde;
          brindeDescricao = premio['label'] as String• ?• 'Produto grátis';
          titulo = 'Brinde: $brindeDescricao';
          descricao = 'Brinde será adicionado ao seu pedido';
          break;

        case 'premioSurpresa':
          tipo = TipoCupom.premioSurpresa;
          premioSurpresaDescricao = premio['label'] as String• ?• 'Aguarde a surpresa!';
          titulo = 'Prêmio Surpresa';
          descricao = 'Será revelado na sua próxima compra';
          break;

        default:
          tipo = TipoCupom.desconto;
          valorDesconto = 5.0;
          titulo = '5% de Desconto';
          descricao = 'Desconto aplicado automaticamente na próxima compra';
      }

      final agora = DateTime.now();
      final validade = agora.add(const Duration(days: 60));

      final cupom = CupomCliente(
        id: '', // Será gerado pelo Firestore
        lojaId: lojaId,
        clienteId: clienteId,
        clienteNome: clienteNome,
        clienteEmail: clienteEmail,
        clienteWhatsApp: clienteWhatsApp,
        tipo: tipo,
        codigo: _gerarCodigo(),
        titulo: titulo,
        descricao: descricao,
        valorDesconto: valorDesconto,
        brindeDescricao: brindeDescricao,
        premioSurpresaDescricao: premioSurpresaDescricao,
        dataGanho: agora,
        dataValidade: validade,
        campanhaId: campanhaId,
        roletaId: roletaId,
      );

      // Salva no Firestore
      final docRef = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons_clientes')
          .add(cupom.toMap());

      debugPrint('✅ Cupom criado: ${docRef.id} - ${cupom.titulo}');

      return cupom.copyWith();
    } catch (e) {
      debugPrint('❌ Erro ao criar cupom (type=${e.runtimeType})');
      return null;
    }
  }

  /// Cria os dois cupons do programa de indicação: um para o amigo (quem comprou) e um para o indicador (ativo após o amigo usar o dele).
  static Future<Map<String, String>?> criarCuponsIndicacao({
    required String lojaId,
    required String clienteAmigoId,
    String• clienteAmigoNome,
    String• clienteAmigoEmail,
    String• clienteAmigoWhatsApp,
    required String clienteIndicadorId,
    String• clienteIndicadorNome,
    String• clienteIndicadorEmail,
    String• clienteIndicadorWhatsApp,
    required String tipoDesconto, // 'percentual' | 'valor'
    required double valorDesconto,
    int validadeDias = 60,
  }) async {
    try {
      final agora = DateTime.now();
      final validade = agora.add(Duration(days: validadeDias));
      final tipo = tipoDesconto == 'valor' • TipoCupom.descontoFixo : TipoCupom.desconto;
      final tituloAmigo = tipo == TipoCupom.desconto
          • '${valorDesconto.toStringAsFixed(0)}% de desconto (indicação)'
          : 'R\$ ${valorDesconto.toStringAsFixed(2)} de desconto (indicação)';
      const descricao = 'Válido na próxima compra. Programa de indicação.';

      // 1) Cupom do amigo (quem comprou) – válido na próxima compra; só na primeira compra por indicação
      final codigoAmigo = _gerarCodigoIndicacao();
      final mapAmigo = CupomCliente(
        id: '',
        lojaId: lojaId,
        clienteId: clienteAmigoId,
        clienteNome: clienteAmigoNome,
        clienteEmail: clienteAmigoEmail,
        clienteWhatsApp: clienteAmigoWhatsApp,
        tipo: tipo,
        codigo: codigoAmigo,
        titulo: tituloAmigo,
        descricao: descricao,
        valorDesconto: valorDesconto,
        dataGanho: agora,
        dataValidade: validade,
        ativo: true,
      ).toMap();
      mapAmigo['indicadorId'] = clienteIndicadorId; // para consulta "já ganhou cupom desta indicação?"
      final docRefAmigo = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons_clientes')
          .add(mapAmigo);
      final cupomAmigoId = docRefAmigo.id;

      // 2) Cupom do indicador – ativo só quando o amigo usar o dele
      final codigoIndicador = _gerarCodigoIndicacao();
      final cupomIndicador = CupomCliente(
        id: '',
        lojaId: lojaId,
        clienteId: clienteIndicadorId,
        clienteNome: clienteIndicadorNome,
        clienteEmail: clienteIndicadorEmail,
        clienteWhatsApp: clienteIndicadorWhatsApp,
        tipo: tipo,
        codigo: codigoIndicador,
        titulo: tituloAmigo,
        descricao: 'Seu cupom de indicação será ativado quando seu amigo usar o cupom dele na primeira compra.',
        valorDesconto: valorDesconto,
        dataGanho: agora,
        dataValidade: validade,
        ativo: false,
        cupomAmigoId: cupomAmigoId,
      );
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons_clientes')
          .add(cupomIndicador.toMap());

      debugPrint('✅ Cupons indicação criados: amigo=$cupomAmigoId, indicador aguardando uso');
      return {'cupomAmigoId': cupomAmigoId, 'codigoAmigo': codigoAmigo};
    } catch (e) {
      debugPrint('❌ Erro ao criar cupons indicação (type=${e.runtimeType}): $e');
      return null;
    }
  }

  /// Busca cupons válidos de um cliente
  static Future<List<CupomCliente>> buscarCuponsValidos({
    required String lojaId,
    required String clienteId,
  }) async {
    try {
      final agora = Timestamp.now();

      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons_clientes')
          .where('clienteId', isEqualTo: clienteId)
          .where('usado', isEqualTo: false)
          .where('dataValidade', isGreaterThan: agora)
          .orderBy('dataValidade')
          .get();

      final list = snapshot.docs.map((doc) => CupomCliente.fromDoc(doc)).toList();
      return list.where((c) => c.ativo).toList();
    } catch (e) {
      debugPrint('❌ Erro ao buscar cupons (type=${e.runtimeType})');
      return [];
    }
  }

  /// Busca TODOS os cupons de um cliente (válidos e expirados)
  static Future<List<CupomCliente>> buscarTodosCupons({
    required String lojaId,
    required String clienteId,
  }) async {
    try {
      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons_clientes')
          .where('clienteId', isEqualTo: clienteId)
          .orderBy('dataGanho', descending: true)
          .get();

      return snapshot.docs.map((doc) => CupomCliente.fromDoc(doc)).toList();
    } catch (e) {
      debugPrint('❌ Erro ao buscar cupons (type=${e.runtimeType})');
      return [];
    }
  }

  /// Marca um cupom como usado no pedido.
  /// Cupons de indicação do remetente (quem indicou) só são ativados quando o admin
  /// confirma a venda — use [ativarCuponsIndicacaoPorPedidoConfirmado] nesse momento.
  static Future<bool> usarCupom({
    required String lojaId,
    required String cupomId,
    required String pedidoId,
  }) async {
    try {
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons_clientes')
          .doc(cupomId)
          .update({
        'usado': true,
        'dataUso': FieldValue.serverTimestamp(),
        'pedidoId': pedidoId,
      });
      debugPrint('✅ Cupom $cupomId marcado como usado no pedido $pedidoId');
      return true;
    } catch (e) {
      debugPrint('❌ Erro ao usar cupom (type=${e.runtimeType})');
      return false;
    }
  }

  /// Ativa os cupons de indicação do remetente quando o admin confirma a venda.
  /// Deve ser chamado após o pedido ser confirmado (ex.: em PrePedidoService.confirmarPrePedido).
  /// Busca cupons usados neste pedido e ativa os cupons dos indicadores (cupomAmigoId apontando para eles).
  static Future<void> ativarCuponsIndicacaoPorPedidoConfirmado({
    required String lojaId,
    required String pedidoId,
  }) async {
    try {
      final cuponsUsadosNestePedido = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons_clientes')
          .where('pedidoId', isEqualTo: pedidoId)
          .get();
      for (final doc in cuponsUsadosNestePedido.docs) {
        final cupomAmigoId = doc.id;
        final refs = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection('cupons_clientes')
            .where('cupomAmigoId', isEqualTo: cupomAmigoId)
            .get();
        for (final ref in refs.docs) {
          await ref.reference.update({'ativo': true});
          debugPrint('✅ Cupom indicação ativado: ${ref.id} (venda $pedidoId confirmada pelo admin)');
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao ativar cupons indicação (type=${e.runtimeType})');
    }
  }

  /// Aplica cupons automaticamente no carrinho
  static Future<Map<String, dynamic>> aplicarCuponsAutomaticos({
    required String lojaId,
    required String clienteId,
    required double subtotal,
    required double frete,
    required List<Map<String, dynamic>> itens,
  }) async {
    double descontoTotal = 0.0;
    double freteDesconto = 0.0;
    List<String> cuponsAplicados = [];
    List<Map<String, dynamic>> brindes = [];
    String• mensagemPremioSurpresa;

    try {
      // Busca cupons válidos
      final cupons = await buscarCuponsValidos(
        lojaId: lojaId,
        clienteId: clienteId,
      );

      for (final cupom in cupons) {
        switch (cupom.tipo) {
          case TipoCupom.desconto:
            // Aplica desconto percentual
            final desconto = subtotal * (cupom.valorDesconto! / 100);
            descontoTotal += desconto;
            cuponsAplicados.add(cupom.id);
            debugPrint('✅ Aplicado desconto ${cupom.valorDesconto}%: R\$ ${desconto.toStringAsFixed(2)}');
            break;

          case TipoCupom.descontoFixo:
            // Aplica desconto fixo
            final desconto = cupom.valorDesconto!;
            descontoTotal += desconto;
            cuponsAplicados.add(cupom.id);
            debugPrint('✅ Aplicado desconto fixo: R\$ ${desconto.toStringAsFixed(2)}');
            break;

          case TipoCupom.freteGratis:
            // Zera o frete
            freteDesconto = frete;
            cuponsAplicados.add(cupom.id);
            debugPrint('✅ Aplicado frete grátis: R\$ ${frete.toStringAsFixed(2)}');
            break;

          case TipoCupom.brinde:
            // Adiciona brinde
            brindes.add({
              'nome': cupom.brindeDescricao ?• 'Brinde',
              'quantidade': 1,
              'preco': 0.0,
              'cupomId': cupom.id,
            });
            cuponsAplicados.add(cupom.id);
            debugPrint('✅ Adicionado brinde: ${cupom.brindeDescricao}');
            break;

          case TipoCupom.premioSurpresa:
            // Revela prêmio surpresa
            mensagemPremioSurpresa = cupom.premioSurpresaDescricao ?• 'Você ganhou um prêmio especial!';
            cuponsAplicados.add(cupom.id);
            debugPrint('✅ Prêmio surpresa revelado: $mensagemPremioSurpresa');
            break;
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao aplicar cupons (type=${e.runtimeType})');
    }

    return {
      'descontoTotal': descontoTotal,
      'freteDesconto': freteDesconto,
      'frete': frete - freteDesconto,
      'cuponsAplicados': cuponsAplicados,
      'brindes': brindes,
      'mensagemPremioSurpresa': mensagemPremioSurpresa,
      'total': subtotal - descontoTotal + (frete - freteDesconto),
    };
  }

  /// Remove cupons expirados automaticamente
  static Future<int> limparCuponsExpirados({
    required String lojaId,
  }) async {
    try {
      final agora = Timestamp.now();

      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons_clientes')
          .where('usado', isEqualTo: false)
          .where('dataValidade', isLessThan: agora)
          .get();

      int contador = 0;
      for (final doc in snapshot.docs) {
        await doc.reference.delete();
        contador++;
      }

      debugPrint('✅ Removidos $contador cupons expirados');
      return contador;
    } catch (e) {
      debugPrint('❌ Erro ao limpar cupons expirados (type=${e.runtimeType})');
      return 0;
    }
  }
}
