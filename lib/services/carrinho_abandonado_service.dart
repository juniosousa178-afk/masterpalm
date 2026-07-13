// lib/services/carrinho_abandonado_service.dart
// Recuperação de carrinho abandonado: listar e enviar lembrete por e-mail/WhatsApp.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'ai_loja_service.dart';
import 'catalog_public_url_service.dart';
import 'email_service.dart';

/// Resultado do envio de lembrete por e-mail (nunca marca enviado se [ok] for false).
class EnvioLembreteEmailResultado {
  const EnvioLembreteEmailResultado({
    required this.ok,
    required this.mensagem,
    this.emailUsado = '',
  });

  final bool ok;
  final String mensagem;
  final String emailUsado;
}

/// Configuração da recuperação de carrinho (salva em lojas/{lojaId}/config/config.carrinhoAbandonado)
class CarrinhoAbandonadoConfig {
  final bool ativo;
  final int horasAbandono;
  final bool enviarEmail;

  CarrinhoAbandonadoConfig({
    this.ativo = false,
    this.horasAbandono = 24,
    this.enviarEmail = true,
  });

  Map<String, dynamic> toMap() => {
        'ativo': ativo,
        'horasAbandono': horasAbandono,
        'enviarEmail': enviarEmail,
      };

  static CarrinhoAbandonadoConfig fromMap(Map<String, dynamic>? map) {
    if (map == null) return CarrinhoAbandonadoConfig();
    return CarrinhoAbandonadoConfig(
      ativo: map['ativo'] as bool? ?? false,
      horasAbandono: (map['horasAbandono'] as int?) ?? 24,
      enviarEmail: map['enviarEmail'] as bool? ?? true,
    );
  }
}

/// Dados de um cliente com carrinho abandonado
class CarrinhoAbandonadoItem {
  final String clienteId;
  final String nome;
  final String email;
  final String telefone;
  final List<Map<String, dynamic>> itens;
  final DateTime? ultimaAtualizacao;
  final DateTime? lembreteEnviadoEm;

  CarrinhoAbandonadoItem({
    required this.clienteId,
    required this.nome,
    required this.email,
    required this.telefone,
    required this.itens,
    this.ultimaAtualizacao,
    this.lembreteEnviadoEm,
  });

  int get totalItens =>
      itens.fold(0, (s, e) => s + ((e['quantidade'] as num?)?.toInt() ?? 1));
}

/// Status do carrinho na collection carrinhos_abandonados (catálogo público).
const String kCarrinhoStatusAtivo = 'ativo';
const String kCarrinhoStatusAbandonado = 'abandonado';
const String kCarrinhoStatusRecuperado = 'recuperado';

/// Item de carrinho abandonado vindo do catálogo (collection carrinhos_abandonados).
class CarrinhoAbandonadoCatalogoItem {
  final String cartId;
  final String lojaId;
  final List<Map<String, dynamic>> produtos;
  final String clienteNome;
  final String clienteTelefone;
  final String clienteWhatsapp;
  final String clienteEmail;
  final String clienteCpf;
  final String enderecoCompleto;
  final String cupom;
  final double frete;
  final double desconto;
  final double? totalOverride;
  final int visitasCatalogo;
  final int retornosCatalogo;
  final bool clienteRecorrente;
  final DateTime? criadoEm;
  final DateTime? ultimoUpdate;
  final String status;
  final Map<String, dynamic> raw;

  CarrinhoAbandonadoCatalogoItem({
    required this.cartId,
    required this.lojaId,
    required this.produtos,
    this.clienteNome = '',
    this.clienteTelefone = '',
    this.clienteWhatsapp = '',
    this.clienteEmail = '',
    this.clienteCpf = '',
    this.enderecoCompleto = '',
    this.cupom = '',
    this.frete = 0,
    this.desconto = 0,
    this.totalOverride,
    this.visitasCatalogo = 0,
    this.retornosCatalogo = 0,
    this.clienteRecorrente = false,
    this.criadoEm,
    this.ultimoUpdate,
    this.status = kCarrinhoStatusAtivo,
    this.raw = const {},
  });

  int get totalItens =>
      produtos.fold(0, (s, e) => s + ((e['quantidade'] as num?)?.toInt() ?? 1));

  String get telefoneEfetivo =>
      clienteWhatsapp.trim().isNotEmpty ? clienteWhatsapp : clienteTelefone;

  factory CarrinhoAbandonadoCatalogoItem.fromFirestore({
    required String cartId,
    required String lojaId,
    required Map<String, dynamic> d,
    required String status,
  }) {
    final produtosRaw = d['produtos'] ?? d['itens'] ?? d['items'];
    final produtos = produtosRaw is List
        ? produtosRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    final tsUpdate = d['ultimoUpdate'] ?? d['updatedAt'] ?? d['ultimaAtualizacao'];
    final ultimoUpdate = tsUpdate is Timestamp ? tsUpdate.toDate() : null;
    final tsCriado = d['criadoEm'] ?? d['createdAt'];
    final criadoEm = tsCriado is Timestamp ? tsCriado.toDate() : null;

    String endereco = (d['enderecoFormatado'] ??
            d['clienteEndereco'] ??
            d['enderecoCompleto'] ??
            '')
        .toString()
        .trim();
    if (endereco.isEmpty) {
      final end = d['endereco'] ?? d['clienteEnderecoMap'];
      if (end is Map) {
        final m = Map<String, dynamic>.from(end);
        endereco = [
          m['rua'] ?? m['logradouro'],
          m['numero'],
          m['complemento'],
          m['bairro'],
          m['cidade'],
          m['estado'],
          m['cep'],
          m['referencia'],
        ]
            .where((e) => e != null && e.toString().trim().isNotEmpty)
            .map((e) => e.toString().trim())
            .join(', ');
      }
    }

    double? asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.'));
      return null;
    }

    return CarrinhoAbandonadoCatalogoItem(
      cartId: cartId,
      lojaId: lojaId,
      produtos: produtos,
      clienteNome: (d['clienteNome'] ?? d['nome'] ?? '').toString(),
      clienteTelefone:
          (d['clienteTelefone'] ?? d['telefone'] ?? d['phone'] ?? '').toString(),
      clienteWhatsapp:
          (d['clienteWhatsapp'] ?? d['whatsapp'] ?? '').toString(),
      clienteEmail: (d['clienteEmail'] ?? d['email'] ?? '').toString(),
      clienteCpf: (d['clienteCpf'] ?? d['cpf'] ?? '').toString(),
      enderecoCompleto: endereco,
      cupom: (d['cupom'] ?? d['cupomCodigo'] ?? d['codigoCupom'] ?? '')
          .toString(),
      frete: asDouble(d['frete'] ?? d['freteValor'] ?? d['valorFrete']) ?? 0,
      desconto: asDouble(d['desconto'] ?? d['descontoValor']) ?? 0,
      totalOverride: asDouble(d['total'] ?? d['valorTotal']),
      visitasCatalogo: (d['visitasCatalogo'] as num?)?.toInt() ?? 0,
      retornosCatalogo: (d['retornosCatalogo'] as num?)?.toInt() ?? 0,
      clienteRecorrente: d['clienteRecorrente'] == true ||
          d['recorrente'] == true ||
          ((d['quantidadePedidosAnteriores'] as num?)?.toInt() ?? 0) > 0,
      criadoEm: criadoEm,
      ultimoUpdate: ultimoUpdate,
      status: status,
      raw: d,
    );
  }
}


/// Métricas simples de recuperação do catálogo (contagens por status).
class MetricasRecuperacaoCatalogo {
  final int abandonados;
  final int recuperados;

  const MetricasRecuperacaoCatalogo({
    this.abandonados = 0,
    this.recuperados = 0,
  });

  int get total => abandonados + recuperados;
  double get taxaRecuperacaoPercent =>
      total > 0 ? (recuperados / total) * 100 : 0.0;
}

class CarrinhoAbandonadoService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collectionCarrinhosAbandonados = 'carrinhos_abandonados';

  /// Minutos sem checkout para considerar carrinho abandonado (catálogo).
  static const int minutosAbandonoCatalogo = 30;

  static Future<CarrinhoAbandonadoConfig> getConfig(String lojaId) async {
    try {
      final doc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('config')
          .get();
      final data = doc.data();
      final raw = data?['carrinhoAbandonado'];
      return CarrinhoAbandonadoConfig.fromMap(
        raw is Map ? Map<String, dynamic>.from(Map.from(raw)) : null,
      );
    } catch (_) {
      return CarrinhoAbandonadoConfig();
    }
  }

  static Future<void> setConfig(
      String lojaId, CarrinhoAbandonadoConfig config) async {
    await _db
        .collection('lojas')
        .doc(lojaId)
        .collection('config')
        .doc('config')
        .set({'carrinhoAbandonado': config.toMap()}, SetOptions(merge: true));
  }

  /// Lista clientes com carrinho abandonado (carrinho não vazio + última atualização há mais de X horas).
  static Future<List<CarrinhoAbandonadoItem>> listarCarrinhosAbandonados({
    required String lojaId,
    int? horasAbandono,
  }) async {
    try {
      final config = await getConfig(lojaId);
      final horas = horasAbandono ?? config.horasAbandono;
      final limite = DateTime.now().subtract(Duration(hours: horas));

      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('clientes')
          .get();

      final lista = <CarrinhoAbandonadoItem>[];
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final carrinho = d['carrinho'];
        if (carrinho == null || carrinho is! List || carrinho.isEmpty) continue;

        final ts = d['ultimaAtualizacaoCarrinho'];
        final ultimaAtualizacao = ts is Timestamp ? ts.toDate() : null;
        if (ultimaAtualizacao == null || ultimaAtualizacao.isAfter(limite)) {
          continue;
        }

        final lembreteTs = d['lembreteCarrinhoEnviadoEm'];
        final lembreteEnviadoEm =
            lembreteTs is Timestamp ? lembreteTs.toDate() : null;

        final itens =
            carrinho.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        lista.add(CarrinhoAbandonadoItem(
          clienteId: doc.id,
          nome: (d['nome'] ?? 'Cliente').toString(),
          email: (d['email'] ?? '').toString(),
          telefone: (d['telefone'] ?? d['whatsapp'] ?? '').toString(),
          itens: itens,
          ultimaAtualizacao: ultimaAtualizacao,
          lembreteEnviadoEm: lembreteEnviadoEm,
        ));
      }
      lista.sort((a, b) => (a.ultimaAtualizacao ?? DateTime(0))
          .compareTo(b.ultimaAtualizacao ?? DateTime(0)));
      return lista;
    } catch (e) {
      debugPrint('⚠️ [CARRINHO-ABANDONADO] Erro ao listar: $e');
      return [];
    }
  }

  /// Mensagem padrão do lembrete.
  static String mensagemLembrete(String nomeCliente, String link) {
    return 'Olá, $nomeCliente! Você deixou itens no carrinho. Que tal finalizar sua compra? Acesse: $link';
  }

  /// Template com itens (texto plano + HTML) para e-mail de recuperação.
  static ({String texto, String html}) montarTemplateLembrete({
    required String nomeCliente,
    required String link,
    String? nomeLoja,
    List<Map<String, dynamic>>? produtos,
  }) {
    final nome = nomeCliente.trim().isEmpty ? 'cliente' : nomeCliente.trim();
    final loja = (nomeLoja ?? 'nossa loja').trim().isEmpty
        ? 'nossa loja'
        : nomeLoja!.trim();
    final buf = StringBuffer();
    buf.writeln('Olá, $nome!');
    buf.writeln('');
    buf.writeln(
        'Você deixou itens no carrinho da $loja. Que tal finalizar sua compra?');
    buf.writeln('');
    if (produtos != null && produtos.isNotEmpty) {
      buf.writeln('Itens:');
      for (final p in produtos) {
        final n = (p['nome'] ?? p['name'] ?? 'Produto').toString();
        final q = (p['quantidade'] as num?)?.toInt() ?? 1;
        final cor = (p['cor'] ?? '').toString().trim();
        final tam = (p['tamanho'] ?? '').toString().trim();
        final extras = [
          if (cor.isNotEmpty) 'cor $cor',
          if (tam.isNotEmpty) 'tam $tam',
        ].join(', ');
        buf.writeln(extras.isEmpty ? '  • ${q}x $n' : '  • ${q}x $n ($extras)');
      }
      buf.writeln('');
    }
    buf.writeln('Acesse seu carrinho: $link');
    buf.writeln('');
    buf.writeln('Se já finalizou a compra, ignore este e-mail.');
    final texto = buf.toString();
    final escaped = texto
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');
    final html =
        '<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;font-size:14px;color:#333;line-height:1.5;">$escaped</body></html>';
    return (texto: texto, html: html);
  }

  static String? _normalizarEmail(String? raw) {
    final e = (raw ?? '').trim().toLowerCase();
    if (e.isEmpty || !e.contains('@') || e.startsWith('@') || e.endsWith('@')) {
      return null;
    }
    return e;
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// Localiza e-mail do cliente: campo direto → doc clientes da loja (tel/id) → raw do carrinho.
  static Future<String?> resolverEmailCliente({
    required String lojaId,
    String? emailDireto,
    String? clienteId,
    String? telefone,
    String? whatsapp,
    Map<String, dynamic>? rawCarrinho,
  }) async {
    final direto = _normalizarEmail(emailDireto);
    if (direto != null) return direto;

    if (rawCarrinho != null) {
      final fromRaw = _normalizarEmail(
        (rawCarrinho['clienteEmail'] ??
                rawCarrinho['email'] ??
                rawCarrinho['cliente_email'])
            ?.toString(),
      );
      if (fromRaw != null) return fromRaw;
    }

    if (lojaId.trim().isEmpty) return null;

    try {
      final col = _db.collection('lojas').doc(lojaId).collection('clientes');
      if (clienteId != null && clienteId.trim().isNotEmpty) {
        final doc = await col.doc(clienteId.trim()).get();
        if (doc.exists) {
          final fromId = _normalizarEmail(doc.data()?['email']?.toString());
          if (fromId != null) return fromId;
        }
      }

      final telCandidates = <String>{
        _digits(telefone ?? ''),
        _digits(whatsapp ?? ''),
        if (rawCarrinho != null)
          _digits((rawCarrinho['clienteTelefone'] ??
                  rawCarrinho['telefone'] ??
                  rawCarrinho['whatsapp'] ??
                  '')
              .toString()),
      }.where((t) => t.length >= 10).toSet();

      if (telCandidates.isEmpty) return null;

      final snap = await col.get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final t = _digits((d['telefone'] ?? d['whatsapp'] ?? '').toString());
        if (t.length < 10) continue;
        final match = telCandidates.any(
          (c) => t == c || t.endsWith(c) || c.endsWith(t),
        );
        if (!match) continue;
        final found = _normalizarEmail(d['email']?.toString());
        if (found != null) return found;
      }
    } catch (e) {
      debugPrint('⚠️ [CARRINHO-ABANDONADO] resolverEmailCliente: $e');
    }
    return null;
  }

  /// Envia via Cloud Function `sendEmail` (web) com fallback SMTP nativo.
  /// Não grava marcação — caller só marca se [EnvioLembreteEmailResultado.ok].
  static Future<bool> _entregarEmail({
    required String lojaId,
    required String destinatario,
    required String assunto,
    required String texto,
    required String html,
    String? remetenteNome,
  }) async {
    try {
      final projectId = Firebase.app().options.projectId;
      final response = await http.post(
        Uri.parse(
          'https://southamerica-east1-$projectId.cloudfunctions.net/sendEmail',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'to': destinatario,
          'subject': assunto,
          'html': html,
          'text': texto,
          'lojaId': lojaId,
        }),
      );
      if (response.statusCode == 200) {
        debugPrint('✅ [CARRINHO-ABANDONADO] Email CF OK → $destinatario');
        return true;
      }
      debugPrint(
        '⚠️ [CARRINHO-ABANDONADO] CF email ${response.statusCode}: ${response.body}',
      );
    } catch (e) {
      debugPrint(
        '⚠️ [CARRINHO-ABANDONADO] CF email falhou (type=${e.runtimeType})',
      );
    }

    // SMTP direto não funciona no navegador; evita falso negativo silencioso.
    if (kIsWeb) return false;

    try {
      return await EmailService.enviarEmail(
        destinatario: destinatario,
        assunto: assunto,
        mensagem: texto,
        remetenteNome: remetenteNome ?? 'Loja',
      );
    } catch (e) {
      debugPrint('⚠️ [CARRINHO-ABANDONADO] SMTP falhou (type=${e.runtimeType})');
      return false;
    }
  }

  /// Envia lembrete por e-mail (cliente da loja) e marca no Firestore só se entregue.
  static Future<EnvioLembreteEmailResultado> enviarLembreteEmail({
    required String lojaId,
    required String clienteId,
    required String emailDestino,
    required String nomeCliente,
    String? nomeLoja,
    String? telefone,
    List<Map<String, dynamic>>? itens,
  }) async {
    final email = await resolverEmailCliente(
      lojaId: lojaId,
      emailDireto: emailDestino,
      clienteId: clienteId,
      telefone: telefone,
    );
    if (email == null) {
      return const EnvioLembreteEmailResultado(
        ok: false,
        mensagem: 'E-mail do cliente não encontrado ou inválido',
      );
    }
    final link =
        await CatalogPublicUrlService.montarUrlCatalogoPublicoAsync(lojaId);
    final assunto =
        'Você deixou itens no carrinho${nomeLoja != null && nomeLoja.isNotEmpty ? ' - $nomeLoja' : ''}';
    final tpl = montarTemplateLembrete(
      nomeCliente: nomeCliente,
      link: link,
      nomeLoja: nomeLoja,
      produtos: itens,
    );
    try {
      final ok = await _entregarEmail(
        lojaId: lojaId,
        destinatario: email,
        assunto: assunto,
        texto: tpl.texto,
        html: tpl.html,
        remetenteNome: nomeLoja,
      );
      if (!ok) {
        return EnvioLembreteEmailResultado(
          ok: false,
          mensagem: 'Falha ao enviar e-mail para $email',
          emailUsado: email,
        );
      }
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('clientes')
          .doc(clienteId)
          .update({'lembreteCarrinhoEnviadoEm': FieldValue.serverTimestamp()});
      return EnvioLembreteEmailResultado(
        ok: true,
        mensagem: 'E-mail enviado para $email',
        emailUsado: email,
      );
    } catch (e) {
      debugPrint('⚠️ [CARRINHO-ABANDONADO] Erro ao enviar email: $e');
      return EnvioLembreteEmailResultado(
        ok: false,
        mensagem: 'Erro ao enviar e-mail',
        emailUsado: email,
      );
    }
  }

  /// E-mail de lembrete para carrinho do catálogo. Só marca enviado se CF/SMTP OK.
  static Future<EnvioLembreteEmailResultado> enviarLembreteEmailCatalogo({
    required String lojaId,
    required String cartId,
    required String emailDestino,
    required String nomeCliente,
    required String linkRecuperacao,
    String? nomeLoja,
    String? telefone,
    String? whatsapp,
    List<Map<String, dynamic>>? produtos,
    Map<String, dynamic>? raw,
  }) async {
    final email = await resolverEmailCliente(
      lojaId: lojaId,
      emailDireto: emailDestino,
      telefone: telefone,
      whatsapp: whatsapp,
      rawCarrinho: raw,
    );
    if (email == null) {
      return const EnvioLembreteEmailResultado(
        ok: false,
        mensagem: 'E-mail do cliente não encontrado ou inválido',
      );
    }
    final assunto =
        'Você deixou itens no carrinho${nomeLoja != null && nomeLoja.isNotEmpty ? ' - $nomeLoja' : ''}';
    final tpl = montarTemplateLembrete(
      nomeCliente: nomeCliente,
      link: linkRecuperacao,
      nomeLoja: nomeLoja,
      produtos: produtos,
    );
    try {
      final ok = await _entregarEmail(
        lojaId: lojaId,
        destinatario: email,
        assunto: assunto,
        texto: tpl.texto,
        html: tpl.html,
        remetenteNome: nomeLoja,
      );
      if (!ok) {
        return EnvioLembreteEmailResultado(
          ok: false,
          mensagem: 'Falha ao enviar e-mail para $email',
          emailUsado: email,
        );
      }
      if (cartId.trim().isNotEmpty) {
        await _db
            .collection('lojas')
            .doc(lojaId)
            .collection(_colCarrinhos(lojaId))
            .doc(cartId)
            .set({
          'lembreteEmailEnviadoEm': FieldValue.serverTimestamp(),
          'lembreteEmailDestino': email,
          if (_normalizarEmail(emailDestino) == null) 'clienteEmail': email,
        }, SetOptions(merge: true));
      }
      return EnvioLembreteEmailResultado(
        ok: true,
        mensagem: 'E-mail enviado para $email',
        emailUsado: email,
      );
    } catch (e) {
      debugPrint('⚠️ [CARRINHO-ABANDONADO] Erro email catálogo: $e');
      return EnvioLembreteEmailResultado(
        ok: false,
        mensagem: 'Erro ao enviar e-mail',
        emailUsado: email,
      );
    }
  }

  /// Abre o WhatsApp com mensagem pré-preenchida para enviar ao cliente (admin envia manualmente).
  static Future<bool> abrirWhatsAppLembrete({
    required String telefone,
    required String nomeCliente,
    required String link,
  }) async {
    final tel = telefone.replaceAll(RegExp(r'[^0-9]'), '');
    if (tel.length < 10) return false;
    final numero = tel.startsWith('55') ? tel : '55$tel';
    final msg = mensagemLembrete(nomeCliente, link);
    final uri =
        Uri.parse('https://wa.me/$numero?text=${Uri.encodeComponent(msg)}');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Carrinhos abandonados do catálogo (lojas/{lojaId}/carrinhos_abandonados)
  // ═══════════════════════════════════════════════════════════════════════════

  static String _colCarrinhos(String lojaId) => _collectionCarrinhosAbandonados;

  /// Registra ou atualiza carrinho do catálogo (ao adicionar itens).
  static Future<void> registrarCarrinho({
    required String lojaId,
    required String cartId,
    required List<Map<String, dynamic>> produtos,
    String clienteNome = '',
    String clienteTelefone = '',
  }) async {
    if (lojaId.trim().isEmpty || cartId.trim().isEmpty) return;
    try {
      final ref = _db
          .collection('lojas')
          .doc(lojaId)
          .collection(_colCarrinhos(lojaId))
          .doc(cartId);
      final now = FieldValue.serverTimestamp();
      await ref.set({
        'cartId': cartId,
        'lojaId': lojaId,
        'produtos': produtos,
        'clienteNome': clienteNome.trim(),
        'clienteTelefone': clienteTelefone.trim(),
        'criadoEm': now,
        'ultimoUpdate': now,
        'status': kCarrinhoStatusAtivo,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ [CARRINHO-ABANDONADO] registrarCarrinho: $e');
    }
  }

  /// Marca carrinho como abandonado.
  static Future<void> marcarAbandonado(String lojaId, String cartId) async {
    if (lojaId.trim().isEmpty || cartId.trim().isEmpty) return;
    try {
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(_colCarrinhos(lojaId))
          .doc(cartId)
          .update({
        'status': kCarrinhoStatusAbandonado,
        'ultimoUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ [CARRINHO-ABANDONADO] marcarAbandonado: $e');
    }
  }

  /// Marca carrinho como recuperado (após checkout).
  static Future<void> recuperarCarrinho(String lojaId, String cartId) async {
    if (lojaId.trim().isEmpty || cartId.trim().isEmpty) return;
    try {
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(_colCarrinhos(lojaId))
          .doc(cartId)
          .update({
        'status': kCarrinhoStatusRecuperado,
        'ultimoUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ [CARRINHO-ABANDONADO] recuperarCarrinho: $e');
    }
  }

  /// Retorna os produtos do carrinho por ID (para link de recuperação). Null se não existir ou já recuperado.
  static Future<List<Map<String, dynamic>>?> getCarrinhoPorId(
      String lojaId, String cartId) async {
    if (lojaId.trim().isEmpty || cartId.trim().isEmpty) return null;
    try {
      final doc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(_colCarrinhos(lojaId))
          .doc(cartId)
          .get();
      if (!doc.exists) return null;
      final d = doc.data();
      if (d == null) return null;
      final status = (d['status'] ?? '').toString();
      if (status == kCarrinhoStatusRecuperado) return null;
      final produtos = d['produtos'];
      if (produtos is! List || produtos.isEmpty) return null;
      return produtos.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('⚠️ [CARRINHO-ABANDONADO] getCarrinhoPorId: $e');
      return null;
    }
  }

  /// Lista carrinhos abandonados do catálogo. Considera ativo com ultimoUpdate > X min como abandonado e atualiza status.
  static Future<List<CarrinhoAbandonadoCatalogoItem>>
      listarCarrinhosAbandonadosCatalogo({
    required String lojaId,
    int minutosAbandono = minutosAbandonoCatalogo,
  }) async {
    if (lojaId.trim().isEmpty) return [];
    try {
      final limite =
          DateTime.now().subtract(Duration(minutes: minutosAbandono));
      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(_colCarrinhos(lojaId))
          .get();
      final lista = <CarrinhoAbandonadoCatalogoItem>[];
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final status = (d['status'] ?? '').toString();
        final produtosRaw = d['produtos'];
        final produtos = produtosRaw is List
            ? (produtosRaw)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
            : <Map<String, dynamic>>[];
        if (produtos.isEmpty &&
            (d['itens'] is! List || (d['itens'] as List).isEmpty)) {
          continue;
        }

        final tsUpdate = d['ultimoUpdate'];
        final ultimoUpdate = tsUpdate is Timestamp ? tsUpdate.toDate() : null;

        if (status == kCarrinhoStatusAtivo &&
            ultimoUpdate != null &&
            ultimoUpdate.isBefore(limite)) {
          await marcarAbandonado(lojaId, doc.id);
        }

        final considerAbandonado = status == kCarrinhoStatusAbandonado ||
            (status == kCarrinhoStatusAtivo &&
                ultimoUpdate != null &&
                ultimoUpdate.isBefore(limite));
        if (!considerAbandonado && status != kCarrinhoStatusAtivo) continue;

        lista.add(
          CarrinhoAbandonadoCatalogoItem.fromFirestore(
            cartId: doc.id,
            lojaId: lojaId,
            d: d,
            status: considerAbandonado ? kCarrinhoStatusAbandonado : status,
          ),
        );
      }
      lista.sort((a, b) => (b.ultimoUpdate ?? DateTime(0))
          .compareTo(a.ultimoUpdate ?? DateTime(0)));
      return lista;
    } catch (e) {
      debugPrint(
          '⚠️ [CARRINHO-ABANDONADO] listarCarrinhosAbandonadosCatalogo: $e');
      return [];
    }
  }

  /// Contagens por status (abandonado / recuperado) para métricas. Só leitura; não altera dados.
  static Future<MetricasRecuperacaoCatalogo> getMetricasRecuperacaoCatalogo(
      String lojaId) async {
    if (lojaId.trim().isEmpty) return const MetricasRecuperacaoCatalogo();
    try {
      final ref =
          _db.collection('lojas').doc(lojaId).collection(_colCarrinhos(lojaId));
      final snapAbandonados = await ref
          .where('status', isEqualTo: kCarrinhoStatusAbandonado)
          .count()
          .get();
      final snapRecuperados = await ref
          .where('status', isEqualTo: kCarrinhoStatusRecuperado)
          .count()
          .get();
      final abandonados = snapAbandonados.count ?? 0;
      final recuperados = snapRecuperados.count ?? 0;
      return MetricasRecuperacaoCatalogo(
          abandonados: abandonados, recuperados: recuperados);
    } catch (e) {
      debugPrint('⚠️ [CARRINHO-ABANDONADO] getMetricasRecuperacaoCatalogo: $e');
      return const MetricasRecuperacaoCatalogo();
    }
  }

  /// Mensagem WhatsApp para recuperação de carrinho (catálogo). Fallback quando IA não está disponível.
  static String mensagemWhatsAppRecuperacao(
      String nomeLoja, String linkRecuperacao) {
    return 'Olá! Você deixou itens no carrinho da loja $nomeLoja. Deseja finalizar? $linkRecuperacao';
  }

  /// Sugere mensagem de recuperação via IA (tipo recuperacaoCarrinho). Em falha, retorna mensagem fixa.
  static Future<String> sugerirMensagemRecuperacaoCatalogo({
    required String nomeLoja,
    required String linkRecuperacao,
    String clienteNome = '',
    List<Map<String, dynamic>>? produtos,
    DateTime? ultimoUpdate,
  }) async {
    final buffer = StringBuffer();
    buffer.write('Loja: $nomeLoja. ');
    if (clienteNome.trim().isNotEmpty) {
      buffer.write('Cliente: ${clienteNome.trim()}. ');
    }
    double? valorTotal;
    if (produtos != null && produtos.isNotEmpty) {
      final resumos = <String>[];
      double soma = 0.0;
      for (final p in produtos.take(10)) {
        final nome = (p['nome'] ?? p['produtoNome'] ?? 'item').toString();
        final qtd = (p['quantidade'] as num?)?.toInt() ?? 1;
        resumos.add('$nome ($qtd)');
        final precoRaw =
            p['preco'] ?? p['preco_venda'] ?? p['price'] ?? p['precoFinal'];
        final preco = precoRaw is num
            ? precoRaw.toDouble()
            : double.tryParse('$precoRaw');
        if (preco != null && preco > 0) soma += preco * qtd;
      }
      if (resumos.isNotEmpty) buffer.write('Itens: ${resumos.join(", ")}. ');
      if (soma > 0) valorTotal = soma;
    }
    if (valorTotal != null) {
      buffer.write(
          'Valor total do carrinho: R\$ ${valorTotal.toStringAsFixed(2).replaceAll('.', ',')}. ');
    }
    if (ultimoUpdate != null) {
      final diff = DateTime.now().difference(ultimoUpdate);
      final horas = diff.inHours;
      final min = diff.inMinutes % 60;
      if (horas > 0) {
        buffer.write('Abandonado há ${horas}h${min > 0 ? " ${min}min" : ""}. ');
      } else {
        buffer.write('Abandonado há ${diff.inMinutes} min. ');
      }
    }
    buffer.write(
        'Link de recuperação: $linkRecuperacao. Objetivo: mensagem curta para WhatsApp que incentive a finalizar a compra, incluindo o link.');
    try {
      final msg = await AiLojaService.sugerirMensagemWhatsApp(
        tipo: 'recuperacaoCarrinho',
        contexto: buffer.toString(),
      );
      return (msg.trim().isNotEmpty)
          ? msg.trim()
          : mensagemWhatsAppRecuperacao(nomeLoja, linkRecuperacao);
    } catch (e) {
      debugPrint('⚠️ [CARRINHO-ABANDONADO] IA recuperação: $e');
      return mensagemWhatsAppRecuperacao(nomeLoja, linkRecuperacao);
    }
  }

  /// Abre WhatsApp com mensagem de recuperação de carrinho (catálogo).
  /// [mensagem] opcional: usa mensagem sugerida pela IA; se null, usa mensagem fixa.
  static Future<bool> abrirWhatsAppRecuperacaoCatalogo({
    required String telefone,
    required String nomeLoja,
    required String linkRecuperacao,
    String? mensagem,
  }) async {
    final tel = telefone.replaceAll(RegExp(r'[^0-9]'), '');
    if (tel.length < 10) return false;
    final numero = tel.startsWith('55') ? tel : '55$tel';
    final msg =
        mensagem ?? mensagemWhatsAppRecuperacao(nomeLoja, linkRecuperacao);
    final uri =
        Uri.parse('https://wa.me/$numero?text=${Uri.encodeComponent(msg)}');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
