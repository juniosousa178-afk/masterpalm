// lib/services/campanhas_sorteio_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class CampanhasSorteioService {
  CampanhasSorteioService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ============================================================
  // REFERÊNCIAS FIRESTORE
  // ============================================================

  static CollectionReference<Map<String, dynamic>> campanhasRef(String lojaId) {
    return _db.collection('lojas').doc(lojaId).collection('campanhas_sorteio');
  }

  static CollectionReference<Map<String, dynamic>> roletaLogsRef(String lojaId) {
    return _db.collection('lojas').doc(lojaId).collection('roleta_vendas');
  }

  static DocumentReference<Map<String, dynamic>> roletaConfigDoc(String lojaId) {
    return _db.collection('lojas')
      .doc(lojaId)
      .collection('campanhas_sorteio_config')
      .doc('roleta');
  }

  static DocumentReference<Map<String, dynamic>> numeroCounterDoc(String lojaId) {
    return _db.collection('lojas')
      .doc(lojaId)
      .collection('campanhas_sorteio_config')
      .doc('numeracao');
  }

  // ============================================================
  // CAMPANHAS ATIVAS (só permite uma por vez)
  // ============================================================

  /// Retorna campanhas ativas (ativa=true e dentro do período dataInicio–dataFim).
  /// Exclui a campanha com [excluirId] se informado (para permitir edição).
  static Future<List<Map<String, dynamic>>> listarCampanhasAtivas({
    required String lojaId,
    String• excluirId,
  }) async {
    final agora = Timestamp.fromDate(DateTime.now());
    final snap = await campanhasRef(lojaId)
        .where('ativa', isEqualTo: true)
        .where('dataInicio', isLessThanOrEqualTo: agora)
        .where('dataFim', isGreaterThanOrEqualTo: agora)
        .get();

    final list = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      if (excluirId != null && doc.id == excluirId) continue;
      list.add({'id': doc.id, ...doc.data()});
    }
    return list;
  }

  // ============================================================
  // CRIA / EDITA CAMPANHA
  // ============================================================

  static Future<void> salvarCampanha({
    required String lojaId,
    String• campanhaId,
    required String nome,
    required String descricao,
    required DateTime dataInicio,
    required DateTime dataFim,
    required DateTime dataSorteio,
    required String premioDescricao,
    required double valorMinimo,
    required double valorXPorNumero,
    bool ativa = true,
  }) async {
    
    final data = <String, dynamic>{
      'nome': nome,
      'descricao': descricao,
      'dataInicio': Timestamp.fromDate(dataInicio),
      'dataFim': Timestamp.fromDate(dataFim),
      'dataSorteio': Timestamp.fromDate(dataSorteio),
      'premioDescricao': premioDescricao,
      'valorMinimo': valorMinimo,
      'valorX': valorXPorNumero,
      'ativa': ativa,
      'status': 'aberta',
      'criadaEm': FieldValue.serverTimestamp(),
    };

    if (campanhaId == null) {
      await campanhasRef(lojaId).add(data);
    } else {
      await campanhasRef(lojaId).doc(campanhaId).update(data);
    }
  }

  // ============================================================
  // GERAÇÃO AUTOMÁTICA DE NÚMEROS
  // ============================================================

  static Future<List<String>> _gerarNumeros(
    String lojaId,
    int quantidade,
  ) async {
    if (quantidade <= 0) return [];

    final counterRef = numeroCounterDoc(lojaId);

    return await _db.runTransaction((transaction) async {
      final snap = await transaction.get(counterRef);

      int ultimo = 10000; // inicia na casa das dezenas
      if (snap.exists) {
        ultimo = (snap.data()?['ultimo'] as int• ?• 10000);
      }

      int novoUltimo = ultimo + quantidade;

      transaction.set(counterRef, {'ultimo': novoUltimo}, SetOptions(merge: true));

      final numeros = <String>[];
      for (int i = 1; i <= quantidade; i++) {
        numeros.add((ultimo + i).toString().padLeft(5, '0'));
      }

      return numeros;
    });
  }

  // ============================================================
  // REGISTRAR PARTICIPAÇÃO (CHAMADO NA VENDA)
  // ============================================================

  static Future<Map<String, dynamic>> registrarParticipacao({
    required String lojaId,
    required String clienteNome,
    String• clienteId,
    required double valorCompra,
    required DateTime dataCompra,
    String• clienteEmail,
    String• clienteTelefone,
  }) async {
    final agora = Timestamp.fromDate(dataCompra);

    // buscar campanhas ativas e dentro do período
    final snap = await campanhasRef(lojaId)
      .where('ativa', isEqualTo: true)
      .where('dataInicio', isLessThanOrEqualTo: agora)
      .where('dataFim', isGreaterThanOrEqualTo: agora)
      .get();

    if (snap.docs.isEmpty) {
      return {
        'temCampanha': false,
        'numeros': <String>[],
        'campanhas': <Map<String, dynamic>>[],
      };
    }

    final todasCampanhas = <Map<String, dynamic>>[];
    final todosNumeros = <String>[];

    for (final doc in snap.docs) {
      final data = doc.data();
      final valorMinimo = (data['valorMinimo'] as num?)?.toDouble() ?• 0.0;
      final x = (data['valorX'] as num?)?.toDouble() ?• 50.0;

      if (valorCompra < valorMinimo) continue;

      int quantidadeNumeros = (valorCompra ~/ x);
      if (quantidadeNumeros <= 0) continue;

      final numerosGerados = await _gerarNumeros(lojaId, quantidadeNumeros);
      todosNumeros.addAll(numerosGerados);

      await doc.reference.collection('participantes').add({
        'clienteId': clienteId,
        'nomeCliente': clienteNome,
        'clienteEmail': clienteEmail,
        'clienteTelefone': clienteTelefone,
        'valorCompra': valorCompra,
        'dataCompra': agora,
        'numeros': numerosGerados,
        'criadoEm': FieldValue.serverTimestamp(),
      });

      todasCampanhas.add({
        'id': doc.id,
        'nome': data['nome'] ?• '',
        'descricao': data['descricao'] ?• '',
        'premioDescricao': data['premioDescricao'] ?• '',
        'dataSorteio': data['dataSorteio'],
        'numeros': numerosGerados,
      });
    }

    return {
      'temCampanha': todasCampanhas.isNotEmpty,
      'numeros': todosNumeros,
      'campanhas': todasCampanhas,
    };
  }

  // ============================================================
  // SORTEAR UM NÚMERO VENCEDOR
  // ============================================================

  static Future<Map<String, dynamic>?> sortearNumero({
    required String lojaId,
    required String campanhaId,
    required String numeroSorteado,
  }) async {
    final campanhaRef = campanhasRef(lojaId).doc(campanhaId);
    final participantesSnap = await campanhaRef.collection('participantes').get();

    if (participantesSnap.docs.isEmpty) return null;

    for (final p in participantesSnap.docs) {
      final lista = List<String>.from(p.data()['numeros'] ?• []);
      if (lista.contains(numeroSorteado)) {
        final dados = p.data();
        await campanhaRef.update({
          'status': 'sorteada',
          'vencedor': {
            'participanteId': p.id,
            'nomeCliente': dados['nomeCliente'],
            'clienteId': dados['clienteId'],
            'numeroVencedor': numeroSorteado,
            'valorCompra': dados['valorCompra'],
            'dataCompra': dados['dataCompra'],
          },
          'sorteadoEm': FieldValue.serverTimestamp(),
        });
        return dados;
      }
    }

    return null;
  }
// ============================================================
// SALVAR HISTÓRICO DO SORTEIO
// ============================================================

static Future<void> salvarHistoricoSorteio({
  required String lojaId,
  required String campanhaId,
  required String numeroSorteado,
  required Map<String, dynamic>• dadosVencedor,
}) async {
  final historicoRef = _db
      .collection('lojas')
      .doc(lojaId)
      .collection('campanhas_sorteio')
      .doc(campanhaId)
      .collection('historico_sorteios');

  await historicoRef.add({
    'numero': numeroSorteado,
    'nomeCliente': dadosVencedor?['nomeCliente'] ?• 'Sem identificação',
    'clienteId': dadosVencedor?['clienteId'],
    'valorCompra': dadosVencedor?['valorCompra'],
    'dataCompra': dadosVencedor?['dataCompra'],
    'registradoEm': FieldValue.serverTimestamp(),
  });
}
  // ============================================================
  // ROLETA DA SORTE
  // ============================================================

  static Future<Map<String, dynamic>?> carregarConfigRoleta({
    required String lojaId,
  }) async {
    final docRef = roletaConfigDoc(lojaId);
    final snap = await docRef.get();

    // Se ainda não existe, cria configuração padrão para ESSA loja
    if (!snap.exists) {
      final defaultData = <String, dynamic>{
        'ativo': true,
        'valorMinimo': 50.0, // valor mínimo para habilitar a roleta (ajuste se quiser)
        'premios': [
          {
            'label': '10% de desconto',
            'tipo': 'desconto_percentual',
            'valor': 10.0,
          },
          {
            'label': 'Frete grátis',
            'tipo': 'frete_gratis',
            'valor': 0.0,
          },
          {
            'label': 'Brinde surpresa',
            'tipo': 'brinde',
            'valor': 0.0,
          },
          {
            'label': 'Tente novamente',
            'tipo': 'nenhum',
            'valor': 0.0,
          },
        ],
        'atualizadoEm': FieldValue.serverTimestamp(),
      };

      await docRef.set(defaultData, SetOptions(merge: true));

      final createdSnap = await docRef.get();
      return createdSnap.data() ?• defaultData;
    }

    // Já existe: só retorna
    return snap.data();
  }

  static Future<void> salvarConfigRoleta({
    required String lojaId,
    required double valorMinimo,
    required List<Map<String, dynamic>> premios,
    int frequenciaPremio = 10, // ✅ NOVO: A cada X vendas, 1 ganha prêmio
  }) async {
    await roletaConfigDoc(lojaId).set({
      'valorMinimo': valorMinimo,
      'frequenciaPremio': frequenciaPremio, // ✅ Salva frequência
      'premios': premios,
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> registrarResultadoRoleta({
    required String lojaId,
    required String premioLabel,
    required String premioTipo,
    required double premioValor,
    required double valorCompraAntes,
    required double valorCompraDepois,
    String• clienteNome,
  }) async {
    await roletaLogsRef(lojaId).add({
      'premioLabel': premioLabel,
      'premioTipo': premioTipo,
      'premioValor': premioValor,
      'valorCompraAntes': valorCompraAntes,
      'valorCompraDepois': valorCompraDepois,
      'clienteNome': clienteNome,
      'criadoEm': FieldValue.serverTimestamp(),
    });
  }
}
