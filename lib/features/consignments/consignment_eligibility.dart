/// Product eligibility for Consignados picker. Hive is never authority.
const consignmentProductUnavailableReason =
    'Produto ainda não disponível para consignação.';

class ConsignmentPickerItem {
  const ConsignmentPickerItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.availableQty,
    required this.stockKind,
    required this.variacoes,
    required this.eligible,
    this.unavailableReason = consignmentProductUnavailableReason,
  });

  final String productId;
  final String name;
  final double price;
  final int availableQty;
  final String stockKind;
  final Map<String, dynamic> variacoes;
  final bool eligible;
  final String unavailableReason;
}

bool _nonemptyMap(dynamic value) => value is Map && value.isNotEmpty;

int? _intQty(dynamic value) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  return int.tryParse('$value');
}

bool _technicalKey(String value) {
  final n = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return n.isEmpty ||
      n == 'sem-tamanho' ||
      n == 'semtamanho' ||
      n == 'sem-cor' ||
      n == 'semcor' ||
      n == 'unico' ||
      n == 'unique' ||
      n == 'u';
}

bool _hasGradeAttrs(Map<String, dynamic> stock) {
  for (final key in const ['tamanhos', 'cores']) {
    final list = stock[key];
    if (list is List && list.any((v) => v.toString().trim().isNotEmpty)) {
      return true;
    }
  }
  return ['estoquePorTamanho', 'estoquePorCor', 'variacoesExtraTipo']
      .any((k) => _nonemptyMap(stock[k]));
}

bool _isGradeMatrix(Map<String, dynamic> variacoes) {
  final sizes = variacoes.keys
      .map((e) => e.toString())
      .where((s) => !_technicalKey(s))
      .toList();
  final colors = <String>{};
  for (final cells in variacoes.values) {
    if (cells is! Map) continue;
    for (final color in cells.keys) {
      final key = color.toString();
      if (key == 'custo' || _technicalKey(key)) continue;
      colors.add(key.trim().toLowerCase());
    }
  }
  return sizes.isNotEmpty && colors.isNotEmpty;
}

bool _hasBothSizeAndColorLists(Map<String, dynamic> stock) {
  bool nonempty(dynamic list) =>
      list is List &&
      list.any((v) {
        final s = v.toString().trim();
        return s.isNotEmpty && !_technicalKey(s);
      });
  return nonempty(stock['tamanhos']) && nonempty(stock['cores']);
}

bool _isTrueGrade(Map<String, dynamic> stock, Map<String, dynamic> variacoes) {
  final hasExtra = _nonemptyMap(stock['variacoesExtraTipo']);
  if (_isGradeMatrix(variacoes) || _hasBothSizeAndColorLists(stock)) return true;
  final outer = variacoes.keys
      .map((e) => e.toString())
      .where((s) => !_technicalKey(s))
      .toList();
  return hasExtra && outer.isNotEmpty;
}

double _price(Map<String, dynamic>? draft, Map<String, dynamic> stock) {
  for (final src in [draft, stock]) {
    if (src == null) continue;
    for (final key in const ['preco', 'precoVenda', 'precoFinal']) {
      final v = src[key];
      if (v is num) return v.toDouble();
      final parsed = double.tryParse('$v');
      if (parsed != null) return parsed;
    }
  }
  return 0;
}

ConsignmentPickerItem evaluateConsignmentPickerItem({
  required String productId,
  required String lojaId,
  required Map<String, dynamic> stock,
  Map<String, dynamic>? draft,
  Map<String, dynamic>? dependency,
  Map<String, dynamic>? tombstone,
}) {
  final name = (draft?['nome'] ?? stock['nome'] ?? productId).toString();
  ConsignmentPickerItem deny() => ConsignmentPickerItem(
        productId: productId,
        name: name,
        price: _price(draft, stock),
        availableQty: _intQty(stock['quantidade']) ?? 0,
        stockKind: (stock['stockKind'] ?? '').toString(),
        variacoes: const {},
        eligible: false,
      );

  if (tombstone?['p'] == true || stock['pendingSoftDelete'] == true) return deny();
  final claimed = '${stock['lojaId'] ?? stock['storeId'] ?? draft?['lojaId'] ?? draft?['storeId'] ?? ''}'
      .trim();
  if (claimed.isNotEmpty && claimed != lojaId) return deny();
  if (draft == null) return deny();
  if (dependency == null || dependency['comboIds'] is! List) return deny();
  if (stock['ativo'] == false) return deny();
  final kind = stock['stockKind'];
  if (kind != 'simple' && kind != 'variation') return deny();
  final revision = _intQty(stock['stockRevision']);
  if (revision == null || revision < 0) return deny();
  if (kind == 'combo' ||
      (stock['tipoProduto'] ?? '').toString() == 'combo' ||
      (stock['itensCombo'] is List && (stock['itensCombo'] as List).isNotEmpty)) {
    return ConsignmentPickerItem(
      productId: productId,
      name: name,
      price: _price(draft, stock),
      availableQty: _intQty(stock['quantidade']) ?? 0,
      stockKind: 'combo',
      variacoes: const {},
      eligible: false,
      unavailableReason: 'Produtos do tipo combo ainda não são suportados nesta operação.',
    );
  }
  final variacoes = stock['variacoes'] is Map
      ? Map<String, dynamic>.from(stock['variacoes'] as Map)
      : <String, dynamic>{};
  if (kind == 'simple') {
    if (_nonemptyMap(variacoes) || _hasGradeAttrs(stock)) return deny();
  } else {
    if (!_nonemptyMap(variacoes)) return deny();
  }
  final qty = _intQty(stock['quantidade']);
  if (qty == null) return deny();
  if (qty < 1) {
    return ConsignmentPickerItem(
      productId: productId,
      name: name,
      price: _price(draft, stock),
      availableQty: 0,
      stockKind: kind as String,
      variacoes: variacoes,
      eligible: false,
      unavailableReason: 'Sem estoque',
    );
  }
  final isGrade = kind == 'variation' && _isTrueGrade(stock, variacoes);
  return ConsignmentPickerItem(
    productId: productId,
    name: name,
    price: _price(draft, stock),
    availableQty: qty,
    stockKind: isGrade ? 'grade' : (kind as String),
    variacoes: variacoes,
    eligible: true,
    unavailableReason: '',
  );
}

List<ConsignmentPickerItem> consignmentPickerVisibleItems(
  List<ConsignmentPickerItem> all, {
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  final matches = q.isEmpty
      ? all
      : all.where((e) =>
          e.name.toLowerCase().contains(q) ||
          e.productId.toLowerCase().contains(q));
  // Prefer eligible first, then disabled (zero stock / unsupported) for visibility.
  final list = matches.toList()
    ..sort((a, b) {
      if (a.eligible == b.eligible) return a.name.compareTo(b.name);
      return a.eligible ? -1 : 1;
    });
  return list.take(80).toList();
}
