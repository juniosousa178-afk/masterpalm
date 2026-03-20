// lib/services/cliente_web_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cliente_web.dart';
import 'firestore_paths.dart';

/// Serviço de autenticação e gerenciamento de clientes do catálogo web
class ClienteWebService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Chaves para SharedPreferences
  static const String _keyClienteId = 'cliente_web_id';
  static const String _keyLojaId = 'cliente_web_loja_id';

  static DateTime? _pedidoDataCriacao(Map<String, dynamic> pedido) {
    for (final key in const ['dataCriacao', 'criadoEm', 'createdAt']) {
      final value = pedido[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
    }
    return null;
  }

  // ============================================================================
  // AUTENTICAÇÃO
  // ============================================================================

  /// Retorna o cliente atualmente autenticado (se houver)
  static Future<ClienteWeb?> getClienteAutenticado(String lojaId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clienteId = prefs.getString(_keyClienteId);
      final lojaIdSalva = prefs.getString(_keyLojaId);

      // Verifica se é da mesma loja
      if (clienteId == null || lojaIdSalva != lojaId) {
        return null;
      }

      final doc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesWebCol)
          .doc(clienteId)
          .get();

      if (!doc.exists) {
        await logout(); // Cliente não existe mais, fazer logout
        return null;
      }

      return ClienteWeb.fromMap(doc.data()!, doc.id);
    } catch (e) {
      debugPrint('❌ Erro ao buscar cliente autenticado (type=${e.runtimeType})');
      return null;
    }
  }

  /// Faz login ou cadastro do cliente
  ///
  /// Se o email já existe, faz login
  /// Se não existe, cria novo cliente
  static Future<ClienteWeb?> loginOuCadastro({
    required String lojaId,
    required String nome,
    required String email,
    String? telefone,
    String? cpf,
  }) async {
    try {
      // Buscar cliente existente pelo email
      final querySnapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesWebCol)
          .where('email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();

      ClienteWeb cliente;

      if (querySnapshot.docs.isNotEmpty) {
        // Cliente já existe - fazer login
        final doc = querySnapshot.docs.first;
        cliente = ClienteWeb.fromMap(doc.data(), doc.id);

        // Atualizar dados básicos se mudaram
        if (cliente.nome != nome || cliente.telefone != telefone || cliente.cpf != cpf) {
          cliente = cliente.copyWith(
            nome: nome,
            telefone: telefone,
            cpf: cpf,
          );
          await doc.reference.update(cliente.toMap());
        }

        debugPrint('✅ Login realizado: ${cliente.email}');
      } else {
        // Cliente novo - criar cadastro
        final novoCliente = ClienteWeb(
          id: '', // Será definido pelo Firestore
          nome: nome,
          email: email.trim().toLowerCase(),
          telefone: telefone,
          cpf: cpf,
        );

        final docRef = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.clientesWebCol)
            .add(novoCliente.toMap());

        cliente = ClienteWeb(
          id: docRef.id,
          nome: nome,
          email: email.trim().toLowerCase(),
          telefone: telefone,
          cpf: cpf,
        );

        debugPrint('✅ Cliente cadastrado: ${cliente.email}');
      }

      // Salvar sessão
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyClienteId, cliente.id);
      await prefs.setString(_keyLojaId, lojaId);

      return cliente;
    } catch (e) {
      debugPrint('❌ Erro ao fazer login/cadastro (type=${e.runtimeType})');
      return null;
    }
  }

  /// Faz logout do cliente
  static Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyClienteId);
      await prefs.remove(_keyLojaId);
      debugPrint('✅ Logout realizado');
    } catch (e) {
      debugPrint('❌ Erro ao fazer logout (type=${e.runtimeType})');
    }
  }

  // ============================================================================
  // PERFIL
  // ============================================================================

  /// Atualiza dados do cliente
  static Future<bool> atualizarPerfil({
    required String lojaId,
    required String clienteId,
    String? nome,
    String? telefone,
    String? cpf,
    String? cep,
    String? endereco,
    String? numero,
    String? complemento,
    String? bairro,
    String? cidade,
    String? estado,
  }) async {
    try {
      final updates = <String, dynamic>{
        'atualizadoEm': FieldValue.serverTimestamp(),
      };

      if (nome != null) updates['nome'] = nome;
      if (telefone != null) updates['telefone'] = telefone;
      if (cpf != null) updates['cpf'] = cpf;
      if (cep != null) updates['cep'] = cep;
      if (endereco != null) updates['endereco'] = endereco;
      if (numero != null) updates['numero'] = numero;
      if (complemento != null) updates['complemento'] = complemento;
      if (bairro != null) updates['bairro'] = bairro;
      if (cidade != null) updates['cidade'] = cidade;
      if (estado != null) updates['estado'] = estado;

      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesWebCol)
          .doc(clienteId)
          .update(updates);

      debugPrint('✅ Perfil atualizado');
      return true;
    } catch (e) {
      debugPrint('❌ Erro ao atualizar perfil (type=${e.runtimeType})');
      return false;
    }
  }

  // ============================================================================
  // CUPONS
  // ============================================================================

  /// Adiciona um cupom ao cliente
  static Future<bool> adicionarCupom({
    required String lojaId,
    required String clienteId,
    required String codigo,
    required double desconto,
    required DateTime dataExpiracao,
    String? origem,
  }) async {
    try {
      final cliente = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesWebCol)
          .doc(clienteId)
          .get();

      if (!cliente.exists) return false;

      final cupons = List<Map<String, dynamic>>.from(
        cliente.data()?['cupons'] ?? []
      );

      // Verifica se cupom já existe
      final jaExiste = cupons.any((c) => c['codigo'] == codigo);
      if (jaExiste) {
        debugPrint('⚠️ Cupom $codigo já existe para este cliente');
        return false;
      }

      // Adiciona novo cupom
      cupons.add({
        'codigo': codigo,
        'desconto': desconto,
        'dataExpiracao': Timestamp.fromDate(dataExpiracao),
        'usado': false,
        'dataUso': null,
        'origem': origem,
      });

      await cliente.reference.update({
        'cupons': cupons,
        'atualizadoEm': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Cupom $codigo adicionado ao cliente');
      return true;
    } catch (e) {
      debugPrint('❌ Erro ao adicionar cupom (type=${e.runtimeType})');
      return false;
    }
  }

  /// Marca um cupom como usado
  static Future<bool> usarCupom({
    required String lojaId,
    required String clienteId,
    required String codigo,
  }) async {
    try {
      final cliente = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesWebCol)
          .doc(clienteId)
          .get();

      if (!cliente.exists) return false;

      final cupons = List<Map<String, dynamic>>.from(
        cliente.data()?['cupons'] ?? []
      );

      // Encontra e marca cupom como usado
      bool encontrado = false;
      for (var i = 0; i < cupons.length; i++) {
        if (cupons[i]['codigo'] == codigo) {
          cupons[i]['usado'] = true;
          cupons[i]['dataUso'] = Timestamp.now();
          encontrado = true;
          break;
        }
      }

      if (!encontrado) {
        debugPrint('⚠️ Cupom $codigo não encontrado');
        return false;
      }

      await cliente.reference.update({
        'cupons': cupons,
        'atualizadoEm': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Cupom $codigo marcado como usado');
      return true;
    } catch (e) {
      debugPrint('❌ Erro ao usar cupom (type=${e.runtimeType})');
      return false;
    }
  }

  /// Retorna cupom válido do cliente (se houver)
  ///
  /// Retorna o primeiro cupom não usado e não expirado
  static Future<CupomCliente?> getCupomValido({
    required String lojaId,
    required String clienteId,
  }) async {
    try {
      final cliente = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesWebCol)
          .doc(clienteId)
          .get();

      if (!cliente.exists) return null;

      final clienteObj = ClienteWeb.fromMap(cliente.data()!, cliente.id);
      final cuponsValidos = clienteObj.cuponsValidos;

      if (cuponsValidos.isEmpty) return null;

      // Retorna o cupom com maior desconto
      cuponsValidos.sort((a, b) => b.desconto.compareTo(a.desconto));
      return cuponsValidos.first;
    } catch (e) {
      debugPrint('❌ Erro ao buscar cupom válido (type=${e.runtimeType})');
      return null;
    }
  }

  // ============================================================================
  // HISTÓRICO
  // ============================================================================

  /// Retorna pedidos do cliente
  static Future<List<Map<String, dynamic>>> getPedidos({
    required String lojaId,
    required String clienteId,
  }) async {
    try {
      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('pre_pedidos')
          .where('cliente.id', isEqualTo: clienteId)
            .orderBy('dataCriacao', descending: true)
          .limit(50)
          .get();

      final pedidos = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      pedidos.sort((a, b) {
        final dtA = _pedidoDataCriacao(a);
        final dtB = _pedidoDataCriacao(b);
        if (dtA != null && dtB != null) return dtB.compareTo(dtA);
        if (dtA != null) return -1;
        if (dtB != null) return 1;
        return 0;
      });
      return pedidos;
    } catch (e) {
      debugPrint('❌ Erro ao buscar pedidos (type=${e.runtimeType})');
      return [];
    }
  }
}
