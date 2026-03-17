import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class NumeroSorteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Verifica se existe campanha ativa para a loja
  static Future<Map<String, dynamic>?> getCampanhaAtiva(String lojaId) async {
    try {
      final now = DateTime.now();

      final querySnap = await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .where('ativo', isEqualTo: true)
          .where('dataInicio', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .where('dataFim', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
          .limit(1)
          .get();

      if (querySnap.docs.isEmpty) return null;

      final doc = querySnap.docs.first;
      return {
        'id': doc.id,
        ...doc.data(),
      };
    } catch (e) {
      debugPrint('❌ Erro ao buscar campanha ativa (type=${e.runtimeType})');
      return null;
    }
  }

  /// Gera um número único da sorte para o cliente
  static Future<String> gerarNumeroSorte(
    String lojaId,
    String campanhaId,
  ) async {
    try {
      // Buscar último número gerado
      final participantesSnap = await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .doc(campanhaId)
          .collection('participantes')
          .orderBy('numeroSorte', descending: true)
          .limit(1)
          .get();

      int proximoNumero = 1;

      if (participantesSnap.docs.isNotEmpty) {
        final ultimoNumero = participantesSnap.docs.first.data()['numeroSorte'] as String?;
        if (ultimoNumero != null) {
          final numeroInt = int.tryParse(ultimoNumero) ?? 0;
          proximoNumero = numeroInt + 1;
        }
      }

      // Formatar com zeros à esquerda (ex: 00001, 00002, ...)
      return proximoNumero.toString().padLeft(5, '0');
    } catch (e) {
      debugPrint('❌ Erro ao gerar número da sorte (type=${e.runtimeType})');
      // Fallback: gerar número aleatório
      final random = Random();
      final numero = random.nextInt(99999) + 1;
      return numero.toString().padLeft(5, '0');
    }
  }

  /// Salva o número da sorte no histórico da campanha
  static Future<void> salvarParticipante({
    required String lojaId,
    required String campanhaId,
    required String numeroSorte,
    required String clienteNome,
    required String clienteEmail,
    required String clienteTelefone,
    required String pedidoId,
    required double valorPedido,
  }) async {
    try {
      await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .doc(campanhaId)
          .collection('participantes')
          .add({
        'numeroSorte': numeroSorte,
        'clienteNome': clienteNome,
        'clienteEmail': clienteEmail,
        'clienteTelefone': clienteTelefone,
        'pedidoId': pedidoId,
        'valorPedido': valorPedido,
        'dataParticipacao': FieldValue.serverTimestamp(),
        'sorteado': false,
      });

      debugPrint('✅ Participante salvo: $clienteNome - Número: $numeroSorte');
    } catch (e) {
      debugPrint('❌ Erro ao salvar participante (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Envia o número da sorte por WhatsApp
  static String gerarMensagemWhatsApp({
    required String clienteNome,
    required String numeroSorte,
    required String nomeCampanha,
    required DateTime dataFim,
  }) {
    return '''
🎉 *Parabéns ${clienteNome.split(' ').first}!*

Você ganhou um número da sorte! 🍀

🎫 *Seu número:* $numeroSorte

📢 *Campanha:* $nomeCampanha
📅 *Sorteio:* ${dataFim.day.toString().padLeft(2, '0')}/${dataFim.month.toString().padLeft(2, '0')}/${dataFim.year}

Boa sorte! 🎊
''';
  }

  /// Envia o número da sorte por Email (HTML)
  static String gerarEmailHtml({
    required String clienteNome,
    required String numeroSorte,
    required String nomeCampanha,
    required DateTime dataFim,
  }) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; background: #f5f5f5; padding: 20px; }
    .container { background: white; padding: 30px; border-radius: 10px; max-width: 600px; margin: 0 auto; }
    .header { text-align: center; color: #4CAF50; }
    .numero { font-size: 48px; font-weight: bold; color: #FF5722; text-align: center; padding: 20px; background: #FFF3E0; border-radius: 10px; margin: 20px 0; }
    .info { background: #E3F2FD; padding: 15px; border-radius: 5px; margin: 15px 0; }
    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🎉 Parabéns!</h1>
      <p>Você ganhou um número da sorte!</p>
    </div>

    <p>Olá <strong>${clienteNome.split(' ').first}</strong>,</p>

    <p>Sua compra foi confirmada e você foi automaticamente inscrito no sorteio!</p>

    <div class="numero">
      🎫 $numeroSorte
    </div>

    <div class="info">
      <p><strong>📢 Campanha:</strong> $nomeCampanha</p>
      <p><strong>📅 Data do Sorteio:</strong> ${dataFim.day.toString().padLeft(2, '0')}/${dataFim.month.toString().padLeft(2, '0')}/${dataFim.year}</p>
    </div>

    <p style="text-align: center; margin-top: 30px;">
      <strong>Boa sorte! 🍀</strong>
    </p>

    <div class="footer">
      <p>Esta é uma mensagem automática, por favor não responda.</p>
    </div>
  </div>
</body>
</html>
''';
  }

  /// Busca todos os participantes de uma campanha para o sorteio
  static Future<List<Map<String, dynamic>>> getParticipantes(
    String lojaId,
    String campanhaId,
  ) async {
    try {
      final snap = await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .doc(campanhaId)
          .collection('participantes')
          .orderBy('numeroSorte')
          .get();

      return snap.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Erro ao buscar participantes (type=${e.runtimeType})');
      return [];
    }
  }

  /// Busca participantes com data de participação (mesmo critério do Histórico).
  /// Usar no Globo para que a contagem e a lista batam com a aba "Participantes" do Histórico.
  static Future<List<Map<String, dynamic>>> getParticipantesParaSorteio(
    String lojaId,
    String campanhaId,
  ) async {
    try {
      final snap = await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .doc(campanhaId)
          .collection('participantes')
          .orderBy('dataParticipacao', descending: true)
          .limit(500)
          .get();

      return snap.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Erro ao buscar participantes para sorteio (type=${e.runtimeType})');
      return [];
    }
  }

  /// Marca um participante como sorteado
  static Future<void> marcarComoSorteado({
    required String lojaId,
    required String campanhaId,
    required String participanteId,
  }) async {
    try {
      await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .doc(campanhaId)
          .collection('participantes')
          .doc(participanteId)
          .update({
        'sorteado': true,
        'dataSorteio': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Participante marcado como sorteado: $participanteId');
    } catch (e) {
      debugPrint('❌ Erro ao marcar como sorteado (type=${e.runtimeType})');
      rethrow;
    }
  }
}
