// lib/services/cupom_desconto_service.dart
// Serviço para gerenciar cupons de desconto com todas as regras de negócio

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/logger.dart';
import '../models/cupom.dart';

class CupomDescontoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Controle para evitar spam de logs de permission-denied
  static bool _permissionDeniedLoggedListarDisponiveis = false;
  static bool _permissionDeniedLoggedListarTodos = false;

  // ========== CRUD ==========

  /// Cria um novo cupom
  /// Retorna null se não tiver permissão
  Future<String?> criarCupom({
    required String lojaId,
    required String codigo,
    required String nome,
    required double valor,
    required String tipo,
    String aplicarEm = 'total',
    List<String>? produtoIds,
    bool freteGratis = false,
    bool usoUnico = false,
    bool usoUnicoGlobal = false,
    String? clienteId,
    DateTime? dataInicio,
    DateTime? dataFim,
    double? valorMinimo,
    int? qtdMaximaUsos,
    String? ownerEmail,
    bool pessoal = false,
  }) async {
    try {
      // Validar código único
      final existe = await _verificarCodigoExiste(lojaId, codigo);
      if (existe) {
        throw Exception('Já existe um cupom com este código');
      }

      final cupom = Cupom(
        id: '', // Será gerado pelo Firestore
        codigo: codigo.toUpperCase().trim(),
        nome: nome,
        valor: valor,
        tipo: tipo,
        aplicarEm: aplicarEm,
        produtoIds: produtoIds ?? const [],
        freteGratis: freteGratis,
        usoUnico: usoUnico,
        usoUnicoGlobal: usoUnicoGlobal,
        clienteId: clienteId,
        ownerEmail: ownerEmail,
        ativo: true,
        dataInicio: dataInicio,
        dataFim: dataFim,
        valorMinimo: valorMinimo,
        qtdMaximaUsos: qtdMaximaUsos,
        criadoEm: DateTime.now(),
      );

      final payload = cupom.toFirestore();
      if (pessoal) payload['pessoal'] = true;

      final docRef = await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons')
          .add(payload);

      logD('✅ Cupom criado: ${docRef.id} - $codigo');
      return docRef.id;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CupomService] Sem permissão para criar cupom');
        return null;
      }
      rethrow;
    }
  }

  /// Cria cupom de vale-compra (devolução)
  /// Retorna null se não tiver permissão
  Future<String?> criarValeCompra({
    required String lojaId,
    required String clienteId,
    required String clienteNome,
    required double valor,
    String? motivoDevolucao,
  }) async {
    final codigo = 'VALE${DateTime.now().millisecondsSinceEpoch}';

    return await criarCupom(
      lojaId: lojaId,
      codigo: codigo,
      nome: 'Vale-Compra - $clienteNome',
      valor: valor,
      tipo: 'fixo',
      aplicarEm: 'total',
      usoUnico: true,
      clienteId: clienteId, // Vinculado ao cliente
      dataInicio: DateTime.now(),
      dataFim: DateTime.now().add(const Duration(days: 365)), // 1 ano
    );
  }

  /// Busca cupom por código
  Future<Cupom?> buscarPorCodigo(String lojaId, String codigo) async {
    try {
      final snapshot = await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons')
          .where('codigo', isEqualTo: codigo.toUpperCase().trim())
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      return Cupom.fromFirestore(snapshot.docs.first);
    } catch (e, st) {
      logE('❌ Erro ao buscar cupom (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Lista cupons disponíveis para um cliente
  /// Retorna stream vazio se não tiver permissão (sem crashar)
  Stream<List<Cupom>> listarDisponiveis(String lojaId, String clienteId) {
    // StreamController para controlar erros de permissão
    final controller = StreamController<List<Cupom>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;

    void startListening() {
      subscription = _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons')
          .where('ativo', isEqualTo: true)
          .limit(50)
          .snapshots()
          .listen(
        (snapshot) {
          // Reset flag se conseguiu conectar
          _permissionDeniedLoggedListarDisponiveis = false;

          final cupons = snapshot.docs
              .map((doc) => Cupom.fromFirestore(doc))
              .where((cupom) {
            // Filtrar apenas cupons que o cliente pode usar
            // Verificação de valor será feita na hora de aplicar

            // Fora da validade
            final agora = DateTime.now();
            if (cupom.dataInicio != null && agora.isBefore(cupom.dataInicio!)) {
              return false;
            }
            if (cupom.dataFim != null && agora.isAfter(cupom.dataFim!)) {
              return false;
            }

            // Cupom específico de outro cliente
            if (cupom.clienteId != null && cupom.clienteId != clienteId) {
              return false;
            }

            // Uso único global já utilizado
            if (cupom.usoUnicoGlobal && cupom.qtdUsosAtuais > 0) {
              return false;
            }

            // Uso único por cliente já utilizado
            if (cupom.usoUnico && cupom.usadosPor.contains(clienteId)) {
              return false;
            }

            // Limite de usos atingido
            if (cupom.qtdMaximaUsos != null &&
                cupom.qtdUsosAtuais >= cupom.qtdMaximaUsos!) {
              return false;
            }

            return true;
          }).toList();

          // Ordenar: vale-compra primeiro, depois por valor
          cupons.sort((a, b) {
            if (a.clienteId != null && b.clienteId == null) return -1;
            if (a.clienteId == null && b.clienteId != null) return 1;
            return b.valor.compareTo(a.valor);
          });

          controller.add(cupons);
        },
        onError: (error) {
          // Tratamento de permission-denied sem spam de logs
          if (error is FirebaseException &&
              error.code == 'permission-denied') {
            if (!_permissionDeniedLoggedListarDisponiveis) {
              _permissionDeniedLoggedListarDisponiveis = true;
              logW('⚠️ [CupomService] Sem permissão para listar cupons disponíveis - retornando lista vazia');
            }
            // Retorna lista vazia ao invés de propagar erro
            controller.add([]);
            // Cancela subscription para evitar retry automático
            subscription?.cancel();
          } else {
            // Outros erros: log e retorna lista vazia
            logE('❌ [CupomService] Erro ao listar cupons (type=${error.runtimeType})', error: error);
            controller.add([]);
          }
        },
        cancelOnError: false,
      );
    }

    controller.onListen = startListening;
    controller.onCancel = () {
      subscription?.cancel();
    };

    return controller.stream.asBroadcastStream();
  }

  /// Lista todos os cupons (admin)
  /// Retorna stream vazio se não tiver permissão (sem crashar)
  Stream<List<Cupom>> listarTodos(String lojaId) {
    final controller = StreamController<List<Cupom>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;

    void startListening() {
      subscription = _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons')
          .orderBy('criadoEm', descending: true)
          .limit(100)
          .snapshots()
          .listen(
        (snapshot) {
          _permissionDeniedLoggedListarTodos = false;
          controller.add(
            snapshot.docs.map((doc) => Cupom.fromFirestore(doc)).toList(),
          );
        },
        onError: (error) {
          if (error is FirebaseException &&
              error.code == 'permission-denied') {
            if (!_permissionDeniedLoggedListarTodos) {
              _permissionDeniedLoggedListarTodos = true;
              logW('⚠️ [CupomService] Sem permissão para listar todos cupons (admin) - retornando lista vazia');
            }
            controller.add([]);
            subscription?.cancel();
          } else {
            logE('❌ [CupomService] Erro ao listar todos cupons (type=${error.runtimeType})', error: error);
            controller.add([]);
          }
        },
        cancelOnError: false,
      );
    }

    controller.onListen = startListening;
    controller.onCancel = () {
      subscription?.cancel();
    };

    return controller.stream.asBroadcastStream();
  }

  /// Atualiza cupom
  /// Retorna false se não tiver permissão
  Future<bool> atualizar(String lojaId, String cupomId,
      Map<String, dynamic> dados) async {
    try {
      await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons')
          .doc(cupomId)
          .update({
        ...dados,
        'atualizadoEm': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CupomService] Sem permissão para atualizar cupom');
        return false;
      }
      rethrow;
    }
  }

  /// Ativa/desativa cupom
  /// Retorna false se não tiver permissão
  Future<bool> toggleAtivo(String lojaId, String cupomId, bool ativo) async {
    return await atualizar(lojaId, cupomId, {'ativo': ativo});
  }

  /// Deleta cupom
  /// Retorna false se não tiver permissão
  Future<bool> deletar(String lojaId, String cupomId) async {
    try {
      await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons')
          .doc(cupomId)
          .delete();

      logD('🗑️ Cupom deletado: $cupomId');
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CupomService] Sem permissão para deletar cupom');
        return false;
      }
      rethrow;
    }
  }

  // ========== VALIDAÇÃO E USO ==========

  /// Valida se cupom pode ser usado
  Future<Map<String, dynamic>> validarCupom({
    required String lojaId,
    required String codigo,
    required String clienteId,
    required double valorPedido,
  }) async {
    final cupom = await buscarPorCodigo(lojaId, codigo);

    if (cupom == null) {
      return {
        'valido': false,
        'erro': 'Cupom não encontrado',
      };
    }

    if (!cupom.podeSerUsado(clienteId, valorPedido)) {
      String erro = 'Cupom não pode ser usado';

      if (!cupom.ativo) {
        erro = 'Cupom inativo';
      } else if (cupom.dataInicio != null &&
          DateTime.now().isBefore(cupom.dataInicio!)) {
        erro = 'Cupom ainda não válido';
      } else if (cupom.dataFim != null &&
          DateTime.now().isAfter(cupom.dataFim!)) {
        erro = 'Cupom expirado';
      } else if (cupom.valorMinimo != null &&
          valorPedido < cupom.valorMinimo!) {
        erro =
            'Valor mínimo de R\$ ${cupom.valorMinimo!.toStringAsFixed(2)} não atingido';
      } else if (cupom.clienteId != null && cupom.clienteId != clienteId) {
        erro = 'Cupom não disponível para este cliente';
      } else if (cupom.usoUnicoGlobal && cupom.qtdUsosAtuais > 0) {
        erro = 'Cupom já foi utilizado';
      } else if (cupom.usoUnico && cupom.usadosPor.contains(clienteId)) {
        erro = 'Você já utilizou este cupom';
      } else if (cupom.qtdMaximaUsos != null &&
          cupom.qtdUsosAtuais >= cupom.qtdMaximaUsos!) {
        erro = 'Limite de usos atingido';
      }

      return {
        'valido': false,
        'erro': erro,
      };
    }

    return {
      'valido': true,
      'cupom': cupom,
    };
  }

  /// Registra uso do cupom
  /// Retorna false se não tiver permissão ou erro
  Future<bool> registrarUso({
    required String lojaId,
    required String cupomId,
    required String clienteId,
  }) async {
    try {
      final cupomRef = _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons')
          .doc(cupomId);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(cupomRef);
        if (!snapshot.exists) {
          throw Exception('Cupom não encontrado');
        }

        final cupom = Cupom.fromFirestore(snapshot);

        // Verificar se já foi usado (proteção contra race condition)
        if (cupom.usoUnico && cupom.usadosPor.contains(clienteId)) {
          throw Exception('Cupom já foi usado por este cliente');
        }

        if (cupom.usoUnicoGlobal && cupom.qtdUsosAtuais > 0) {
          throw Exception('Cupom já foi usado');
        }

        // Atualizar uso
        final usadosPor = List<String>.from(cupom.usadosPor);
        if (!usadosPor.contains(clienteId)) {
          usadosPor.add(clienteId);
        }

        transaction.update(cupomRef, {
          'usadosPor': usadosPor,
          'qtdUsosAtuais': FieldValue.increment(1),
          'atualizadoEm': FieldValue.serverTimestamp(),
        });

        logD('✅ Uso do cupom registrado: $cupomId para cliente $clienteId');
      });
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CupomService] Sem permissão para registrar uso do cupom');
        return false;
      }
      rethrow;
    }
  }

  /// Desfaz uso do cupom (em caso de cancelamento de pedido)
  /// Retorna false se não tiver permissão
  Future<bool> desfazerUso({
    required String lojaId,
    required String cupomId,
    required String clienteId,
  }) async {
    try {
      final cupomRef = _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons')
          .doc(cupomId);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(cupomRef);
        if (!snapshot.exists) return;

        final cupom = Cupom.fromFirestore(snapshot);

        final usadosPor = List<String>.from(cupom.usadosPor);
        usadosPor.remove(clienteId);

        transaction.update(cupomRef, {
          'usadosPor': usadosPor,
          'qtdUsosAtuais': FieldValue.increment(-1),
          'atualizadoEm': FieldValue.serverTimestamp(),
        });

        logD('↩️ Uso do cupom desfeito: $cupomId para cliente $clienteId');
      });
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CupomService] Sem permissão para desfazer uso do cupom');
        return false;
      }
      rethrow;
    }
  }

  // ========== HELPERS ==========

  Future<bool> _verificarCodigoExiste(String lojaId, String codigo) async {
    try {
      final snapshot = await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('cupons')
          .where('codigo', isEqualTo: codigo.toUpperCase().trim())
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CupomService] Sem permissão para verificar código do cupom');
        return false; // Assume que não existe para permitir tentativa de criar
      }
      rethrow;
    }
  }
}
