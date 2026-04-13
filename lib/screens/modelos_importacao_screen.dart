// lib/screens/modelos_importacao_screen.dart
// Modelos CSV para importação: editar linhas no app e baixar o arquivo.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/file_saver.dart' as file_saver;

/// Abas: 0 estoque, 1 clientes, 2 fornecedores, 3 precificação.
class ModelosImportacaoScreen extends StatefulWidget {
  final int initialTabIndex;

  const ModelosImportacaoScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<ModelosImportacaoScreen> createState() =>
      _ModelosImportacaoScreenState();
}

class _ModelosImportacaoScreenState extends State<ModelosImportacaoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _estoqueHeaders = [
    'nome',
    'preco',
    'preco_custo',
    'quantidade',
    'categoria',
    'subcategoria',
    'sku',
    'codigo_barras',
    'descricao',
    'imagen',
  ];

  static const _clientesHeaders = [
    'Nome',
    'Telefone',
    'Instagram',
    'CEP',
    'Cidade',
  ];

  static const _fornecedoresHeaders = [
    'Nome',
    'Telefone',
    'E-mail',
    'Instagram',
    'WhatsApp',
  ];

  static const _precificacaoHeaders = [
    'Nome',
    'Custo',
    'Quantidade',
    'Codigo',
  ];

  late List<List<TextEditingController>> _estoqueCtrls;
  late List<List<TextEditingController>> _clientesCtrls;
  late List<List<TextEditingController>> _fornecedoresCtrls;
  late List<List<TextEditingController>> _precificacaoCtrls;

  /// Qual aba está exportando (null = nenhuma).
  int? _exportingTabIndex;

  @override
  void initState() {
    super.initState();
    final tab = widget.initialTabIndex.clamp(0, 3);
    _tabController = TabController(length: 4, vsync: this, initialIndex: tab);
    _estoqueCtrls = _controllersFromSeeds([
      [
        'Exemplo Pulseira',
        '29,90',
        '12,50',
        '10',
        'Semijoias',
        'Pulseiras',
        'SKU-DEMO-001',
        '7891234567890',
        'Substitua pelos seus produtos',
        'https://picsum.photos/seed/masterpalm-demo/800/800',
      ],
    ]);
    _clientesCtrls = _controllersFromSeeds([
      [
        'Maria Silva',
        '5511987654321',
        'mariasilva',
        '01310100',
        'São Paulo',
      ],
    ]);
    _fornecedoresCtrls = _controllersFromSeeds([
      [
        'Fornecedor Exemplo Ltda',
        '5511977777777',
        'contato@fornecedor.com.br',
        'fornecedor_exemplo',
        '5511977777777',
      ],
    ]);
    _precificacaoCtrls = _controllersFromSeeds([
      ['Pulseira modelo A', '15,50', '1', 'SKU-PUL-01'],
      ['Colar modelo B', '22,00', '2', ''],
    ]);
  }

  List<List<TextEditingController>> _controllersFromSeeds(
      List<List<String>> seeds) {
    return seeds
        .map((row) => row.map((c) => TextEditingController(text: c)).toList())
        .toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final row in _estoqueCtrls) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final row in _clientesCtrls) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final row in _fornecedoresCtrls) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final row in _precificacaoCtrls) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  static String _csvEscape(String cell) {
    final t = cell.trim();
    if (t.contains(';') ||
        t.contains('"') ||
        t.contains('\n') ||
        t.contains('\r')) {
      return '"${t.replaceAll('"', '""')}"';
    }
    return t;
  }

  static String _buildCsv(List<String> headers, List<List<String>> rows) {
    final sb = StringBuffer();
    sb.writeln(headers.map(_csvEscape).join(';'));
    for (final r in rows) {
      sb.writeln(r.map(_csvEscape).join(';'));
    }
    return sb.toString();
  }

  List<List<String>> _readRows(List<List<TextEditingController>> ctrls) {
    return ctrls.map((r) => r.map((c) => c.text).toList()).toList();
  }

  Future<void> _exportar(
    List<String> headers,
    List<List<TextEditingController>> ctrls,
    String fileName,
    int tabIndex,
  ) async {
    setState(() => _exportingTabIndex = tabIndex);
    try {
      final csv = _buildCsv(headers, _readRows(ctrls));
      final bytes = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(csv),
      ]);
      await file_saver.saveFile(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Arquivo salvo: $fileName. Abra no Excel, ajuste se quiser e salve como .xlsx antes de importar, quando o app pedir Excel.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível salvar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingTabIndex = null);
    }
  }

  void _addLinha(List<List<TextEditingController>> ctrls, int colCount) {
    setState(() {
      ctrls.add(List.generate(colCount, (_) => TextEditingController()));
    });
  }

  void _removerUltima(List<List<TextEditingController>> ctrls) {
    if (ctrls.length <= 1) return;
    setState(() {
      final removed = ctrls.removeLast();
      for (final c in removed) {
        c.dispose();
      }
    });
  }

  Widget _bloco({
    required String titulo,
    required String descricao,
    required List<String> headers,
    required List<List<TextEditingController>> ctrls,
    required String fileName,
    required int tabIndex,
  }) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titulo,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(descricao, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: cs.outlineVariant),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest),
                  children: headers
                      .map(
                        (h) => Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            h,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                      .toList(),
                ),
                ...ctrls.asMap().entries.map((e) {
                  final i = e.key;
                  final row = e.value;
                  return TableRow(
                    children: row.asMap().entries.map((ce) {
                      return Padding(
                        padding: const EdgeInsets.all(4),
                        child: TextField(
                          controller: ce.value,
                          decoration: InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            hintText: 'Linha ${i + 1}',
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _exportingTabIndex != null
                    ? null
                    : () => _exportar(headers, ctrls, fileName, tabIndex),
                icon: _exportingTabIndex == tabIndex
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download, size: 18),
                label: const Text('Baixar CSV editado'),
              ),
              OutlinedButton.icon(
                onPressed: _exportingTabIndex != null
                    ? null
                    : () => _addLinha(ctrls, headers.length),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Adicionar linha'),
              ),
              OutlinedButton.icon(
                onPressed: _exportingTabIndex != null
                    ? null
                    : () => _removerUltima(ctrls),
                icon: const Icon(Icons.remove, size: 18),
                label: const Text('Remover última linha'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modelos de importação'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Estoque'),
            Tab(text: 'Clientes'),
            Tab(text: 'Fornecedores'),
            Tab(text: 'Precificação'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _bloco(
            titulo: 'Produtos (estoque)',
            descricao:
                'Edite as células abaixo ou adicione linhas. O app aceita .xlsx e .csv (na Web, PDF não). Coluna imagen (também aceita imagens): URLs públicas http(s); várias fotos separadas por | ou ;. Na importação, o app baixa e salva no Firebase Storage.',
            headers: _estoqueHeaders,
            ctrls: _estoqueCtrls,
            fileName: 'masterpalm-estoque-editado.csv',
            tabIndex: 0,
          ),
          _bloco(
            titulo: 'Clientes',
            descricao:
                'Importação no app usa em geral .xlsx: após editar o CSV, salve como Excel se necessário. Primeira linha do arquivo = cabeçalho.',
            headers: _clientesHeaders,
            ctrls: _clientesCtrls,
            fileName: 'masterpalm-clientes-editado.csv',
            tabIndex: 1,
          ),
          _bloco(
            titulo: 'Fornecedores',
            descricao:
                'Mesma ideia: edite aqui, baixe o CSV e converta para .xlsx se o app solicitar apenas Excel.',
            headers: _fornecedoresHeaders,
            ctrls: _fornecedoresCtrls,
            fileName: 'masterpalm-fornecedores-editado.csv',
            tabIndex: 2,
          ),
          _bloco(
            titulo: 'Precificação universal',
            descricao:
                'Coluna D (código) é opcional. Linha 1 do arquivo importado costuma ser ignorada pelo app.',
            headers: _precificacaoHeaders,
            ctrls: _precificacaoCtrls,
            fileName: 'masterpalm-precificacao-editado.csv',
            tabIndex: 3,
          ),
        ],
      ),
    );
  }
}
