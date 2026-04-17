// Resumo textual de combo configurável (carrinho, pré-pedido, admin, WhatsApp).

import 'produto_variacao_extra.dart';

/// Helper pequeno e reutilizável para exibir composição do combo sem JSON cru.
abstract final class ComboConfiguravelResumo {
  ComboConfiguravelResumo._();

  /// Resumo do kit + variações dos componentes (quando houver) + variações do próprio item pai.
  static String textoParaItemMap(Map<String, dynamic> item) {
    final salvo = (item['comboConfiguravelResumo'] ?? '').toString().trim();
    final linhas =
        textoParaLinhasSelecaoMultilinha(item['itensComboComSelecao']);
    final varPai = ProdutoVariacaoExtra.linhaVariacoesParaSeparacao(item)
        .trim()
        .replaceAll(', ', ' · ');

    final buf = StringBuffer();
    if (salvo.isNotEmpty) {
      // [comboConfiguravelResumo] já reflete grupos + nomes + variações (ex.: sheet
      // configurável). Repetir cada linha de [itensComboComSelecao] duplicava
      // Tam/Cor/Extra. Combo legado não grava [comboConfiguravelResumo] — aí usamos
      // só [textoParaLinhasSelecaoMultilinha] abaixo.
      buf.write(salvo);
    } else if (linhas.isNotEmpty) {
      buf.write(linhas.join('\n'));
    }
    if (varPai.isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(varPai);
    }
    return buf.toString().trim();
  }

  /// Uma linha por componente do combo (tam/cor/extra via helper central).
  static List<String> textoParaLinhasSelecaoMultilinha(dynamic raw) {
    if (raw is! List || raw.isEmpty) return [];
    final partes = <String>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(
        e.map((k, v) => MapEntry(k.toString(), v)),
      );
      final nome = (m['nome'] ?? '').toString().trim();
      if (nome.isEmpty) continue;
      final q = m['quantidade'] is num
          ? (m['quantidade'] as num).toInt()
          : int.tryParse('${m['quantidade']}') ?? 1;
      final base = q > 1 ? '$nome ×$q' : nome;
      final vars = ProdutoVariacaoExtra.linhaVariacoesParaSeparacao(m)
          .trim()
          .replaceAll(', ', ' · ');
      if (vars.isNotEmpty) {
        partes.add('· $base · $vars');
      } else {
        partes.add('· $base');
      }
    }
    return partes;
  }

  /// Monta texto em uma linha (ex.: WhatsApp).
  static String textoParaLinhasSelecao(dynamic raw) {
    final m = textoParaLinhasSelecaoMultilinha(raw);
    if (m.isEmpty) return '';
    return m.join(' ');
  }
}
