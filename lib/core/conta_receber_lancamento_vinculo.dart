// Idempotência: recebimento de conta a receber → lançamento financeiro vinculado.

import '../financeiro/financeiro_constants.dart';
import '../models/conta_receber.dart';
import '../models/lancamento_financeiro.dart';

/// ID estável cross-device quando a conta está vinculada a uma venda fiada.
String contaReceberStableId(ContaReceber conta) {
  final vendaId = conta.vendaIdFirebase.trim();
  if (vendaId.isEmpty) return '';
  return '${vendaId}_p${conta.parcelaNumero.clamp(1, 999)}';
}

String _diaRecebimento(DateTime dataRecebimento) {
  final d = dataRecebimento;
  return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}

String _centavosRecebimento(double valor) =>
    (valor.abs() * 100).round().toString();

String _sanitizeStableId(String id) =>
    id.trim().replaceAll('/', '_').replaceAll(':', '_');

/// Documento canônico em `lancamentos_financeiros` para um recebimento (legado Hive key).
String lancamentoFinanceiroDocIdParaContaReceber({
  required int contaHiveKey,
  required int parcelaNumero,
  required double valor,
  required DateTime dataRecebimento,
}) {
  final key = contaHiveKey;
  if (key < 0) return 'mp_cr_invalido';
  final cents = _centavosRecebimento(valor);
  final dia = _diaRecebimento(dataRecebimento);
  return 'mp_cr_${key}_${parcelaNumero.clamp(1, 999)}_${cents}_$dia';
}

/// Documento canônico cross-device (vendaIdFirebase + parcela).
String lancamentoFinanceiroDocIdParaContaReceberStable({
  required String contaReceberStableId,
  required int parcelaNumero,
  required double valor,
  required DateTime dataRecebimento,
}) {
  final stable = _sanitizeStableId(contaReceberStableId);
  if (stable.isEmpty) return 'mp_cr2_invalido';
  final cents = _centavosRecebimento(valor);
  final dia = _diaRecebimento(dataRecebimento);
  return 'mp_cr2_${stable}_${parcelaNumero.clamp(1, 999)}_${cents}_$dia';
}

String referenciaExternaContaReceber({
  required int contaHiveKey,
  required int parcelaNumero,
  required double valor,
  required DateTime dataRecebimento,
}) {
  final cents = _centavosRecebimento(valor);
  final dia = _diaRecebimento(dataRecebimento);
  return 'cr_receb:$contaHiveKey:$parcelaNumero:$cents:$dia';
}

String referenciaExternaContaReceberStable({
  required String contaReceberStableId,
  required int parcelaNumero,
  required double valor,
  required DateTime dataRecebimento,
}) {
  final stable = _sanitizeStableId(contaReceberStableId);
  final cents = _centavosRecebimento(valor);
  final dia = _diaRecebimento(dataRecebimento);
  return 'cr_receb2:$stable:$parcelaNumero:$cents:$dia';
}

/// Referência cross-device principal: `mp_cr2_{contaReceberId}__{baixaId}`.
String referenciaExternaContaReceberFirestore({
  required String contaReceberDocId,
  required String baixaId,
}) {
  final doc = _sanitizeStableId(contaReceberDocId);
  final bx = baixaId.trim();
  if (doc.isEmpty || bx.isEmpty) return '';
  return 'mp_cr2_${doc}__$bx';
}

/// Doc id do LF = mesma referência (idempotência forte).
String lancamentoFinanceiroDocIdFirestore({
  required String contaReceberDocId,
  required String baixaId,
}) {
  final ref = referenciaExternaContaReceberFirestore(
    contaReceberDocId: contaReceberDocId,
    baixaId: baixaId,
  );
  if (ref.isEmpty) return 'mp_cr2_invalido';
  return ref.length > 500 ? ref.substring(0, 500) : ref;
}

/// Preferência: Firestore doc+baixa; depois ID estável (cross-device); fallback Hive key.
({String docId, String ref}) idsRecebimentoContaReceber({
  required ContaReceber conta,
  required int contaHiveKey,
  required int parcelaNumero,
  required double valor,
  required DateTime dataRecebimento,
  String? contaReceberDocId,
  String? baixaId,
}) {
  final parcela = parcelaNumero.clamp(1, 999);
  final doc = (contaReceberDocId ?? '').trim();
  final bx = (baixaId ?? '').trim();
  if (doc.isNotEmpty && bx.isNotEmpty) {
    final ref = referenciaExternaContaReceberFirestore(
      contaReceberDocId: doc,
      baixaId: bx,
    );
    return (
      docId: lancamentoFinanceiroDocIdFirestore(
        contaReceberDocId: doc,
        baixaId: bx,
      ),
      ref: ref,
    );
  }

  final stable = contaReceberStableId(conta);
  if (stable.isNotEmpty) {
    return (
      docId: lancamentoFinanceiroDocIdParaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: parcela,
        valor: valor,
        dataRecebimento: dataRecebimento,
      ),
      ref: referenciaExternaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: parcela,
        valor: valor,
        dataRecebimento: dataRecebimento,
      ),
    );
  }
  if (contaHiveKey >= 0) {
    return (
      docId: lancamentoFinanceiroDocIdParaContaReceber(
        contaHiveKey: contaHiveKey,
        parcelaNumero: parcela,
        valor: valor,
        dataRecebimento: dataRecebimento,
      ),
      ref: referenciaExternaContaReceber(
        contaHiveKey: contaHiveKey,
        parcelaNumero: parcela,
        valor: valor,
        dataRecebimento: dataRecebimento,
      ),
    );
  }
  return (docId: 'mp_cr_invalido', ref: '');
}

class ContaReceberRecebimentoRefParsed {
  final String stableId;
  final int? hiveKey;
  final int parcelaNumero;
  final int centavos;
  final String dia;
  final String contaReceberDocId;
  final String baixaId;

  const ContaReceberRecebimentoRefParsed({
    this.stableId = '',
    this.hiveKey,
    this.parcelaNumero = 1,
    this.centavos = 0,
    this.dia = '',
    this.contaReceberDocId = '',
    this.baixaId = '',
  });

  double get valor => centavos / 100.0;

  bool get isStable => stableId.isNotEmpty;

  bool get isFirestoreDocBaixa =>
      contaReceberDocId.isNotEmpty && baixaId.isNotEmpty;
}

ContaReceberRecebimentoRefParsed? parseReferenciaExternaContaReceber(String ref) {
  final r = ref.trim();
  if (r.startsWith('mp_cr2_') && r.contains('__')) {
    final sep = r.indexOf('__');
    if (sep > 'mp_cr2_'.length) {
      final bx = r.substring(sep + 2);
      if (bx.startsWith('bx_')) {
        return ContaReceberRecebimentoRefParsed(
          contaReceberDocId: r.substring('mp_cr2_'.length, sep),
          baixaId: bx,
        );
      }
    }
  }
  if (r.startsWith('cr_receb2:')) {
    final parts = r.split(':');
    if (parts.length < 5) return null;
    final stable = parts[1].trim();
    if (stable.isEmpty) return null;
    final parcela = int.tryParse(parts[2]) ?? 1;
    final cents = int.tryParse(parts[3]) ?? 0;
    final dia = parts[4].trim();
    return ContaReceberRecebimentoRefParsed(
      stableId: stable,
      parcelaNumero: parcela,
      centavos: cents,
      dia: dia,
    );
  }
  if (r.startsWith('cr_receb:') && !r.startsWith('cr_receb:orfao')) {
    final parts = r.split(':');
    if (parts.length < 5) return null;
    final hive = int.tryParse(parts[1]);
    if (hive == null || hive < 0) return null;
    final parcela = int.tryParse(parts[2]) ?? 1;
    final cents = int.tryParse(parts[3]) ?? 0;
    final dia = parts[4].trim();
    return ContaReceberRecebimentoRefParsed(
      hiveKey: hive,
      parcelaNumero: parcela,
      centavos: cents,
      dia: dia,
    );
  }
  return null;
}

bool lancamentoVinculadoAContaReceber(LancamentoFinanceiro l) {
  if (l.origem == FinanceiroOrigemLancamento.contaReceberFiado) return true;
  final ref = l.referenciaExterna.trim();
  if (ref.startsWith('cr_receb:') && !ref.startsWith('cr_receb:orfao')) {
    return true;
  }
  if (ref.startsWith('cr_receb2:')) return true;
  if (ref.startsWith('mp_cr2_') || ref.startsWith('mp_cr_')) {
    return !ref.contains('orfao') && !ref.contains('invalido');
  }
  return lancamentoIdContaReceber(l.id) &&
      !l.id.contains('orfao') &&
      !l.id.contains('invalido');
}

bool lancamentoIdContaReceber(String id) {
  final s = id.trim();
  return s.startsWith('mp_cr_') || s.startsWith('mp_cr2_');
}

ContaReceberRecebimentoRefParsed? recebimentoRefFromLancamento(
  LancamentoFinanceiro l,
) {
  final parsed = parseReferenciaExternaContaReceber(l.referenciaExterna);
  if (parsed != null) return parsed;

  final id = l.id.trim();
  if (id.startsWith('mp_cr2_') && id.contains('__')) {
    final parsed = parseReferenciaExternaContaReceber(id);
    if (parsed != null && parsed.isFirestoreDocBaixa) return parsed;
  }
  if (id.startsWith('mp_cr2_')) {
    final body = id.substring('mp_cr2_'.length);
    final idx = body.lastIndexOf('_');
    if (idx <= 0) return null;
    final rest = body.substring(0, idx);
    final dia = body.substring(idx + 1);
    final parts = rest.split('_');
    if (parts.length < 3) return null;
    final cents = int.tryParse(parts[parts.length - 1]) ?? 0;
    final parcela = int.tryParse(parts[parts.length - 2]) ?? 1;
    final stable = parts.sublist(0, parts.length - 2).join('_');
    return ContaReceberRecebimentoRefParsed(
      stableId: stable,
      parcelaNumero: parcela,
      centavos: cents,
      dia: dia,
    );
  }
  if (id.startsWith('mp_cr_') && !id.startsWith('mp_cr_orfao')) {
    final body = id.substring('mp_cr_'.length);
    final idx = body.lastIndexOf('_');
    if (idx <= 0) return null;
    final rest = body.substring(0, idx);
    final dia = body.substring(idx + 1);
    final parts = rest.split('_');
    if (parts.length < 3) return null;
    final cents = int.tryParse(parts[2]) ?? 0;
    final parcela = int.tryParse(parts[1]) ?? 1;
    final hive = int.tryParse(parts[0]);
    if (hive == null) return null;
    return ContaReceberRecebimentoRefParsed(
      hiveKey: hive,
      parcelaNumero: parcela,
      centavos: cents,
      dia: dia,
    );
  }
  return null;
}
