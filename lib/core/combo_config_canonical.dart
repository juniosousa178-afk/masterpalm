// Estrutura canônica persistida em [Produto.comboConfig] (Fase 1: modelo + sync).
// UI e regras de negócio completas vêm em fases seguintes.

/// Chaves do mapa [Produto.comboConfig].
abstract final class ComboConfigKeys {
  static const String version = 'version';
  static const String grupos = 'grupos';
  static const String precoBase = 'precoBase';

  /// Campos por grupo (documentação; validação rígida nas fases de UI).
  static const String grupoId = 'id';
  static const String grupoTitulo = 'titulo';
  static const String grupoTipo = 'tipo';
  static const String grupoObrigatorio = 'obrigatorio';
  static const String grupoSelecaoMin = 'selecaoMin';
  static const String grupoSelecaoMax = 'selecaoMax';
  static const String grupoQtdMinPorOpcao = 'qtdMinPorOpcao';
  static const String grupoQtdMaxPorOpcao = 'qtdMaxPorOpcao';
  static const String grupoPermiteRepetirOpcao = 'permiteRepetirOpcao';
  static const String grupoOpcoes = 'opcoes';
  static const String grupoObservacao = 'observacao';

  /// Campos por opção.
  static const String opProductId = 'productId';
  static const String opNome = 'nome';
  static const String opSlug = 'slug';
  static const String opPrecoAdicional = 'precoAdicional';
  static const String opDescontoEmbutidoValor = 'descontoEmbutidoValor';
  static const String opDescontoEmbutidoPercentual = 'descontoEmbutidoPercentual';
  /// Limites por opção (Fase 2 cadastro). 0 em [opQtdMax] = sem teto no cadastro.
  static const String opQtdMin = 'qtdMin';
  static const String opQtdMax = 'qtdMax';
  static const String opPermiteRepetir = 'permiteRepetir';
}

/// Versão do schema gravado em [ComboConfigKeys.version].
const int kComboConfigSchemaVersion = 1;

/// Tipos de grupo previstos (referência; não bloqueia parse na Fase 1).
const Set<String> kComboConfigTiposGrupo = {
  'unica_obrigatoria',
  'unica_opcional',
  'multipla_opcional',
  'multipla_quantidade',
  'fixo',
};

/// Utilitários para [Produto.comboConfig].
class ComboConfigCanonical {
  ComboConfigCanonical._();

  /// `true` se há configuração utilizável (lista [grupos] não vazia após normalizar).
  static bool isEffective(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return false;
    final g = raw[ComboConfigKeys.grupos];
    return g is List && g.isNotEmpty;
  }

  /// Converte valor Firestore/JSON em mapa Hive-safe; retorna `null` se inválido ou sem grupos.
  static Map<String, dynamic>? parseFromFirestore(dynamic raw) {
    if (raw == null) return null;
    if (raw is! Map) return null;
    final deep = _deepStringDynamicMap(Map<dynamic, dynamic>.from(raw));
    if (deep.isEmpty) return null;
    final grupos = deep[ComboConfigKeys.grupos];
    if (grupos is! List || grupos.isEmpty) return null;

    final ver = deep[ComboConfigKeys.version];
    deep[ComboConfigKeys.version] =
        ver is num ? ver.toInt() : kComboConfigSchemaVersion;

    return deep;
  }

  /// Cópia defensiva para gravar no Hive / reenviar ao Firestore.
  static Map<String, dynamic>? copyMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final parsed = parseFromFirestore(m);
    return parsed;
  }

  static Map<String, dynamic> _deepStringDynamicMap(Map<dynamic, dynamic> src) {
    final out = <String, dynamic>{};
    for (final e in src.entries) {
      out[e.key.toString()] = _cloneValue(e.value);
    }
    return out;
  }

  static dynamic _cloneValue(dynamic v) {
    if (v == null) return null;
    if (v is num || v is String || v is bool) return v;
    if (v is Map) {
      return _deepStringDynamicMap(Map<dynamic, dynamic>.from(v));
    }
    if (v is List) {
      return v.map(_cloneValue).toList();
    }
    return v.toString();
  }
}
