import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Identidade estável da linha na UI de nova/editar venda.
///
/// `VendaItem` persistido não tem lineId (vendas legadas). Este id é apenas
/// de sessão de edição — não deve ser gravado em Hive/Firestore.
const kNovaVendaLineIdKey = 'lineId';

const _uuid = Uuid();

String newNovaVendaLineId() => _uuid.v4();

Map<String, dynamic> novaVendaEmptyLine() => {
      kNovaVendaLineIdKey: newNovaVendaLineId(),
      'produto': '',
      'preco': 0.0,
      'quantidade': 1,
      'tamanho': '',
      'cor': '',
      'extraValor': '',
      'variacaoExtraResumo': '',
    };

String? novaVendaLineIdOf(Map<String, dynamic> line) {
  final id = (line[kNovaVendaLineIdKey] as String?)?.trim();
  if (id == null || id.isEmpty) return null;
  return id;
}

/// Preenche `lineId` em falta e substitui duplicatas na mesma lista.
void ensureNovaVendaLineIds(List<Map<String, dynamic>> lines) {
  final seen = <String>{};
  for (final line in lines) {
    var id = novaVendaLineIdOf(line);
    if (id == null || seen.contains(id)) {
      id = newNovaVendaLineId();
      line[kNovaVendaLineIdKey] = id;
    }
    seen.add(id);
  }
}

int indexOfExactNovaVendaLine(
  List<Map<String, dynamic>> lines, {
  String? lineId,
  Map<String, dynamic>? instance,
}) {
  final id = lineId?.trim();
  if (id != null && id.isNotEmpty) {
    final i = lines.indexWhere((m) => novaVendaLineIdOf(m) == id);
    if (i >= 0) return i;
  }
  if (instance != null) {
    return lines.indexWhere((m) => identical(m, instance));
  }
  return -1;
}

/// Remove a linha exata (lineId ou instância). Não usa productId nem `==` de Map.
/// Retorna `false` se a linha já não existir (double tap / stale callback).
bool removeExactNovaVendaLine(
  List<Map<String, dynamic>> lines, {
  String? lineId,
  Map<String, dynamic>? instance,
}) {
  final idx = indexOfExactNovaVendaLine(
    lines,
    lineId: lineId,
    instance: instance,
  );
  if (idx < 0) return false;
  lines.removeAt(idx);
  return true;
}

Key novaVendaLineWidgetKey(Map<String, dynamic> line, String prefix) {
  final id = novaVendaLineIdOf(line) ?? 'obj-${identityHashCode(line)}';
  return ValueKey('$prefix$id');
}

double novaVendaSubtotalOf(List<Map<String, dynamic>> lines) {
  var subtotal = 0.0;
  for (final item in lines) {
    final preco = (item['preco'] ?? 0.0) as num;
    final qtd = (item['quantidade'] ?? 1) as num;
    subtotal += preco.toDouble() * qtd.toInt();
  }
  return subtotal;
}

double novaVendaDescontoValor({
  required double subtotal,
  required double desconto,
  required bool descontoEmReais,
}) {
  if (subtotal <= 0) return 0;
  if (descontoEmReais) {
    return desconto.clamp(0.0, subtotal);
  }
  return (subtotal * (desconto / 100)).clamp(0.0, subtotal);
}

double novaVendaTotalOf({
  required double subtotal,
  required double descontoValor,
  required double frete,
}) {
  return subtotal - descontoValor + frete;
}
