// Bloco de tamanho/cor/extra para uma opção do combo configurável (catálogo público).
// Alinhado ao fluxo de [CatalogComboVariationSheet].

import 'package:flutter/material.dart';

import '../../../core/catalog_color_from_name.dart';
import '../../../core/produto_variacao_extra.dart';
import '../../../core/safe_cast.dart' show asMap, asMapDeep;
import '../../../widgets/variacao_extras_collapsible.dart';

/// `true` quando tamanho/cor/extra obrigatórios estão preenchidos (mesma regra do combo legado).
bool catalogComboOpcaoVariacaoValida(
  Map<String, dynamic>? p,
  Map<String, String> sel,
) {
  if (p == null) return true;
  final variacoes = asMapDeep(p['variacoes']);
  final estoquePorTamanho = asMap(p['estoquePorTamanho']);
  final estoquePorCor = asMap(p['estoquePorCor']);
  final usaVariacoes = variacoes.isNotEmpty;
  final temVariacaoSoloCor = _mapTemVariacaoSoloCor(p);

  var temTamanhos = estoquePorTamanho.isNotEmpty;
  if (!temTamanhos && usaVariacoes) {
    for (final e in variacoes.entries) {
      if (e.key.toString() == 'sem-tamanho') continue;
      if (e.value is Map) {
        var total = 0;
        for (final v in (e.value as Map).values) {
          total += ProdutoVariacaoExtra.somarCelula(v);
        }
        if (total > 0) {
          temTamanhos = true;
          break;
        }
      }
    }
  }

  final tam = (sel['tamanho'] ?? '').trim();
  final cor = (sel['cor'] ?? '').trim();
  final extra = (sel['extra'] ?? '').trim();

  if (temVariacaoSoloCor) {
    if (cor.isEmpty) return false;
  } else {
    if (temTamanhos && tam.isEmpty) return false;
    if (usaVariacoes && tam.isNotEmpty) {
      final mapaTamanho = variacoes[tam];
      if (mapaTamanho is Map && mapaTamanho.isNotEmpty) {
        final keysComEstoque = mapaTamanho.keys
            .map((k) => k.toString())
            .where((k) => ProdutoVariacaoExtra.somarCelula(mapaTamanho[k]) > 0)
            .toList();
        if (keysComEstoque.length > 1 ||
            (keysComEstoque.length == 1 &&
                keysComEstoque.first != 'sem-cor')) {
          if (cor.isEmpty) return false;
        }
      }
    }
  }

  final extras =
      ProdutoVariacaoExtra.opcoesExtraPara(variacoes, tam, cor);
  if (extras.isNotEmpty && extra.isEmpty) return false;

  if (!temVariacaoSoloCor &&
      !temTamanhos &&
      estoquePorCor.isNotEmpty &&
      cor.isEmpty) {
    return false;
  }
  return true;
}

bool _mapTemVariacaoSoloCor(Map<String, dynamic> p) {
  final v = asMapDeep(p['variacoes']);
  if (v.isEmpty) return false;
  final st = v['sem-tamanho'];
  return st is Map && st.isNotEmpty;
}

/// Retorna mensagem curta se faltar variação; `null` se ok ou sem produto.
String? catalogComboOpcaoVariacaoMensagemErro(
  Map<String, dynamic>? p,
  Map<String, String> sel,
  String nomeItem,
) {
  if (p == null) return null;
  if (catalogComboOpcaoVariacaoValida(p, sel)) return null;
  return 'Defina tamanho/cor/variação para «$nomeItem».';
}

/// Chips de variação para um produto do catálogo (mapa Firestore).
class CatalogComboOpcaoVariacaoBlock extends StatelessWidget {
  const CatalogComboOpcaoVariacaoBlock({
    super.key,
    required this.produto,
    required this.comboProductId,
    required this.fieldSuffix,
    required this.tamanho,
    required this.cor,
    required this.extra,
    required this.onChanged,
  });

  final Map<String, dynamic>? produto;
  final String comboProductId;
  /// Identificador único para ValueKey (ex.: "${gi}_$oi").
  final String fieldSuffix;
  final String tamanho;
  final String cor;
  final String extra;
  final void Function({required String tamanho, required String cor, required String extra})
      onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = produto;
    if (p == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.65),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Produto não encontrado no catálogo — variações na separação do pedido.',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final extras =
        ProdutoVariacaoExtra.opcoesExtraPara(asMapDeep(p['variacoes']), tamanho, cor);
    final labelExtra = ProdutoVariacaoExtra.labelExtraParaProduto(
      asMapDeep(p['variacoes']),
      p['variacoesExtraTipo'] != null
          ? asMapDeep(p['variacoesExtraTipo'])
          : null,
    );

    final temVariacaoSoloCor = _mapTemVariacaoSoloCor(p);

    Map<String, int> tamanhosDisponiveis = {};
    Map<String, int> coresDisponiveis = {};
    Map<String, double> precoPorTamanho = {};
    bool temTamanhos = false;

    final variacoes = asMapDeep(p['variacoes']);
    final estoqueTam = asMap(p['estoquePorTamanho']);
    final precoTamRaw = p['precoPorTamanho'];
    if (precoTamRaw is Map && precoTamRaw.isNotEmpty) {
      precoTamRaw.forEach((k, v) {
        if (v is num && v > 0) {
          precoPorTamanho[k.toString()] = v.toDouble();
          tamanhosDisponiveis[k.toString()] = 1;
        }
      });
    }
    if (variacoes.isNotEmpty) {
      for (final e in variacoes.entries) {
        if (e.key.toString() == 'sem-tamanho') continue;
        if (e.value is Map) {
          var total = 0;
          for (final v in (e.value as Map).values) {
            total += ProdutoVariacaoExtra.somarCelula(v);
          }
          if (total > 0) {
            tamanhosDisponiveis[e.key.toString()] = total;
          }
        }
      }
      temTamanhos = tamanhosDisponiveis.isNotEmpty;
      if (!temTamanhos && variacoes['sem-tamanho'] is Map) {
        final sm = variacoes['sem-tamanho'] as Map;
        sm.forEach((k, v) {
          final q = ProdutoVariacaoExtra.somarCelula(v);
          if (q > 0) {
            coresDisponiveis[k.toString()] = q;
          }
        });
      }
      final tamSel = tamanho;
      if (tamSel.isNotEmpty && variacoes.containsKey(tamSel)) {
        coresDisponiveis.clear();
        final mapa = variacoes[tamSel];
        if (mapa is Map) {
          mapa.forEach((k, v) {
            final q = ProdutoVariacaoExtra.somarCelula(v);
            if (q > 0) coresDisponiveis[k.toString()] = q;
          });
        }
      }
    } else if (estoqueTam.isNotEmpty) {
      estoqueTam.forEach((k, v) {
        final q = v is num ? v.truncate() : 0;
        if (q > 0) tamanhosDisponiveis[k.toString()] = q;
      });
      temTamanhos = tamanhosDisponiveis.isNotEmpty;
    } else if (precoPorTamanho.isNotEmpty) {
      temTamanhos = true;
    }
    if (temTamanhos && tamanhosDisponiveis.isEmpty && precoPorTamanho.isNotEmpty) {
      precoPorTamanho.forEach((k, v) {
        tamanhosDisponiveis[k] = 1;
      });
    }
    if (!temTamanhos && tamanhosDisponiveis.isEmpty) {
      final tamanhosList = p['tamanhos'];
      if (tamanhosList is List && tamanhosList.isNotEmpty) {
        for (final t in tamanhosList) {
          final k = t.toString().trim();
          if (k.isNotEmpty) tamanhosDisponiveis[k] = 1;
        }
        temTamanhos = tamanhosDisponiveis.isNotEmpty;
      }
    }
    if (!temTamanhos && coresDisponiveis.isEmpty) {
      final ec = asMap(p['estoquePorCor']);
      ec.forEach((k, v) {
        final q = v is num ? v.truncate() : 0;
        if (q > 0) {
          coresDisponiveis[k.toString()] = q;
        }
      });
    }

    final primaryColor = theme.colorScheme.primary;
    final labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );

    final temAlgumaUi = temTamanhos ||
        (temVariacaoSoloCor && coresDisponiveis.isNotEmpty) ||
        (!temVariacaoSoloCor && coresDisponiveis.isNotEmpty) ||
        extras.isNotEmpty;
    if (!temAlgumaUi) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 6, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (temTamanhos) ...[
            Text('Tamanho', style: labelStyle),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tamanhosDisponiveis.entries.map((e) {
                final sel = tamanho == e.key;
                final precoT = precoPorTamanho[e.key];
                final label = precoT != null && precoT > 0
                    ? '${e.key} (R\$ ${precoT.toStringAsFixed(2).replaceAll('.', ',')})'
                    : e.key;
                return FilterChip(
                  label: Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  selected: sel,
                  onSelected: (v) {
                    if (!v) {
                      onChanged(tamanho: '', cor: '', extra: '');
                      return;
                    }
                    final variacoes = asMapDeep(p['variacoes']);
                    var novaCor = '';
                    var novoExtra = '';
                    final mapa = variacoes[e.key];
                    if (mapa is Map) {
                      final keys = mapa.keys
                          .map((k) => k.toString())
                          .where((k) =>
                              ProdutoVariacaoExtra.somarCelula(mapa[k]) > 0)
                          .toList();
                      if (keys.length == 1 && keys.first == 'sem-cor') {
                        novaCor = 'sem-cor';
                      }
                    }
                    onChanged(
                        tamanho: e.key, cor: novaCor, extra: novoExtra);
                  },
                  selectedColor: primaryColor.withOpacity(0.25),
                  checkmarkColor: primaryColor,
                  side: BorderSide(
                    color: sel ? primaryColor : theme.dividerColor,
                    width: sel ? 2 : 1,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                );
              }).toList(),
            ),
          ] else if (coresDisponiveis.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Único (sem tamanho)',
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7)),
              ),
            ),
          if (temVariacaoSoloCor && coresDisponiveis.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Cor', style: labelStyle),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: coresDisponiveis.entries.map((e) {
                final sel = cor == e.key;
                return FilterChip(
                  avatar: CircleAvatar(
                    backgroundColor: catalogColorFromName(e.key),
                    radius: 11,
                  ),
                  label: Text(e.key,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  selected: sel,
                  onSelected: (v) {
                    onChanged(
                        tamanho: tamanho,
                        cor: v ? e.key : '',
                        extra: v ? extra : '');
                  },
                  selectedColor: primaryColor.withOpacity(0.25),
                  checkmarkColor: primaryColor,
                  side: BorderSide(
                    color: sel ? primaryColor : theme.dividerColor,
                    width: sel ? 2 : 1,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                );
              }).toList(),
            ),
          ] else if (!temVariacaoSoloCor && coresDisponiveis.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Cor', style: labelStyle),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: coresDisponiveis.entries.map((e) {
                if (e.key == 'sem-cor') return const SizedBox.shrink();
                final sel = cor == e.key;
                return FilterChip(
                  avatar: CircleAvatar(
                    backgroundColor: catalogColorFromName(e.key),
                    radius: 11,
                  ),
                  label: Text(e.key,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  selected: sel,
                  onSelected: (v) {
                    onChanged(
                        tamanho: tamanho,
                        cor: v ? e.key : '',
                        extra: v ? extra : '');
                  },
                  selectedColor: primaryColor.withOpacity(0.25),
                  checkmarkColor: primaryColor,
                  side: BorderSide(
                    color: sel ? primaryColor : theme.dividerColor,
                    width: sel ? 2 : 1,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                );
              }).toList(),
            ),
          ],
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(labelExtra, style: labelStyle),
            const SizedBox(height: 6),
            VariacaoExtrasCollapsible(
              key: ValueKey('cfg_combo_extra_${comboProductId}_$fieldSuffix'),
              options: extras,
              selectedValue: extra.trim().isEmpty ? null : extra,
              spacing: 8,
              runSpacing: 8,
              onOptionChosen: (ex) {
                onChanged(tamanho: tamanho, cor: cor, extra: ex);
              },
              itemBuilder: (context, ex, _) {
                final sel = extra == ex;
                return FilterChip(
                  label: Text(ex),
                  selected: sel,
                  onSelected: (v) {
                    onChanged(
                        tamanho: tamanho,
                        cor: cor,
                        extra: v ? ex : '');
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
