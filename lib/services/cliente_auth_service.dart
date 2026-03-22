import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logger.dart';
import '../repositories/cliente_portal_repository.dart';
import 'firestore_paths.dart';
import '../repositories/meus_pedidos_repository.dart';
import 'email_service.dart';
import 'cliente_auth_helpers.dart';

/// Serviço de autenticação EXCLUSIVO para clientes do catálogo (quem compra na loja).
///
/// FONTE PRINCIPAL (FASE 4): Usa lojas/{lojaId}/clientes como identidade.
/// Ver docs/MAPA_CLIENTES_E_PATHS.md.
///
/// ═══════════════════════════════════════════════════════════════════════════
/// 🔒 SEPARAÇÃO OBRIGATÓRIA: cadastro/login do cliente no catálogo NÃO PODE ter
///    nada a ver com o cadastro ou uso do APK/app web (dono da loja).
/// ═══════════════════════════════════════════════════════════════════════════
///
/// ? Cliente (catálogo): usa apenas lojas/{lojaId}/clientes + SharedPreferences
///   (cliente_logado, cliente_loja_id). NÃO usa Firebase Auth, NÃO escreve em
///   users/ nem usuarios/.
/// ? Dono da loja (APK/web): usa Firebase Auth + users/{uid} + usuarios/{email}
///   + StoreResolverService. NUNCA usar dados de cliente do catálogo para loja.
///
/// Assim, um mesmo email pode ser dono de uma loja (admin) e cliente em outra,
/// sem mistura de sessões ou dados.
class ClienteAuthService {
  static const String _keyClienteLogado = 'cliente_logado';
  static const String _keyLojaId = 'cliente_loja_id';
  static final ClientePortalRepository _clientePortalRepository =
      ClientePortalRepository();
  static final MeusPedidosRepository _meusPedidosRepository =
      MeusPedidosRepository();

  /// Cadastrar novo cliente
  static Future<Map<String, dynamic>> cadastrar({
    required String lojaId,
    required String nome,
    required String email,
    required String senha,
    String? telefone,
  }) async {
    try {
      // Verificar se email já existe
      final existe = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCol)
          .where('email', isEqualTo: email.toLowerCase().trim())
          .limit(1)
          .get();

      if (existe.docs.isNotEmpty) {
        return {
          'success': false,
          'error': 'Este email já está cadastrado. Faça login.',
        };
      }

      // Criar novo cliente
      final clienteId = gerarClienteId();
      final senhaHash = hashSenha(senha);

      final dadosCliente = {
        'id': clienteId,
        'nome': nome.trim(),
        'email': email.toLowerCase().trim(),
        'senhaHash': senhaHash,
        'telefone': telefone?.trim() ?? '',
        'portalToken': gerarPortalToken(),
        'dataCadastro': FieldValue.serverTimestamp(),
        'cupons': [],
        'pedidos': [],
        'favoritos': [],
        'ativo': true,
      };

      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCol)
          .doc(clienteId)
          .set(dadosCliente);

      // Salvar sessão
      await _salvarSessao(lojaId, clienteId, dadosCliente);

      return {
        'success': true,
        'clienteId': clienteId,
        'nome': nome,
        'email': email,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Erro ao cadastrar: $e',
      };
    }
  }

  /// Fazer login
  static Future<Map<String, dynamic>> login({
    required String lojaId,
    required String email,
    required String senha,
  }) async {
    try {
      // Buscar cliente por email
      final resultado = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCol)
          .where('email', isEqualTo: email.toLowerCase().trim())
          .limit(1)
          .get();

      if (resultado.docs.isEmpty) {
        return {
          'success': false,
          'error': 'Email não encontrado.',
        };
      }

      final clienteDoc = resultado.docs.first;
      final dados = clienteDoc.data();

      // Verificar se está ativo
      if (dados['ativo'] == false) {
        return {
          'success': false,
          'error': 'Conta desativada. Entre em contato com a loja.',
        };
      }

      // Verificar senha (senhaHash no Firestore é por loja; comparação em string)
      final senhaHash = hashSenha(senha);
      final hashSalvo = (dados['senhaHash'] ?? '').toString().trim();
      if (hashSalvo.isEmpty || hashSalvo != senhaHash) {
        return {
          'success': false,
          'error': 'Senha incorreta.',
        };
      }

      final portalToken = await _ensurePortalToken(
        lojaId: lojaId,
        clienteId: clienteDoc.id,
        dados: dados,
      );
      dados['portalToken'] = portalToken;

      // Salvar sessão
      await _salvarSessao(lojaId, clienteDoc.id, dados);

      return {
        'success': true,
        'clienteId': clienteDoc.id,
        'nome': dados['nome'],
        'email': dados['email'],
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Erro ao fazer login: $e',
      };
    }
  }

  /// Salvar sessão localmente
  static Future<void> _salvarSessao(
    String lojaId,
    String clienteId,
    Map<String, dynamic> dados,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLojaId, lojaId);
    await prefs.setString(
      _keyClienteLogado,
      json.encode({
        'clienteId': clienteId,
        'nome': dados['nome'],
        'email': dados['email'],
        'telefone': dados['telefone'] ?? '',
        'portalToken': dados['portalToken'] ?? '',
      }),
    );
  }

  /// Obtém portalToken dos dados ou via CF getDadosCompletos (a CF cria o token se faltar).
  /// Não faz update direto em clientes — regras exigem portalToken na escrita; token é criado no servidor.
  static Future<String> _ensurePortalToken({
    required String lojaId,
    required String clienteId,
    required Map<String, dynamic> dados,
  }) async {
    final existente = (dados['portalToken'] ?? '').toString().trim();
    if (existente.isNotEmpty) return existente;

    final email = (dados['email'] ?? '').toString().trim().toLowerCase();
    if (email.isEmpty) return '';

    try {
      final d = await getDadosCompletos(lojaId: lojaId, clienteId: clienteId, email: email);
      final token = (d?['portalToken'] ?? '').toString().trim();
      if (token.isNotEmpty && d != null) dados['portalToken'] = token;
      return token;
    } catch (_) {
      return '';
    }
  }

  /// Obter cliente logado
  static Future<Map<String, dynamic>?> getClienteLogado() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dadosJson = prefs.getString(_keyClienteLogado);

      if (dadosJson == null) return null;

      return json.decode(dadosJson) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Obter ID da loja do cliente logado
  static Future<String?> getLojaId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyLojaId);
    } catch (e) {
      return null;
    }
  }

  /// Verificar se está logado
  static Future<bool> isLogado() async {
    final cliente = await getClienteLogado();
    return cliente != null;
  }

  /// Fazer logout
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyClienteLogado);
    await prefs.remove(_keyLojaId);
  }

  /// Atualizar dados do cliente
  static Future<Map<String, dynamic>> atualizarDados({
    required String lojaId,
    required String clienteId,
    String? nome,
    String? email,
    String? telefone,
    Map<String, dynamic>? endereco,
  }) async {
    try {
      final updates = <String, dynamic>{};

      if (nome != null) updates['nome'] = nome.trim();
      if (telefone != null) updates['telefone'] = telefone.trim();
      if (endereco != null) updates['endereco'] = endereco;

      // Se está mudando o email, verificar se já não existe outro cliente com esse email
      if (email != null && email.trim().isNotEmpty) {
        final emailNormalizado = email.toLowerCase().trim();

        // Buscar se existe outro cliente com esse email
        final existe = await FirebaseFirestore.instance
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.clientesCol)
            .where('email', isEqualTo: emailNormalizado)
            .limit(1)
            .get();

        // Se encontrou um documento e não é o próprio cliente
        if (existe.docs.isNotEmpty && existe.docs.first.id != clienteId) {
          return {
            'success': false,
            'error': 'Este email já está sendo usado por outro cliente.',
          };
        }

        updates['email'] = emailNormalizado;
      }

      if (updates.isEmpty) {
        return {'success': true};
      }

      final cliente = await getClienteLogado();
      final portalToken = (cliente?['portalToken'] ?? '').toString().trim();
      if (portalToken.isEmpty) {
        return {'success': false, 'error': 'Sessão inválida. Faça login novamente.'};
      }
      updates['portalToken'] = portalToken;

      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCol)
          .doc(clienteId)
          .update(updates);

      // Atualizar sessão local se mudou nome, email ou telefone
      if (cliente != null) {
        if (nome != null) cliente['nome'] = nome.trim();
        if (email != null) cliente['email'] = email.toLowerCase().trim();
        if (telefone != null) cliente['telefone'] = telefone.trim();
        if ((cliente['portalToken'] ?? '').toString().trim().isEmpty) {
          final portalToken = await _ensurePortalToken(
            lojaId: lojaId,
            clienteId: clienteId,
            dados: updates,
          );
          cliente['portalToken'] = portalToken;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyClienteLogado, json.encode(cliente));
      }

      return {'success': true};
    } catch (e, st) {
      logE('Erro ao atualizar dados (type=${e.runtimeType})', error: e, st: st);
      return {'success': false, 'error': 'Erro ao atualizar dados: $e'};
    }
  }

  /// Adiciona ou remove produto dos favoritos
  static Future<Map<String, dynamic>> toggleFavorito({
    required String lojaId,
    required String clienteId,
    required String email,
    required String productId,
  }) async {
    try {
      final dados = await getDadosCompletos(
        lojaId: lojaId,
        clienteId: clienteId,
        email: email,
      );
      if (dados == null) {
        return {'success': false, 'error': 'Cliente não encontrado'};
      }

      final ref = FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCol)
          .doc(clienteId);
      final favoritos = List<String>.from((dados['favoritos'] ?? []).map((e) => e.toString()));
      final idx = favoritos.indexOf(productId);

      if (idx >= 0) {
        favoritos.removeAt(idx);
      } else {
        favoritos.add(productId);
      }

      final token = (dados['portalToken'] ?? '').toString().trim();
      if (token.isEmpty) {
        return {'success': false, 'error': 'Sessão inválida. Faça login novamente.'};
      }
      await ref.update({'favoritos': favoritos, 'portalToken': token});
      return {
        'success': true,
        'isFavorito': favoritos.contains(productId),
        'favoritos': favoritos,
      };
    } catch (e, st) {
      logE('Erro toggleFavorito (type=${e.runtimeType})', error: e, st: st);
      return {'success': false, 'error': 'Erro ao atualizar favoritos'};
    }
  }

  /// Salva carrinho do cliente (persistente).
  /// Exige portalToken na sessão (regras Firestore).
  static Future<void> saveCarrinho({
    required String lojaId,
    required String clienteId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final cliente = await getClienteLogado();
      final portalToken = (cliente?['portalToken'] ?? '').toString().trim();
      if (portalToken.isEmpty) return;

      final serializable = items.map((e) {
        final m = <String, dynamic>{};
        for (final entry in e.entries) {
          final v = entry.value;
          if (v == null) continue;
          if (v is DateTime) {
            m[entry.key] = Timestamp.fromDate(v);
          } else if (v is Map || v is List || v is num || v is bool || v is String) {
            m[entry.key] = v;
          }
        }
        return m;
      }).toList();
      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCol)
          .doc(clienteId)
          .update({
        'carrinho': serializable,
        'ultimaAtualizacaoCarrinho': FieldValue.serverTimestamp(),
        'portalToken': portalToken,
      });
    } catch (e, st) {
      logE('Erro saveCarrinho (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Carrega carrinho persistido do cliente (via CF).
  /// Se [onFalhaCarregamento] for passado, chama quando CF falhar (para SnackBar etc).
  static Future<List<Map<String, dynamic>>> getCarrinho({
    required String lojaId,
    required String clienteId,
    required String email,
    void Function()? onFalhaCarregamento,
  }) async {
    try {
      final dados = await getDadosCompletos(
        lojaId: lojaId,
        clienteId: clienteId,
        email: email,
      );
      if (dados == null) {
        logW('getCarrinho: getDadosCompletos retornou null (CF pode ter falhado)');
        onFalhaCarregamento?.call();
        return [];
      }
      final raw = dados['carrinho'];
      if (raw == null || raw is! List) return [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e, st) {
      logE('Erro getCarrinho (type=${e.runtimeType})', error: e, st: st);
      onFalhaCarregamento?.call();
      return [];
    }
  }

  /// Retorna lista de IDs dos produtos favoritos (via CF).
  /// Se [onFalhaCarregamento] for passado, chama quando CF falhar (para SnackBar etc).
  static Future<List<String>> getFavoritos({
    required String lojaId,
    required String clienteId,
    required String email,
    void Function()? onFalhaCarregamento,
  }) async {
    try {
      final dados = await getDadosCompletos(
        lojaId: lojaId,
        clienteId: clienteId,
        email: email,
      );
      if (dados == null) {
        logW('getFavoritos: getDadosCompletos retornou null (CF pode ter falhado)');
        onFalhaCarregamento?.call();
        return [];
      }
      return List<String>.from((dados['favoritos'] ?? []).map((e) => e.toString()))
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e, st) {
      logE('Erro getFavoritos (type=${e.runtimeType})', error: e, st: st);
      onFalhaCarregamento?.call();
      return [];
    }
  }

  /// Buscar dados completos do cliente via CF getClienteCatalog.
  /// FONTE: clientes (identidade, cupons, favoritos, pedidos legados).
  static Future<Map<String, dynamic>?> getDadosCompletos({
    required String lojaId,
    required String clienteId,
    required String email,
  }) async {
    try {
      final emailNorm = email.trim().toLowerCase();
      if (emailNorm.isEmpty) return null;

      final callable = FirebaseFunctions.instance.httpsCallable('getClienteCatalog');
      final result = await callable.call<Map<String, dynamic>>({
        'lojaId': lojaId,
        'clienteId': clienteId,
        'email': emailNorm,
      });

      final data = result.data as Map<String, dynamic>?;
      if (data == null || data.isEmpty) return null;

      final portalToken = (data['portalToken'] ?? '').toString().trim();
      if (portalToken.isNotEmpty) {
        final cliente = await getClienteLogado();
        if (cliente != null && cliente['clienteId']?.toString() == clienteId) {
          cliente['portalToken'] = portalToken;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyClienteLogado, json.encode(cliente));
        }
      }

      return Map<String, dynamic>.from(data);
    } on FirebaseFunctionsException catch (e) {
      logE(
        'getClienteCatalog CF falhou: code=${e.code} message=${e.message} details=${e.details}',
        error: e,
      );
      logW('getDadosCompletos: CF indisponível (lojaId=$lojaId clienteId=$clienteId)');
      return null;
    } catch (e, st) {
      logE(
        'getDadosCompletos erro (lojaId=$lojaId clienteId=$clienteId type=${e.runtimeType})',
        error: e,
        st: st,
      );
      return null;
    }
  }

  /// Busca pedidos do cliente para exibir no perfil.
  /// FONTE: clientes_portal (espelho Meus Pedidos). Gera portalToken on-demand se faltar.
  /// Retorna pedidos e indica se é preciso reconectar (quando não foi possível obter portalToken).
  static Future<({List<Map<String, dynamic>> pedidos, bool precisaReconectar})>
      getPedidosDoCliente({
    required String lojaId,
    required String email,
    String? clienteId,
  }) async {
    try {
      String? portalToken;
      final clienteLogado = await getClienteLogado();
      if (clienteLogado != null) {
        final sameCliente = clienteId != null &&
            clienteId.isNotEmpty &&
            clienteLogado['clienteId']?.toString() == clienteId;
        final sameEmail =
            clienteLogado['email']?.toString().trim().toLowerCase() ==
                email.trim().toLowerCase();
        if (sameCliente || sameEmail) {
          portalToken = clienteLogado['portalToken']?.toString().trim();
        }
      }

      if ((portalToken == null || portalToken.isEmpty) &&
          clienteId != null &&
          clienteId.trim().isNotEmpty) {
        final dados = await getDadosCompletos(
          lojaId: lojaId,
          clienteId: clienteId.trim(),
          email: email.trim().toLowerCase(),
        );
        if (dados != null) {
          portalToken = (dados['portalToken'] ?? '').toString().trim();
        }
      }

      if (portalToken == null || portalToken.isEmpty) {
        return (
          pedidos: <Map<String, dynamic>>[],
          precisaReconectar: true,
        );
      }

      final pedidos = await _meusPedidosRepository.getPedidosDoCliente(
        lojaId: lojaId,
        email: email,
        clienteId: clienteId,
        portalToken: portalToken,
      );
      return (pedidos: pedidos, precisaReconectar: false);
    } catch (e, st) {
      logE(
        '❌ Erro ao buscar pedidos do cliente (type=${e.runtimeType})',
        error: e,
        st: st,
      );
      return (
        pedidos: <Map<String, dynamic>>[],
        precisaReconectar: true,
      );
    }
  }

  /// Busca cupons da roleta (clientes_catalogo/{email}/cupons) e normaliza formato.
  /// USO ESPECÍFICO: clientes_catalogo é cache de cupons roleta; identidade em clientes.
  static Future<List<Map<String, dynamic>>> getCuponsRoleta({
    required String lojaId,
    required String email,
  }) async {
    if (email.trim().isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCatalogoCol)
          .doc(email.trim().toLowerCase())
          .collection('cupons')
          .get();

      return snap.docs.map((doc) {
        final d = doc.data();
        final tipo = (d['tipo'] ?? 'desconto').toString();
        final valor = (d['valor'] as num?)?.toDouble() ?? 0.0;
        return {
          'codigo': d['codigo'] ?? doc.id,
          'desconto': tipo == 'frete_gratis' ? 0.0 : valor,
          'validade': null,
          'dataExpiracao': d['dataExpiracao'],
          'usado': d['usado'] ?? false,
          'origem': d['origem'] ?? 'roleta_sorte',
          'tipo': tipo,
          'descricao': d['descricao'],
        };
      }).toList();
    } catch (e) {
      logW('⚠️ getCuponsRoleta (type=${e.runtimeType})');
      return [];
    }
  }

  /// Marca um cupom da roleta como usado no perfil do cliente (não pode ser usado novamente).
  /// Atualiza clientes_catalogo/{email}/cupons/{codigo}. USO ESPECÍFICO: cupons roleta.
  static Future<bool> marcarCupomRoletaComoUsado({
    required String lojaId,
    required String email,
    required String codigo,
  }) async {
    final emailNorm = email.trim().toLowerCase();
    final codigoNorm = codigo.trim();
    if (emailNorm.isEmpty || codigoNorm.isEmpty) return false;
    try {
      final ref = FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCatalogoCol)
          .doc(emailNorm)
          .collection('cupons')
          .doc(codigoNorm);

      final doc = await ref.get();
      if (!doc.exists) {
        logW('⚠️ marcarCupomRoletaComoUsado: cupom não encontrado $codigoNorm');
        return false;
      }

      await ref.update({
        'usado': true,
        'dataUso': FieldValue.serverTimestamp(),
      });
      logD('✅ Cupom roleta marcado como usado: $codigoNorm');
      return true;
    } catch (e, st) {
      logE('❌ marcarCupomRoletaComoUsado (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Busca números da sorte das campanhas (participações em campanhas_sorteio)
  static Future<List<Map<String, dynamic>>> getNumerosSorteCampanhas({
    required String lojaId,
    String? clienteId,
    required String email,
  }) async {
    final emailNorm = email.trim().toLowerCase();
    if (emailNorm.isEmpty && (clienteId == null || clienteId.isEmpty)) return [];

    try {
      final campanhasSnap = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .get();

      final resultados = <Map<String, dynamic>>[];

      for (final campanhaDoc in campanhasSnap.docs) {
        Query<Map<String, dynamic>> q;
        if (emailNorm.isNotEmpty) {
          q = campanhaDoc.reference
              .collection('participantes')
              .where('clienteEmail', isEqualTo: emailNorm)
              .limit(50);
        } else if (clienteId != null && clienteId.isNotEmpty) {
          q = campanhaDoc.reference
              .collection('participantes')
              .where('clienteId', isEqualTo: clienteId)
              .limit(50);
        } else {
          continue;
        }

        final participanteSnap = await q.get();

        for (final pDoc in participanteSnap.docs) {
          final p = pDoc.data();
          final status = (p['status'] ?? 'valido').toString();
          if (status != 'valido') continue;
          final pEmail = (p['clienteEmail'] ?? p['email'] ?? '').toString().trim().toLowerCase();
          final pClienteId = (p['clienteId'] ?? '').toString();
          final numero = (p['numeroSorte'] ?? p['numero'] ?? '').toString();

          if (numero.isEmpty) continue;
          final match = (clienteId != null && clienteId.isNotEmpty && pClienteId == clienteId) ||
              (emailNorm.isNotEmpty && pEmail == emailNorm);
          if (match) {
            resultados.add({
              'numeroSorte': numero,
              'data': p['dataParticipacao'] != null
                  ? formatarTimestamp(p['dataParticipacao'])
                  : (p['criadoEm'] != null ? formatarTimestamp(p['criadoEm']) : ''),
              'valor': (p['valorPedido'] ?? p['totalVenda'] as num?)?.toDouble() ?? 0.0,
              'campanhaNome': campanhaDoc.data()['nome'] ?? campanhaDoc.data()['titulo'] ?? 'Campanha',
            });
          }
        }
      }

      resultados.sort((a, b) => (b['data'] ?? '').compareTo(a['data'] ?? ''));
      return resultados;
    } catch (e) {
      logW('⚠️ getNumerosSorteCampanhas (type=${e.runtimeType})');
      return [];
    }
  }

  /// Login com Google (cliente por lojaId: busca ou cria doc em lojas/{lojaId}/clientes)
  static Future<Map<String, dynamic>> loginComGoogle({
    required String lojaId,
    required String email,
    required String nome,
    String? googleUid,
  }) async {
    try {
      final emailNorm = email.toLowerCase().trim();
      if (emailNorm.isEmpty) {
        return {'success': false, 'error': 'Email do Google não disponível.'};
      }

      final resultado = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCol)
          .where('email', isEqualTo: emailNorm)
          .limit(1)
          .get();

      Map<String, dynamic> dadosCliente;
      String clienteId;

      if (resultado.docs.isNotEmpty) {
        final doc = resultado.docs.first;
        clienteId = doc.id;
        dadosCliente = doc.data();
        if (dadosCliente['ativo'] == false) {
          return {'success': false, 'error': 'Conta desativada. Entre em contato com a loja.'};
        }
        if (googleUid != null && googleUid.isNotEmpty) {
          final token = (dadosCliente['portalToken'] ?? '').toString().trim();
          doc.reference.update({'googleUid': googleUid, 'portalToken': token.isNotEmpty ? token : ''});
          dadosCliente['googleUid'] = googleUid;
        }
      } else {
        clienteId = googleUid ?? gerarClienteId();
        dadosCliente = {
          'id': clienteId,
          'nome': nome.trim().isEmpty ? emailNorm.split('@').first : nome.trim(),
          'email': emailNorm,
          'telefone': '',
          'googleUid': googleUid ?? '',
          'portalToken': gerarPortalToken(),
          'dataCadastro': FieldValue.serverTimestamp(),
          'cupons': [],
          'pedidos': [],
          'favoritos': [],
          'ativo': true,
        };
        await FirebaseFirestore.instance
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.clientesCol)
            .doc(clienteId)
            .set(dadosCliente);
      }

      final portalToken = await _ensurePortalToken(
        lojaId: lojaId,
        clienteId: clienteId,
        dados: dadosCliente,
      );
      dadosCliente['portalToken'] = portalToken;
      await _salvarSessao(lojaId, clienteId, dadosCliente);

      return {
        'success': true,
        'clienteId': clienteId,
        'nome': dadosCliente['nome'],
        'email': dadosCliente['email'],
      };
    } catch (e, st) {
      logE('Erro loginComGoogle (type=${e.runtimeType})', error: e, st: st);
      return {'success': false, 'error': 'Erro ao entrar com Google: $e'};
    }
  }

  /// Solicitar redefinição de senha (esqueci a senha).
  /// Na Web usa Cloud Function (envio de email no servidor). No app mobile usa SMTP direto.
  static Future<Map<String, dynamic>> solicitarRedefinicaoSenha({
    required String lojaId,
    required String email,
  }) async {
    try {
      final emailNorm = email.toLowerCase().trim();
      if (emailNorm.isEmpty) {
        return {'success': false, 'error': 'Informe seu email.'};
      }

      // Na Web: Cloud Function envia o email (Socket não existe no browser).
      if (kIsWeb) {
        return await _solicitarRedefinicaoSenhaViaCloudFunction(
          lojaId: lojaId,
          email: emailNorm,
        );
      }

      // App mobile: Firestore + EmailService (SMTP direto).
      final resultado = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCol)
          .where('email', isEqualTo: emailNorm)
          .limit(1)
          .get();

      if (resultado.docs.isEmpty) {
        return {'success': false, 'error': 'Email não encontrado nesta loja.'};
      }

      final doc = resultado.docs.first;
      final docData = doc.data();
      var token = (docData['portalToken'] ?? '').toString().trim();
      if (token.isEmpty) {
        final d = await getDadosCompletos(lojaId: lojaId, clienteId: doc.id, email: emailNorm);
        token = (d?['portalToken'] ?? '').toString().trim();
      }
      final codigo = '${100000 + Random().nextInt(900000)}';
      final expiraEm = DateTime.now().add(const Duration(minutes: 15));

      await doc.reference.update({
        'senhaResetCodigo': codigo,
        'senhaResetExpiraEm': Timestamp.fromDate(expiraEm),
        'portalToken': token,
      });

      final enviado = await EmailService.enviarEmail(
        destinatario: emailNorm,
        assunto: 'Código para redefinir sua senha - MasterPalm',
        mensagem: 'Seu código para redefinir a senha é: $codigo\n\n'
            'Ele é válido por 15 minutos. Se você não solicitou essa alteração, ignore este email.',
      );

      if (!enviado) {
        await doc.reference.update({
          'senhaResetCodigo': FieldValue.delete(),
          'senhaResetExpiraEm': FieldValue.delete(),
          'portalToken': token,
        });
        return {
          'success': false,
          'error': 'Não foi possível enviar o email. Tente novamente ou entre em contato com a loja.',
        };
      }

      return {'success': true};
    } catch (e, st) {
      logE('Erro solicitarRedefinicaoSenha (type=${e.runtimeType})', error: e, st: st);
      return {'success': false, 'error': 'Erro ao solicitar redefinição: $e'};
    }
  }

  /// Chamada à Cloud Function para enviar código de redefinição (usado na Web).
  static Future<Map<String, dynamic>> _solicitarRedefinicaoSenhaViaCloudFunction({
    required String lojaId,
    required String email,
  }) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'southamerica-east1');
      final callable = functions.httpsCallable('solicitarRedefinicaoSenhaCatalogo');
      await callable.call(<String, dynamic>{'lojaId': lojaId, 'email': email});
      return {'success': true};
    } on FirebaseFunctionsException catch (e) {
      final msg = e.message ?? e.details?.toString() ?? 'Erro ao enviar o código.';
      return {'success': false, 'error': msg};
    } catch (e, st) {
      logE('Erro _solicitarRedefinicaoSenhaViaCloudFunction (type=${e.runtimeType})', error: e, st: st);
      return {
        'success': false,
        'error': 'Não foi possível enviar o email. Tente novamente ou entre em contato com a loja.',
      };
    }
  }

  /// Redefinir senha usando o código enviado por email.
  static Future<Map<String, dynamic>> redefinirSenhaComCodigo({
    required String lojaId,
    required String email,
    required String codigo,
    required String novaSenha,
  }) async {
    try {
      final emailNorm = email.toLowerCase().trim();
      final codigoLimpo = codigo.trim().replaceAll(RegExp(r'[^0-9]'), '');
      if (emailNorm.isEmpty || codigoLimpo.length != 6) {
        return {'success': false, 'error': 'Email e código de 6 dígitos são obrigatórios.'};
      }
      if (novaSenha.length < 8) {
        return {'success': false, 'error': 'A nova senha deve ter pelo menos 8 caracteres.'};
      }

      final resultado = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCol)
          .where('email', isEqualTo: emailNorm)
          .limit(1)
          .get();

      if (resultado.docs.isEmpty) {
        return {'success': false, 'error': 'Email não encontrado.'};
      }

      final doc = resultado.docs.first;
      final dados = doc.data();
      final codigoSalvo = (dados['senhaResetCodigo'] ?? '').toString().trim();
      final expiraEm = dados['senhaResetExpiraEm'];
      DateTime? expiraEmDt;
      if (expiraEm != null) {
        if (expiraEm is Timestamp) expiraEmDt = expiraEm.toDate();
      }

      if (codigoSalvo.isEmpty || codigoSalvo != codigoLimpo) {
        return {'success': false, 'error': 'Código inválido.'};
      }
      var token = (dados['portalToken'] ?? '').toString().trim();
      if (token.isEmpty) {
        final d = await getDadosCompletos(lojaId: lojaId, clienteId: doc.id, email: emailNorm);
        token = (d?['portalToken'] ?? '').toString().trim();
      }
      if (expiraEmDt == null || DateTime.now().isAfter(expiraEmDt)) {
        await doc.reference.update({
          'senhaResetCodigo': FieldValue.delete(),
          'senhaResetExpiraEm': FieldValue.delete(),
          'portalToken': token,
        });
        return {'success': false, 'error': 'Código expirado. Solicite um novo.'};
      }

      final novaSenhaHash = hashSenha(novaSenha);
      await doc.reference.update({
        'senhaHash': novaSenhaHash,
        'senhaResetCodigo': FieldValue.delete(),
        'senhaResetExpiraEm': FieldValue.delete(),
        'portalToken': token,
      });

      return {'success': true};
    } catch (e, st) {
      logE('Erro redefinirSenhaComCodigo (type=${e.runtimeType})', error: e, st: st);
      return {'success': false, 'error': 'Erro ao redefinir senha: $e'};
    }
  }

  /// Redefinir senha do cliente pela loja (dono da loja define nova senha sem código).
  /// Use quando o cliente esqueceu a senha e a loja define uma nova para ele.
  static Future<Map<String, dynamic>> redefinirSenhaPelaLoja({
    required String lojaId,
    required String email,
    required String novaSenha,
  }) async {
    try {
      final emailNorm = email.toLowerCase().trim();
      if (emailNorm.isEmpty) {
        return {'success': false, 'error': 'Informe o email do cliente.'};
      }
      if (novaSenha.length < 8) {
        return {'success': false, 'error': 'A nova senha deve ter pelo menos 8 caracteres.'};
      }

      final resultado = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCol)
          .where('email', isEqualTo: emailNorm)
          .limit(1)
          .get();

      if (resultado.docs.isEmpty) {
        return {'success': false, 'error': 'Cliente com este email não encontrado nesta loja.'};
      }

      final doc = resultado.docs.first;
      final docData = doc.data();
      final token = (docData['portalToken'] ?? '').toString().trim();
      final novaSenhaHash = hashSenha(novaSenha);
      await doc.reference.update({
        'senhaHash': novaSenhaHash,
        'senhaResetCodigo': FieldValue.delete(),
        'senhaResetExpiraEm': FieldValue.delete(),
        if (token.isNotEmpty) 'portalToken': token,
      });

      return {'success': true};
    } catch (e, st) {
      logE('Erro redefinirSenhaPelaLoja (type=${e.runtimeType})', error: e, st: st);
      return {'success': false, 'error': 'Erro ao redefinir senha: $e'};
    }
  }

  /// Alterar senha
  static Future<Map<String, dynamic>> alterarSenha({
    required String lojaId,
    required String clienteId,
    required String senhaAtual,
    required String novaSenha,
  }) async {
    try {
      // Buscar dados atuais
      final doc = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.clientesCol)
          .doc(clienteId)
          .get();

      if (!doc.exists) {
        return {'success': false, 'error': 'Cliente não encontrado.'};
      }

      final dados = doc.data()!;

      // Verificar senha atual (comparação em string, como no login)
      final senhaAtualHash = hashSenha(senhaAtual);
      final hashSalvo = (dados['senhaHash'] ?? '').toString().trim();
      if (hashSalvo.isEmpty || hashSalvo != senhaAtualHash) {
        return {'success': false, 'error': 'Senha atual incorreta.'};
      }

      // Atualizar senha (regra exige portalToken no payload)
      final token = (dados['portalToken'] ?? '').toString().trim();
      if (token.isEmpty) {
        return {'success': false, 'error': 'Sessão inválida. Faça login novamente.'};
      }
      final novaSenhaHash = hashSenha(novaSenha);
      await doc.reference.update({'senhaHash': novaSenhaHash, 'portalToken': token});

      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': 'Erro ao alterar senha: $e'};
    }
  }

  /// Último endereço usado em pedido. FONTE: clientes_portal (espelho).
  static Future<Map<String, dynamic>?> getUltimoEnderecoIndexado({
    required String lojaId,
    String? portalToken,
  }) async {
    final token = portalToken?.trim();
    if (token == null || token.isEmpty) return null;
    return _clientePortalRepository.getUltimoEndereco(
      lojaId: lojaId,
      portalToken: token,
    );
  }
}
