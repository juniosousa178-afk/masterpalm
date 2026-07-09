// lib/services/pre_pedido_service.dart

import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/combo_configuravel_resumo.dart';
import '../core/logger.dart';
import '../core/produto_variacao_extra.dart';
import '../repositories/cliente_portal_repository.dart';
import '../repositories/pedido_repository.dart';
import '../repositories/pedido_status_publico_repository.dart';
import 'notificacao_vendas_service.dart';
import 'pedido_collection_resolver.dart';
import 'indicacao_config_service.dart';
import 'cupons_service.dart';
import 'cliente_auth_service.dart';
import 'cliente_auth_helpers.dart';
import 'pre_pedido_helpers.dart';
import 'catalog_pre_pedido_compute.dart';
import 'catalog_cart_item_snapshot.dart';
import '../core/hive_box_names.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import 'vendas_service.dart';
import 'package:hive/hive.dart';

/// Coerção segura de campos string do Firestore (evita `as String?` no web).
String? _firestoreStringFieldOrNull(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}

/// Serviço para gerenciar pré-pedidos do catálogo
/// Pré-pedidos são enviados via WhatsApp e aguardam confirmação do vendedor
class PrePedidoService {
  static final _firestore = FirebaseFirestore.instance;
  static final _clientePortalRepository = ClientePortalRepository();
  static final _pedidoRepository = PedidoRepository();
  static final _pedidoStatusPublicoRepository = PedidoStatusPublicoRepository();

  static CollectionReference<Map<String, dynamic>> _prePedidosRef(
    String lojaId,
  ) {
    return _pedidoRepository.collectionRef(
      flowType: PedidoFlowType.prePedidos,
      lojaId: lojaId,
    );
  }

  /// Marca pré-pedido anterior como substituído na mesma intenção de compra (best-effort).
  /// Não altera `status` legado (pendente/confirmado) para compatibilidade; use `governancaStatus` no painel.
  static Future<void> _marcarPrePedidoComoSubstituido({
    required String lojaId,
    required String prePedidoAntigoId,
    required String novoPrePedidoId,
  }) async {
    try {
      await _pedidoRepository.updatePedido(
        flowType: PedidoFlowType.prePedidos,
        lojaId: lojaId,
        pedidoId: prePedidoAntigoId,
        data: {
          'governancaStatus': 'substituido',
          'substituidoPor': novoPrePedidoId,
          'substituidoEm': FieldValue.serverTimestamp(),
          'dataAtualizacao': FieldValue.serverTimestamp(),
        },
      );
      logD(
          '✅ [GOVERNANÇA] Pré-pedido $prePedidoAntigoId marcado como substituido por $novoPrePedidoId');
    } catch (e, st) {
      logW(
          '⚠️ [GOVERNANÇA] Não foi possível marcar pré-pedido $prePedidoAntigoId como substituido (type=${e.runtimeType}): $e\n$st');
    }
  }

  static String _gerarPortalToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Resolve portalToken para salvar pedido em clientes_portal.
  /// Ordem de prioridade: portalTokenFromSession > getDadosCompletos > query por clienteId > query por email > criar cliente.
  /// Logs rastreáveis em cada etapa.
  static Future<String?> _resolvePortalTokenForPedido({
    required String lojaId,
    required Map<String, dynamic> pedidoData,
    String? portalTokenFromSession,
  }) async {
    final cliente = pedidoData['cliente'];
    final clienteMap =
        cliente is Map ? Map<String, dynamic>.from(cliente) : <String, dynamic>{};
    final clienteId = (clienteMap['id'] ?? '').toString().trim();
    final email = (clienteMap['email'] ?? '').toString().trim().toLowerCase();
    if (email.isEmpty) {
      logW('[PORTAL] _resolvePortalTokenForPedido: email vazio, não é possível vincular ao portal');
      return null;
    }

    // 1) Usar portalToken da sessão ou do próprio pedido (evita dependência de CF)
    final tokenSessao = (portalTokenFromSession ?? '').toString().trim();
    final tokenNoPedido = (clienteMap['portalToken'] ?? '').toString().trim();
    final tokenPrioritario = tokenSessao.isNotEmpty ? tokenSessao : tokenNoPedido;
    if (tokenPrioritario.isNotEmpty) {
      logD('[PORTAL] Usando portalToken ${tokenSessao.isNotEmpty ? "da sessão" : "do pedido"} (lojaId=$lojaId clienteId=$clienteId)');
      return tokenPrioritario;
    }

    // 2) Por clienteId: tentar getDadosCompletos (CF)
    if (clienteId.isNotEmpty) {
      try {
        final dados = await ClienteAuthService.getDadosCompletos(
          lojaId: lojaId,
          clienteId: clienteId,
          email: email,
        );
        final token = (dados?['portalToken'] ?? '').toString().trim();
        if (token.isNotEmpty) {
          logD('[PORTAL] portalToken obtido via getDadosCompletos (clienteId=$clienteId)');
          return token;
        }
      } catch (e) {
        logW('[PORTAL] getDadosCompletos falhou (clienteId=$clienteId): $e');
      }

      // 2b) Fallback: leitura direta do doc clientes (se CF falhou)
      try {
        final doc = await _firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('clientes')
            .doc(clienteId)
            .get();
        if (doc.exists) {
          final data = doc.data() ?? {};
          var token = (data['portalToken'] ?? '').toString().trim();
          if (token.isEmpty) {
            token = _gerarPortalToken();
            await doc.reference.update({'portalToken': token});
            logD('[PORTAL] portalToken criado no doc clientes (clienteId=$clienteId)');
          }
          return token;
        }
      } catch (e) {
        logW('[PORTAL] Fallback leitura clientes por id falhou: $e');
      }
    }

    // 3) Query por email em clientes
    try {
      final snapshot = await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('clientes')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final clienteData = doc.data();
        var portalToken = (clienteData['portalToken'] ?? '').toString().trim();
        if (portalToken.isEmpty) {
          portalToken = _gerarPortalToken();
          await doc.reference.update({'portalToken': portalToken});
          logD('[PORTAL] portalToken criado no doc clientes (por email, docId=${doc.id})');
        }
        return portalToken;
      }
    } catch (e) {
      logW('[PORTAL] Query clientes por email falhou: $e');
    }

    // 4) Último recurso: criar cliente mínimo com portalToken (garante que pedido apareça em Meus Pedidos)
    try {
      final result = await _ensureClienteComPortalToken(
        lojaId: lojaId,
        email: email,
        nome: (clienteMap['nome'] ?? 'Cliente').toString().trim(),
        telefone: (clienteMap['telefone'] ?? '').toString().trim(),
      );
      if (result != null && result.isNotEmpty) {
        logD('[PORTAL] Cliente criado com portalToken (email=$email) - pedido ficará visível em Meus Pedidos');
        return result;
      }
    } catch (e) {
      logE('[PORTAL] Falha ao criar cliente mínimo para portal (email=$email)', error: e);
    }

    logW('[PORTAL] Não foi possível resolver portalToken - pedido NÃO aparecerá em Meus Pedidos');
    return null;
  }

  /// Cria cliente mínimo em clientes quando não existe, para garantir vínculo com clientes_portal.
  /// Retorna portalToken ou null em caso de falha.
  /// Usa doc id determinístico (clienteIdPorEmail) + transação: duas execuções simultâneas
  /// para o mesmo email gravam no mesmo doc, eliminando race e duplicidade.
  /// Nota: Transaction.get() no client SDK não aceita Query; confiamos no id determinístico.
  static Future<String?> _ensureClienteComPortalToken({
    required String lojaId,
    required String email,
    required String nome,
    required String telefone,
  }) async {
    final emailNorm = email.trim().toLowerCase();
    if (emailNorm.isEmpty) return null;

    final docId = clienteIdPorEmail(lojaId, emailNorm);
    final docRef = _firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('clientes')
        .doc(docId);

    return _firestore.runTransaction<String?>((tx) async {
      final snap = await tx.get(docRef);
      if (snap.exists) {
        final data = snap.data() ?? {};
        var token = (data['portalToken'] ?? '').toString().trim();
        if (token.isEmpty) {
          token = _gerarPortalToken();
          tx.update(docRef, {'portalToken': token});
        }
        return token;
      }

      final portalToken = _gerarPortalToken();
      var nomeFirestore = nome.trim();
      if (nomeFirestore.isEmpty) {
        nomeFirestore = emailNorm.split('@').first;
      }
      if (nomeFirestore.length < 2) {
        nomeFirestore = nomeFirestore.isEmpty ? 'Cliente' : '$nomeFirestore·';
      }
      tx.set(docRef, {
        'id': docId,
        'email': emailNorm,
        'nome': nomeFirestore,
        'telefone': telefone,
        'portalToken': portalToken,
        'dataCadastro': FieldValue.serverTimestamp(),
        'cupons': <dynamic>[],
        'favoritos': <dynamic>[],
        'ativo': true,
      });
      return portalToken;
    });
  }

  static Future<void> _saveClientePortalPedidoResumo({
    required String lojaId,
    required String pedidoId,
    required Map<String, dynamic> pedidoData,
    String? overrideStatus,
    String? portalTokenFromSession,
  }) async {
    final portalToken = await _resolvePortalTokenForPedido(
      lojaId: lojaId,
      pedidoData: pedidoData,
      portalTokenFromSession: portalTokenFromSession,
    );
    if (portalToken == null || portalToken.isEmpty) {
      logW('[PORTAL] _saveClientePortalPedidoResumo: portalToken nulo (pedidoId=$pedidoId) - pedido não aparecerá em Meus Pedidos');
      return;
    }

    final frete = pedidoData['frete'];
    final freteMap = frete is Map ? Map<String, dynamic>.from(frete) : null;
    final itens = (pedidoData['itens'] as List?) ?? const [];

    await _clientePortalRepository.savePedidoResumo(
      lojaId: lojaId,
      portalToken: portalToken,
      pedidoId: pedidoId,
      data: {
        'pedidoId': pedidoId,
        'lojaId': lojaId,
        'status': (overrideStatus ?? pedidoData['status'] ?? 'pendente').toString(),
        'dataCriacao': pedidoData['dataCriacao'],
        'dataAtualizacao': FieldValue.serverTimestamp(),
        'total': (pedidoData['total'] as num?)?.toDouble() ?? 0.0,
        'itensResumo': itens
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .map((item) => {
                  'nome': catalogPedidoItemDisplayName(item),
                  'quantidade': (item['quantidade'] as num?)?.toInt() ?? 1,
                })
            .where((item) => (item['nome'] ?? '').toString().trim().isNotEmpty)
            .toList(growable: false),
        if ((pedidoData['codigoRastreio'] ?? '').toString().trim().isNotEmpty)
          'codigoRastreio': pedidoData['codigoRastreio'],
        if (((pedidoData['codigo_rastreio'] ?? '').toString().trim().isNotEmpty) &&
            (pedidoData['codigoRastreio'] ?? '').toString().trim().isEmpty)
          'codigoRastreio': pedidoData['codigo_rastreio'],
        if (freteMap != null &&
            (freteMap['nome'] ?? '').toString().trim().isNotEmpty)
          'freteNome': freteMap['nome'],
      },
    );
  }

  static Future<void> _deleteClientePortalPedidoResumo({
    required String lojaId,
    required String pedidoId,
    required Map<String, dynamic> pedidoData,
  }) async {
    final portalToken = await _resolvePortalTokenForPedido(
      lojaId: lojaId,
      pedidoData: pedidoData,
    );
    if (portalToken == null || portalToken.isEmpty) return;
    await _clientePortalRepository.deletePedidoResumo(
      lojaId: lojaId,
      portalToken: portalToken,
      pedidoId: pedidoId,
    );
  }

  /// Cria um pré-pedido e retorna dados completos (id + conteúdo)
  ///
  /// Retorna Map com 'id' e todos os dados do pedido.
  /// Usa os dados já montados para evitar leitura pós-criação (regras Firestore
  /// permitem create público mas read apenas admin - catálogo web é anônimo).
  static Future<Map<String, dynamic>?> criarPrePedido({
    required String lojaId,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    String?
        clienteId, // ID do cliente logado (clientes collection) para rastreio no perfil
    required Map<String, dynamic> entrega,
    required String pagamento,
    String observacao = '',
    String? cupomCodigo,
    String? cupomFreteCodigo,
    double desconto = 0.0,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    String? premioRoletaDescricao,
    String? vendedorRef, // ✅ ID do vendedor para comissão (vem do link ?ref=)
    String? indicacaoClienteId, // ✅ ID do cliente que indicou (link ?indicacao=clienteId)
    String?
        origemCheckout, // 'whatsapp' quando finalizado por WhatsApp (para notificação específica)
    String? portalTokenFromSession, // ✅ portalToken da sessão (evita falha em Meus Pedidos)
    /// ID de outro pré-pedido da mesma sessão que este documento substitui (governança; não afeta totais).
    String? substituiPrePedidoId,
    /// Fingerprint do checkout (catálogo público) para auditoria / painel.
    String? checkoutFingerprint,
  }) async {
    try {
      final money = computeCatalogPrePedidoMoneySnapshot(
        items: items,
        entrega: entrega,
        pagamento: pagamento,
        desconto: desconto,
      );
      final itensList = money.itensList;
      final subtotal = money.subtotal;
      final total = money.total;
      final freteGratis = entrega['freteGratis'] == true;
      final freteValor = (entrega['valor'] as num?)?.toDouble() ?? 0.0;

      // Criar documento do pré-pedido
      final prePedidoData = {
        'lojaId': lojaId,
        'tipo': 'catalogo_web',
        'status': 'pendente', // pendente | confirmado | cancelado

        // Cliente (email em lowercase para queries no perfil)
        'cliente': {
          'nome': customer['nome'] ?? '',
          'cpf': customer['cpf'] ?? '',
          'email': (customer['email'] ?? '').toString().toLowerCase().trim(),
          'telefone': customer['telefone'] ?? '',
          'endereco': customer['endereco'] ?? {},
          'enderecoFormatado': customer['enderecoFormatado'] ?? '',
          if (clienteId != null && clienteId.isNotEmpty) 'id': clienteId,
          if (portalTokenFromSession != null && portalTokenFromSession.isNotEmpty)
            'portalToken': portalTokenFromSession,
        },

        // Itens
        'itens': itensList,

        // Valores
        'subtotal': subtotal,
        'frete': {
          'nome': entrega['nome'] ?? 'Entrega',
          'valor': freteValor,
          'gratis': freteGratis,
          'tipo': entrega['tipo'] ?? '',
          if (entrega['plataforma'] != null) 'plataforma': entrega['plataforma'],
          if (entrega['service_id'] != null) 'service_id': entrega['service_id'],
          if (entrega['servico_id'] != null) 'servico_id': entrega['servico_id'],
        },
        'cupom': cupomCodigo != null
            ? {
                'codigo': cupomCodigo,
                'desconto': desconto,
              }
            : null,
        'cupomFrete': cupomFreteCodigo != null && cupomFreteCodigo.isNotEmpty
            ? {'codigo': cupomFreteCodigo}
            : null,
        'total': total,

        // Pagamento
        'pagamento': pagamento,
        'statusPagamento': determinarStatusPagamento(
            pagamento), // pendente | aprovado | rejeitado
        'observacao': observacao,

        // ✅ Prêmio da Roleta (se houver)
        'premioRoleta': premioRoletaDescricao != null ||
                cupomRoletaCodigo != null
            ? {
                'descricao': premioRoletaDescricao ?? '',
                'tipo': determinarTipoPremio(premioRoletaDescricao,
                    cupomRoletaCodigo, cupomRoletaDesconto),
                'valor': cupomRoletaDesconto ?? 0.0,
                'codigo': cupomRoletaCodigo,
                'status': 'pendente', // pendente | ativo | usado
                'dataGanho': FieldValue.serverTimestamp(),
                'dataAtivacao':
                    null, // será preenchido após confirmação de pagamento
                'valido': false, // só fica true após confirmação de pagamento
              }
            : null,

        // ✅ Vendedor (para comissão - link com ?ref=vendedorId)
        'vendedorRef': vendedorRef,
        'temComissao': vendedorRef != null && vendedorRef.isNotEmpty,

        // ✅ Indicação (quem indicou este cliente - link ?indicacao=clienteId)
        'indicacaoClienteId': indicacaoClienteId,

        // Metadata
        'dataCriacao': FieldValue.serverTimestamp(),
        'dataAtualizacao': FieldValue.serverTimestamp(),
        'origem': 'catalogo_web',
        'vendaId': null, // Será preenchido quando confirmar
        if (origemCheckout != null && origemCheckout.isNotEmpty)
          'origemCheckout': origemCheckout,
        // Governança operacional (catálogo): legado sem campo = tratado como ativo no painel
        'governancaStatus': 'ativo',
        if (substituiPrePedidoId != null && substituiPrePedidoId.trim().isNotEmpty)
          'substituiPrePedidoId': substituiPrePedidoId.trim(),
        if (checkoutFingerprint != null && checkoutFingerprint.trim().isNotEmpty)
          'checkoutFingerprint': checkoutFingerprint.trim(),
      };

      // ✅ SALVAR/ATUALIZAR CLIENTE AUTOMATICAMENTE
      await _salvarOuAtualizarCliente(
        lojaId: lojaId,
        customer: customer,
        pedidoId: null, // Será preenchido abaixo
        total: total,
      );

      // ✅ [PORTAL] Garantir portalToken em cliente ANTES de salvar (CF syncPedidoStatusPublico
      // precisa disso para gravar em clientes_portal). Sem isso, pedido não aparece em Meus Pedidos.
      final emailParaPortal = (customer['email'] ?? '').toString().trim().toLowerCase();
      if (emailParaPortal.isNotEmpty) {
        String? portalTokenParaPedido = portalTokenFromSession?.trim().isNotEmpty == true
            ? portalTokenFromSession!.trim()
            : null;
        portalTokenParaPedido ??= await _ensureClienteComPortalToken(
          lojaId: lojaId,
          email: emailParaPortal,
          nome: (customer['nome'] ?? 'Cliente').toString().trim(),
          telefone: (customer['telefone'] ?? '').toString().trim(),
        );
        if (portalTokenParaPedido != null) {
          final clienteAtual = Map<String, dynamic>.from(prePedidoData['cliente'] as Map);
          clienteAtual['portalToken'] = portalTokenParaPedido;
          prePedidoData['cliente'] = clienteAtual;
        }
      }

      // Salvar no Firestore
      final docRef = await _pedidoRepository.createPedido(
        flowType: PedidoFlowType.prePedidos,
        lojaId: lojaId,
        data: prePedidoData,
      );

      logD('✅ Pré-pedido criado: ${docRef.id}');

      final antigo = substituiPrePedidoId?.trim();
      if (antigo != null &&
          antigo.isNotEmpty &&
          antigo != docRef.id) {
        unawaited(_marcarPrePedidoComoSubstituido(
          lojaId: lojaId,
          prePedidoAntigoId: antigo,
          novoPrePedidoId: docRef.id,
        ));
      }

      // Notificação admin é criada pela Cloud Function onPrePedidoCreated (funciona na web e no APK)

      // 🎯 [PORTAL] Gravar em clientes_portal (ESPELHO DERIVADO) IMEDIATAMENTE para "Meus Pedidos"
      final pedidoDataComId = {'id': docRef.id, ...prePedidoData};
      unawaited(_saveClientePortalPedidoResumo(
        lojaId: lojaId,
        pedidoId: docRef.id,
        pedidoData: pedidoDataComId,
        portalTokenFromSession: portalTokenFromSession,
      ).then((_) => logD('[PORTAL] clientes_portal atualizado para pedido ${docRef.id}'))
          .catchError((e) => logW('[PORTAL] Erro ao gravar clientes_portal (não bloqueia): $e')));

      // ✅ Atualizar endereço na coleção clientes para "Usar último endereço" (catálogo web/APK)
      try {
        final email = (customer['email'] ?? '').toString().trim().toLowerCase();
        if (email.isNotEmpty) {
          if (clienteId != null && clienteId.isNotEmpty) {
            await _firestore
                .collection('lojas')
                .doc(lojaId)
                .collection('clientes')
                .doc(clienteId)
                .update({
              'endereco': customer['endereco'] ?? {},
              'enderecoFormatado': customer['enderecoFormatado'] ?? '',
              'email': email,
            });
            logD(
                '✅ [PRE-PEDIDO] Endereço atualizado no perfil do cliente (clienteId)');
          } else {
            // Sem login: atualizar por email para "último endereço" funcionar quando logar depois
            final snap = await _firestore
                .collection('lojas')
                .doc(lojaId)
                .collection('clientes')
                .where('email', isEqualTo: email)
                .limit(1)
                .get();
            if (snap.docs.isNotEmpty) {
              await snap.docs.first.reference.update({
                'endereco': customer['endereco'] ?? {},
                'enderecoFormatado': customer['enderecoFormatado'] ?? '',
                'email': email,
              });
              logD(
                  '✅ [PRE-PEDIDO] Endereço atualizado no perfil do cliente (por email)');
            }
          }
        }
      } catch (e) {
        logW(
            '⚠️ [PRE-PEDIDO] Erro ao atualizar endereço do cliente (não bloqueia) (type=${e.runtimeType})');
      }

      // ✅ Programa de indicação: destinatário ganha cupom na primeira compra; remetente ganha cupom que só ativa após o destinatário usar o dele
      if (indicacaoClienteId != null &&
          indicacaoClienteId.isNotEmpty &&
          clienteId != null &&
          clienteId.isNotEmpty) {
        try {
          final cfg = await IndicacaoConfigService.getConfig(lojaId);
          if (cfg.ativo) {
            // Só cria cupons na primeira compra do destinatário por este indicador
            final jaRecebeu = await _firestore
                .collection('lojas')
                .doc(lojaId)
                .collection('cupons_clientes')
                .where('clienteId', isEqualTo: clienteId)
                .where('indicadorId', isEqualTo: indicacaoClienteId)
                .limit(1)
                .get();
            if (jaRecebeu.docs.isNotEmpty) {
              logD('✅ [INDICAÇÃO] Destinatário já recebeu cupom desta indicação; não duplica.');
            } else {
              final refDoc = await _firestore
                  .collection('lojas')
                  .doc(lojaId)
                  .collection('clientes')
                  .doc(indicacaoClienteId)
                  .get();
              final refData = refDoc.data() ?? {};
              final res = await CuponsService.criarCuponsIndicacao(
              lojaId: lojaId,
              clienteAmigoId: clienteId,
              clienteAmigoNome: (customer['nome'] ?? '').toString(),
              clienteAmigoEmail: (customer['email'] ?? '').toString(),
              clienteAmigoWhatsApp: (customer['telefone'] ?? '').toString(),
              clienteIndicadorId: indicacaoClienteId,
              clienteIndicadorNome: (refData['nome'] ?? '').toString(),
              clienteIndicadorEmail: (refData['email'] ?? '').toString(),
              clienteIndicadorWhatsApp: (refData['telefone'] ?? refData['whatsapp'] ?? '').toString(),
              tipoDesconto: cfg.tipo,
              valorDesconto: cfg.valor,
              validadeDias: cfg.validadeDias,
            );
              if (res != null) {
                logD('✅ [INDICAÇÃO] Cupons criados (1ª compra): amigo ${res['codigoAmigo']}; remetente ativa quando amigo usar.');
              }
            }
          }
        } catch (e) {
          logW('⚠️ [PRE-PEDIDO] Erro ao criar cupons de indicação (não bloqueia): $e');
        }
      }

      // ✅ ATUALIZAR HISTÓRICO DO CLIENTE COM ID DO PEDIDO
      await _adicionarPedidoAoHistoricoCliente(
        lojaId: lojaId,
        customer: customer,
        pedidoId: docRef.id,
        total: total,
      );

      // Pré-pedido de envio (carrinho SuperFrete/Melhor Envio): Cloud Function
      // onPrePedidoShippingPreOrder — idempotente, somente no backend.
      final plataformaFrete = (entrega['plataforma'] ?? '').toString().trim();
      if (plataformaFrete.isNotEmpty && plataformaFrete != 'manual') {
        logD(
            '📦 [PRÉ-PEDIDO] Envio externo enfileirado no servidor ($plataformaFrete)');
      }

      // E-mail ao cliente e ao vendedor: Cloud Function onPrePedidoCreated (SMTP no
      // servidor; catálogo web não consegue enviar SMTP a partir do browser).
      // Ver functions/index.js — evita duplicar e mantém a mesma mensagem em todas as plataformas.

      // Retorna dados completos (evita buscarPrePedido - regras não permitem read público)
      return {
        'id': docRef.id,
        ...prePedidoData,
      };
    } catch (e, st) {
      logE('❌ Erro ao criar pré-pedido (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Busca um pré-pedido pelo ID (requer permissão admin no Firestore)
  static Future<Map<String, dynamic>?> buscarPrePedido({
    required String lojaId,
    required String prePedidoId,
  }) async {
    try {
      final doc = await _prePedidosRef(lojaId).doc(prePedidoId).get();

      if (!doc.exists) {
        logW('⚠️ Pré-pedido não encontrado: $prePedidoId');
        return null;
      }

      return {
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      };
    } catch (e, st) {
      logE('❌ Erro ao buscar pré-pedido (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Lista todos os pré-pedidos pendentes de uma loja
  static Stream<List<Map<String, dynamic>>> streamPrePedidosPendentes({
    required String lojaId,
  }) {
    return _pedidoRepository
        .streamPedidos(
          flowType: PedidoFlowType.prePedidos,
          lojaId: lojaId,
          buildQuery: (query) => query
              .where('status', isEqualTo: 'pendente')
              .orderBy('dataCriacao', descending: true),
        )
        .asBroadcastStream();
  }

  /// Lista todos os pré-pedidos de uma loja (com filtros opcionais)
  static Stream<List<Map<String, dynamic>>> streamPrePedidos({
    required String lojaId,
    String?
        status, // null ou 'todos' = todos, 'pendente', 'confirmado', 'cancelado'
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> query = _prePedidosRef(lojaId);

    // Se status é 'todos' ou null, mostrar todos os pedidos
    // Caso contrário, filtrar pelo status específico
    if (status != null && status != 'todos') {
      query = query.where('status', isEqualTo: status);
    }

    query = query.orderBy('dataCriacao', descending: true).limit(limit);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }).toList();
    }).asBroadcastStream();
  }

  /// Confirma um pré-pedido e cria a venda
  ///
  /// Retorna o vendaId criado
  /// ✅ ATUALIZADO: Notifica vendedor se houver vendedorRef
  static Future<String?> confirmarPrePedido({
    required String lojaId,
    required String prePedidoId,
    required String vendaId, // ID da venda criada pelo vendedor
    double valorVenda = 0.0,
    double valorComissao = 0.0,
  }) async {
    try {
      // ✅ Buscar dados do pré-pedido antes de deletar (para notificação)
      final prePedidoDoc = await _prePedidosRef(lojaId).doc(prePedidoId).get();

      final prePedidoData = prePedidoDoc.data();
      final vendedorRef = _firestoreStringFieldOrNull(prePedidoData?['vendedorRef']);
      final clienteData = prePedidoData?['cliente'] as Map?;
      final clienteNome =
          (clienteData)?['nome'] ?? 'Cliente';

      // Atualizar status para 'confirmado' e salvar vendaId (mantém doc para rastreio: em preparação → enviado → entregue)
      await _pedidoRepository.updatePedido(
        flowType: PedidoFlowType.prePedidos,
        lojaId: lojaId,
        pedidoId: prePedidoId,
        data: {
        'status': 'confirmado',
        'vendaId': vendaId,
        'dataAtualizacao': FieldValue.serverTimestamp(),
        },
      );

      logD('✅ Pré-pedido confirmado: $prePedidoId → Venda: $vendaId');

      // Indicação: ativar cupons do remetente quando a venda é confirmada pelo admin
      await CuponsService.ativarCuponsIndicacaoPorPedidoConfirmado(
        lojaId: lojaId,
        pedidoId: prePedidoId,
      );

      // ✅ NOTIFICAR VENDEDOR SE HOUVER
      if (vendedorRef != null && vendedorRef.isNotEmpty) {
        try {
          final vendedorDoc = await _firestore
              .collection('lojas')
              .doc(lojaId)
              .collection('vendedores')
              .doc(vendedorRef)
              .get();

          final vendedorEmail = vendedorDoc.data()?['email'] ?? '';

          await NotificacaoVendasService().notificarVendedorVendaConfirmada(
            storeId: lojaId,
            vendedorUid: vendedorRef,
            vendedorEmail: vendedorEmail,
            pedidoId: prePedidoId,
            vendaId: vendaId,
            clienteNome: clienteNome,
            valorVenda: valorVenda,
            valorComissao: valorComissao,
          );
        } catch (e) {
          logW('⚠️ [CONFIRMAR] Erro ao notificar vendedor (type=${e.runtimeType})');
        }
      }

      // E-mail ao cliente (confirmado): Cloud Function onPrePedidoClienteEmail

      return vendaId;
    } catch (e, st) {
      logE('❌ Erro ao confirmar pré-pedido (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Cancela um pré-pedido
  /// ✅ ATUALIZADO: Notifica vendedor se houver vendedorRef
  static Future<bool> cancelarPrePedido({
    required String lojaId,
    required String prePedidoId,
    String? motivo,
  }) async {
    try {
      // ✅ Buscar dados do pré-pedido antes de deletar (para notificação)
      final prePedidoDoc = await _prePedidosRef(lojaId).doc(prePedidoId).get();

      final prePedidoData = prePedidoDoc.data();
      final vendedorRef = _firestoreStringFieldOrNull(prePedidoData?['vendedorRef']);
      final clienteData = prePedidoData?['cliente'] as Map?;
      final clienteNome =
          (clienteData)?['nome'] ?? 'Cliente';
      final vendaIdPrePedido = (prePedidoData?['vendaId'] ?? '').toString().trim();

      if (vendaIdPrePedido.isNotEmpty) {
        try {
          final vendasBox =
              await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
          final produtosBox =
              await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
          final key = int.tryParse(vendaIdPrePedido);
          final venda = key != null ? vendasBox.get(key) : null;
          if (venda != null) {
            await VendasService.devolverEstoqueParaVendaRemovida(
              venda: venda,
              produtosBox: produtosBox,
              lojaId: lojaId,
              estornoOrigem: 'pre_pedido_cancelado',
            );
          } else {
            logW(
              '⚠️ [CANCELAR] vendaId=$vendaIdPrePedido não encontrada no Hive; '
              'estorno de estoque ignorado',
            );
          }
        } catch (e, st) {
          logE(
            '❌ [CANCELAR] Falha ao estornar estoque do pré-pedido (type=${e.runtimeType})',
            error: e,
            st: st,
          );
          rethrow;
        }
      }

      // Mantém um espelho público sanitizado mesmo quando o pré-pedido privado é removido.
      try {
        if (prePedidoData != null) {
          await _pedidoStatusPublicoRepository.saveFromPedidoPrivado(
            lojaId: lojaId,
            pedidoId: prePedidoId,
            pedidoData: Map<String, dynamic>.from(prePedidoData),
            overrideStatus: 'cancelado',
            overrideDataAtualizacao: FieldValue.serverTimestamp(),
          );
          await _saveClientePortalPedidoResumo(
            lojaId: lojaId,
            pedidoId: prePedidoId,
            pedidoData: Map<String, dynamic>.from(prePedidoData),
            overrideStatus: 'cancelado',
          );
        }
      } catch (e) {
        logW(
          '⚠️ [CANCELAR] Erro ao atualizar pedido_status_publico (não bloqueia) (type=${e.runtimeType})',
        );
      }

      // Deletar o documento ao invés de apenas marcar como cancelado
      await _pedidoRepository.deletePedido(
        flowType: PedidoFlowType.prePedidos,
        lojaId: lojaId,
        pedidoId: prePedidoId,
      );

      logD('✅ Pré-pedido deletado: $prePedidoId');

      // ✅ NOTIFICAR VENDEDOR SE HOUVER
      if (vendedorRef != null && vendedorRef.isNotEmpty) {
        try {
          final vendedorDoc = await _firestore
              .collection('lojas')
              .doc(lojaId)
              .collection('vendedores')
              .doc(vendedorRef)
              .get();

          final vendedorEmail = vendedorDoc.data()?['email'] ?? '';

          await NotificacaoVendasService().notificarVendedorVendaCancelada(
            storeId: lojaId,
            vendedorUid: vendedorRef,
            vendedorEmail: vendedorEmail,
            pedidoId: prePedidoId,
            clienteNome: clienteNome,
            motivo: motivo,
          );
        } catch (e) {
          logW('⚠️ [CANCELAR] Erro ao notificar vendedor (type=${e.runtimeType})');
        }
      }

      return true;
    } catch (e, st) {
      logE('❌ Erro ao cancelar pré-pedido (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Exclui um pré-pedido finalizado (entregue/cancelado) - para limpar testes
  static Future<bool> excluirPrePedido({
    required String lojaId,
    required String prePedidoId,
  }) async {
    try {
      Map<String, dynamic>? prePedidoData;
      try {
        prePedidoData = await _pedidoRepository.getPedidoById(
          flowType: PedidoFlowType.prePedidos,
          lojaId: lojaId,
          pedidoId: prePedidoId,
        );
      } catch (e) {
        logW(
          '⚠️ [EXCLUIR] Falha ao buscar pré-pedido antes de excluir (clientes_portal pode ficar órfão): '
          'lojaId=$lojaId prePedidoId=$prePedidoId (type=${e.runtimeType})',
        );
      }

      await _pedidoRepository.deletePedido(
        flowType: PedidoFlowType.prePedidos,
        lojaId: lojaId,
        pedidoId: prePedidoId,
      );

      logD('✅ Pré-pedido excluído: $prePedidoId');

      try {
        await _pedidoStatusPublicoRepository.deleteByPedidoId(
          lojaId: lojaId,
          pedidoId: prePedidoId,
        );
        if (prePedidoData != null) {
          await _deleteClientePortalPedidoResumo(
            lojaId: lojaId,
            pedidoId: prePedidoId,
            pedidoData: Map<String, dynamic>.from(prePedidoData),
          );
        }
      } catch (e) {
        logW(
          '⚠️ [EXCLUIR] Erro ao remover pedido_status_publico (não bloqueia) (type=${e.runtimeType})',
        );
      }

      return true;
    } catch (e, st) {
      logE('❌ Erro ao excluir pré-pedido (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Campos de pagamento/gateway — nunca alterados por mudança operacional de status.
  static const Set<String> camposPagamentoProtegidos = {
    'statusPagamento',
    'paymentId',
    'paidAt',
    'mpPaymentStatus',
    'mp_payment_id',
    'mpPaymentId',
    'gatewayPaymentId',
  };

  /// Atualização só logística: [status] + [dataAtualizacao] (+ extras de envio).
  /// Não reprocessa MP, não baixa estoque, não cria venda/cliente.
  static Future<bool> atualizarStatusOperacionalPedidoCatalogo({
    required String lojaId,
    required String pedidoId,
    required String novoStatus,
    Map<String, dynamic>? extraUpdates,
  }) async {
    final extra = <String, dynamic>{};
    if (extraUpdates != null) {
      for (final e in extraUpdates.entries) {
        if (!camposPagamentoProtegidos.contains(e.key)) {
          extra[e.key] = e.value;
        }
      }
    }
    return atualizarStatus(
      lojaId: lojaId,
      prePedidoId: pedidoId,
      novoStatus: novoStatus,
      extraUpdates: extra.isEmpty ? null : extra,
    );
  }

  /// Atualiza o status de um pré-pedido.
  /// E-mails ao cliente: Cloud Function onPrePedidoClienteEmail.
  static Future<bool> atualizarStatus({
    required String lojaId,
    required String prePedidoId,
    required String novoStatus,
    Map<String, dynamic>? extraUpdates,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': novoStatus,
        'dataAtualizacao': FieldValue.serverTimestamp(),
      };
      if (extraUpdates != null && extraUpdates.isNotEmpty) {
        updates.addAll(extraUpdates);
      }
      await _pedidoRepository.updatePedido(
        flowType: PedidoFlowType.prePedidos,
        lojaId: lojaId,
        pedidoId: prePedidoId,
        data: updates,
      );

      logD(
          '✅ Status do pré-pedido $prePedidoId atualizado para: $novoStatus');

      return true;
    } catch (e, st) {
      logE('❌ Erro ao atualizar status (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Conta pré-pedidos pendentes
  static Future<int> contarPendentes({required String lojaId}) async {
    try {
      final snapshot = await _prePedidosRef(lojaId)
          .where('status', isEqualTo: 'pendente')
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e, st) {
      logE('❌ Erro ao contar pré-pedidos (type=${e.runtimeType})', error: e, st: st);
      return 0;
    }
  }

  /// Gera URL pública para visualizar o pré-pedido
  ///
  /// Usa HTTPS para ser clicável no WhatsApp
  /// Exemplo: https://app.mastepalm.com.br/c/nathy-pratas-e-folheados?pedido=abc123
  ///
  /// O AndroidManifest está configurado para interceptar esses links e abrir no app
  static String gerarUrlPedido({
    required String prePedidoId,
    required String lojaId,
    String baseUrl = 'https://app.mastepalm.com.br',
    bool useCustomScheme = false, // ✅ HTTPS por padrão para ser clicável
  }) {
    if (useCustomScheme) {
      // Custom scheme - só funciona se app estiver instalado
      return 'masterpalm://pedido/$prePedidoId?loja=$lojaId';
    } else {
      // HTTPS - clicável no WhatsApp e abre no app se instalado
      return '$baseUrl/c/$lojaId?pedido=$prePedidoId';
    }
  }

  /// Formata os dados do pré-pedido para exibição
  static String formatarParaWhatsApp({
    required Map<String, dynamic> prePedido,
    required String lojaId,
    String baseUrl = 'https://app.mastepalm.com.br',
    String? lojaSlug,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('🛍️ Novo pedido');
    buffer.writeln('');

    // Itens
    final itens = (prePedido['itens'] as List?) ?? [];
    for (final item in itens) {
      final itemMap = Map<String, dynamic>.from(item as Map);
      final nome = catalogPedidoItemDisplayName(itemMap);
      final qty = item['quantidade'] ?? 1;
      final preco = (item['precoUnitario'] as num?)?.toDouble() ?? 0.0;
      final linhaVar =
          ProdutoVariacaoExtra.linhaVariacoesParaSeparacao(itemMap);

      if (linhaVar.isNotEmpty) {
        buffer.write('${qty}x $nome ($linhaVar)');
      } else {
        buffer.write('${qty}x $nome');
      }
      final comboLegivel = ComboConfiguravelResumo.textoParaItemMap(itemMap);
      if (comboLegivel.isNotEmpty) {
        final bloco = comboLegivel.replaceAll('\n', '\n   ');
        buffer.write('\n   $bloco');
      }

      final totalItem = preco * qty;
      buffer.writeln(
          ' – R\$ ${formatarValor(totalItem)}'); // ✅ CORRIGIDO: mostrar total do item (preco * qtd)
    }

    buffer.writeln('');

    // Valores
    final subtotal = (prePedido['subtotal'] as num?)?.toDouble() ?? 0.0;
    final frete = prePedido['frete'] as Map<String, dynamic>?;
    final freteNome = frete?['nome'] ?? 'Entrega';
    final freteValor = (frete?['valor'] as num?)?.toDouble() ?? 0.0;
    final freteGratis = frete?['gratis'] == true;
    final total = (prePedido['total'] as num?)?.toDouble() ?? 0.0;

    buffer.writeln('Subtotal: R\$ ${formatarValor(subtotal)}');

    if (freteGratis) {
      buffer.writeln('Entrega: $freteNome – R\$ 0,00');
    } else {
      buffer.writeln('Entrega: $freteNome – R\$ ${formatarValor(freteValor)}');
    }

    // Cupom (se houver)
    final cupom = prePedido['cupom'] as Map<String, dynamic>?;
    if (cupom != null) {
      final desconto = (cupom['desconto'] as num?)?.toDouble() ?? 0.0;
      if (desconto > 0) {
        buffer.writeln('Desconto: -R\$ ${formatarValor(desconto)}');
      }
    }

    buffer.writeln('Total: R\$ ${formatarValor(total)}');

    // Pagamento
    final pagamento = prePedido['pagamento'] ?? '';
    buffer.writeln('Pagamento: $pagamento');
    buffer.writeln('');

    // Cliente
    final cliente = prePedido['cliente'] as Map<String, dynamic>?;
    if (cliente != null) {
      buffer.writeln('Cliente: ${cliente['nome'] ?? ''}');
      final tel = (cliente['telefone'] ?? '').toString();
      if (tel.isNotEmpty) {
        buffer.writeln('Tel.: $tel');
      }
      final endereco = cliente['enderecoFormatado']?.toString() ?? '';
      if (endereco.isNotEmpty) {
        buffer.writeln('Endereço: $endereco');
      }
    }

    // ✅ Prêmio da Roleta (se houver)
    final premioRoleta = prePedido['premioRoleta'] as Map<String, dynamic>?;
    if (premioRoleta != null) {
      final tipo = premioRoleta['tipo']?.toString() ?? '';
      final descricao = premioRoleta['descricao']?.toString() ?? '';

      buffer.writeln('');
      buffer.writeln('🎁 PRÊMIO DA ROLETA:');

      if (tipo == 'brinde' && descricao.isNotEmpty) {
        buffer.writeln('   Brinde: $descricao');
        buffer.writeln('   ⚠️ Será entregue junto com o pedido');
      } else if (tipo == 'desconto') {
        final valor = (premioRoleta['valor'] as num?)?.toDouble() ?? 0.0;
        buffer.writeln('   Cupom de $valor% OFF');
        buffer.writeln(
            '   ⚠️ Válido para a próxima compra após pagamento confirmado');
      } else if (tipo == 'frete_gratis') {
        buffer.writeln('   Frete Grátis');
        buffer.writeln(
            '   ⚠️ Válido para a próxima compra após pagamento confirmado');
      }
    }

    // Observações
    final obs = (prePedido['observacao'] ?? '').toString().trim();
    if (obs.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('📝 Observações: $obs');
    }

    buffer.writeln('');

    // Link do pedido - usa HTTPS para ser clicável no WhatsApp
    final prePedidoId = prePedido['id'] ?? '';
    if (prePedidoId.isNotEmpty) {
      final url = gerarUrlPedido(
        prePedidoId: prePedidoId,
        lojaId: lojaId,
        baseUrl: baseUrl,
        useCustomScheme: false, // ✅ HTTPS para ser clicável
      );
      buffer.writeln('🔗 Ver pedido: $url');
    }

    return buffer.toString();
  }

  /// Formata valor monetário

  // ✅ Salva ou atualiza cliente no estoque_clientes (admin/histórico)
  /// DOMÍNIO ADMIN: estoque_clientes não é perfil do catálogo. Side-effect para historico admin.
  /// Identidade do catálogo está em clientes (via _ensureClienteComPortalToken).
  static Future<void> _salvarOuAtualizarCliente({
    required String lojaId,
    required Map<String, dynamic> customer,
    String? pedidoId,
    required double total,
  }) async {
    try {
      final telefone = (customer['telefone'] ?? '')
          .toString()
          .replaceAll(RegExp(r'[^0-9]'), '');

      if (telefone.isEmpty) {
        logD(
            '⚠️ [CLIENTE-AUTO-SAVE] Telefone vazio, não foi possível salvar cliente');
        return;
      }

      // Gerar ID único baseado no telefone
      final clienteId = telefone;

      // Verificar se cliente já existe
      final clienteRef = _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_clientes')
          .doc(clienteId);

      final clienteDoc = await clienteRef.get();
      final clienteExiste = clienteDoc.exists;

      if (clienteExiste) {
        // Cliente existe - atualizar informações
        logD(
            '🔄 [CLIENTE-AUTO-SAVE] Cliente já existe, atualizando dados...');

        final dados = clienteDoc.data() ?? {};

        await clienteRef.update({
          'nome': customer['nome'] ?? dados['nome'],
          'email': customer['email'] ?? dados['email'],
          'cpf': customer['cpf'] ?? dados['cpf'],
          'endereco': customer['endereco'] ?? dados['endereco'],
          'enderecoFormatado':
              customer['enderecoFormatado'] ?? dados['enderecoFormatado'],
          'updatedAt': FieldValue.serverTimestamp(),
        });

        logD(
            '✅ [CLIENTE-AUTO-SAVE] Cliente atualizado: ${customer['nome']}');
      } else {
        // Cliente novo - criar
        logD('📝 [CLIENTE-AUTO-SAVE] Criando novo cliente...');

        final clienteData = {
          'id': clienteId,
          'lojaId': lojaId,
          'nome': customer['nome'] ?? '',
          'telefone': customer['telefone'] ?? '',
          'email': customer['email'] ?? '',
          'cpf': customer['cpf'] ?? '',
          'endereco': customer['endereco'] ?? {},
          'enderecoFormatado': customer['enderecoFormatado'] ?? '',
          'instagram': '',
          'cep': (customer['endereco'] as Map?)?['cep'] ?? '',
          'cidade': (customer['endereco'] as Map?)?['cidade'] ?? '',
          'avatarUrl': null,

          // Histórico de compras
          'historicoCompras': [],
          'totalCompras': 0.0,
          'quantidadeCompras': 0,

          // Metadata
          'origem': 'catalogo_web',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        await clienteRef.set(clienteData);

        logD(
            '✅ [CLIENTE-AUTO-SAVE] Novo cliente criado: ${customer['nome']}');
      }
    } catch (e, st) {
      logE('❌ [CLIENTE-AUTO-SAVE] Erro ao salvar cliente (type=${e.runtimeType})', error: e, st: st);
    }
  }

  // ✅ Adiciona pedido ao histórico do cliente em estoque_clientes
  /// DOMÍNIO ADMIN: estoque_clientes (histórico para admin). Não é perfil do catálogo.
  static Future<void> _adicionarPedidoAoHistoricoCliente({
    required String lojaId,
    required Map<String, dynamic> customer,
    required String pedidoId,
    required double total,
  }) async {
    try {
      final telefone = (customer['telefone'] ?? '')
          .toString()
          .replaceAll(RegExp(r'[^0-9]'), '');

      if (telefone.isEmpty) return;

      final clienteId = telefone;

      final clienteRef = _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_clientes')
          .doc(clienteId);

      final clienteDoc = await clienteRef.get();
      if (!clienteDoc.exists) return;

      final dados = clienteDoc.data() ?? {};
      final historicoAtual =
          (dados['historicoCompras'] as List?)?.cast<Map<String, dynamic>>() ??
              [];
      final totalComprasAtual =
          (dados['totalCompras'] as num?)?.toDouble() ?? 0.0;
      final quantidadeComprasAtual = (dados['quantidadeCompras'] as int?) ?? 0;

      // Adicionar novo pedido ao histórico
      historicoAtual.add({
        'pedidoId': pedidoId,
        'data': FieldValue.serverTimestamp(),
        'total': total,
        'status': 'pendente', // pendente | confirmado | cancelado
      });

      await clienteRef.update({
        'historicoCompras': historicoAtual,
        'totalCompras': totalComprasAtual + total,
        'quantidadeCompras': quantidadeComprasAtual + 1,
        'ultimaCompra': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      logD(
          '✅ [CLIENTE-AUTO-SAVE] Pedido $pedidoId adicionado ao histórico do cliente');
    } catch (e, st) {
      logE(
          '❌ [CLIENTE-AUTO-SAVE] Erro ao adicionar pedido ao histórico (type=${e.runtimeType})', error: e, st: st);
    }
  }
}
