// Sync Hive ↔ Firestore para contas a receber / fiado.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/conta_receber_dedup.dart';
import '../core/conta_receber_identity.dart';
import '../core/conta_receber_lancamento_vinculo.dart';
import '../models/conta_receber.dart';
import 'conta_receber_service.dart';
import 'firestore_paths.dart';

class ContaReceberPullResultado {
  final int importados;
  final int atualizados;
  final int pulados;
  final int erros;
  final bool ignoradoJaEmExecucao;

  const ContaReceberPullResultado({
    this.importados = 0,
    this.atualizados = 0,
    this.pulados = 0,
    this.erros = 0,
    this.ignoradoJaEmExecucao = false,
  });
}

class ContaReceberMigracaoResultado {
  final int enviados;
  final int pulados;
  final int erros;

  const ContaReceberMigracaoResultado({
    this.enviados = 0,
    this.pulados = 0,
    this.erros = 0,
  });
}

class ContaReceberBaixaRemotaResultado {
  final bool sucesso;
  final bool idempotente;
  final String? mensagemErro;

  const ContaReceberBaixaRemotaResultado({
    required this.sucesso,
    this.idempotente = false,
    this.mensagemErro,
  });
}

abstract final class ContaReceberFirestoreService {
  ContaReceberFirestoreService._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  static bool _pullEmExecucao = false;

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _ref(String lojaId, String id) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(id);
  }

  static String chaveRegistroPull(String lojaId) =>
      'conta_receber_pull_${lojaId.trim()}';

  static String chaveRemoteUpdatedAt(String lojaId, String docId) =>
      'cr_fs_uat_${lojaId.trim()}_${docId.trim()}';

  static DateTime? _fsDateTime(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static double _fsDouble(dynamic v, [double fallback = 0]) {
    if (v is num) return v.toDouble();
    return fallback;
  }

  static int _fsInt(dynamic v, [int fallback = 0]) {
    if (v is num) return v.toInt();
    return fallback;
  }

  static bool _fsBool(dynamic v, [bool fallback = false]) {
    if (v is bool) return v;
    return fallback;
  }

  static String _fsString(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    return v.toString();
  }

  static List<Map<String, dynamic>> _parseHistorico(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static String _jsonValue(dynamic v) {
    if (v is num) return v.toString();
    if (v is bool) return v ? 'true' : 'false';
    return '"${v.toString().replaceAll('"', r'\"')}"';
  }

  static String historicoPagamentosJsonFromFirestore(dynamic raw) {
    final hist = _parseHistorico(raw);
    if (hist.isEmpty) return '[]';
    final buf = StringBuffer('[');
    for (var i = 0; i < hist.length; i++) {
      if (i > 0) buf.write(',');
      buf.write('{');
      var first = true;
      hist[i].forEach((k, val) {
        if (!first) buf.write(',');
        first = false;
        buf.write('"');
        buf.write(k.replaceAll('"', r'\"'));
        buf.write('":');
        buf.write(_jsonValue(val));
      });
      buf.write('}');
    }
    buf.write(']');
    return buf.toString();
  }

  static Map<String, dynamic> mapContaReceber(
    ContaReceber c, {
    required String docId,
    String lastWriteOrigin = 'app',
    bool cancelada = false,
    DateTime? deletedAt,
  }) {
    final loja = c.lojaId.trim();
    return {
      'lojaId': loja,
      'contaReceberId': docId,
      'vendaIdFirebase': c.vendaIdFirebase.trim(),
      'vendaKey': c.vendaKey,
      'clienteId': '',
      'clienteNome': c.clienteNome.trim(),
      'valorOriginal': c.valorOriginal,
      'valorPago': c.valorPago,
      'saldoAtual': c.saldoRestante,
      'valor': c.saldoRestante,
      'status': c.status,
      'pago': c.pago,
      'parcelaNumero': c.parcelaNumero,
      'parcelaTotal': c.parcelaTotal,
      'dataVencimento': Timestamp.fromDate(c.dataVencimento),
      'dataVenda': Timestamp.fromDate(c.dataVenda),
      'observacao': c.observacao,
      'historicoPagamentos': c.historicoPagamentos(),
      'lembrete2DiasEnviado': c.lembrete2DiasEnviado,
      'cancelada': cancelada,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt) : null,
      'schemaVersion': kContaReceberSchemaVersion,
      'lastWriteOrigin': lastWriteOrigin,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static ContaReceber? contaFromFirestore(
    String docId,
    Map<String, dynamic> data,
    String lojaIdEsperada,
  ) {
    try {
      final lojaDoc = _fsString(data['lojaId']).trim();
      if (lojaDoc.isNotEmpty && lojaDoc != lojaIdEsperada) return null;
      if (_fsBool(data['cancelada']) || data['deletedAt'] != null) return null;

      final venc = _fsDateTime(data['dataVencimento']);
      final venda = _fsDateTime(data['dataVenda']);
      if (venc == null || venda == null) return null;

      final saldo = _fsDouble(data['saldoAtual'], _fsDouble(data['valor']));
      final valorOriginal = _fsDouble(data['valorOriginal'], saldo);
      final valorPago = _fsDouble(data['valorPago']);

      return ContaReceber(
        lojaId: lojaIdEsperada,
        clienteNome: _fsString(data['clienteNome']),
        valor: saldo,
        valorOriginal: valorOriginal,
        valorPago: valorPago,
        dataVencimento: venc,
        dataVenda: venda,
        pago: _fsBool(data['pago']),
        observacao: _fsString(data['observacao']),
        vendaKey: _fsInt(data['vendaKey']),
        idFirebase: docId,
        parcelaNumero: _fsInt(data['parcelaNumero'], 1),
        parcelaTotal: _fsInt(data['parcelaTotal'], 1),
        lembrete2DiasEnviado: _fsBool(data['lembrete2DiasEnviado']),
        status: _fsString(data['status'], ContaReceberStatus.pendente),
        historicoPagamentosJson: historicoPagamentosJsonFromFirestore(
          data['historicoPagamentos'],
        ),
        vendaIdFirebase: _fsString(data['vendaIdFirebase']),
      );
    } catch (e) {
      debugPrint(
        '[CR-FS] Parse remoto $docId (type=${e.runtimeType})',
      );
      return null;
    }
  }

  static Future<int?> _remoteUpdatedAtMs(String lojaId, String docId) async {
    try {
      final box = Hive.isBoxOpen('config')
          ? Hive.box('config')
          : await Hive.openBox('config');
      final v = box.get(chaveRemoteUpdatedAt(lojaId, docId));
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _salvarRemoteUpdatedAtMs(
    String lojaId,
    String docId,
    int ms,
  ) async {
    try {
      final box = Hive.isBoxOpen('config')
          ? Hive.box('config')
          : await Hive.openBox('config');
      await box.put(chaveRemoteUpdatedAt(lojaId, docId), ms);
    } catch (_) {}
  }

  static int? _updatedAtMsFromDoc(Map<String, dynamic> data) {
    final u = _fsDateTime(data['updatedAt']);
    return u?.millisecondsSinceEpoch;
  }

  static ContaReceber? _findLocalByDocOrStable(
    Box<ContaReceber> box,
    String lojaId,
    String docId,
    Map<String, dynamic> data,
  ) {
    for (final c in box.values) {
      if (!ContaReceberService.contaPertenceALoja(c, lojaId)) continue;
      if ((c.idFirebase ?? '').trim() == docId) return c;
    }
    final vendaId = _fsString(data['vendaIdFirebase']).trim();
    final parcela = _fsInt(data['parcelaNumero'], 1);
    if (vendaId.isNotEmpty) {
      final stable = '${vendaId}_p${parcela.clamp(1, 999)}';
      for (final c in box.values) {
        if (!ContaReceberService.contaPertenceALoja(c, lojaId)) continue;
        if (contaReceberStableId(c) == stable) return c;
      }
    }
    final remotoParse = contaFromFirestore(docId, data, lojaId);
    if (remotoParse != null) {
      final chaveRemota = contaReceberChaveSemantica(remotoParse);
      if (chaveRemota.isNotEmpty) {
        for (final c in box.values) {
          if (!ContaReceberService.contaPertenceALoja(c, lojaId)) continue;
          if (contaReceberChaveSemantica(c) == chaveRemota) return c;
        }
      }
    }
    for (final c in box.values) {
      if (!ContaReceberService.contaPertenceALoja(c, lojaId)) continue;
      if (resolveContaReceberDocId(c) == docId) return c;
    }
    return null;
  }

  static Future<void> _applyRemoteToLocal({
    required Box<ContaReceber> box,
    required ContaReceber remoto,
    ContaReceber? local,
  }) async {
    if (local != null) {
      local
        ..lojaId = remoto.lojaId
        ..clienteNome = remoto.clienteNome
        ..valor = remoto.valor
        ..valorOriginal = remoto.valorOriginal
        ..valorPago = remoto.valorPago
        ..dataVencimento = remoto.dataVencimento
        ..dataVenda = remoto.dataVenda
        ..pago = remoto.pago
        ..observacao = remoto.observacao
        ..vendaKey = remoto.vendaKey
        ..idFirebase = remoto.idFirebase
        ..parcelaNumero = remoto.parcelaNumero
        ..parcelaTotal = remoto.parcelaTotal
        ..lembrete2DiasEnviado = remoto.lembrete2DiasEnviado
        ..status = remoto.status
        ..historicoPagamentosJson = remoto.historicoPagamentosJson
        ..vendaIdFirebase = remoto.vendaIdFirebase;
      local.normalizarCamposFinanceiros();
      await local.save();
      return;
    }
    remoto.garantirDocIdFirestore(remoto.idFirebase ?? '');
    await box.add(remoto);
    await remoto.save();
  }

  /// Pull Firestore → Hive com merge por `updatedAt` (remoto mais novo vence).
  static Future<ContaReceberPullResultado> pullContasReceberRemotas(
    String lojaId, {
    bool forcarMesmoSemTimestamp = false,
  }) =>
      pullLojaFirestoreParaHive(lojaId, forcarMesmoSemTimestamp: forcarMesmoSemTimestamp);

  static Future<ContaReceberPullResultado> pullLojaFirestoreParaHive(
    String lojaId, {
    bool forcarMesmoSemTimestamp = false,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return const ContaReceberPullResultado();
    if (_pullEmExecucao) {
      return const ContaReceberPullResultado(ignoradoJaEmExecucao: true);
    }
    _pullEmExecucao = true;

    var imp = 0, att = 0, pul = 0, err = 0;

    try {
      final box = await ContaReceberService.openBoxLoja(loja);
      final qs = await _db
          .collection('lojas')
          .doc(loja)
          .collection(FSPaths.contasReceberCol)
          .get();

      for (final doc in qs.docs) {
        try {
          final data = doc.data();
          if (_fsString(data['lojaId']).trim().isNotEmpty &&
              _fsString(data['lojaId']).trim() != loja) {
            pul++;
            continue;
          }
          if (_fsBool(data['cancelada']) || data['deletedAt'] != null) {
            pul++;
            continue;
          }
          final remoto = contaFromFirestore(doc.id, data, loja);
          if (remoto == null) {
            err++;
            continue;
          }

          final remoteMs = _updatedAtMsFromDoc(data);
          final localKnownMs = await _remoteUpdatedAtMs(loja, doc.id);
          final local = _findLocalByDocOrStable(box, loja, doc.id, data);

          final remotoTemBaixaMaisRecente = local != null &&
              _fsDouble(data['valorPago']) > local.valorPago + 0.01;
          final remotoSaldoMenor = local != null &&
              _fsDouble(data['saldoAtual'], _fsDouble(data['valor'])) <
                  local.saldoRestante - 0.01;

          if (local != null &&
              remoteMs != null &&
              localKnownMs != null &&
              remoteMs <= localKnownMs &&
              !forcarMesmoSemTimestamp &&
              !remotoTemBaixaMaisRecente &&
              !remotoSaldoMenor) {
            pul++;
            continue;
          }

          await _applyRemoteToLocal(box: box, remoto: remoto, local: local);
          if (remoteMs != null) {
            await _salvarRemoteUpdatedAtMs(loja, doc.id, remoteMs);
          }
          if (local == null) {
            imp++;
          } else {
            att++;
          }
        } catch (e) {
          err++;
          debugPrint('[CR-FS] Pull doc ${doc.id} (type=${e.runtimeType})');
        }
      }
    } catch (e) {
      debugPrint('[CR-FS] Pull query (type=${e.runtimeType})');
    } finally {
      _pullEmExecucao = false;
    }

    return ContaReceberPullResultado(
      importados: imp,
      atualizados: att,
      pulados: pul,
      erros: err,
    );
  }

  /// Hive → Firestore (Política A): só cria se doc remoto não existir.
  static Future<ContaReceberMigracaoResultado> publicarContasHivePendentes(
    String lojaId,
  ) =>
      migrarLojaHiveParaFirestorePolicyA(lojaId);

  static Future<ContaReceberMigracaoResultado> migrarLojaHiveParaFirestorePolicyA(
    String lojaId,
  ) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return const ContaReceberMigracaoResultado();

    var env = 0, pul = 0, err = 0;
    try {
      final box = await ContaReceberService.openBoxLoja(loja);
      final chavesRemotasFraca = <String>{};
      try {
        final qs = await _db
            .collection('lojas')
            .doc(loja)
            .collection(FSPaths.contasReceberCol)
            .get();
        for (final doc in qs.docs) {
          final data = doc.data();
          if (_fsBool(data['cancelada']) || data['deletedAt'] != null) continue;
          final parsed = contaFromFirestore(doc.id, data, loja);
          if (parsed == null) continue;
          final fraca = contaReceberChaveFraca(parsed);
          if (fraca.isNotEmpty) chavesRemotasFraca.add(fraca);
        }
      } catch (_) {}

      for (final c in box.values) {
        if (!ContaReceberService.contaPertenceALoja(c, loja)) continue;
        if (!contaReceberElegivelParaPublicarHive(c)) {
          if (contaReceberInativaParaSync(c)) {
            debugPrint(
              '[CR-SYNC][PUBLICAR-SKIP-INATIVA] id=${resolveContaReceberDocId(c)}',
            );
          }
          pul++;
          continue;
        }
        normalizarContaReceberId(c);
        final docId = resolveContaReceberDocId(c);
        if (docId.isEmpty) {
          pul++;
          continue;
        }
        final fracaLocal = contaReceberChaveFraca(c);
        if (fracaLocal.isNotEmpty && chavesRemotasFraca.contains(fracaLocal)) {
          debugPrint(
            '[CR-SYNC][PUBLICAR-SKIP-REMOTO] chave=$fracaLocal id=$docId',
          );
          pul++;
          continue;
        }
        try {
          final ref = _ref(loja, docId);
          final snap = await ref.get();
          if (snap.exists) {
            c.garantirDocIdFirestore(docId);
            if (c.isInBox) {
              try {
                await c.save();
              } catch (_) {}
            }
            pul++;
            continue;
          }
          final data = mapContaReceber(c, docId: docId, lastWriteOrigin: 'migr_hive');
          data['createdAt'] = FieldValue.serverTimestamp();
          await ref.set(data, SetOptions(merge: true));
          c.garantirDocIdFirestore(docId);
          if (c.isInBox) {
            try {
              await c.save();
            } catch (_) {}
          }
          if (fracaLocal.isNotEmpty) chavesRemotasFraca.add(fracaLocal);
          env++;
        } catch (e) {
          err++;
          debugPrint('[CR-FS] Migr doc $docId (type=${e.runtimeType})');
        }
      }
    } catch (e) {
      debugPrint('[CR-FS] Migr query (type=${e.runtimeType})');
    }
    return ContaReceberMigracaoResultado(
      enviados: env,
      pulados: pul,
      erros: err,
    );
  }

  static Future<bool> upsertContaReceber(
    ContaReceber conta, {
    String lastWriteOrigin = 'app',
    int maxTentativas = 3,
  }) async {
    final loja = conta.lojaId.trim();
    if (loja.isEmpty) {
      debugPrint('[CR-FS][UPSERT-ERRO] lojaId vazio origem=$lastWriteOrigin');
      return false;
    }
    normalizarContaReceberId(conta);
    final docId = resolveContaReceberDocId(conta);
    if (docId.isEmpty) {
      debugPrint(
        '[CR-FS][UPSERT-ERRO] docId vazio lojaId=$loja origem=$lastWriteOrigin',
      );
      return false;
    }
    debugPrint(
      '[CR-FS][UPSERT-INICIO] path=lojas/$loja/contas_receber/$docId '
      'origem=$lastWriteOrigin',
    );

    Object? ultimoErro;
    for (var tentativa = 1; tentativa <= maxTentativas; tentativa++) {
      try {
        final data = mapContaReceber(
          conta,
          docId: docId,
          lastWriteOrigin: lastWriteOrigin,
        );
        await _ref(loja, docId).set(data, SetOptions(merge: true));
        conta.garantirDocIdFirestore(docId);
        if (conta.isInBox) {
          try {
            await conta.save();
          } catch (_) {}
        }
        debugPrint(
          '[CR-FS][UPSERT-OK] id=$docId origem=$lastWriteOrigin '
          'tentativa=$tentativa',
        );
        return true;
      } on FirebaseException catch (e) {
        ultimoErro = e;
        debugPrint(
          '[CR-FS][UPSERT-ERRO] id=$docId code=${e.code} message=${e.message} '
          'tentativa=$tentativa/$maxTentativas',
        );
      } catch (e) {
        ultimoErro = e;
        debugPrint(
          '[CR-FS][UPSERT-ERRO] id=$docId type=${e.runtimeType} message=$e '
          'tentativa=$tentativa/$maxTentativas',
        );
      }
      if (tentativa < maxTentativas) {
        await Future<void>.delayed(Duration(milliseconds: 350 * tentativa));
      }
    }
    debugPrint(
      '[CR-FS][UPSERT-ERRO] id=$docId falha_final origem=$lastWriteOrigin '
      'erro=$ultimoErro',
    );
    return false;
  }

  /// Garante cache Hive quando o doc já existe no Firestore (backfill/pull).
  static Future<bool> importarContaRemotaParaHive({
    required String lojaId,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    final loja = lojaId.trim();
    final id = docId.trim();
    if (loja.isEmpty || id.isEmpty) return false;
    if (_fsBool(data['cancelada']) || data['deletedAt'] != null) return false;

    final remoto = contaFromFirestore(id, data, loja);
    if (remoto == null) return false;

    try {
      final box = await ContaReceberService.openBoxLoja(loja);
      final local = _findLocalByDocOrStable(box, loja, id, data);
      if (local != null) {
        await _applyRemoteToLocal(box: box, remoto: remoto, local: local);
        debugPrint('[CR-PULL][MERGE] remoteId=$id localId=${local.idFirebase}');
        return true;
      }
      if (hiveJaTemContaSemantica(
        contas: box.values,
        lojaId: loja,
        candidata: remoto,
      )) {
        return false;
      }
      await _applyRemoteToLocal(box: box, remoto: remoto, local: null);
      debugPrint('[CR-PULL][MERGE] remoteId=$id localId=novo');
      return true;
    } catch (e) {
      debugPrint(
        '[CR-FS] importarContaRemota $id (type=${e.runtimeType})',
      );
      return false;
    }
  }

  static Future<bool> publicarContaSeRemotoAusente(ContaReceber conta) async {
    final loja = conta.lojaId.trim();
    if (loja.isEmpty) return false;
    final docId = resolveContaReceberDocId(conta);
    try {
      final ref = _ref(loja, docId);
      if ((await ref.get()).exists) {
        conta.garantirDocIdFirestore(docId);
        if (conta.isInBox) {
          try {
            await conta.save();
          } catch (_) {}
        }
        return true;
      }
      return upsertContaReceber(conta, lastWriteOrigin: 'publish_local');
    } catch (e) {
      debugPrint('[CR-FS] publicarConta (type=${e.runtimeType})');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> buscarContaReceberRemota({
    required String lojaId,
    required String contaReceberId,
  }) async {
    final loja = lojaId.trim();
    final id = contaReceberId.trim();
    if (loja.isEmpty || id.isEmpty) return null;
    try {
      final snap = await _ref(loja, id).get();
      if (!snap.exists) return null;
      return snap.data();
    } catch (e) {
      debugPrint('[CR-FS] buscar $id (type=${e.runtimeType})');
      return null;
    }
  }

  /// Baixa idempotente no Firestore (histórico com `baixaId`).
  static Future<ContaReceberBaixaRemotaResultado> baixarContaTransacional({
    required ContaReceber conta,
    required String lojaId,
    required double valorRecebido,
    required String formaPagamento,
    required DateTime dataRecebimento,
    String? referenciaFinanceira,
  }) =>
      registrarBaixaRemota(
        conta: conta,
        lojaId: lojaId,
        valorRecebido: valorRecebido,
        formaPagamento: formaPagamento,
        dataRecebimento: dataRecebimento,
        referenciaFinanceira: referenciaFinanceira,
      );

  static Future<ContaReceberBaixaRemotaResultado> registrarBaixaRemota({
    required ContaReceber conta,
    required String lojaId,
    required double valorRecebido,
    required String formaPagamento,
    required DateTime dataRecebimento,
    String? referenciaFinanceira,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) {
      return const ContaReceberBaixaRemotaResultado(
        sucesso: false,
        mensagemErro: 'Loja inválida.',
      );
    }

    final docId = resolveContaReceberDocId(conta);
    final baixaId = baixaIdDeterministico(
      contaReceberId: docId,
      valor: valorRecebido,
      dataRecebimento: dataRecebimento,
      formaPagamento: formaPagamento,
    );

    try {
      final ref = _ref(loja, docId);
      final result = await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw StateError('Conta remota não encontrada.');
        }
        final data = Map<String, dynamic>.from(snap.data() ?? {});
        final hist = _parseHistorico(data['historicoPagamentos']);
        for (final h in hist) {
          if (_fsString(h['baixaId']) == baixaId && !_fsBool(h['estornada'])) {
            return 'idempotente';
          }
        }

        final saldo = _fsDouble(data['saldoAtual'], _fsDouble(data['valor']));
        if (valorRecebido > saldo + 0.01) {
          throw StateError('Valor maior que saldo remoto.');
        }

        final novoSaldo = (saldo - valorRecebido).clamp(0.0, double.infinity);
        final valorPago = _fsDouble(data['valorPago']) + valorRecebido;
        final entry = <String, dynamic>{
          'baixaId': baixaId,
          'valor': valorRecebido,
          'data': dataRecebimento.toIso8601String(),
          'forma': formaPagamento.trim(),
          'estornada': false,
        };
        final refFin = referenciaFinanceira?.trim();
        if (refFin != null && refFin.isNotEmpty) {
          entry['referenciaFinanceira'] = refFin;
        }
        hist.add(entry);

        String status = ContaReceberStatus.pendente;
        var pago = false;
        if (novoSaldo < 0.01) {
          status = ContaReceberStatus.paga;
          pago = true;
        } else if (valorPago > 0.01) {
          status = ContaReceberStatus.parcial;
        }

        tx.set(
          ref,
          {
            ...data,
            'historicoPagamentos': hist,
            'valorPago': valorPago,
            'saldoAtual': novoSaldo,
            'valor': novoSaldo,
            'status': status,
            'pago': pago,
            'lastWriteOrigin': 'baixa',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return 'ok';
      });

      conta.garantirDocIdFirestore(docId);
      if (result == 'idempotente') {
        return const ContaReceberBaixaRemotaResultado(
          sucesso: true,
          idempotente: true,
        );
      }
      return const ContaReceberBaixaRemotaResultado(sucesso: true);
    } on StateError catch (e) {
      return ContaReceberBaixaRemotaResultado(
        sucesso: false,
        mensagemErro: e.message,
      );
    } catch (e) {
      debugPrint('[CR-FS] Baixa remota (type=${e.runtimeType})');
      return ContaReceberBaixaRemotaResultado(
        sucesso: false,
        mensagemErro: 'Não foi possível sincronizar a baixa com o servidor.',
      );
    }
  }

  /// Estorna baixa no Firestore (marca `estornada`, reabre saldo).
  static Future<bool> estornarBaixaRemota({
    required String lojaId,
    required String contaReceberDocId,
    required String baixaId,
  }) async {
    final loja = lojaId.trim();
    final docId = contaReceberDocId.trim();
    final bx = baixaId.trim();
    if (loja.isEmpty || docId.isEmpty || bx.isEmpty) return false;

    try {
      final ref = _ref(loja, docId);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final data = Map<String, dynamic>.from(snap.data() ?? {});
        final hist = _parseHistorico(data['historicoPagamentos']);
        var alterou = false;
        double valorEstorno = 0;
        for (final h in hist) {
          if (_fsString(h['baixaId']) != bx) continue;
          if (_fsBool(h['estornada'])) return;
          h['estornada'] = true;
          h['estornoAt'] = DateTime.now().toIso8601String();
          valorEstorno = _fsDouble(h['valor']);
          alterou = true;
          break;
        }
        if (!alterou || valorEstorno <= 0) return;

        final saldo = _fsDouble(data['saldoAtual'], _fsDouble(data['valor']));
        final valorPago =
            (_fsDouble(data['valorPago']) - valorEstorno).clamp(0.0, double.infinity);
        final novoSaldo = saldo + valorEstorno;

        String status = ContaReceberStatus.pendente;
        var pago = false;
        if (novoSaldo < 0.01) {
          status = ContaReceberStatus.paga;
          pago = true;
        } else if (valorPago > 0.01) {
          status = ContaReceberStatus.parcial;
        }

        tx.set(
          ref,
          {
            ...data,
            'historicoPagamentos': hist,
            'valorPago': valorPago,
            'saldoAtual': novoSaldo,
            'valor': novoSaldo,
            'status': status,
            'pago': pago,
            'lastWriteOrigin': 'estorno_baixa',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      return true;
    } catch (e) {
      debugPrint('[CR-FS] Estorno remoto (type=${e.runtimeType})');
      return false;
    }
  }

  static Future<void> marcarCanceladaRemota({
    required String lojaId,
    required String contaReceberDocId,
  }) async {
    final loja = lojaId.trim();
    final id = contaReceberDocId.trim();
    if (loja.isEmpty || id.isEmpty) return;
    try {
      await _ref(loja, id).set({
        'cancelada': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'status': ContaReceberStatus.cancelada,
        'lastWriteOrigin': 'cancel',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[CR-FS] cancel remoto (type=${e.runtimeType})');
    }
  }

  /// Pull + migração conservadora (tela / full sync).
  static Future<ContaReceberPullResultado> sincronizarRemoto(String lojaId) =>
      ContaReceberService.sincronizarRemoto(lojaId);
}
