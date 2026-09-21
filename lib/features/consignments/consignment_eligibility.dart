import '../../utils/text_utils.dart';

/// Product eligibility for Consignados picker. Hive is never authority.
const consignmentProductUnavailableReason =
    'Produto ainda não disponível para consignação.';

/// Authoritative Mirjoias product code field on stock/draft docs.
const consignmentAuthoritativeProductCodeField = 'codigoBarras';

class ConsignmentPickerItem {
  const ConsignmentPickerItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.availableQty,
    required this.stockKind,
    required this.variacoes,
    required this.eligible,
    this.productCode = '',
    this.unavailableReason = consignmentProductUnavailableReason,
    this.stockRevision,
  });

  final String productId;
  final String name;
  /// Store product code (authoritative: [consignmentAuthoritativeProductCodeField]).
  final String productCode;
  final double price;
  final int availableQty;
  final String stockKind;
  final Map<String, dynamic> variacoes;
  final bool eligible;
  final String unavailableReason;
  final int? stockRevision;

  ConsignmentPickerItem copyWith({
    String? productCode,
    String? name,
    double? price,
    int? availableQty,
    String? stockKind,
    Map<String, dynamic>? variacoes,
    bool? eligible,
    String? unavailableReason,
    int? stockRevision,
  }) {
    return ConsignmentPickerItem(
      productId: productId,
      name: name ?? this.name,
      productCode: productCode ?? this.productCode,
      price: price ?? this.price,
      availableQty: availableQty ?? this.availableQty,
      stockKind: stockKind ?? this.stockKind,
      variacoes: variacoes ?? this.variacoes,
      eligible: eligible ?? this.eligible,
      unavailableReason: unavailableReason ?? this.unavailableReason,
      stockRevision: stockRevision ?? this.stockRevision,
    );
  }
}

/// Resolve product code without numeric coercion (preserves leading zeros).
String consignmentProductCodeFromMaps(
  Map<String, dynamic>? draft,
  Map<String, dynamic>? stock,
) {
  for (final src in [stock, draft]) {
    if (src == null) continue;
    for (final key in const [
      consignmentAuthoritativeProductCodeField,
      'sku',
      'codigo',
      'codigoProduto',
      'productCode',
      'barcode',
      'code',
    ]) {
      final raw = src[key];
      if (raw == null) continue;
      final s = raw.toString().trim();
      if (s.isNotEmpty) return s;
    }
  }
  return '';
}

String consignmentPickerNormalizeQuery(String input) => normalizeText(input);

String consignmentPickerNormalizeCode(String input) => input.trim().toLowerCase();

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
  final productCode = consignmentProductCodeFromMaps(draft, stock);
  ConsignmentPickerItem deny() => ConsignmentPickerItem(
        productId: productId,
        name: name,
        productCode: productCode,
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
      productCode: productCode,
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
      productCode: productCode,
      price: _price(draft, stock),
      availableQty: 0,
      stockKind: kind as String,
      variacoes: variacoes,
      eligible: false,
      unavailableReason: '0 disponíveis para consignação',
    );
  }
  final isGrade = kind == 'variation' && _isTrueGrade(stock, variacoes);
  final stockKindOut = isGrade ? 'grade' : (kind as String);
  return ConsignmentPickerItem(
    productId: productId,
    name: name,
    productCode: productCode,
    price: _price(draft, stock),
    availableQty: _sellablePickerQty(qty, stockKindOut, variacoes),
    stockKind: stockKindOut,
    variacoes: variacoes,
    eligible: true,
    unavailableReason: '',
    stockRevision: revision,
  );
}

int _cellQtyDeep(dynamic value) {
  if (value is int) return value < 0 ? 0 : value;
  if (value is num) {
    final n = value.toInt();
    return n < 0 ? 0 : n;
  }
  if (value is Map) {
    var sum = 0;
    for (final e in value.entries) {
      final k = e.key.toString();
      if (k == 'custo' || k == '__custoUnitario') continue;
      if (e.value is num) {
        final n = (e.value as num).toInt();
        if (n > 0) sum += n;
      }
    }
    return sum;
  }
  return int.tryParse('$value') ?? 0;
}

int _sellablePickerQty(int aggregate, String stockKind, Map<String, dynamic> variacoes) {
  if (stockKind == 'simple' || variacoes.isEmpty) return aggregate;
  var sum = 0;
  var any = false;
  for (final cells in variacoes.values) {
    if (cells is! Map) continue;
    for (final e in cells.entries) {
      final k = e.key.toString();
      if (k == 'custo' || k == '__custoUnitario') continue;
      any = true;
      sum += _cellQtyDeep(e.value);
    }
  }
  if (!any) return aggregate;
  return aggregate > 0 ? (sum < aggregate ? sum : aggregate) : sum;
}

bool consignmentPickerItemMatchesQuery(ConsignmentPickerItem item, String query) {
  final qRaw = query.trim();
  if (qRaw.isEmpty) return true;
  final qName = consignmentPickerNormalizeQuery(qRaw);
  final qCode = consignmentPickerNormalizeCode(qRaw);
  final code = consignmentPickerNormalizeCode(item.productCode);
  // Exact or prefix only — never strip leading zeros via numeric parse / mid-string digit match.
  if (code.isNotEmpty && (code == qCode || code.startsWith(qCode))) return true;
  if (consignmentPickerNormalizeQuery(item.name).contains(qName)) return true;
  if (item.productId.toLowerCase().contains(qCode)) return true;
  return false;
}

/// Visible picker rows for [query].
/// Empty query → all eligible (no page truncate). Non-empty → name/code matches,
/// including disabled rows so operators can see why a SKU is unavailable.
List<ConsignmentPickerItem> consignmentPickerVisibleItems(
  List<ConsignmentPickerItem> all, {
  String query = '',
}) {
  final qRaw = query.trim();
  final qCode = consignmentPickerNormalizeCode(qRaw);
  final Iterable<ConsignmentPickerItem> matches;
  if (qRaw.isEmpty) {
    matches = all.where((e) => e.eligible);
  } else {
    matches = all.where((e) => consignmentPickerItemMatchesQuery(e, qRaw));
  }
  final list = matches.toList()
    ..sort((a, b) {
      if (qCode.isNotEmpty) {
        final aExact = consignmentPickerNormalizeCode(a.productCode) == qCode;
        final bExact = consignmentPickerNormalizeCode(b.productCode) == qCode;
        if (aExact != bExact) return aExact ? -1 : 1;
      }
      if (a.eligible == b.eligible) return a.name.compareTo(b.name);
      return a.eligible ? -1 : 1;
    });
  return list;
}
