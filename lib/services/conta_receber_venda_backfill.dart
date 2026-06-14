// Backfill idempotente: vendas com saldo a receber → contas_receber no Firestore.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/conta_receber_identity.dart';
import '../core/conta_receber_venda_vinculo.dart';
import '../core/hive_box_names.dart';
import '../models/conta_receber.dart';
import '../models/venda.dart';
import 'conta_receber_firestore_service.dart';
import 'conta_receber_service.dart';
import 'firestore_paths.dart';

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

  static FirebaseFirestore _firestoreDb() {
    // Mesmo Firestore dos upserts (incl. fake em testes via override interno).
    // ignore: invalid_use_of_visible_for_testing_member
    return ContaReceberFirestoreService.debugFirestoreOverride ??
        FirebaseFirestore.instance;
  }

  static Future<FiadoVendaMetadata?> _buscarMetadadosFiadoVendaRemota({
    required String lojaId,
    required String vendaIdFirebase,
  }) async {
    final loja = lojaId.trim();
    final idV = vendaIdFirebase.trim();
    if (loja.isEmpty || idV.isEmpty) return null;
    try {
      final db = _firestoreDb();
      final snap = await db
          .collection('lojas')
          .doc(loja)
          .collection(FSPaths.estoqueVendasCol)
          .doc(idV)
          .get();
      if (!snap.exists || snap.data() == null) return null;
      final data = Map<String, dynamic>.from(snap.data()!);
      final vencRaw = data['dataVencimentoFiado'];
      if (vencRaw is Timestamp) {
        data['dataVencimentoFiado'] = vencRaw.toDate().toIso8601String();
      }
      return parseFiadoMetadataFromFirestoreMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Monta contas esperadas quando o dispositivo só tem a venda (ex.: pull mobile).
  static Future<List<ContaReceber>> montarContasFromVendaFiada({
    required Venda venda,
    required String lojaId,
  }) async {
    final vendaId = idVendaEstavelParaContaReceber(venda);
    FiadoVendaMetadata? metaRemota;
    if (vendaId.isNotEmpty) {
      metaRemota = await _buscarMetadadosFiadoVendaRemota(
        lojaId: lojaId,
        vendaIdFirebase: vendaId,
      );
    }
    return montarContasReceberFromVenda(
      venda: venda,
      lojaId: lojaId,
      metaRemota: metaRemota,
    );
  }

  static List<ContaReceber> _contasLocaisVinculadas({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    required Venda venda,
  }) {
    final vk = vendaHiveKeyOrNull(venda);
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

  /// Cria docs remotos ausentes a partir de vendas com saldo a receber.
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
          if (!vendaPossuiSaldoAReceber(venda)) {
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
              : await montarContasFromVendaFiada(venda: venda, lojaId: loja);

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
