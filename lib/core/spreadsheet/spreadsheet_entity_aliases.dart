import 'spreadsheet_header_normalizer.dart';

/// Definição de campo importável com aliases normalizados.
class SpreadsheetFieldDef {
  const SpreadsheetFieldDef({
    required this.field,
    required this.aliases,
    this.required = false,
    this.isIdentifier = false,
  });

  final String field;
  final Set<String> aliases;
  final bool required;
  final bool isIdentifier;
}

class SpreadsheetEntityAliases {
  const SpreadsheetEntityAliases({required this.fields});

  final List<SpreadsheetFieldDef> fields;

  Set<String> get allAliasTokens => fields.expand((f) => f.aliases).toSet();

  Set<String> get requiredAliasTokens =>
      fields.where((f) => f.required).expand((f) => f.aliases).toSet();

  Set<String> get optionalAliasTokens =>
      fields.where((f) => !f.required).expand((f) => f.aliases).toSet();

  Set<String> requiredFields() =>
      fields.where((f) => f.required).map((f) => f.field).toSet();
}

const clienteSpreadsheetAliases = SpreadsheetEntityAliases(
  fields: [
    SpreadsheetFieldDef(
      field: 'nome',
      aliases: {
        'nome',
        'cliente',
        'nome do cliente',
        'name',
        'customer',
      },
      required: true,
    ),
    SpreadsheetFieldDef(
      field: 'telefone',
      aliases: {
        'telefone',
        'celular',
        'whatsapp',
        'phone',
        'fone',
        'tel',
      },
      required: true,
      isIdentifier: true,
    ),
    SpreadsheetFieldDef(
      field: 'instagram',
      aliases: {'instagram', 'ig', 'insta'},
    ),
    SpreadsheetFieldDef(
      field: 'cep',
      aliases: {'cep', 'codigo postal', 'zip'},
      isIdentifier: true,
    ),
    SpreadsheetFieldDef(
      field: 'cidade',
      aliases: {'cidade', 'city', 'municipio'},
    ),
  ],
);

const fornecedorSpreadsheetAliases = SpreadsheetEntityAliases(
  fields: [
    SpreadsheetFieldDef(
      field: 'nome',
      aliases: {'nome', 'razao social', 'fornecedor', 'name'},
      required: true,
    ),
    SpreadsheetFieldDef(
      field: 'telefone',
      aliases: {'telefone', 'celular', 'phone', 'fone'},
      required: true,
      isIdentifier: true,
    ),
    SpreadsheetFieldDef(
      field: 'email',
      aliases: {'email', 'e mail', 'mail'},
    ),
    SpreadsheetFieldDef(
      field: 'instagram',
      aliases: {'instagram', 'ig'},
    ),
    SpreadsheetFieldDef(
      field: 'whatsapp',
      aliases: {'whatsapp', 'wa', 'zap'},
      isIdentifier: true,
    ),
  ],
);

const precificacaoSpreadsheetAliases = SpreadsheetEntityAliases(
  fields: [
    SpreadsheetFieldDef(
      field: 'nome',
      aliases: {'nome', 'produto', 'item', 'name'},
      required: true,
    ),
    SpreadsheetFieldDef(
      field: 'custo',
      aliases: {
        'custo',
        'preco custo',
        'valor custo',
        'cost',
        'preco de custo',
      },
      required: true,
    ),
    SpreadsheetFieldDef(
      field: 'quantidade',
      aliases: {'quantidade', 'qtd', 'qty'},
    ),
    SpreadsheetFieldDef(
      field: 'codigoProduto',
      aliases: {
        'codigo',
        'codigo produto',
        'sku',
        'codigo interno',
        'barcode',
        'codigo barras',
      },
      isIdentifier: true,
    ),
  ],
);

/// Aliases de produtos/estoque — preserva lista existente de estoque_screen.
const produtoSpreadsheetAliases = SpreadsheetEntityAliases(
  fields: [
    SpreadsheetFieldDef(
      field: 'nome',
      aliases: {
        'nome',
        'name',
        'produto',
        'product',
        'titulo',
        'title',
        'nome do produto',
      },
      required: true,
    ),
    SpreadsheetFieldDef(
      field: 'preco',
      aliases: {
        'preco',
        'valor',
        'price',
        'preco venda',
        'valor venda',
        'preco unitario',
        'preco unit',
        'preco de venda',
        'valor unitario',
        'valor unit',
        'preco final',
        'valor final',
        'vlr',
        'vl',
        'venda',
      },
    ),
    SpreadsheetFieldDef(
      field: 'quantidade',
      aliases: {
        'quantidade',
        'qtd',
        'estoque',
        'stock',
        'quant',
        'quantidade estoque',
      },
    ),
    SpreadsheetFieldDef(
      field: 'codigo_barras',
      aliases: {
        'codigo barras',
        'codigo_barras',
        'barcode',
        'ean',
        'gtin',
        'codigo',
      },
      isIdentifier: true,
    ),
    SpreadsheetFieldDef(
      field: 'sku',
      aliases: {
        'sku',
        'codigo interno',
        'codigo_interno',
        'codigo produto',
        'referencia',
      },
      isIdentifier: true,
    ),
    SpreadsheetFieldDef(
      field: 'custo',
      aliases: {
        'preco custo',
        'preco de custo',
        'preco_custo',
        'preco de custo unitario',
        'preco_custo_unitario',
        'custo',
        'custo real',
        'custo_real',
        'valor custo',
        'valor de custo',
      },
    ),
  ],
);

String? fieldForHeader(String rawHeader, SpreadsheetEntityAliases entity) {
  final normalized = normalizeSpreadsheetHeader(rawHeader);
  if (normalized.isEmpty) return null;
  for (final def in entity.fields) {
    if (def.aliases.contains(normalized)) return def.field;
  }
  return null;
}
