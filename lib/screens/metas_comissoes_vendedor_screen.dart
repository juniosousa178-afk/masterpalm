// Sprint4-R2 / R5.3 — tela pessoal Metas & Comissões (vendedor).

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../core/access_scope_service.dart';
import '../core/gestao_comercial_meta_comissao.dart';
import '../core/hive_box_names.dart';
import '../core/meta_vendedor_legacy_bridge.dart';
import '../core/venda_exclusao_tombstone.dart';
import '../models/venda.dart';
import '../services/comissao_config_service.dart';
import '../services/gestao_comercial_service.dart';
import '../services/loja_id_service.dart';
import '../services/meta_firestore_service.dart';

class MetasComissoesVendedorScreen extends StatefulWidget {
  const MetasComissoesVendedorScreen({super.key});

  @override
  State<MetasComissoesVendedorScreen> createState() =>
      _MetasComissoesVendedorScreenState();
}

class _MetasComissoesVendedorScreenState
    extends State<MetasComissoesVendedorScreen> {
  static const _primary = Color(0xFF6366F1);
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  bool _loading = true;
  String? _erro;
  MetaPessoalProgresso? _meta;
  ComissaoPessoalResultado? _comissao;
  String? _periodoLabel;
  DateTime? _atualizadoEm;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final identity = await AccessScopeService.loadIdentity();
      if (!identity.isSeller) {
        setState(() {
          _erro = 'Esta tela é exclusiva do perfil vendedor.';
          _loading = false;
        });
        return;
      }
      final lojaId = (await LojaIdService.getWithTimeoutThenSessionFallback(
            timeout: const Duration(seconds: 10),
          ))
              ?.trim() ??
          '';
      if (lojaId.isEmpty || identity.uid.isEmpty) {
        throw Exception('Loja ou vendedor não identificados.');
      }

      var config = await GestaoComercialService.carregarConfigVendedor(
        lojaId: lojaId,
        vendedorUid: identity.uid,
      );

      final now = DateTime.now();
      final mesRef =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

      // Bridge legada: lojas/.../metas (sem cruzar GERAL / outros sellers).
      try {
        final metas = await MetaFirestoreService.getMetas(lojaId: lojaId);
        final legada = resolveMetaLegadaParaVendedor(
          metas: metas,
          identity: identity,
          mesRef: mesRef,
        );
        config = aplicarMetaLegadaSeVazia(config: config, legada: legada);
      } catch (_) {}

      // Bridge legada: comissoes_vendedores → global.
      try {
        final vendedorLegado = await ComissaoConfigService.getComissaoVendedor(
          lojaId: lojaId,
          vendedorUid: identity.uid,
        );
        final globalLegado = await ComissaoConfigService.getConfig(lojaId);
        config = aplicarComissaoLegadaSeVazia(
          config: config,
          vendedorLegado: vendedorLegado,
          globalLegado: globalLegado,
        );
      } catch (_) {}

      final boxName = HiveBoxNames.vendas(lojaId);
      Box<Venda> box;
      if (Hive.isBoxOpen(boxName)) {
        box = Hive.box<Venda>(boxName);
      } else {
        box = await Hive.openBox<Venda>(boxName);
      }

      final tombstones = await VendaExclusaoTombstone.idsParaLoja(lojaId);

      final meta = calcularMetaPessoal(
        config: config,
        identity: identity,
        vendas: box.values,
        lojaId: lojaId,
        agora: now,
        tombstonesExclusao: tombstones,
      );
      final comissao = calcularComissaoPessoal(
        config: config,
        identity: identity,
        vendas: box.values,
        lojaId: lojaId,
        agora: now,
        tombstonesExclusao: tombstones,
      );

      if (!mounted) return;
      setState(() {
        _meta = meta;
        _comissao = comissao;
        _periodoLabel = mesRef;
        _atualizadoEm = DateTime.now();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Falha ao carregar metas (type=${e.runtimeType})';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas & Comissões'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _carregar,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _erro != null
              ? Center(child: Text(_erro!))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _metaCard(),
                      const SizedBox(height: 12),
                      _comissaoCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _metaCard() {
    final m = _meta!;
    final restante = m.configurada && m.metaMensal > 0
        ? (m.metaMensal - m.realizadoMensal).clamp(0.0, double.infinity)
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Meta mensal individual',
                style: Theme.of(context).textTheme.titleMedium),
            if (_periodoLabel != null) ...[
              const SizedBox(height: 4),
              Text('Período: $_periodoLabel',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ],
            const SizedBox(height: 8),
            if (!m.configurada)
              Text(m.mensagem,
                  style: const TextStyle(fontWeight: FontWeight.w600))
            else ...[
              if (m.metaMensal > 0)
                Text('Meta: ${_money.format(m.metaMensal)}'),
              if (m.metaDiaria > 0)
                Text('Meta diária: ${_money.format(m.metaDiaria)}'),
              if (m.metaAnual > 0)
                Text('Meta anual: ${_money.format(m.metaAnual)}'),
              const SizedBox(height: 8),
              Text('Realizado: ${_money.format(m.realizadoMensal)}'),
              if (restante != null)
                Text('Restante: ${_money.format(restante)}'),
              Text('Vendas próprias: ${m.qtdVendasMensal}'),
              Text('Status: ${m.mensagem}'),
              const SizedBox(height: 8),
              if (m.percentualMensal != null)
                Text(
                  'Progresso: ${m.percentualMensal!.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _primary,
                  ),
                )
              else
                const Text(
                    'Progresso percentual indisponível (sem meta mensal).'),
              if (_atualizadoEm != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Atualizado: ${DateFormat('dd/MM/yyyy HH:mm').format(_atualizadoEm!)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _comissaoCard() {
    final c = _comissao!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Comissão própria',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Regra: ${c.regraAplicada}'),
            if (c.faixaAtingidaLabel != '—')
              Text('Faixa: ${c.faixaAtingidaLabel}'),
            const SizedBox(height: 8),
            Text('Acumulada: ${_money.format(c.acumulada)}'),
            Text('Pendente: ${_money.format(c.pendente)}'),
            Text('Paga: ${_money.format(c.paga)}'),
            Text('Vendas na base: ${c.qtdVendasBase}'),
          ],
        ),
      ),
    );
  }
}
