import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/produto.dart';
import 'bulk_promocao_service.dart';
import 'produto_desconto_pix.dart';
import 'produto_remote_sync_guard.dart';
import 'stock_catalog_backend_service.dart';

String _produtos(int n) => n == 1 ? '1 produto' : '$n produtos';

String _pct(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// One bulk editorial change: the exact partial patch sent per product and its local mirror.
/// Only editorial fields; stock, cost, price, categories and publication never travel here.
class BulkEditorialPlano {
  BulkEditorialPlano._({
    required this.prefixoOperacao,
    required this.patch,
    required this.aplicar,
    required this.descricao,
    required this.progresso,
    required this.tituloSucesso,
    required this.tituloFalha,
  });

  factory BulkEditorialPlano.descontoPix(double percentual) {
    if (!ProdutoDescontoPix.valido(percentual)) {
      throw ArgumentError.value(percentual, 'percentual', 'fora da regra do desconto no Pix');
    }
    final v = percentual.toDouble();
    return BulkEditorialPlano._(
      prefixoOperacao: 'pixset',
      patch: {'percentualDescontoPix': v},
      aplicar: (p) => p.percentualDescontoPix = v,
      descricao: 'Desconto no Pix de ${_pct(v)}%',
      progresso: 'Aplicando desconto no Pix…',
      tituloSucesso: 'Desconto no Pix aplicado',
      tituloFalha: 'Desconto no Pix',
    );
  }

  factory BulkEditorialPlano.dividirSemJuros(int maxParcelas) {
    if (maxParcelas < 1 || maxParcelas > 24) {
      throw ArgumentError.value(maxParcelas, 'maxParcelas');
    }
    return BulkEditorialPlano._(
      prefixoOperacao: 'parcel',
      patch: {'divideSemJuros': true, 'maxParcelasSemJuros': maxParcelas},
      aplicar: (p) => p
        ..divideSemJuros = true
        ..maxParcelasSemJuros = maxParcelas,
      descricao: 'Dividir sem juros em até ${maxParcelas}x',
      progresso: 'Aplicando dividir sem juros…',
      tituloSucesso: 'Dividir sem juros aplicado',
      tituloFalha: 'Dividir sem juros',
    );
  }

  /// Same fields the product form persists for an active promotion; an unset period is cleared.
  factory BulkEditorialPlano.ativarPromocao({
    double? percentual,
    double? valor,
    DateTime? inicio,
    DateTime? fim,
  }) {
    if ((percentual == null) == (valor == null) ||
        (percentual != null && !(percentual > 0 && percentual <= 100)) ||
        (valor != null && !(valor > 0 && valor.isFinite))) {
      throw ArgumentError('Informe só percentual (0–100] ou só valor (> 0)');
    }
    return BulkEditorialPlano._(
      prefixoOperacao: 'promoon',
      patch: {
        'emPromocao': true,
        'percentualPromo': percentual,
        'valorPromo': valor,
        'dataInicioPromo': inicio?.toIso8601String(),
        'dataFimPromo': fim?.toIso8601String(),
      },
      aplicar: (p) => p
        ..emPromocao = true
        ..percentualPromo = percentual
        ..valorPromo = valor
        ..dataInicioPromo = inicio
        ..dataFimPromo = fim,
      descricao: percentual != null
          ? 'Promoção de ${_pct(percentual)}%'
          : 'Promoção de R\$ ${valor!.toStringAsFixed(2)}',
      progresso: 'Aplicando promoção…',
      tituloSucesso: 'Promoção aplicada',
      tituloFalha: 'Promoção',
    );
  }

  /// Distinguishes operation ids per action so two actions never share an id.
  final String prefixoOperacao;
  final Map<String, dynamic> patch;
  final void Function(Produto p) aplicar;
  final String descricao;
  final String progresso;
  final String tituloSucesso;
  final String tituloFalha;
}

class BulkEditorialCandidato {
  const BulkEditorialCandidato({
    required this.hiveKey,
    required this.docId,
    required this.nome,
    required this.lojaId,
  });

  factory BulkEditorialCandidato.fromProduto(int hiveKey, Produto p) {
    final id = p.idFirebase.trim();
    return BulkEditorialCandidato(
      hiveKey: hiveKey,
      docId: id.isNotEmpty ? id : p.slug.trim(),
      nome: p.nome,
      lojaId: p.lojaId.trim(),
    );
  }

  final int hiveKey;

  /// Same document id used for `estoque_produtos`; empty when never synced.
  final String docId;
  final String nome;
  final String lojaId;
}

class BulkEditorialFalha {
  const BulkEditorialFalha({
    required this.docId,
    required this.mensagem,
    required this.podeTentarDeNovo,
  });

  final String docId;
  final String mensagem;
  final bool podeTentarDeNovo;
}

/// Outcome confirmed by the server; nothing here is inferred from the local save.
class BulkEditorialResultado {
  BulkEditorialResultado({
    required this.plano,
    required this.totalSelecionados,
    required this.confirmados,
    required this.ignorados,
    required this.falhas,
  });

  final BulkEditorialPlano plano;
  final int totalSelecionados;
  final Set<String> confirmados;

  /// Selected products never synced to the cloud (no document to update).
  final int ignorados;
  final List<BulkEditorialFalha> falhas;

  bool get sucessoTotal => falhas.isEmpty && confirmados.isNotEmpty;

  List<String> get idsParaNovaTentativa =>
      (falhas.where((f) => f.podeTentarDeNovo).map((f) => f.docId).toSet().toList())..sort();

  String get titulo => sucessoTotal
      ? plano.tituloSucesso
      : confirmados.isEmpty
          ? '${plano.tituloFalha}: nada foi aplicado'
          : '${plano.tituloFalha}: aplicado em parte';

  List<String> get linhas => [
        '${plano.descricao}.',
        confirmados.length == 1
            ? '1 produto atualizado'
            : '${confirmados.length} produtos atualizados',
        if (falhas.isNotEmpty) falhas.length == 1 ? '1 falhou' : '${falhas.length} falharam',
        if (ignorados > 0)
          '${_produtos(ignorados)} ainda não '
              '${ignorados == 1 ? 'foi sincronizado' : 'foram sincronizados'} com a nuvem '
              'e ${ignorados == 1 ? 'ficou' : 'ficaram'} de fora',
      ];

  String get mensagemSucesso =>
      '${plano.descricao} aplicado em ${_produtos(confirmados.length)}.';
}

/// Bulk editorial changes through `stockCatalogCommand kind=editorial`, one product per command
/// (server rule), with the same partial patch for every product. Editorial only: stock mutations
/// must never go through here.
class BulkEditorialService {
  BulkEditorialService._();

  static String novoBulkId() => 'edbulk_${const Uuid().v4()}';

  /// Same store + bulk + product => same id, so a retried product replays on the server
  /// instead of applying twice.
  static String operationId({
    required BulkEditorialPlano plano,
    required String lojaId,
    required String bulkId,
    required String docId,
  }) {
    final digest = sha256.convert(utf8.encode('$lojaId|$bulkId|$docId'));
    return '${plano.prefixoOperacao}_$digest';
  }

  /// Fail-closed tenant check (same rule as the bulk promotion deactivation).
  static String? validarLoja({
    required String lojaIdAtual,
    required String lojaIdTela,
    required String nomeBox,
    required Iterable<BulkEditorialCandidato> candidatos,
  }) =>
      BulkPromocaoService.validarLoja(
        lojaIdAtual: lojaIdAtual,
        lojaIdTela: lojaIdTela,
        nomeBox: nomeBox,
        candidatos: [
          for (final c in candidatos)
            BulkPromoCandidato(
              hiveKey: c.hiveKey,
              docId: c.docId,
              nome: c.nome,
              lojaId: c.lojaId,
              emPromocao: false,
            ),
        ],
      );

  /// Sequential, a failure never stops the others. [somenteDocIds] restricts a retry.
  static Future<BulkEditorialResultado> executar({
    required BulkEditorialPlano plano,
    required String lojaId,
    required String bulkId,
    required List<BulkEditorialCandidato> candidatos,
    Iterable<String>? somenteDocIds,
    void Function(int processados, int total)? onProgresso,
  }) async {
    final nomes = <String, String>{};
    var ignorados = 0;
    for (final c in candidatos) {
      if (c.docId.isEmpty) {
        ignorados++;
      } else {
        nomes.putIfAbsent(c.docId, () => c.nome);
      }
    }
    final filtro = somenteDocIds?.toSet();
    final ids = nomes.keys.where((id) => filtro == null || filtro.contains(id)).toList()..sort();
    final confirmados = <String>{};
    final falhas = <BulkEditorialFalha>[];
    onProgresso?.call(0, ids.length);
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      try {
        await StockCatalogBackendService.command(
          lojaId: lojaId,
          operationId: operationId(plano: plano, lojaId: lojaId, bulkId: bulkId, docId: id),
          kind: 'editorial',
          items: [
            {'productId': id}
          ],
          editorial: plano.patch,
        );
        confirmados.add(id);
      } catch (error) {
        falhas.add(BulkEditorialFalha(
          docId: id,
          mensagem: mensagemErro(error, nome: nomes[id] ?? id),
          podeTentarDeNovo: BulkPromocaoService.podeTentarDeNovo(error),
        ));
      }
      onProgresso?.call(i + 1, ids.length);
    }
    return BulkEditorialResultado(
      plano: plano,
      totalSelecionados: filtro == null ? candidatos.length : ids.length,
      confirmados: confirmados,
      ignorados: filtro == null ? ignorados : 0,
      falhas: falhas,
    );
  }

  static String mensagemErro(Object error, {required String nome}) {
    final nada = '"$nome" não foi alterado.';
    if (error is StockCatalogProductValidationException) {
      return '"$nome" tem dados que precisam ser revisados no cadastro. $nada';
    }
    if (error is! FirebaseFunctionsException) {
      return 'Não foi possível atualizar "$nome": não confirmado. Tentar novamente é seguro.';
    }
    final msg = error.message ?? '';
    if (error.code == 'failed-precondition' && msg.contains('tombstone')) {
      return '"$nome" foi excluído. $nada';
    }
    if (error.code == 'failed-precondition' && msg.startsWith('Canonical product')) {
      return '"$nome" não foi encontrado na nuvem. $nada';
    }
    final d = error.details;
    if (d is Map && '${d['code'] ?? ''}' == 'OPERATION_PAYLOAD_CONFLICT') {
      return 'Esta operação já foi registrada com outros dados. $nada';
    }
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return 'Você não tem permissão para alterar produtos desta loja. $nada';
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
        return 'Falha de conexão ao atualizar "$nome": não confirmado. Tentar novamente é seguro.';
      case 'failed-precondition':
        return 'Esta loja não permite alterar "$nome" no momento. $nada';
    }
    return 'Não foi possível atualizar "$nome". $nada';
  }

  /// Mirrors only server-confirmed products in Hive without triggering the full-document auto-sync push.
  static Future<int> aplicarNoHive({
    required Box<Produto> box,
    required BulkEditorialPlano plano,
    required List<BulkEditorialCandidato> candidatos,
    required Iterable<String> docIdsConfirmados,
  }) async {
    final confirmados = docIdsConfirmados.toSet();
    var n = 0;
    ProdutoRemoteSyncGuard.applyingRemoteToHive = true;
    try {
      for (final c in candidatos) {
        if (!confirmados.contains(c.docId)) continue;
        final p = box.get(c.hiveKey);
        if (p == null) continue;
        plano.aplicar(p);
        await p.save();
        n++;
      }
    } finally {
      ProdutoRemoteSyncGuard.applyingRemoteToHive = false;
    }
    return n;
  }
}
