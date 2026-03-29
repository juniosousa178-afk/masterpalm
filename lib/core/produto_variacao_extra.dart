// Suporte opcional a eixo extra de variação (extraTipo/extraValor) — retrocompatível.
// Estrutura no Firestore: variacoes[tamanho][cor] = int (legado) OU Map<extraValor, int>.
// Rótulos: variacoesExtraTipo[tamanho][cor][extraValor] = extraTipo (opcional).

/// Valor sugerido no cadastro (grade) quando o lojista deixa [extraTipo] em branco — não é rótulo de catálogo.
const String kVariacaoExtraTipoFallback = 'Modelo';

/// Rótulo neutro do filtro extra no catálogo público (vários produtos / tipos mistos).
const String kVariacaoExtraLabelFiltroGlobal = 'Variação';

/// Rótulo neutro na UI quando não há um único [extraTipo] consistente (detalhe/sheet/resumo sem tipo).
const String kVariacaoExtraLabelNeutra = 'Variação';

abstract final class ProdutoVariacaoExtra {
  static String normKey(String s) {
    var t = s.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  static bool keysMatch(String a, String b) {
    final na = normKey(a);
    final nb = normKey(b);
    if (na == nb) return true;
    final ca = na.replaceAll(' ', '');
    final cb = nb.replaceAll(' ', '');
    return ca.isNotEmpty && ca == cb;
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? 0;
  }

  /// Soma quantidades em uma célula (int ou mapa de extras).
  static int somarCelula(dynamic cell) {
    if (cell == null) return 0;
    if (cell is num) return cell.toInt();
    if (cell is Map) {
      var s = 0;
      for (final v in cell.values) {
        s += _asInt(v);
      }
      return s;
    }
    return _asInt(cell);
  }

  /// Há pelo menos um extraValor não vazio em alguma célula do produto?
  static bool produtoTemEixoExtraVisivel(Map<String, dynamic>? variacoes) {
    if (variacoes == null || variacoes.isEmpty) return false;
    for (final cores in variacoes.values) {
      if (cores is! Map) continue;
      for (final cell in cores.values) {
        if (celulaTemExtrasNaoVazios(cell)) return true;
      }
    }
    return false;
  }

  static bool celulaTemExtrasNaoVazios(dynamic cell) {
    if (cell is! Map || cell.isEmpty) return false;
    for (final k in cell.keys) {
      if (k.toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  /// Estoque para combinação tamanho/cor/extraValor ([extraValor] vazio = legado ou chave '' no mapa).
  static int quantidadeNaCelula(
    dynamic cell,
    String extraValorTrim,
  ) {
    if (cell is num) {
      return extraValorTrim.isEmpty ? cell.toInt() : 0;
    }
    if (cell is Map) {
      if (extraValorTrim.isEmpty) {
        if (cell.containsKey('')) return _asInt(cell['']);
        if (cell.length == 1) return _asInt(cell.values.first);
        return 0;
      }
      for (final e in cell.entries) {
        if (keysMatch(e.key.toString(), extraValorTrim)) {
          return _asInt(e.value);
        }
      }
    }
    return 0;
  }

  /// Opções de extra para (tamanho, cor) com estoque > 0.
  static List<String> opcoesExtraPara(
    Map<String, dynamic>? variacoes,
    String tamanho,
    String cor,
  ) {
    if (variacoes == null || variacoes.isEmpty) return const [];
    final tam = tamanho.trim();
    final c = cor.trim();
    final corKey = c.isEmpty ? 'sem-cor' : c;
    Map? mapaTam;
    if (tam.isEmpty) {
      mapaTam = variacoes['sem-tamanho'] as Map?;
    } else {
      mapaTam = variacoes[tam] as Map?;
    }
    if (mapaTam == null) return const [];
    final cell = mapaTam[corKey];
    if (cell is! Map) return const [];
    final out = <String>[];
    cell.forEach((k, v) {
      if (_asInt(v) <= 0) return;
      final ks = k.toString();
      if (ks.trim().isEmpty) return;
      out.add(ks);
    });
    out.sort((a, b) => normKey(a).compareTo(normKey(b)));
    return out;
  }

  /// Filtro global do catálogo: sempre rótulo neutro (não depende dos produtos do contexto).
  static String labelExtraFiltroCatalogoGlobal() => kVariacaoExtraLabelFiltroGlobal;

  /// Label no detalhe/sheet: um único [extraTipo] não vazio no mapa → esse texto; senão [kVariacaoExtraLabelNeutra].
  static String labelExtraParaProduto(
    Map<String, dynamic>? variacoes,
    Map<String, dynamic>? variacoesExtraTipo,
  ) {
    final tipos = <String>{};
    void scanTipo(String? t) {
      final s = (t ?? '').trim();
      if (s.isNotEmpty) tipos.add(s);
    }

    if (variacoesExtraTipo != null) {
      for (final tm in variacoesExtraTipo.values) {
        if (tm is! Map) continue;
        for (final cm in tm.values) {
          if (cm is! Map) continue;
          for (final tv in cm.values) {
            scanTipo(tv?.toString());
          }
        }
      }
    }

    if (tipos.isEmpty) return kVariacaoExtraLabelNeutra;
    if (tipos.length == 1) return tipos.first;
    return kVariacaoExtraLabelNeutra;
  }

  /// Marca remoção da entrada [cor] no mapa de variações após débito.
  static const Object removeCorCell = Object();

  static String? _resolveMapKeyForExtra(Map<String, dynamic> m, String extraTrim) {
    if (extraTrim.isEmpty) {
      if (m.containsKey('')) return '';
      if (m.length == 1) return m.keys.first;
      return null;
    }
    for (final k in m.keys) {
      if (keysMatch(k, extraTrim)) return k;
    }
    return null;
  }

  /// Débito em uma célula (int ou mapa extra→qtd). [newCell] == [removeCorCell] ⇒ apagar chave cor.
  static ({bool ok, dynamic newCell}) debitarCelula(
    dynamic cell,
    String extraTrim,
    int qtd,
  ) {
    if (qtd <= 0) return (ok: true, newCell: cell);
    final disp = quantidadeNaCelula(cell, extraTrim);
    if (disp < qtd) return (ok: false, newCell: cell);

    if (cell is num) {
      final n = cell.toInt() - qtd;
      return (ok: true, newCell: n <= 0 ? removeCorCell : n);
    }
    if (cell is Map) {
      final m = Map<String, dynamic>.from(
        cell.map((k, v) => MapEntry(k.toString(), v)),
      );
      final rk = _resolveMapKeyForExtra(m, extraTrim);
      if (rk == null) return (ok: false, newCell: cell);
      final cur = _asInt(m[rk]);
      final n = cur - qtd;
      if (n <= 0) {
        m.remove(rk);
      } else {
        m[rk] = n;
      }
      if (m.isEmpty) return (ok: true, newCell: removeCorCell);
      return (ok: true, newCell: m);
    }
    return (ok: false, newCell: cell);
  }

  /// Devolução em uma célula (recria mapa se necessário).
  static dynamic devolverCelula(dynamic cell, String extraTrim, int qtd) {
    if (qtd <= 0) return cell;
    if (cell is num) return cell.toInt() + qtd;
    if (cell is Map) {
      final m = Map<String, dynamic>.from(
        cell.map((k, v) => MapEntry(k.toString(), v)),
      );
      var rk = _resolveMapKeyForExtra(m, extraTrim);
      rk ??= extraTrim.isEmpty ? '' : null;
      if (rk != null) {
        m[rk] = _asInt(m[rk]) + qtd;
      } else {
        m[extraTrim] = qtd;
      }
      return m;
    }
    if (extraTrim.isEmpty) return qtd;
    return <String, dynamic>{extraTrim: qtd};
  }

  /// Coleta valores extra únicos (não vazios) entre produtos para filtro de catálogo.
  static List<String> coletarExtrasGlobais(List<Map<String, dynamic>> produtos) {
    final set = <String>{};
    for (final p in produtos) {
      final v = p['variacoes'];
      if (v is! Map) continue;
      for (final cores in v.values) {
        if (cores is! Map) continue;
        for (final cell in cores.values) {
          if (cell is! Map) continue;
          for (final k in cell.keys) {
            final s = k.toString().trim();
            if (s.isNotEmpty) set.add(s);
          }
        }
      }
    }
    final list = set.toList()..sort((a, b) => normKey(a).compareTo(normKey(b)));
    return list;
  }

  /// Resolve extraTipo para uma célula (t,c,extraValor).
  static String tipoParaCelula(
    Map<String, dynamic>? variacoesExtraTipo,
    String chaveTamanho,
    String corKey,
    String extraValor,
  ) {
    if (variacoesExtraTipo == null) return '';
    final tm = variacoesExtraTipo[chaveTamanho];
    if (tm is! Map) return '';
    final cm = tm[corKey];
    if (cm is! Map) return '';
    final ev = extraValor.trim();
    if (ev.isEmpty) {
      final v = cm[''];
      return v?.toString().trim() ?? '';
    }
    for (final e in cm.entries) {
      if (keysMatch(e.key.toString(), ev)) {
        return e.value?.toString().trim() ?? '';
      }
    }
    return '';
  }

  /// Texto de resumo para carrinho/pedido: tipo explícito quando houver; senão [kVariacaoExtraLabelNeutra].
  static String textoResumoExtra({
    required String extraTipo,
    required String extraValor,
  }) {
    final v = extraValor.trim();
    if (v.isEmpty) return '';
    final t = extraTipo.trim();
    final label = t.isEmpty ? kVariacaoExtraLabelNeutra : t;
    return '$label: $v';
  }
}
