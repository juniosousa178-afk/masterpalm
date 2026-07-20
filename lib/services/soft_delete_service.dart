// lib/services/soft_delete_service.dart
//
// Exclusão suave: ao excluir produto/venda/cliente, move para "lixeira" por 5 segundos.
// Dentro de 5 s: botão Desfazer restaura. Após 5 s: exclui do Hive e Firebase.
// Excluir em lote: cada item pode ser desfeito individualmente em até 5 segundos.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../core/safe_cast.dart';
import '../core/venda_exclusao_tombstone.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import 'produto_exclusao_remota_service.dart';
import 'produto_pull_skip_guard.dart';
import 'produtos_firestore_service.dart';
import 'clientes_firestore_service.dart';
import 'estoque_transaction_service.dart';
import 'notificacao_vendas_service.dart';
import 'vendas_firestore_service.dart';
import 'vendas_service.dart';

const _undoWindow = Duration(seconds: 5);
const _checkInterval = Duration(seconds: 1);
const _prefsKey = 'soft_delete_pending';

/// Registro de exclusão pendente (persistido em SharedPreferences).
class _PendingRecord {
  final String id;
  final String type; // produto, venda, cliente
  final String lojaId;
  final String idFirebase;
  final int hiveKey;
  final int trashKey;
  final String deleteAt; // ISO8601
  /// Motivo / actor / seller — só vendas. Notifica após exclusão definitiva.
  final String? motivoExclusao;
  final String? atorUid;
  final String? vendedorUid;
  final String? vendedorEmail;
  final String? clienteNome;
  /// Estorno já aplicado em [scheduleVendaDelete] — permanente não reestornar.
  final bool estoqueEstornado;
  /// Notificação já enviada — retry não duplica.
  final bool notificacaoEnviada;

  _PendingRecord({
    required this.id,
    required this.type,
    required this.lojaId,
    required this.idFirebase,
    required this.hiveKey,
    required this.trashKey,
    required this.deleteAt,
    this.motivoExclusao,
    this.atorUid,
    this.vendedorUid,
    this.vendedorEmail,
    this.clienteNome,
    this.estoqueEstornado = false,
    this.notificacaoEnviada = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'lojaId': lojaId,
        'idFirebase': idFirebase,
        'hiveKey': hiveKey,
        'trashKey': trashKey,
        'deleteAt': deleteAt,
        if (motivoExclusao != null) 'motivoExclusao': motivoExclusao,
        if (atorUid != null) 'atorUid': atorUid,
        if (vendedorUid != null) 'vendedorUid': vendedorUid,
        if (vendedorEmail != null) 'vendedorEmail': vendedorEmail,
        if (clienteNome != null) 'clienteNome': clienteNome,
        'estoqueEstornado': estoqueEstornado,
        'notificacaoEnviada': notificacaoEnviada,
      };

  _PendingRecord copyWith({
    int? trashKey,
    bool? estoqueEstornado,
    bool? notificacaoEnviada,
  }) =>
      _PendingRecord(
        id: id,
        type: type,
        lojaId: lojaId,
        idFirebase: idFirebase,
        hiveKey: hiveKey,
        trashKey: trashKey ?? this.trashKey,
        deleteAt: deleteAt,
        motivoExclusao: motivoExclusao,
        atorUid: atorUid,
        vendedorUid: vendedorUid,
        vendedorEmail: vendedorEmail,
        clienteNome: clienteNome,
        estoqueEstornado: estoqueEstornado ?? this.estoqueEstornado,
        notificacaoEnviada: notificacaoEnviada ?? this.notificacaoEnviada,
      );

  static _PendingRecord? fromJsonSafe(Map<String, dynamic> m) {
    try {
      final id = m['id'];
      final type = m['type'];
      final lojaId = m['lojaId'];
      final idFirebase = m['idFirebase'];
      final hiveKey = m['hiveKey'];
      final trashKey = m['trashKey'];
      final deleteAt = m['deleteAt'];
      if (id is! String || type is! String || lojaId is! String || idFirebase is! String) return null;
      final hk = hiveKey is int ? hiveKey : (hiveKey is num ? hiveKey.toInt() : null);
      final tk = trashKey is int ? trashKey : (trashKey is num ? trashKey.toInt() : null);
      if (hk == null || tk == null || deleteAt is! String) return null;
      String? opt(String k) {
        final v = m[k];
        if (v is! String) return null;
        final t = v.trim();
        return t.isEmpty ? null : t;
      }

      return _PendingRecord(
        id: id,
        type: type,
        lojaId: lojaId,
        idFirebase: idFirebase,
        hiveKey: hk,
        trashKey: tk,
        deleteAt: deleteAt,
        motivoExclusao: opt('motivoExclusao'),
        atorUid: opt('atorUid'),
        vendedorUid: opt('vendedorUid'),
        vendedorEmail: opt('vendedorEmail'),
        clienteNome: opt('clienteNome'),
        estoqueEstornado: m['estoqueEstornado'] == true,
        notificacaoEnviada: m['notificacaoEnviada'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  DateTime get deleteAtDt => DateTime.parse(deleteAt);
}

/// Cópia profunda de [VendaItem] (não é [HiveObject]; clonar evita partilhar referências mutáveis).
List<VendaItem>? _cloneVendaItens(List<VendaItem>? itens) {
  if (itens == null) return null;
  return itens
      .map(
        (e) => VendaItem(
          produtoNome: e.produtoNome,
          quantidade: e.quantidade,
          precoUnitario: e.precoUnitario,
          tamanho: e.tamanho,
          lojaId: e.lojaId,
          cor: e.cor,
          productId: e.productId,
          variacaoExtraResumo: e.variacaoExtraResumo,
          extraValor: e.extraValor,
          custoUnitario: e.custoUnitario,
          origemCustoItem: e.origemCustoItem,
        ),
      )
      .toList();
}

/// Nova instância de [Venda] para gravar noutra box/key — nunca reutilizar o mesmo [HiveObject].
Venda _cloneVendaParaHive(Venda v) {
  return Venda(
    clienteNome: v.clienteNome,
    produtosDescricao: v.produtosDescricao,
    quantidade: v.quantidade,
    preco: v.preco,
    total: v.total,
    formasPagamento: v.formasPagamento,
    data: v.data,
    tamanho: v.tamanho,
    desconto: v.desconto,
    frete: v.frete,
    vendedor: v.vendedor,
    observacao: v.observacao,
    itens: _cloneVendaItens(v.itens),
    pagamentoDinheiro: v.pagamentoDinheiro,
    pagamentoPix: v.pagamentoPix,
    pagamentoCartao: v.pagamentoCartao,
    taxas: v.taxas,
    custoProdutos: v.custoProdutos,
    descontoValor: v.descontoValor,
    lojaId: v.lojaId,
    idFirebase: v.idFirebase,
    clienteId: v.clienteId,
    statusVenda: v.statusVenda,
    cancelada: v.cancelada,
    estornada: v.estornada,
    origemVenda: v.origemVenda,
    paymentId: v.paymentId,
    orderId: v.orderId,
    prePedidoId: v.prePedidoId,
    pedidoId: v.pedidoId,
    origemCusto: v.origemCusto,
    itensComboSelecaoJson: v.itensComboSelecaoJson,
    vendedorUid: v.vendedorUid,
    vendedorNome: v.vendedorNome,
    vendedorEmail: v.vendedorEmail,
  );
}

class SoftDeleteService {
  SoftDeleteService._();

  static Box<Produto>? _trashProdutos;
  static Box<Venda>? _trashVendas;
  static Box<Cliente>? _trashClientes;
  static Timer? _timer;
  static List<_PendingRecord> _pending = [];
  static bool _loaded = false;

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _pending = [];
        for (final e in list) {
          if (e is! Map) continue;
          final rec = _PendingRecord.fromJsonSafe(Map<String, dynamic>.from(e));
          if (rec != null) {
            _pending.add(rec);
          } else if (kDebugMode) {
            logW('⚠️ [SOFT-DELETE] Registro de pendência inválido ignorado');
          }
        }
      } catch (e) {
        if (kDebugMode) logW('⚠️ [SOFT-DELETE] Erro ao carregar pendências: $e');
        _pending = [];
      }
    }
    _loaded = true;
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _pending.map((r) => r.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  static Future<Box<Produto>> _trashProdutosBox() async {
    _trashProdutos ??= await Hive.openBox<Produto>('trash_produtos');
    return _trashProdutos!;
  }

  static Future<Box<Venda>> _trashVendasBox() async {
    _trashVendas ??= await Hive.openBox<Venda>('trash_vendas');
    return _trashVendas!;
  }

  static Future<Box<Cliente>> _trashClientesBox() async {
    _trashClientes ??= await Hive.openBox<Cliente>('trash_clientes');
    return _trashClientes!;
  }

  /// Agenda exclusão de produto. Retorna id para undo.
  static Future<String?> scheduleProdutoDelete({
    required Produto produto,
    required Box<Produto> produtosBox,
    required String lojaId,
    bool removeFromCatalogo = true,
  }) async {
    await _ensureLoaded();
    final key = produto.key as int?;
    if (key == null) return null;

    produto.lojaId = lojaId;

    var docIdResolved = produto.idFirebase.trim();
    if (docIdResolved.isEmpty && produto.slug.trim().isNotEmpty) {
      final found = await ProdutosFirestoreService.findEstoqueProdutoDocIdBySlug(
        lojaId: lojaId,
        slug: produto.slug,
      );
      if (found != null && found.trim().isNotEmpty) {
        docIdResolved = found.trim();
        produto.idFirebase = docIdResolved;
      }
    }

    // Tombstone remoto antes de esvaziar o Hive: evita janela em que o pull recria o produto.
    var tombstoneOk = docIdResolved.isEmpty;
    if (!tombstoneOk) {
      tombstoneOk =
          await ProdutoExclusaoRemotaService.marcarEstoqueProdutoPendenteSoftDelete(
        produto: produto,
        lojaId: lojaId,
      );
    }
    if (!tombstoneOk && docIdResolved.isNotEmpty) {
      await ProdutoPullSkipGuard.addDocId(lojaId, docIdResolved);
    } else if (docIdResolved.isEmpty && produto.slug.trim().isNotEmpty) {
      await ProdutoPullSkipGuard.addSlug(lojaId, produto.slug.trim());
    }

    if (removeFromCatalogo) {
      try {
        await ProdutoExclusaoRemotaService.removerCatalogoParaProdutoRemovidoDoHive(
          produto: produto,
          lojaId: lojaId,
        );
      } catch (e) {
        logW('⚠️ [SOFT-DELETE] Erro ao remover do catálogo (type=${e.runtimeType})');
      }
    }

    final trashBox = await _trashProdutosBox();
    await produtosBox.delete(key);
    final trashKey = await trashBox.add(produto);

    final id = const Uuid().v4();
    final deleteAt = DateTime.now().add(_undoWindow);
    _pending.add(_PendingRecord(
      id: id,
      type: 'produto',
      lojaId: lojaId,
      idFirebase: produto.idFirebase.isNotEmpty ? produto.idFirebase : '',
      hiveKey: key,
      trashKey: trashKey,
      deleteAt: deleteAt.toIso8601String(),
    ));
    await _save();
    _startTimerIfNeeded();
    return id;
  }

  /// Agenda exclusão de venda. Remove do histórico do cliente.
  ///
  /// [motivoExclusao]/[vendedorUid]/etc. são persistidos na pendência e a
  /// notificação ao vendedor só ocorre na exclusão definitiva (após janela undo).
  static Future<String?> scheduleVendaDelete({
    required Venda venda,
    required Box<Venda> vendasBox,
    required Box<Cliente> clientesBox,
    required String lojaId,
    String? motivoExclusao,
    String? atorUid,
    String? vendedorUid,
    String? vendedorEmail,
    String? clienteNome,
  }) async {
    await _ensureLoaded();
    final key = venda.key as int?;
    if (key == null) return null;

    debugPrint('[VENDA-DELETE] etapa=remover_contas_start lojaId=$lojaId vendaKey=$key');
    await VendasService.removerContasReceberVinculadasAVenda(
      lojaId: lojaId,
      vendaKey: hiveKeyOrNull(key),
      vendaIdFirebase: VendasService.idVendaEstavelParaVinculo(venda),
    );
    debugPrint('[VENDA-DELETE] etapa=remover_contas_ok');

    debugPrint('[VENDA-DELETE] etapa=devolver_estoque_start');
    final produtosBox =
        await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
    try {
      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
        vendaHiveKeyMarcador: key,
      );
    } catch (e, st) {
      if (e is FirebaseException) {
        debugPrint(
          '[VENDA-DELETE] etapa=erro type=FirebaseException code=${e.code} message=${e.message}',
        );
      } else {
        debugPrint(
          '[VENDA-DELETE] etapa=erro type=${e.runtimeType} erro=$e',
        );
      }
      debugPrint('[VENDA-DELETE] etapa=erro stack=$st');
      rethrow;
    }
    debugPrint('[VENDA-DELETE] etapa=devolver_estoque_ok');

    await VendaExclusaoTombstone.registrar(
      lojaId: lojaId,
      idFirebase: venda.idFirebase,
      hiveKey: key,
    );

    final idFb = (venda.idFirebase ?? '').trim();
    if (idFb.isNotEmpty) {
      debugPrint('[VENDA-DELETE] etapa=delete_firestore_start idFb=$idFb');
      try {
        await VendasFirestoreService.deleteVenda(idFb, lojaId: lojaId);
        debugPrint('[VENDA-DELETE] etapa=delete_firestore_ok');
      } catch (e) {
        if (e is FirebaseException) {
          debugPrint(
            '[VENDA-DELETE] etapa=erro type=FirebaseException code=${e.code} message=${e.message}',
          );
        } else {
          debugPrint(
            '[VENDA-DELETE] etapa=erro type=${e.runtimeType} erro=$e',
          );
        }
        logW(
          '[SOFT-DELETE] Falha ao remover venda do Firestore ao excluir (type=${e.runtimeType})',
        );
      }
    } else {
      debugPrint('[VENDA-DELETE] etapa=delete_firestore_skip (sem idFirebase)');
    }

    debugPrint('[VENDA-DELETE] etapa=hive_delete_start');
    final trashBox = await _trashVendasBox();
    venda.lojaId = lojaId;
    final vendaLixeira = _cloneVendaParaHive(venda);
    vendaLixeira.lojaId = lojaId;
    vendaLixeira.cancelada = true;
    vendaLixeira.statusVenda = 'excluida';

    Cliente? cliente;
    try {
      cliente = clientesBox.values.firstWhere(
        (c) => c.lojaId == lojaId && c.nome == venda.clienteNome,
      );
    } catch (_) {
      cliente = null;
    }
    if (cliente != null && cliente.historico != null) {
      cliente.historico!.removeWhere((h) => identical(h, venda) || h.key == key);
      await cliente.save();
      try {
        await ClientesFirestoreService.syncCliente(cliente, lojaId: lojaId);
      } catch (_) {}
    }

    await vendasBox.delete(key);
    final trashKey = await trashBox.add(vendaLixeira);

    final id = const Uuid().v4();
    final deleteAt = DateTime.now().add(_undoWindow);
    final uidSeller = (vendedorUid ?? venda.vendedorUid ?? '').trim();
    final emailSeller = (vendedorEmail ?? venda.vendedorEmail ?? '').trim();
    final nomeCliente = (clienteNome ?? venda.clienteNome).trim();
    _pending.add(_PendingRecord(
      id: id,
      type: 'venda',
      lojaId: lojaId,
      idFirebase: venda.idFirebase ?? '',
      hiveKey: key,
      trashKey: trashKey,
      deleteAt: deleteAt.toIso8601String(),
      motivoExclusao: (motivoExclusao ?? '').trim().isEmpty
          ? null
          : motivoExclusao!.trim(),
      atorUid: (atorUid ?? '').trim().isEmpty ? null : atorUid!.trim(),
      vendedorUid: uidSeller.isEmpty ? null : uidSeller,
      vendedorEmail: emailSeller.isEmpty ? null : emailSeller,
      clienteNome: nomeCliente.isEmpty ? null : nomeCliente,
      estoqueEstornado: true,
      notificacaoEnviada: false,
    ));
    await _save();
    _startTimerIfNeeded();

    // Notificação imediata (não esperar janela undo). Estoque/tombstone intactos.
    final notifOk = await _tryNotificarExclusaoVenda(
      lojaId: lojaId,
      vendedorUid: uidSeller,
      vendedorEmail: emailSeller,
      pedidoId: idFb.isNotEmpty ? idFb : id,
      clienteNome: nomeCliente.isEmpty ? 'Cliente' : nomeCliente,
      motivo: (motivoExclusao ?? '').trim().isEmpty
          ? null
          : motivoExclusao!.trim(),
      adminUid: (atorUid ?? '').trim().isEmpty ? null : atorUid!.trim(),
      pendingId: id,
    );
    if (notifOk) {
      final idx = _pending.indexWhere((p) => p.id == id);
      if (idx >= 0) {
        _pending[idx] = _pending[idx].copyWith(notificacaoEnviada: true);
        await _save();
      }
    }

    debugPrint('[VENDA-DELETE] etapa=schedule_concluido undoId=$id');
    return id;
  }

  /// Agenda exclusão de cliente.
  static Future<String?> scheduleClienteDelete({
    required Cliente cliente,
    required Box<Cliente> clientesBox,
    required String lojaId,
  }) async {
    await _ensureLoaded();
    final key = cliente.key as int?;
    if (key == null) return null;

    final trashBox = await _trashClientesBox();
    cliente.lojaId = lojaId;
    await clientesBox.delete(key);
    final trashKey = await trashBox.add(cliente);

    final id = const Uuid().v4();
    final deleteAt = DateTime.now().add(_undoWindow);
    _pending.add(_PendingRecord(
      id: id,
      type: 'cliente',
      lojaId: lojaId,
      idFirebase: cliente.idFirebase ?? '',
      hiveKey: key,
      trashKey: trashKey,
      deleteAt: deleteAt.toIso8601String(),
    ));
    await _save();
    _startTimerIfNeeded();
    return id;
  }

  /// Desfaz exclusão. Retorna true se desfeito.
  ///
  /// A mesma instância de [HiveObject] não pode estar em duas boxes ao mesmo tempo.
  /// É obrigatório remover da lixeira antes de [Box.add] na box principal (senão o Hive lança).
  static Future<bool> undo(String id) async {
    await _ensureLoaded();
    final idx = _pending.indexWhere((r) => r.id == id);
    if (idx < 0) return false;

    final r = _pending[idx];

    try {
      if (r.type == 'produto') {
        final trashBox = await _trashProdutosBox();
        final prod = trashBox.get(r.trashKey);
        if (prod == null) {
          logW('⚠️ [SOFT-DELETE] undo: produto ausente na lixeira (trashKey=${r.trashKey})');
          return false;
        }
        final mainBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(r.lojaId));
        prod.lojaId = r.lojaId;
        await trashBox.delete(r.trashKey);
        try {
          await mainBox.add(prod);
        } catch (e, st) {
          logE(
            '❌ [SOFT-DELETE] Falha ao restaurar produto na box; recolocando na lixeira (type=${e.runtimeType})',
            error: e,
            st: st,
          );
          final nk = await trashBox.add(prod);
          _pending[idx] = r.copyWith(trashKey: nk);
          await _save();
          return false;
        }
        _pending.removeAt(idx);
        await _save();
        final idFb = prod.idFirebase.trim();
        if (idFb.isNotEmpty) {
          try {
            await ProdutoExclusaoRemotaService.limparEstoquePendenteSoftDelete(
              lojaId: r.lojaId,
              produtoIdFirebase: idFb,
            );
          } catch (e) {
            logW(
              '⚠️ [SOFT-DELETE] Erro ao limpar tombstone estoque no undo (type=${e.runtimeType})',
            );
          }
        }
        await ProdutoPullSkipGuard.removeForProduct(
          lojaId: r.lojaId,
          docId: prod.idFirebase,
          slug: prod.slug,
        );
        return true;
      }
      if (r.type == 'venda') {
        final trashBox = await _trashVendasBox();
        final vendaNaLixeira = trashBox.get(r.trashKey);
        if (vendaNaLixeira == null) {
          logW('⚠️ [SOFT-DELETE] undo: venda ausente na lixeira (trashKey=${r.trashKey})');
          return false;
        }
        final vendaParaRestaurar = _cloneVendaParaHive(vendaNaLixeira);
        vendaParaRestaurar.lojaId = r.lojaId;
        final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(r.lojaId));
        final clientesBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(r.lojaId));
        await trashBox.delete(r.trashKey);
        try {
          await vendasBox.add(vendaParaRestaurar);
        } catch (e, st) {
          logE(
            '❌ [SOFT-DELETE] Falha ao restaurar venda na box; recolocando na lixeira (type=${e.runtimeType})',
            error: e,
            st: st,
          );
          final nk = await trashBox.add(_cloneVendaParaHive(vendaParaRestaurar));
          _pending[idx] = r.copyWith(trashKey: nk);
          await _save();
          return false;
        }
        Cliente? cliente;
        try {
          cliente = clientesBox.values.firstWhere(
            (c) => c.lojaId == r.lojaId && c.nome == vendaParaRestaurar.clienteNome,
          );
        } catch (_) {
          cliente = null;
        }
        if (cliente != null) {
          cliente.adicionarHistorico(vendaParaRestaurar, lojaId: r.lojaId);
          try {
            await ClientesFirestoreService.syncCliente(cliente, lojaId: r.lojaId);
          } catch (_) {}
        }
        try {
          final produtosBoxUndo =
              await Hive.openBox<Produto>(HiveBoxNames.produtos(r.lojaId));
          final vid = (vendaParaRestaurar.idFirebase ?? '').trim().isNotEmpty
              ? vendaParaRestaurar.idFirebase!.trim()
              : 'hive_${r.hiveKey}';
          final marcadorId = r.hiveKey >= 0
              ? r.hiveKey.toString()
              : EstoqueTransactionService.vendaIdMarcadorCatalogoFromKey(
                  vendaParaRestaurar.key,
                );
          await VendasService.reaplicarBaixaEstoquePosUndoExclusaoVenda(
            venda: vendaParaRestaurar,
            produtosBox: produtosBoxUndo,
            lojaId: r.lojaId,
          );
          await EstoqueTransactionService.removerMarcadorDevolucaoVenda(
            r.lojaId,
            vid,
          );
          if (marcadorId != null && marcadorId.isNotEmpty) {
            await EstoqueTransactionService.removerMarcadorDevolucaoVenda(
              r.lojaId,
              marcadorId,
            );
            await EstoqueTransactionService.limparEstornoAplicadoCatalogo(
              r.lojaId,
              marcadorId,
            );
          }
        } catch (e) {
          logW(
            '[SOFT-DELETE] undo venda: reaplicar baixa ou marcador falhou (type=${e.runtimeType})',
          );
        }
        try {
          await VendasFirestoreService.syncVenda(vendaParaRestaurar, lojaId: r.lojaId);
        } catch (e) {
          logW(
            '[SOFT-DELETE] undo venda: sync Firestore falhou (type=${e.runtimeType})',
          );
        }
        try {
          await VendasService.recriarContaReceberFiadoAposUndoSeAplicavel(
            venda: vendaParaRestaurar,
            lojaId: r.lojaId,
          );
        } catch (e) {
          logW(
            '[SOFT-DELETE] undo venda: recriar fiado local falhou (type=${e.runtimeType})',
          );
        }
        _pending.removeAt(idx);
        await _save();
        await VendaExclusaoTombstone.remover(
          lojaId: r.lojaId,
          idFirebase: r.idFirebase.isNotEmpty
              ? r.idFirebase
              : vendaParaRestaurar.idFirebase,
          hiveKey: r.hiveKey,
        );
        return true;
      }
      if (r.type == 'cliente') {
        final trashBox = await _trashClientesBox();
        final cliente = trashBox.get(r.trashKey);
        if (cliente == null) {
          logW('⚠️ [SOFT-DELETE] undo: cliente ausente na lixeira (trashKey=${r.trashKey})');
          return false;
        }
        final mainBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(r.lojaId));
        cliente.lojaId = r.lojaId;
        await trashBox.delete(r.trashKey);
        try {
          await mainBox.add(cliente);
        } catch (e, st) {
          logE(
            '❌ [SOFT-DELETE] Falha ao restaurar cliente na box; recolocando na lixeira (type=${e.runtimeType})',
            error: e,
            st: st,
          );
          final nk = await trashBox.add(cliente);
          _pending[idx] = r.copyWith(trashKey: nk);
          await _save();
          return false;
        }
        _pending.removeAt(idx);
        await _save();
        return true;
      }
    } catch (e, st) {
      logE('❌ [SOFT-DELETE] Erro ao desfazer (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
    return false;
  }

  /// Desfaz múltiplas exclusões (ex.: lote de produtos).
  static Future<int> undoBatch(List<String> ids) async {
    int n = 0;
    for (final id in ids) {
      if (await undo(id)) n++;
    }
    return n;
  }

  static Future<void>? _processExpiredInFlight;

  static void _startTimerIfNeeded() {
    if (_timer?.isActive == true) return;
    _timer = Timer.periodic(_checkInterval, (_) => _processExpired());
  }

  /// Processa pendências expiradas — no máximo uma execução por vez (anti-duplicata).
  static Future<void> _processExpired() async {
    if (_processExpiredInFlight != null) {
      return _processExpiredInFlight!;
    }
    _processExpiredInFlight = _processExpiredImpl();
    try {
      await _processExpiredInFlight;
    } finally {
      _processExpiredInFlight = null;
    }
  }

  static Future<void> _processExpiredImpl() async {
    await _ensureLoaded();
    final now = DateTime.now();
    final toRemove = <_PendingRecord>[];
    for (final r in _pending) {
      if (r.deleteAtDt.isBefore(now)) toRemove.add(r);
    }
    for (final r in toRemove) {
      try {
        await _executeRealDelete(r);
        _pending.removeWhere((p) => p.id == r.id);
      } catch (e, st) {
        logE(
          '❌ [SOFT-DELETE] exclusão definitiva falhou; pendência mantida para retry. '
          'id=${r.id} type=${r.type} (type=${e.runtimeType})',
          error: e,
          st: st,
        );
      }
    }
    if (toRemove.isNotEmpty) await _save();
  }

  static Future<void> _executeRealDelete(_PendingRecord r) async {
    if (r.type == 'produto') {
      final trashBox = await _trashProdutosBox();
      final prod = trashBox.get(r.trashKey);
      if (prod != null) {
        final status =
            await ProdutoExclusaoRemotaService.apagarImagensEEstoqueRemotoComStatus(
          produto: prod,
          lojaId: r.lojaId,
        );
        if (status != ProdutoExclusaoRemotaStatus.confirmada) {
          throw StateError(
            'Exclusão remota de produto pendente (status=$status)',
          );
        }
        await ProdutoPullSkipGuard.removeForProduct(
          lojaId: r.lojaId,
          docId: prod.idFirebase,
          slug: prod.slug,
        );
      } else if (r.idFirebase.trim().isNotEmpty) {
        await ProdutoPullSkipGuard.removeForProduct(
          lojaId: r.lojaId,
          docId: r.idFirebase,
        );
      }
      await trashBox.delete(r.trashKey);
      logD('🗑️ [SOFT-DELETE] Produto excluído permanentemente (Firestore + lixeira local)');
    } else if (r.type == 'venda') {
      final trashBox = await _trashVendasBox();
      final venda = trashBox.get(r.trashKey);
      await VendasService.removerContasReceberVinculadasAVenda(
        lojaId: r.lojaId,
        vendaKey: r.hiveKey >= 0 ? r.hiveKey : null,
        vendaIdFirebase: venda != null
            ? VendasService.idVendaEstavelParaVinculo(venda)
            : null,
      );
      if (venda != null) {
        final produtosBox =
            await Hive.openBox<Produto>(HiveBoxNames.produtos(r.lojaId));
        await VendasService.executarExclusaoPermanente(
          venda: venda,
          produtosBox: produtosBox,
          lojaId: r.lojaId,
          vendaHiveKeyOriginal: r.hiveKey,
          estoqueJaEstornadoNoSchedule: r.estoqueEstornado,
        );
      } else if (!r.estoqueEstornado) {
        debugPrint(
          '[SOFT-DELETE] permanente sem venda na lixeira; estorno já tratado? '
          'estoqueEstornado=${r.estoqueEstornado} idFb=${r.idFirebase}',
        );
      }
      if (trashBox.containsKey(r.trashKey)) {
        await trashBox.delete(r.trashKey);
      }

      // Notificação idempotente: flag local + doc Firestore estável / espelho.
      // Só marca enviada se o serviço confirmar gravação (evita engolir falha).
      if (!r.notificacaoEnviada) {
        final sellerUid = (r.vendedorUid ?? venda?.vendedorUid ?? '').trim();
        final email =
            (r.vendedorEmail ?? venda?.vendedorEmail ?? '').trim();
        final cliente =
            (r.clienteNome ?? venda?.clienteNome ?? 'Cliente').trim();
        final pedidoId = (r.idFirebase.isNotEmpty
                ? r.idFirebase
                : (venda?.idFirebase ?? r.id))
            .trim();
        final ok = await _tryNotificarExclusaoVenda(
          lojaId: r.lojaId,
          vendedorUid: sellerUid,
          vendedorEmail: email,
          pedidoId: pedidoId.isEmpty ? r.id : pedidoId,
          clienteNome: cliente.isEmpty ? 'Cliente' : cliente,
          motivo: r.motivoExclusao,
          adminUid: r.atorUid,
          pendingId: r.id,
        );
        if (ok) {
          final idx = _pending.indexWhere((p) => p.id == r.id);
          if (idx >= 0) {
            _pending[idx] = r.copyWith(notificacaoEnviada: true);
            await _save();
          }
        }
      } else {
        debugPrint(
          '[SOFT-DELETE] skip notificação já enviada pendingId=${r.id}',
        );
        debugPrint(
          '[M39-NOTIFICACAO] stage=skip_already pendingId=${r.id}',
        );
      }
      logD('🗑️ [SOFT-DELETE] Venda ${r.idFirebase} excluída permanentemente (Firestore + local)');
    } else if (r.type == 'cliente') {
      final trashBox = await _trashClientesBox();
      final cliente = trashBox.get(r.trashKey);
      if (cliente != null && (cliente.idFirebase ?? '').isNotEmpty) {
        await ClientesFirestoreService.deleteCliente(cliente.idFirebase!, lojaId: r.lojaId);
      }
      await trashBox.delete(r.trashKey);
      logD('🗑️ [SOFT-DELETE] Cliente ${r.idFirebase} excluído permanentemente (Firestore + local)');
    }
  }

  /// Processa pendências ao iniciar o app (para itens que expiraram enquanto o app estava fechado).
  static Future<void> processOnStartup() async {
    await _ensureLoaded();
    await _processExpired();
    _startTimerIfNeeded();
  }

  /// Somente caminho de notificação — não altera estoque/estorno/tombstone.
  static Future<bool> _tryNotificarExclusaoVenda({
    required String lojaId,
    required String vendedorUid,
    required String vendedorEmail,
    required String pedidoId,
    required String clienteNome,
    String? motivo,
    String? adminUid,
    required String pendingId,
  }) async {
    final seller = vendedorUid.trim();
    if (seller.isEmpty) {
      debugPrint(
        '[M39-NOTIFICACAO] stage=skip_no_seller pendingId=$pendingId '
        'tenant=$lojaId vendaId=$pedidoId',
      );
      logW(
        '[SOFT-DELETE] notificação exclusão sem vendedorUid — skip '
        'pendingId=$pendingId',
      );
      return false;
    }
    try {
      final ok =
          await NotificacaoVendasService().notificarVendedorVendaCancelada(
        storeId: lojaId,
        vendedorUid: seller,
        vendedorEmail: vendedorEmail,
        pedidoId: pedidoId,
        clienteNome: clienteNome,
        motivo: motivo,
        tipoAcao: 'excluida',
        adminUid: adminUid,
      );
      debugPrint(
        '[M39-NOTIFICACAO] stage=soft_delete_result pendingId=$pendingId '
        'ok=$ok sellerUid=$seller',
      );
      return ok;
    } catch (e) {
      logW(
        '[SOFT-DELETE] notificação exclusão venda falhou (type=${e.runtimeType})',
      );
      debugPrint(
        '[M39-NOTIFICACAO] stage=soft_delete_error pendingId=$pendingId '
        'type=${e.runtimeType}',
      );
      return false;
    }
  }
}
