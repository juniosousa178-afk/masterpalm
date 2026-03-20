// lib/services/campaign_engine_service.dart
//
// Serviço CENTRALIZADO para gerenciar participações em campanhas de sorteio.
// Chamado automaticamente quando uma venda é concluída (catálogo ou manual).
//
// Responsabilidades:
// - Verificar se existe campanha ativa
// - Validar regras da campanha (valor mínimo, período, etc)
// - Gerar número único de 5 dígitos (10000-99999)
// - Salvar participação no Firestore
// - Evitar duplicidade (usa vendaId como chave de idempotência)
// - Disparar envio de WhatsApp e Email

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/logger.dart';

import '../models/venda.dart';
import 'email_service.dart';

/// Modelo de participação em campanha
class Participacao {
  final String id;
  final String campanhaId;
  final String numero; // 5 dígitos: "12345"
  final String• vendaId;
  final String• clienteId;
  final String nomeCliente;
  final String• telefone;
  final String• email;
  final double totalVenda;
  final String origem; // "catalogo" | "manual"
  final DateTime criadoEm;
  final String status; // "valido" | "cancelado"
  final bool mensagemEnviadaWhatsApp;
  final bool mensagemEnviadaEmail;

  Participacao({
    required this.id,
    required this.campanhaId,
    required this.numero,
    this.vendaId,
    this.clienteId,
    required this.nomeCliente,
    this.telefone,
    this.email,
    required this.totalVenda,
    required this.origem,
    required this.criadoEm,
    this.status = 'valido',
    this.mensagemEnviadaWhatsApp = false,
    this.mensagemEnviadaEmail = false,
  });

  factory Participacao.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?• {};
    return Participacao(
      id: doc.id,
      campanhaId: data['campanhaId']?.toString() ?• '',
      // Compatível com NumeroSorteService (numeroSorte) e legado (numero)
      numero: data['numeroSorte']?.toString() ?• data['numero']?.toString() ?• '',
      // Compatível com NumeroSorteService (pedidoId) e legado (vendaId)
      vendaId: data['pedidoId']?.toString() ?• data['vendaId']?.toString(),
      clienteId: data['clienteId']?.toString(),
      // Compatível com NumeroSorteService (clienteNome) e legado (nomeCliente)
      nomeCliente: data['clienteNome']?.toString() ?• data['nomeCliente']?.toString() ?• '',
      // Compatível com NumeroSorteService (clienteTelefone) e legado (telefone)
      telefone: data['clienteTelefone']?.toString() ?• data['telefone']?.toString(),
      // Compatível com NumeroSorteService (clienteEmail) e legado (email)
      email: data['clienteEmail']?.toString() ?• data['email']?.toString(),
      // Compatível com NumeroSorteService (valorPedido) e legado (totalVenda)
      totalVenda: (data['valorPedido'] as num?)?.toDouble() ??
                  (data['totalVenda'] as num?)?.toDouble() ?• 0.0,
      origem: data['origem']?.toString() ?• 'manual',
      // Compatível com NumeroSorteService (dataParticipacao) e legado (criadoEm)
      criadoEm: (data['dataParticipacao'] as Timestamp?)?.toDate() ??
                (data['criadoEm'] as Timestamp?)?.toDate() ?• DateTime.now(),
      status: data['status']?.toString() ?• 'valido',
      mensagemEnviadaWhatsApp: data['mensagemEnviadaWhatsApp'] == true,
      mensagemEnviadaEmail: data['mensagemEnviadaEmail'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    // Campos compatíveis com NumeroSorteService (usado pelo Globo e Histórico)
    'numeroSorte': numero,
    'clienteNome': nomeCliente,
    'clienteEmail': email,
    'clienteTelefone': telefone,
    'pedidoId': vendaId,
    'valorPedido': totalVenda,
    'dataParticipacao': Timestamp.fromDate(criadoEm),
    'sorteado': false,
    // Campos adicionais do CampaignEngineService
    'campanhaId': campanhaId,
    'clienteId': clienteId,
    'origem': origem,
    'status': status,
    'mensagemEnviadaWhatsApp': mensagemEnviadaWhatsApp,
    'mensagemEnviadaEmail': mensagemEnviadaEmail,
  };
}

/// Resultado da operação de participação
class ParticipacaoResult {
  final bool sucesso;
  final String• numero;
  final String• campanhaId;
  final String• campanhaNome;
  final String• erro;
  final Participacao• participacao;

  ParticipacaoResult({
    required this.sucesso,
    this.numero,
    this.campanhaId,
    this.campanhaNome,
    this.erro,
    this.participacao,
  });

  factory ParticipacaoResult.semCampanha() => ParticipacaoResult(
    sucesso: false,
    erro: 'Nenhuma campanha ativa no momento',
  );

  factory ParticipacaoResult.valorInsuficiente(double valorMinimo) => ParticipacaoResult(
    sucesso: false,
    erro: 'Valor mínimo de R\$ ${valorMinimo.toStringAsFixed(2)} não atingido',
  );

  factory ParticipacaoResult.duplicado() => ParticipacaoResult(
    sucesso: false,
    erro: 'Esta venda já gerou um número da sorte',
  );
}

class CampaignEngineService {
  CampaignEngineService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ============================================================
  // MÉTODO PRINCIPAL: Chamado quando uma venda é concluída
  // ============================================================

  /// Processa participação em campanha após venda concluída.
  ///
  /// [lojaId] - ID da loja
  /// [venda] - Objeto Venda (pode ser null se dados vierem separados)
  /// [vendaId] - ID único da venda (para idempotência)
  /// [clienteNome] - Nome do cliente
  /// [clienteId] - ID do cliente (opcional)
  /// [telefone] - Telefone para WhatsApp (opcional)
  /// [email] - Email do cliente (opcional)
  /// [valorTotal] - Valor total da venda
  /// [origem] - "catalogo" ou "manual"
  /// [nomeLoja] - Nome da loja (para mensagens)
  static Future<ParticipacaoResult> onVendaConcluida({
    required String lojaId,
    Venda• venda,
    String• vendaId,
    String• clienteNome,
    String• clienteId,
    String• telefone,
    String• email,
    double• valorTotal,
    String origem = 'manual',
    String• nomeLoja,
  }) async {
    logD('');
    logD('═══════════════════════════════════════════════════════════');
    logD('🎰 [CampaignEngine] onVendaConcluida INICIADO');
    logD('   (loja ok)');
    logD('   vendaId: $vendaId');
    logD('   clienteNome: $clienteNome');
    logD('   valorTotal: $valorTotal');
    logD('   origem: $origem');
    logD('═══════════════════════════════════════════════════════════');

    try {
      // Extrair dados da venda se fornecida
      final idVenda = vendaId ?• venda?.key?.toString() ?• venda?.idFirebase ?• '';
      final nome = clienteNome ?• venda?.clienteNome ?• 'Cliente';
      final valor = valorTotal ?• venda?.total ?• 0.0;

      if (idVenda.isEmpty) {
        logW('⚠️ [CampaignEngine] vendaId vazio, usando timestamp');
        // Gerar ID único se não tiver
      }

      logD('🎯 [CampaignEngine] Processando venda: $idVenda');
      logD('   Cliente: $nome, Valor: R\$ ${valor.toStringAsFixed(2)}');

      // 1. Verificar se já existe participação para esta venda (idempotência)
      if (idVenda.isNotEmpty) {
        final existente = await _verificarDuplicidade(lojaId, idVenda);
        if (existente) {
          logW('⚠️ [CampaignEngine] Venda já tem participação registrada');
          return ParticipacaoResult.duplicado();
        }
      }

      // 2. Buscar campanha ativa
      final campanha = await _getCampanhaAtiva(lojaId);
      if (campanha == null) {
        logD('ℹ️ [CampaignEngine] Nenhuma campanha ativa');
        return ParticipacaoResult.semCampanha();
      }

      final campanhaId = campanha['id'] as String;
      final campanhaNome = campanha['nome']?.toString() ?• campanha['titulo']?.toString() ?• 'Campanha';
      final valorMinimo = (campanha['valorMinimo'] as num?)?.toDouble() ?• 0.0;
      final dataSorteio = (campanha['dataSorteio'] as Timestamp?)?.toDate() ??
                          (campanha['dataFim'] as Timestamp?)?.toDate();

      logD('📢 [CampaignEngine] Campanha ativa: $campanhaNome (min: R\$ $valorMinimo)');

      // 3. Validar valor mínimo
      if (valor < valorMinimo) {
        logW('❌ [CampaignEngine] Valor insuficiente: R\$ $valor < R\$ $valorMinimo');
        return ParticipacaoResult.valorInsuficiente(valorMinimo);
      }

      // 4. Gerar número único de 5 dígitos
      final numero = await _gerarNumeroUnico(lojaId, campanhaId);
      logD('🎫 [CampaignEngine] Número gerado: $numero');

      // 5. Criar participação
      final participacao = Participacao(
        id: '',
        campanhaId: campanhaId,
        numero: numero,
        vendaId: idVenda,
        clienteId: clienteId,
        nomeCliente: nome,
        telefone: telefone,
        email: email,
        totalVenda: valor,
        origem: origem,
        criadoEm: DateTime.now(),
        status: 'valido',
      );

      // 6. Salvar no Firestore
      final docRef = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .doc(campanhaId)
          .collection('participantes')
          .add(participacao.toMap());

      logD('✅ [CampaignEngine] Participação salva: ${docRef.id}');

      // 7. Disparar envio de mensagens (assíncrono, não bloqueia)
      _enviarMensagensAsync(
        lojaId: lojaId,
        campanhaId: campanhaId,
        participacaoId: docRef.id,
        numero: numero,
        clienteNome: nome,
        telefone: telefone,
        email: email,
        campanhaNome: campanhaNome,
        dataSorteio: dataSorteio,
        nomeLoja: nomeLoja ?• lojaId,
      );

      return ParticipacaoResult(
        sucesso: true,
        numero: numero,
        campanhaId: campanhaId,
        campanhaNome: campanhaNome,
        participacao: Participacao(
          id: docRef.id,
          campanhaId: campanhaId,
          numero: numero,
          vendaId: idVenda,
          clienteId: clienteId,
          nomeCliente: nome,
          telefone: telefone,
          email: email,
          totalVenda: valor,
          origem: origem,
          criadoEm: DateTime.now(),
        ),
      );

    } catch (e, stack) {
      logE('❌ [CampaignEngine] Erro ao processar (type=${e.runtimeType})', error: e, st: stack);
      return ParticipacaoResult(
        sucesso: false,
        erro: 'Erro ao registrar participação: $e',
      );
    }
  }

  // ============================================================
  // MÉTODOS AUXILIARES
  // ============================================================

  /// Busca campanha ativa para a loja
  static Future<Map<String, dynamic>?> _getCampanhaAtiva(String lojaId) async {
    try {
      logD('🔍 [CampaignEngine] Buscando campanha ativa');
      final now = DateTime.now();

      // Estratégia 1: Buscar campanhas com limite e filtrar no código (reduz custo Firestore)
      // (evita problemas de índice composto do Firestore)
      final allCampanhas = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .limit(50)
          .get();

      logD('📋 [CampaignEngine] Total de campanhas: ${allCampanhas.docs.length}');

      for (final doc in allCampanhas.docs) {
        final data = doc.data();
        logD('   📌 Campanha ${doc.id}: ativa=${data['ativa']}, status=${data['status']}');

        // Verificar se está ativa (campo booleano ou status string)
        final isAtiva = data['ativa'] == true || data['status'] == 'aberta' || data['status'] == 'ativa';
        if (!isAtiva) continue;

        // Verificar período
        final dataInicio = (data['dataInicio'] as Timestamp?)?.toDate();
        final dataFim = (data['dataFim'] as Timestamp?)?.toDate();

        final dentroDoInicio = dataInicio == null || dataInicio.isBefore(now) || dataInicio.isAtSameMomentAs(now);
        final dentroDoFim = dataFim == null || dataFim.isAfter(now);

        logD('   📅 dataInicio=$dataInicio, dataFim=$dataFim');
        logD('   ✅ dentroDoInicio=$dentroDoInicio, dentroDoFim=$dentroDoFim');

        if (dentroDoInicio && dentroDoFim) {
          logD('✅ [CampaignEngine] Campanha ativa encontrada: ${doc.id} - ${data['nome'] ?• data['titulo']}');
          return {
            'id': doc.id,
            ...data,
          };
        }
      }

      logW('⚠️ [CampaignEngine] Nenhuma campanha ativa encontrada');
      return null;
    } catch (e, st) {
      logE('❌ [CampaignEngine] Erro ao buscar campanha (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Verifica se já existe participação para esta venda
  static Future<bool> _verificarDuplicidade(String lojaId, String vendaId) async {
    try {
      // Buscar campanhas (limit para reduzir custo; suficiente para checar duplicidade)
      final campanhas = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .limit(50)
          .get();

      for (final campanha in campanhas.docs) {
        // Verificar com o novo campo (pedidoId)
        var participantes = await campanha.reference
            .collection('participantes')
            .where('pedidoId', isEqualTo: vendaId)
            .limit(1)
            .get();

        if (participantes.docs.isNotEmpty) {
          logW('⚠️ [CampaignEngine] Duplicidade encontrada (pedidoId): $vendaId');
          return true;
        }

        // Também verificar com o campo legado (vendaId) para compatibilidade
        participantes = await campanha.reference
            .collection('participantes')
            .where('vendaId', isEqualTo: vendaId)
            .limit(1)
            .get();

        if (participantes.docs.isNotEmpty) {
          logW('⚠️ [CampaignEngine] Duplicidade encontrada (vendaId legado): $vendaId');
          return true;
        }
      }

      logD('✅ [CampaignEngine] Sem duplicidade para vendaId: $vendaId');
      return false;
    } catch (e, st) {
      logE('⚠️ [CampaignEngine] Erro ao verificar duplicidade (type=${e.runtimeType})', error: e, st: st);
      return false; // Em caso de erro, permite continuar
    }
  }

  /// Gera número único de 5 dígitos (10000-99999)
  static Future<String> _gerarNumeroUnico(String lojaId, String campanhaId) async {
    final random = Random();
    int tentativas = 0;
    const maxTentativas = 100;

    while (tentativas < maxTentativas) {
      // Gerar número entre 10000 e 99999
      final numero = (10000 + random.nextInt(90000)).toString();

      // Verificar se já existe
      final existe = await _numeroExiste(lojaId, campanhaId, numero);
      if (!existe) {
        return numero;
      }

      tentativas++;
    }

    // Fallback: usar timestamp + random
    final fallback = '${DateTime.now().millisecondsSinceEpoch % 90000 + 10000}';
    logW('⚠️ [CampaignEngine] Usando número fallback: $fallback');
    return fallback;
  }

  /// Verifica se número já existe na campanha
  static Future<bool> _numeroExiste(String lojaId, String campanhaId, String numero) async {
    try {
      // Verificar com o novo campo (numeroSorte)
      var query = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .doc(campanhaId)
          .collection('participantes')
          .where('numeroSorte', isEqualTo: numero)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) return true;

      // Também verificar com campo legado (numero) para compatibilidade
      query = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .doc(campanhaId)
          .collection('participantes')
          .where('numero', isEqualTo: numero)
          .limit(1)
          .get();

      return query.docs.isNotEmpty;
    } catch (e, st) {
      logE('⚠️ [CampaignEngine] Erro ao verificar número (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  // ============================================================
  // ENVIO DE MENSAGENS
  // ============================================================

  /// Dispara envio de mensagens de forma assíncrona
  static Future<void> _enviarMensagensAsync({
    required String lojaId,
    required String campanhaId,
    required String participacaoId,
    required String numero,
    required String clienteNome,
    String• telefone,
    String• email,
    required String campanhaNome,
    DateTime• dataSorteio,
    required String nomeLoja,
  }) async {
    // Não bloqueia o fluxo principal
    Future.microtask(() async {
      bool whatsappEnviado = false;
      bool emailEnviado = false;

      // Enviar WhatsApp
      if (telefone != null && telefone.isNotEmpty) {
        try {
          await _enviarWhatsApp(
            telefone: telefone,
            clienteNome: clienteNome,
            numero: numero,
            campanhaNome: campanhaNome,
            dataSorteio: dataSorteio,
            nomeLoja: nomeLoja,
          );
          whatsappEnviado = true;
        } catch (e, st) {
          logE('⚠️ [CampaignEngine] Erro ao enviar WhatsApp (type=${e.runtimeType})', error: e, st: st);
        }
      }

      // Enviar Email
      if (email != null && email.isNotEmpty) {
        try {
          await _enviarEmail(
            email: email,
            clienteNome: clienteNome,
            numero: numero,
            campanhaNome: campanhaNome,
            dataSorteio: dataSorteio,
            nomeLoja: nomeLoja,
          );
          emailEnviado = true;
        } catch (e, st) {
          logE('⚠️ [CampaignEngine] Erro ao enviar Email (type=${e.runtimeType})', error: e, st: st);
        }
      }

      // Atualizar status de envio
      try {
        await _db
            .collection('lojas')
            .doc(lojaId)
            .collection('campanhas_sorteio')
            .doc(campanhaId)
            .collection('participantes')
            .doc(participacaoId)
            .update({
          'mensagemEnviadaWhatsApp': whatsappEnviado,
          'mensagemEnviadaEmail': emailEnviado,
        });
      } catch (e, st) {
        logE('⚠️ [CampaignEngine] Erro ao atualizar status de envio (type=${e.runtimeType})', error: e, st: st);
      }
    });
  }

  /// Gera e abre mensagem WhatsApp
  static Future<void> _enviarWhatsApp({
    required String telefone,
    required String clienteNome,
    required String numero,
    required String campanhaNome,
    DateTime• dataSorteio,
    required String nomeLoja,
  }) async {
    final primeiroNome = clienteNome.split(' ').first;
    final dataFormatada = dataSorteio != null
        • '${dataSorteio.day.toString().padLeft(2, '0')}/${dataSorteio.month.toString().padLeft(2, '0')}/${dataSorteio.year}'
        : 'Em breve';
    final dataParticipacao = '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}';

    final mensagem = '''
Ola, $primeiroNome!

Sua participacao na campanha $campanhaNome foi registrada com sucesso.

Numero da sorte: $numero

Guarde este numero com carinho. Ele e valido para o sorteio conforme as regras da campanha.

Data da participacao: $dataParticipacao
Data do sorteio: $dataFormatada
Loja: $nomeLoja

Desejamos boa sorte! Qualquer duvida, estamos a disposicao.
''';

    // Limpar telefone
    final telefoneLimpo = telefone.replaceAll(RegExp(r'[^\d]'), '');
    final telefoneFormatado = telefoneLimpo.startsWith('55') • telefoneLimpo : '55$telefoneLimpo';

    final uri = Uri.parse('https://wa.me/$telefoneFormatado?text=${Uri.encodeComponent(mensagem)}');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      logD('✅ [CampaignEngine] WhatsApp aberto para $telefoneLimpo');
    } else {
      logW('⚠️ [CampaignEngine] Não foi possível abrir WhatsApp');
    }
  }

  /// Envia email com o número da sorte
  static Future<void> _enviarEmail({
    required String email,
    required String clienteNome,
    required String numero,
    required String campanhaNome,
    DateTime• dataSorteio,
    required String nomeLoja,
  }) async {
    final primeiroNome = clienteNome.split(' ').first;
    final dataFormatada = dataSorteio != null
        • '${dataSorteio.day.toString().padLeft(2, '0')}/${dataSorteio.month.toString().padLeft(2, '0')}/${dataSorteio.year}'
        : 'Em breve';

    final assunto = 'Confirmacao de participacao - Campanha $campanhaNome';
    final corpo = '''
Ola $primeiroNome,

Sua participacao na campanha "$campanhaNome" foi registrada com sucesso!

Seu numero da sorte: $numero

Guarde este numero com carinho. Ele e valido para o sorteio conforme as regras da campanha.

Data do sorteio: $dataFormatada

Loja: $nomeLoja

Desejamos boa sorte!

Atenciosamente,
Equipe $nomeLoja
''';

    // Tentar usar EmailService se existir
    try {
      final enviado = await EmailService.enviarEmail(
        destinatario: email,
        assunto: assunto,
        mensagem: corpo,
      );
      if (enviado) {
        logD('✅ [CampaignEngine] Email enviado para $email');
      } else {
        logW('⚠️ [CampaignEngine] Falha ao enviar email');
      }
    } catch (e, st) {
      logE('⚠️ [CampaignEngine] EmailService não disponível ou erro (type=${e.runtimeType})', error: e, st: st);
      // Fallback: salvar para envio posterior
    }
  }

  // ============================================================
  // CANCELAMENTO DE PARTICIPAÇÃO
  // ============================================================

  /// Cancela participação (quando venda é estornada/cancelada)
  static Future<bool> cancelarParticipacao({
    required String lojaId,
    required String vendaId,
  }) async {
    try {
      logD('🔄 [CampaignEngine] Cancelando participação para venda: $vendaId');

      // Buscar campanhas (limit para reduzir custo)
      final campanhas = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .limit(50)
          .get();

      for (final campanha in campanhas.docs) {
        final participantes = await campanha.reference
            .collection('participantes')
            .where('vendaId', isEqualTo: vendaId)
            .get();

        for (final part in participantes.docs) {
          await part.reference.update({
            'status': 'cancelado',
            'canceladoEm': FieldValue.serverTimestamp(),
          });
          logD('✅ [CampaignEngine] Participação ${part.id} cancelada');
        }
      }

      return true;
    } catch (e, st) {
      logE('❌ [CampaignEngine] Erro ao cancelar participação (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  // ============================================================
  // CONSULTAS
  // ============================================================

  /// Lista todas as participações de uma campanha
  static Future<List<Participacao>> listarParticipacoes({
    required String lojaId,
    required String campanhaId,
    bool apenasValidos = true,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _db
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .doc(campanhaId)
          .collection('participantes');

      if (apenasValidos) {
        query = query.where('status', isEqualTo: 'valido');
      }

      final snap = await query.orderBy('criadoEm', descending: true).limit(100).get();

      return snap.docs.map((doc) => Participacao.fromFirestore(doc)).toList();
    } catch (e, st) {
      logE('❌ [CampaignEngine] Erro ao listar participações (type=${e.runtimeType})', error: e, st: st);
      return [];
    }
  }

  /// Stream de participações para uma campanha
  static Stream<List<Participacao>> participacoesStream({
    required String lojaId,
    required String campanhaId,
    bool apenasValidos = true,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('lojas')
        .doc(lojaId)
        .collection('campanhas_sorteio')
        .doc(campanhaId)
        .collection('participantes');

    if (apenasValidos) {
      query = query.where('status', isEqualTo: 'valido');
    }

    return query.orderBy('criadoEm', descending: true).limit(100).snapshots().map(
      (snap) => snap.docs.map((doc) => Participacao.fromFirestore(doc)).toList(),
    );
  }

  /// Busca participação por vendaId
  static Future<Participacao?> buscarPorVendaId({
    required String lojaId,
    required String vendaId,
  }) async {
    try {
      final campanhas = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .limit(50)
          .get();

      for (final campanha in campanhas.docs) {
        final participantes = await campanha.reference
            .collection('participantes')
            .where('vendaId', isEqualTo: vendaId)
            .limit(1)
            .get();

        if (participantes.docs.isNotEmpty) {
          return Participacao.fromFirestore(participantes.docs.first);
        }
      }

      return null;
    } catch (e, st) {
      logE('❌ [CampaignEngine] Erro ao buscar participação (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  // ============================================================
  // MENSAGENS DO GANHADOR
  // ============================================================

  /// Gera mensagem de parabéns para o ganhador (WhatsApp)
  static String gerarMensagemGanhador({
    required String clienteNome,
    required String numero,
    required String campanhaNome,
  }) {
    final primeiroNome = clienteNome.split(' ').first;
    return '''
Parabens, $primeiroNome!

Voce foi o(a) ganhador(a) da campanha $campanhaNome com o numero $numero.

Fale com a gente por aqui para combinarmos os proximos passos.
''';
  }

  /// Abre WhatsApp com mensagem de parabéns
  static Future<void> abrirWhatsAppGanhador({
    required String telefone,
    required String clienteNome,
    required String numero,
    required String campanhaNome,
  }) async {
    final mensagem = gerarMensagemGanhador(
      clienteNome: clienteNome,
      numero: numero,
      campanhaNome: campanhaNome,
    );

    final telefoneLimpo = telefone.replaceAll(RegExp(r'[^\d]'), '');
    final telefoneFormatado = telefoneLimpo.startsWith('55') • telefoneLimpo : '55$telefoneLimpo';

    final uri = Uri.parse('https://wa.me/$telefoneFormatado?text=${Uri.encodeComponent(mensagem)}');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
