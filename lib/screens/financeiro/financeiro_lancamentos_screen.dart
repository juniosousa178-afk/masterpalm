// lib/screens/financeiro/financeiro_lancamentos_screen.dart

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../financeiro/financeiro_constants.dart';
import '../../models/lancamento_financeiro.dart';
import '../../services/financeiro_firestore_service.dart';
import '../../services/financeiro_hive_store.dart';
import '../../utils/moeda_input_formatter.dart';

class FinanceiroLancamentosScreen extends StatefulWidget {
  const FinanceiroLancamentosScreen({
    super.key,
    required this.lojaId,
    this.lancamentoIdInicial,
  });

  final String lojaId;
  /// Abre o formulário deste lançamento após carregar (ex.: vindo da gestão financeira).
  final String? lancamentoIdInicial;

  @override
  State<FinanceiroLancamentosScreen> createState() =>
      _FinanceiroLancamentosScreenState();
}

class _FinanceiroLancamentosScreenState
    extends State<FinanceiroLancamentosScreen> {
  static const Color _primary = Color(0xFF6366F1);

  Box<LancamentoFinanceiro>? _box;
  bool _loading = true;
  String? _erro;
  String? _pendenteAbrirId;

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  @override
  void initState() {
    super.initState();
    _pendenteAbrirId = widget.lancamentoIdInicial?.trim().isEmpty == true
        ? null
        : widget.lancamentoIdInicial?.trim();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      _box = await FinanceiroHiveStore.openLancamentosBox(widget.lojaId);
      if (_box == null) {
        throw Exception('Não foi possível abrir os lançamentos (armazenamento).');
      }
      if (mounted) {
        setState(() => _loading = false);
        final id = _pendenteAbrirId;
        if (id != null) {
          _pendenteAbrirId = null;
          final existente = _box!.get(id);
          if (existente != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _abrirFormulario(existente: existente);
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.toString();
        });
      }
    }
  }

  List<LancamentoFinanceiro> get _listaOrdenada {
    if (_box == null) return [];
    final list = _box!.values
        .where((l) => l.lojaId == widget.lojaId)
        .toList()
      ..sort((a, b) =>
          b.dataEfetivaPagamentoOuLancamento
              .compareTo(a.dataEfetivaPagamentoOuLancamento));
    return list;
  }

  Future<void> _abrirFormulario({LancamentoFinanceiro? existente}) async {
    final box = _box;
    if (box == null) return;
    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LancamentoFormSheet(
        lojaId: widget.lojaId,
        box: box,
        existente: existente,
        onSalvar: (l) async {
          await box.put(l.id, l);
          return FinanceiroFirestoreService.upsertLancamento(l);
        },
      ),
    );
    if (salvo == true && mounted) setState(() {});
  }

  Future<void> _excluir(LancamentoFinanceiro l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text(l.descricao),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true && _box != null) {
      final id = l.id;
      final lojaId = widget.lojaId;
      await _box!.delete(id);
      final remotoOk =
          await FinanceiroFirestoreService.deleteLancamento(lojaId: lojaId, id: id);
      if (mounted) {
        if (!remotoOk) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Removido neste aparelho. A exclusão na nuvem pode não ter concluído.',
              ),
              action: SnackBarAction(
                label: 'Tentar de novo',
                onPressed: () async {
                  final ok2 = await FinanceiroFirestoreService.deleteLancamento(
                    lojaId: lojaId,
                    id: id,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok2
                              ? 'Exclusão na nuvem concluída.'
                              : 'Ainda sem confirmação da nuvem. Verifique a conexão.',
                        ),
                    ),
                  );
                },
              ),
            ),
          );
        }
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Lançamentos financeiros'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _box == null ? null : () => _abrirFormulario(),
        backgroundColor: _primary,
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _erro != null
              ? Center(child: Text(_erro!))
              : RefreshIndicator(
                  color: _primary,
                  onRefresh: _open,
                  child: _listaOrdenada.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Icon(Icons.receipt_long,
                                size: 56, color: Colors.grey),
                            SizedBox(height: 12),
                            Center(
                              child: Text(
                                'Nenhum lançamento.\nToque em Novo para adicionar.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          itemCount: _listaOrdenada.length,
                          itemBuilder: (_, i) {
                            final l = _listaOrdenada[i];
                            final df = DateFormat('dd/MM/yyyy');
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(
                                  l.descricao.isEmpty
                                      ? '(sem descrição)'
                                      : l.descricao,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${FinanceiroTipoLancamento.legivel(l.tipo)} · ${l.status}\n'
                                  '${df.format(l.dataEfetivaPagamentoOuLancamento)}'
                                  '${l.referenciaExterna.trim().isNotEmpty ? '\nRef: ${l.referenciaExterna.trim()}' : ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                isThreeLine: true,
                                trailing: Text(
                                  _moeda.format(l.valor),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onTap: () => _abrirFormulario(existente: l),
                                onLongPress: () => _excluir(l),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _LancamentoFormSheet extends StatefulWidget {
  const _LancamentoFormSheet({
    required this.lojaId,
    required this.box,
    required this.onSalvar,
    this.existente,
  });

  final String lojaId;
  final Box<LancamentoFinanceiro> box;
  final LancamentoFinanceiro? existente;
  /// Hive já gravado; retorna se o upsert remoto teve sucesso.
  final Future<bool> Function(LancamentoFinanceiro l) onSalvar;

  @override
  State<_LancamentoFormSheet> createState() => _LancamentoFormSheetState();
}

class _LancamentoFormSheetState extends State<_LancamentoFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descCtrl;
  late TextEditingController _valorCtrl;
  late TextEditingController _fornCtrl;
  late TextEditingController _obsCtrl;
  late TextEditingController _centroCtrl;
  late TextEditingController _formaCtrl;
  late TextEditingController _subCtrl;
  late TextEditingController _refExternaCtrl;

  late String _tipo;
  late String _categoria;
  late String _status;
  late DateTime _dataLanc;
  DateTime? _dataPag;
  late bool _recorrente;

  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _descCtrl = TextEditingController(text: e?.descricao ?? '');
    _valorCtrl = TextEditingController(
      text: e != null ? MoedaInputFormatter.format(e.valor) : '',
    );
    _fornCtrl = TextEditingController(text: e?.fornecedor ?? '');
    _obsCtrl = TextEditingController(text: e?.observacao ?? '');
    _centroCtrl = TextEditingController(text: e?.centroCusto ?? '');
    _formaCtrl = TextEditingController(text: e?.formaPagamento ?? '');
    _subCtrl = TextEditingController(text: e?.subcategoria ?? '');
    _refExternaCtrl =
        TextEditingController(text: e?.referenciaExterna ?? '');
    _tipo = FinanceiroTipoLancamento.tipoOuPadrao(
        e?.tipo ?? FinanceiroTipoLancamento.despesaOperacional);
    _categoria = financeiroCategoriaOuPadrao(
        e?.categoria.isNotEmpty == true ? e!.categoria : '');
    _status = e?.status ?? FinanceiroStatusLancamento.pago;
    _dataLanc = e?.dataLancamento ?? DateTime.now();
    _dataPag = e?.dataPagamento;
    _recorrente = e?.recorrente ?? false;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _valorCtrl.dispose();
    _fornCtrl.dispose();
    _obsCtrl.dispose();
    _centroCtrl.dispose();
    _formaCtrl.dispose();
    _subCtrl.dispose();
    _refExternaCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isPagamento}) async {
    final initial = isPagamento
        ? (_dataPag ?? _dataLanc)
        : _dataLanc;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        if (isPagamento) {
          _dataPag = d;
        } else {
          _dataLanc = d;
        }
      });
    }
  }

  void _resetParaNovo() {
    _descCtrl.clear();
    _valorCtrl.clear();
    _fornCtrl.clear();
    _obsCtrl.clear();
    _centroCtrl.clear();
    _formaCtrl.clear();
    _subCtrl.clear();
    _refExternaCtrl.clear();
    setState(() {
      _tipo = FinanceiroTipoLancamento.despesaOperacional;
      _categoria = kFinanceiroCategoriasPadrao.first.categoria;
      _status = FinanceiroStatusLancamento.pago;
      _dataLanc = DateTime.now();
      _dataPag = null;
      _recorrente = false;
    });
  }

  Future<void> _salvar({bool fecharAoConcluir = true}) async {
    if (!_formKey.currentState!.validate()) return;
    final valor = MoedaInputFormatter.parse(_valorCtrl.text);
    if (valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor maior que zero.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final sessao = await Hive.openBox('sessao');
      final usuarioNome =
          (sessao.get('usuario_logado') ?? '').toString().trim();
      final usuarioId =
          (sessao.get('usuario_logado') ?? '').toString().trim();

      final id = widget.existente?.id ?? const Uuid().v4();
      final comp = widget.existente;
      final l = LancamentoFinanceiro(
        id: id,
        lojaId: widget.lojaId,
        descricao: _descCtrl.text.trim(),
        valor: valor,
        tipo: _tipo,
        categoria: _categoria,
        subcategoria: _subCtrl.text.trim(),
        status: _status,
        formaPagamento: _formaCtrl.text.trim(),
        fornecedor: _fornCtrl.text.trim(),
        observacao: _obsCtrl.text.trim(),
        dataLancamento: _dataLanc,
        dataPagamento: _status == FinanceiroStatusLancamento.pago
            ? (_dataPag ?? _dataLanc)
            : null,
        competenciaMes: _dataLanc.month,
        competenciaAno: _dataLanc.year,
        recorrente: _recorrente,
        usuarioId: usuarioId,
        usuarioNome: usuarioNome,
        centroCusto: _centroCtrl.text.trim(),
        anexoComprovante: comp?.anexoComprovante ?? '',
        referenciaExterna: _refExternaCtrl.text.trim(),
        origem: FinanceiroOrigemLancamento.manual,
      );

      final prosseguir =
          await _confirmarDuplicidadeCompraMercadoriaSeNecessario(l);
      if (!prosseguir || !mounted) return;

      final remotoOk = await widget.onSalvar(l);
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      if (!remotoOk) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Salvo neste aparelho, mas a sincronização com a nuvem falhou.',
            ),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Tentar na nuvem',
              onPressed: () async {
                final ok = await FinanceiroFirestoreService.upsertLancamento(l);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Sincronizado com a nuvem.'
                          : 'Ainda sem sucesso. Verifique a conexão.',
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }

      if (fecharAoConcluir) {
        Navigator.pop(context, true);
      } else {
        _resetParaNovo();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              remotoOk
                  ? 'Lançamento salvo. Novo formulário.'
                  : 'Lançamento salvo localmente. Novo formulário.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Retorna false se o usuário cancelar diante de suspeita de duplicidade.
  Future<bool> _confirmarDuplicidadeCompraMercadoriaSeNecessario(
    LancamentoFinanceiro l,
  ) async {
    final suspeitos = _encontrarSuspeitosCompraMercadoria(
      box: widget.box,
      lojaId: widget.lojaId,
      candidato: l,
      excluirId: widget.existente?.id,
    );
    if (suspeitos.isEmpty) return true;
    final df = DateFormat('dd/MM/yy');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Possível duplicidade'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Já existe lançamento parecido (compra de mercadoria, mesmo valor, '
                'mesma data e mesma descrição). Deseja salvar mesmo assim?',
              ),
              const SizedBox(height: 12),
              ...suspeitos.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '· ${s.descricao.isEmpty ? '(sem descrição)' : s.descricao} · '
                    'R\$ ${s.valor.toStringAsFixed(2)} · '
                    '${df.format(s.dataEfetivaPagamentoOuLancamento)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar assim mesmo'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.98,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  widget.existente == null
                      ? 'Novo lançamento'
                      : 'Editar lançamento',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descrição *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (s) =>
                      (s == null || s.trim().isEmpty) ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _refExternaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Referência (opcional)',
                    hintText: 'NF, código interno, nota…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _valorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoedaInputFormatter()],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _tipo,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                  ),
                  items: FinanceiroTipoLancamento.todos
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(FinanceiroTipoLancamento.legivel(t)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _tipo = v ?? _tipo),
                ),
                if (_tipo == FinanceiroTipoLancamento.compraMercadoria) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade700),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.amber.shade900),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Atenção: use este tipo apenas quando esta despesa não estiver '
                            'sendo controlada no módulo de compras. Lançar aqui e também '
                            'registrar o mesmo gasto na compra pode duplicar o valor nos relatórios.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _categoria,
                  decoration: const InputDecoration(
                    labelText: 'Categoria',
                    border: OutlineInputBorder(),
                  ),
                  items: kFinanceiroCategoriasPadrao
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.categoria,
                          child: Text(c.categoria.replaceAll('_', ' ')),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _categoria = v ?? _categoria),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _subCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Subcategoria',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: FinanceiroStatusLancamento.pago,
                      child: Text('Pago'),
                    ),
                    DropdownMenuItem(
                      value: FinanceiroStatusLancamento.pendente,
                      child: Text('Pendente'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? _status),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _formaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Forma de pagamento',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fornCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Fornecedor',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _centroCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Centro de custo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _obsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observação',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Recorrente'),
                  value: _recorrente,
                  onChanged: (v) => setState(() => _recorrente = v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data do lançamento'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_dataLanc)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => _pickDate(isPagamento: false),
                ),
                if (_status == FinanceiroStatusLancamento.pago)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Data de pagamento'),
                    subtitle: Text(
                      DateFormat('dd/MM/yyyy')
                          .format(_dataPag ?? _dataLanc),
                    ),
                    trailing: const Icon(Icons.event_available),
                    onTap: () => _pickDate(isPagamento: true),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _salvando ? null : () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed:
                            _salvando ? null : () => _salvar(fecharAoConcluir: true),
                        child: _salvando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Salvar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (widget.existente == null)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _salvando
                          ? null
                          : () => _salvar(fecharAoConcluir: false),
                      child: const Text('Salvar e novo'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _normalizarDescricaoDuplicidade(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool _mesmoDiaCivilLancamento(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Comparação estrita (compra_mercadoria, valor, dia e descrição).
List<LancamentoFinanceiro> _encontrarSuspeitosCompraMercadoria({
  required Box<LancamentoFinanceiro> box,
  required String lojaId,
  required LancamentoFinanceiro candidato,
  String? excluirId,
}) {
  if (candidato.tipo != FinanceiroTipoLancamento.compraMercadoria) {
    return const [];
  }
  final alvo = _normalizarDescricaoDuplicidade(candidato.descricao);
  if (alvo.isEmpty) return const [];
  final d = candidato.dataEfetivaPagamentoOuLancamento;
  final lid = lojaId.trim();
  final out = <LancamentoFinanceiro>[];
  for (final x in box.values) {
    if (x.lojaId.trim() != lid) continue;
    if (excluirId != null && x.id == excluirId) continue;
    if (x.tipo != FinanceiroTipoLancamento.compraMercadoria) continue;
    if ((x.valor - candidato.valor).abs() >= 0.009) continue;
    if (!_mesmoDiaCivilLancamento(x.dataEfetivaPagamentoOuLancamento, d)) {
      continue;
    }
    if (_normalizarDescricaoDuplicidade(x.descricao) != alvo) continue;
    out.add(x);
    if (out.length >= 5) break;
  }
  return out;
}
