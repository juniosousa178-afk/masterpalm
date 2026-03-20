// lib/services/plano_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

final logger = Logger();

class PlanoService {
  static final _db = FirebaseFirestore.instance;

  /// ----- Helpers privados -----
  static DocumentReference<Map<String, dynamic>> _userDocByEmail(String email) {
    return _db.collection('usuarios').doc(email.toLowerCase().trim());
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> _getByEmail(
      String email) {
    return _userDocByEmail(email).get();
  }

  /// Quando precisar achar pelo UID (compat com bases antigas):
  /// procura `usuarios` onde `authUid == uid` e retorna o primeiro.
  static Future<DocumentSnapshot<Map<String, dynamic>>?>
      _findDocByUid(String uid) async {
    final q = await _db
        .collection('usuarios')
        .where('authUid', isEqualTo: uid)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return q.docs.first;
  }

  /// ✅ Lê o plano de permissões a partir de um UID específico (compat).
  /// Procura o doc por `authUid == uid`. Se não achar, retorna {}.
  static Future<Map<String, bool>> getPlanoByUid(String uid) async {
    try {
      final snap = await _findDocByUid(uid);
      if (snap == null || !snap.exists) return {};
      final data = snap.data() ?• const <String, dynamic>{};
      final raw = data['permissoes'];
      if (raw is Map) {
        return Map<String, bool>.from(
          raw.map((k, v) => MapEntry(k.toString(), (v is bool) • v : v == true)),
        );
      }
      return {};
    } catch (e) {
      logger.e('Erro ao carregar plano por UID ($uid) (type=${e.runtimeType})');
      return {};
    }
  }

  /// 🔐 Salvar plano de permissões (no doc do E-MAIL informado)
  static Future<void> salvarPlano(
      String email, Map<String, bool> permissoes) async {
    try {
      await _ensureUserDoc(email); // garante doc e campo email
      await _userDocByEmail(email)
          .set({'permissoes': permissoes}, SetOptions(merge: true));
    } catch (e) {
      logger.e('Erro ao salvar plano no Firebase (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// 🔎 Buscar plano do usuário por E-MAIL.
  /// Se não existir, aplica padrão baseado no `tipo` (ou vendedor).
  static Future<Map<String, bool>> getPlano(String email) async {
    try {
      final snap = await _getByEmail(email);
      if (!snap.exists) {
        // Sem doc: retorna padrão de vendedor (seguro)
        final defaults = permissoesPorTipo('vendedor');
        return defaults;
      }

      final data = snap.data() ?• const <String, dynamic>{};
      final raw = data['permissoes'];

      if (raw is Map) {
        final map = Map<String, bool>.from(
          raw.map((k, v) => MapEntry(k.toString(), (v is bool) • v : v == true)),
        );
        if (map.isNotEmpty) return map;
        // Sem permissões definidas → usa o tipo, se existir
        final tipo = (data['tipo'] ?• 'vendedor').toString().toLowerCase();
        final defaults = permissoesPorTipo(tipo);
        return defaults;
      }

      // Sem campo "permissoes" → padrão por tipo
      final tipo = (data['tipo'] ?• 'vendedor').toString().toLowerCase();
      final defaults = permissoesPorTipo(tipo);
      return defaults;
    } catch (e) {
      logger.e('Erro ao buscar plano no Firebase (type=${e.runtimeType})');
      return {};
    }
  }

  /// 🧩 Ativar permissões padrão (sobrescreve/merge) para um e-mail específico
  static Future<void> ativarTodas(String email, List<String> permissoes) async {
    final mapa = {for (var p in permissoes) p: true};
    try {
      await _ensureUserDoc(email);
      await _userDocByEmail(email)
          .set({'permissoes': mapa}, SetOptions(merge: true));
    } catch (e) {
      logger.e('Erro ao ativar permissões padrão (type=${e.runtimeType})');
    }
  }

  /// ♻️ Restaura permissões padrão (por e-mail)
  static Future<void> resetarParaPadrao(String email) async {
    final snap = await _getByEmail(email);
    final tipo = (snap.data()?['tipo'] ?• 'vendedor').toString().toLowerCase();
    final defaults = permissoesPorTipo(tipo);
    await salvarPlano(email, defaults);
  }

  /// 🌱 Garante que o doc do usuário (por e-mail) exista e tenha o campo "email"
  static Future<void> _ensureUserDoc(String email) async {
    final ref = _userDocByEmail(email);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else if ((snap.data()?['email'] ?• '') != email) {
      await ref.set({'email': email}, SetOptions(merge: true));
    }
  }

  // 🔁 Lista de permissões padrão (superconjunto para conveniência)
  static const List<String> permissoesPadrao = [
    // Loja / Catálogo
    'catalogo_publico',
    'catalogo', // alias legado
    'minha_loja',
    'configuaracoes_catalogo', // (sic) mantém a mesma key usada nas rotas

    // Operação
    'estoque',
    'vendas',
    'clientes',
    'fornecedores',
    'precificacao',

    // Relatórios
    'relatorios',
    'relatorio_financeiro',
    'historico_cliente',

    // Administração / Segurança
    'cadastro_usuarios',
    'licenca',
    'alterar_pin',
    'backup',
  ];

  /// 🔁 Permissões por tipo
  static Map<String, bool> permissoesPorTipo(String tipo) {
    switch (tipo) {
      case 'programador':
        return {for (var p in permissoesPadrao) p: true};
      case 'admin':
        return {for (var p in permissoesPadrao) p: true};
      default: // vendedor
        return {
          'catalogo': true,
          'catalogo_publico': true,
          'minha_loja': false,
          'configuaracoes_catalogo': false,
          'estoque': true,
          'vendas': true,
          'clientes': true,
          'fornecedores': false,
          'precificacao': false,
          'relatorios': false,
          'relatorio_financeiro': false,
          'historico_cliente': true,
          'cadastro_usuarios': false,
          'licenca': false,
          'alterar_pin': false,
          'backup': false,
        };
    }
  }
}
