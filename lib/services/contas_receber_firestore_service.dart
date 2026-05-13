// Espelho Firestore para Contas a receber (Hive continua como cache local).
//
// Erros de rede/regras são logados e não propagados (P0 não bloqueia venda local).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/conta_receber.dart';
import 'firestore_paths.dart';

class ContasReceberFirestoreService {
  ContasReceberFirestoreService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _uuid = Uuid();

  static CollectionReference<Map<String, dynamic>> _col(String lojaId) {
    return _db
        .collection('lojas')
        .doc(lojaId.trim())
        .collection(FSPaths.contasReceberCol);
  }

  static String _origemApp() => kIsWeb ? 'web' : 'app';

  static String _sanitizeDocIdSegment(String s) {
    return s.replaceAll(RegExp(r'[/\\]'), '_').trim();
  }

  /// Doc id estável quando há venda Firestore + nº parcela; senão reutiliza [conta.idFirebase];
  /// caso contrário retorna null (gerar UUID na escrita).
  static String? gerarDocIdParaConta({
    required ContaReceber conta,
    String? vendaFirebaseId,
  }) {
    final vid = (vendaFirebaseId ?? '').trim();
    if (vid.isNotEmpty && conta.parcelaNumero >= 1) {
      return 'conta_${_sanitizeDocIdSegment(vid)}_${conta.parcelaNumero}';
    }
    final existing = (conta.idFirebase ?? '').trim();
    if (existing.isNotEmpty) return existing;
    return null;
  }

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static Timestamp? _readTs(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v;
    if (v is DateTime) return Timestamp.fromDate(v);
    return null;
  }

  static Map<String, dynamic> _mapFromConta({
    required ContaReceber conta,
    required String lojaId,
    required String docId,
    String? vendaFirebaseId,
    required String formaOrigem,
    String? recoveryId,
  }) {
    final pago = conta.pago;
    final status = pago ? 'pago' : 'pendente';
    final vid = (vendaFirebaseId ?? '').trim();
    final map = <String, dynamic>{
      'id': docId,
      'lojaId': lojaId.trim(),
      'clienteNome': conta.clienteNome,
      'clienteNomeLower': conta.clienteNome.trim().toLowerCase(),
      'valor': conta.valor,
      'dataVencimento': Timestamp.fromDate(_dateOnly(conta.dataVencimento)),
      'dataVenda': Timestamp.fromDate(_dateOnly(conta.dataVenda)),
      'pago': pago,
      'observacao': conta.observacao,
      'vendaKey': conta.vendaKey,
      'vendaFirebaseId': vid,
      'parcelaNumero': conta.parcelaNumero,
      'parcelaTotal': conta.parcelaTotal,
      'lembrete2DiasEnviado': conta.lembrete2DiasEnviado,
      'status': status,
      'formaOrigem': formaOrigem,
      'updatedAt': FieldValue.serverTimestamp(),
      'origem': _origemApp(),
    };
    if (conta.key != null) {
      final k = conta.key;
      if (k is int) map['idFirebaseLocal'] = k;
    }
    if (recoveryId != null && recoveryId.trim().isNotEmpty) {
      map['recoveryId'] = recoveryId.trim();
    }
    return map;
  }

  static Future<void> upsertConta({
    required ContaReceber conta,
    required String lojaId,
    String? vendaFirebaseId,
    String formaOrigem = 'manual',
    String? recoveryId,
  }) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) return;

    try {
      var docId = gerarDocIdParaConta(conta: conta, vendaFirebaseId: vendaFirebaseId);
      docId ??= (conta.idFirebase ?? '').trim().isNotEmpty
          ? conta.idFirebase!.trim()
          : _uuid.v4();

      if ((conta.idFirebase ?? '').trim().isEmpty) {
        conta.idFirebase = docId;
        if (conta.isInBox) {
          await conta.save();
        }
      } else {
        docId = conta.idFirebase!.trim();
      }

      final ref = _col(lid).doc(docId);
      final snap = await ref.get();
      final payload = _mapFromConta(
        conta: conta,
        lojaId: lid,
        docId: docId,
        vendaFirebaseId: vendaFirebaseId,
        formaOrigem: formaOrigem,
        recoveryId: recoveryId,
      );
      if (!snap.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
      await ref.set(payload, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint(
        '⚠️ [CR-FS] upsertConta falhou (type=${e.runtimeType}) lojaId=$lojaId',
      );
      debugPrint('$st');
    }
  }

  static Future<void> upsertContasDeVendaFiada({
    required List<ContaReceber> contas,
    required String lojaId,
    String? vendaFirebaseId,
  }) async {
    for (final c in contas) {
      await upsertConta(
        conta: c,
        lojaId: lojaId,
        vendaFirebaseId: vendaFirebaseId,
        formaOrigem: 'fiado_venda',
      );
    }
  }

  static Future<void> marcarContaPaga({
    required ContaReceber conta,
    required String lojaId,
    DateTime? dataPagamento,
  }) async {
    final id = (conta.idFirebase ?? '').trim();
    if (id.isEmpty) return;
    final lid = lojaId.trim();
    if (lid.isEmpty) return;
    try {
      final quando = dataPagamento ?? DateTime.now();
      await _col(lid).doc(id).set(
        {
          'pago': true,
          'status': 'pago',
          'dataPagamento': Timestamp.fromDate(quando),
          'updatedAt': FieldValue.serverTimestamp(),
          'origem': _origemApp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint(
        '⚠️ [CR-FS] marcarContaPaga falhou (type=${e.runtimeType}) docId=$id',
      );
      debugPrint('$st');
    }
  }

  static Future<void> marcarContaValorEPendenteNoFirestore({
    required ContaReceber conta,
    required String lojaId,
  }) async {
    final id = (conta.idFirebase ?? '').trim();
    if (id.isEmpty) return;
    final lid = lojaId.trim();
    if (lid.isEmpty) return;
    try {
      await _col(lid).doc(id).set(
        {
          'valor': conta.valor,
          'pago': conta.pago,
          'status': conta.pago ? 'pago' : 'pendente',
          'updatedAt': FieldValue.serverTimestamp(),
          'origem': _origemApp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint(
        '⚠️ [CR-FS] marcarContaValorEPendente falhou (type=${e.runtimeType}) docId=$id',
      );
      debugPrint('$st');
    }
  }

  /// Marca um documento remoto como excluído (não apaga físico).
  static Future<void> marcarContaComoExcluidaNoFirestore({
    required String lojaId,
    required ContaReceber conta,
  }) async {
    final id = (conta.idFirebase ?? '').trim();
    if (id.isEmpty) return;
    try {
      await _col(lojaId).doc(id).set(
        {
          'status': 'excluido',
          'updatedAt': FieldValue.serverTimestamp(),
          'origem': _origemApp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint(
        '⚠️ [CR-FS] marcarContaComoExcluida falhou (type=${e.runtimeType}) docId=$id',
      );
      debugPrint('$st');
    }
  }

  static Future<void> marcarContasDaVendaComoCanceladasOuExcluidas({
    required String lojaId,
    int? vendaKey,
    String? vendaFirebaseId,
  }) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) return;
    final ids = <String>{};
    try {
      final col = _col(lid);
      final vid = (vendaFirebaseId ?? '').trim();
      if (vid.isNotEmpty) {
        final q = await col.where('vendaFirebaseId', isEqualTo: vid).get();
        for (final d in q.docs) {
          ids.add(d.id);
        }
      }
      if (vendaKey != null && vendaKey > 0) {
        final q2 = await col.where('vendaKey', isEqualTo: vendaKey).get();
        for (final d in q2.docs) {
          ids.add(d.id);
        }
      }
      if (ids.isEmpty) return;

      var batch = _db.batch();
      var n = 0;
      for (final id in ids) {
        batch.set(
          col.doc(id),
          {
            'status': 'excluido',
            'updatedAt': FieldValue.serverTimestamp(),
            'origem': _origemApp(),
          },
          SetOptions(merge: true),
        );
        n++;
        if (n >= 400) {
          await batch.commit();
          batch = _db.batch();
          n = 0;
        }
      }
      if (n > 0) await batch.commit();
    } catch (e, st) {
      debugPrint(
        '⚠️ [CR-FS] marcarContasDaVendaComoCanceladasOuExcluidas falhou (type=${e.runtimeType})',
      );
      debugPrint('$st');
    }
  }

  static ContaReceber? _contaFromRemoteDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String lojaId,
  ) {
    final m = doc.data();
    if (m == null) return null;
    final status = (m['status'] ?? 'pendente').toString();
    if (status == 'excluido' || status == 'cancelado') return null;

    final dv = _readTs(m['dataVencimento']);
    final dven = _readTs(m['dataVenda']);
    if (dv == null || dven == null) return null;

    final nome = (m['clienteNome'] ?? '').toString();
    if (nome.isEmpty) return null;

    final valor = (m['valor'] as num?)?.toDouble() ?? 0.0;
    final pago = m['pago'] == true;
    final obs = (m['observacao'] ?? '').toString();
    final vk = (m['vendaKey'] as num?)?.toInt() ?? 0;
    final pn = (m['parcelaNumero'] as num?)?.toInt() ?? 1;
    final pt = (m['parcelaTotal'] as num?)?.toInt() ?? 1;
    final lembrete = m['lembrete2DiasEnviado'] == true;

    return ContaReceber(
      lojaId: lojaId.trim(),
      clienteNome: nome,
      valor: valor,
      dataVencimento: dv.toDate(),
      dataVenda: dven.toDate(),
      pago: pago,
      observacao: obs,
      vendaKey: vk,
      idFirebase: doc.id,
      parcelaNumero: pn,
      parcelaTotal: pt,
      lembrete2DiasEnviado: lembrete,
    );
  }

  /// Pull conservador: documentos ativos → Hive (merge por idFirebase).
  static Future<void> sincronizarFirestoreParaHive({
    required String lojaId,
    required Box<ContaReceber> box,
  }) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) return;

    try {
      final col = _col(lid);
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      const page = 120;
      var guard = 0;
      while (guard < 80) {
        guard++;
        Query<Map<String, dynamic>> q =
            col.orderBy(FieldPath.documentId).limit(page);
        if (cursor != null) {
          q = q.startAfterDocument(cursor);
        }
        final snap = await q.get();
        if (snap.docs.isEmpty) break;

        for (final doc in snap.docs) {
          final remote = _contaFromRemoteDoc(doc, lid);
          if (remote == null) continue;

          ContaReceber? localMatch;
          for (final c in box.values) {
            if (c.lojaId == lid && (c.idFirebase ?? '').trim() == doc.id) {
              localMatch = c;
              break;
            }
          }

          if (localMatch != null) {
            localMatch.clienteNome = remote.clienteNome;
            localMatch.valor = remote.valor;
            localMatch.dataVencimento = remote.dataVencimento;
            localMatch.dataVenda = remote.dataVenda;
            localMatch.pago = remote.pago;
            localMatch.observacao = remote.observacao;
            localMatch.vendaKey = remote.vendaKey;
            localMatch.parcelaNumero = remote.parcelaNumero;
            localMatch.parcelaTotal = remote.parcelaTotal;
            localMatch.lembrete2DiasEnviado = remote.lembrete2DiasEnviado;
            if ((localMatch.idFirebase ?? '').isEmpty) {
              localMatch.idFirebase = doc.id;
            }
            await localMatch.save();
          } else {
            await box.add(remote);
          }
        }
        cursor = snap.docs.last;
        if (snap.size < page) break;
      }
    } catch (e, st) {
      debugPrint(
        '⚠️ [CR-FS] sincronizarFirestoreParaHive falhou (type=${e.runtimeType}) lojaId=$lid',
      );
      debugPrint('$st');
    }
  }
}
