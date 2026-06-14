// Backfill idempotente: vendas fiadas remotas → contas_receber no Firestore.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/conta_receber_identity.dart';
import '../core/conta_receber_venda_vinculo.dart';
import '../core/hive_box_names.dart';
import '../core/safe_cast.dart';
import '../models/conta_receber.dart';
import '../models/venda.dart';
import 'conta_receber_firestore_service.dart';
import 'conta_receber_service.dart';

class ContaReceberBackfillResultado {
  final int criadas;
  final int jaExistiam;
  final int ignoradas;
  final int erros;

  const ContaReceberBackfillResultado({
    this.criadas = 0,
    this.jaExistiam = 0,
    this.ignoradas = 0,
    this.erros = 0,
  });
}

abstract final class ContaReceberVendaBackfillService {
  ContaReceberVendaBackfillService._();

  static bool _vendaPertenceALoja(Venda venda, String lojaId) {
    final loja = lojaId.trim();
    if (loja.isEmpty) return false;
    final vl = (venda.lojaId ?? '').trim();
    return vl == loja || vl.isEmpty;
  }

  static DateTime? _parseVencimentoFiado(Venda venda) {
    final match = RegExp(
      r'Vencimento:\s*(\d{2})/(\d{2})/(\d{4})',
      caseSensitive: false,
    ).firstMatch(venda.formasPagamento);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
    );
  }

  static bool vendaTemSaldoFiadoAberto(Venda venda) {
    if (!venda.formasPagamento.toLowerCase().contains('fiado')) return false;
    final pago = venda.pagamentoDinheiro + venda.pagamentoPix + venda.pagamentoCartao;
    final saldo = calcularSaldoFiadoVenda(
      total: venda.total,
      totalPagoAgora: pago,
    );
    return saldo > 0.01;
  }

  /// Monta contas esperadas quando o dispositivo só tem a venda (ex.: pull mobile).
  static List<ContaReceber> montarContasFromVendaFiada({
    required Venda venda,
    required String lojaId,
  }) {
    final loja = lojaId.trim();
    if (loja.isEmpty || !vendaTemSaldoFiadoAberto(venda)) return [];

    final vendaId = idVendaEstavelParaContaReceber(venda);
    if (vendaId.isEmpty) return [];

    final venc = _parseVencimentoFiado(venda) ??
        venda.data.add(const Duration(days: 30));
    final pago =
        venda.pagamentoDinheiro + venda.pagamentoPix + venda.pagamentoCartao;
    final saldo = calcularSaldoFiadoVenda(
      total: venda.total,
      totalPagoAgora: pago,
    );
    if (saldo <= 0.01) return [];

    final vk = hiveKeyOrNull(venda.key);
    final obs = venda.observacao.trim();

    return [
      ContaReceber(
        lojaId: loja,
        clienteNome: venda.clienteNome.trim().isEmpty
            ? 'Cliente'
            : venda.clienteNome.trim(),
        valor: saldo,
        valorOriginal: saldo,
        dataVencimento: venc,
        dataVenda: venda.data,
        vendaKey: vk != null && vk >= 0 ? vk : -1,
        vendaIdFirebase: vendaId,
        observacao: obs.isEmpty ? 'Venda fiada' : obs,
        parcelaNumero: 1,
        parcelaTotal: 1,
      ),
    ];
  }

  static List<ContaReceber> _contasLocaisVinculadas({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    required Venda venda,
  }) {
    final vk = hiveKeyOrNull(venda.key);
    final idV = idVendaEstavelParaContaReceber(venda);
    return contas
        .where(
          (c) => contaReceberVinculadaAVenda(
            conta: c,
            lojaId: lojaId,
            vendaKey: vk,
            vendaIdFirebase: idV,
          ),
        )
        .toList();
  }

  /// Republica contas locais já vinculadas à venda (retry pós-syncVenda).
  static Future<int> republicarContasVinculadasAVenda({
    required String lojaId,
    required Venda venda,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return 0;
    final crBox = await ContaReceberService.openBoxLoja(loja);
    final vinculadas = _contasLocaisVinculadas(
      contas: crBox.values,
      lojaId: loja,
      venda: venda,
    );
    var ok = 0;
    for (final c in vinculadas) {
      normalizarContaReceberId(c);
      final publicado = await ContaReceberFirestoreService.upsertContaReceber(
        c,
        lastWriteOrigin: 'republicar_pos_venda',
      );
      if (publicado) ok++;
    }
    return ok;
  }

  /// Cria docs remotos ausentes a partir de vendas fiadas (Hive local / pull vendas).
  static Future<ContaReceberBackfillResultado> backfillFromVendasFiadas(
    String lojaId,
  ) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return const ContaReceberBackfillResultado();

    var criadas = 0, existiam = 0, ignoradas = 0, erros = 0;

    try {
      Box<Venda> vendasBox;
      if (Hive.isBoxOpen(HiveBoxNames.vendas(loja))) {
        vendasBox = Hive.box<Venda>(HiveBoxNames.vendas(loja));
      } else {
        vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(loja));
      }

      final crBox = await ContaReceberService.openBoxLoja(loja);

      for (final venda in vendasBox.values) {
        try {
          if (!_vendaPertenceALoja(venda, loja)) {
            ignoradas++;
            continue;
          }
          if (!vendaTemSaldoFiadoAberto(venda)) {
            ignoradas++;
            continue;
          }
          final idV = idVendaEstavelParaContaReceber(venda);
          if (idV.isEmpty) {
            ignoradas++;
            continue;
          }

          final locais = _contasLocaisVinculadas(
            contas: crBox.values,
            lojaId: loja,
            venda: venda,
          );
          final candidatas = locais.isNotEmpty
              ? locais
              : montarContasFromVendaFiada(venda: venda, lojaId: loja);

          if (candidatas.isEmpty) {
            ignoradas++;
            continue;
          }

          for (final conta in candidatas) {
            normalizarContaReceberId(conta);
            final docId = resolveContaReceberDocId(conta);
            if (docId.isEmpty) {
              ignoradas++;
              continue;
            }

            final remoto = await ContaReceberFirestoreService.buscarContaReceberRemota(
              lojaId: loja,
              contaReceberId: docId,
            );
            if (remoto != null) {
              existiam++;
              continue;
            }

            final ok = await ContaReceberFirestoreService.upsertContaReceber(
              conta,
              lastWriteOrigin: 'backfill_venda_fiada',
            );
            if (ok) {
              criadas++;
            } else {
              erros++;
            }
          }
        } catch (e) {
          erros++;
          debugPrint('[CR-BACKFILL] venda (type=${e.runtimeType})');
        }
      }
    } catch (e) {
      debugPrint('[CR-BACKFILL] query (type=${e.runtimeType})');
      erros++;
    }

    if (criadas > 0) {
      debugPrint(
        '[CR-BACKFILL] loja=$loja criadas=$criadas existiam=$existiam '
        'ignoradas=$ignoradas erros=$erros',
      );
    }

    return ContaReceberBackfillResultado(
      criadas: criadas,
      jaExistiam: existiam,
      ignoradas: ignoradas,
      erros: erros,
    );
  }
}
