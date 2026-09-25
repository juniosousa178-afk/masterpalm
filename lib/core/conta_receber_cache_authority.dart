// Conta a receber — cache authority / terminal watermark helpers.
//
// Hive may mirror Firestore only after a successful remote pull stamps
// remoteAuthorityConfirmed. Offline debt alerts must use trusted open state
// only; uncertain stale opens never generate false overdue warnings.

import '../models/conta_receber.dart';
import 'conta_receber_remote_authority.dart';

/// Cached remote terminal classification (local watermark values).
abstract final class ContaReceberRemoteTerminalState {
  static const open = 'open';
  static const partial = 'partial';
  static const paid = 'paid';
  static const cancelled = 'cancelled';
  static const deleted = 'deleted';
  static const unknown = 'unknown';
}

String classifyContaReceberRemoteTerminalState(ContaReceber c) {
  final status = c.status.trim().toLowerCase();
  if (status == ContaReceberStatus.cancelada) {
    return ContaReceberRemoteTerminalState.cancelled;
  }
  if (c.pago ||
      status == ContaReceberStatus.paga ||
      c.saldoRestante < kContaReceberFinancialEpsilon) {
    return ContaReceberRemoteTerminalState.paid;
  }
  if (c.valorPago > kContaReceberFinancialEpsilon ||
      status == ContaReceberStatus.parcial) {
    return ContaReceberRemoteTerminalState.partial;
  }
  return ContaReceberRemoteTerminalState.open;
}

void stampContaReceberRemoteAuthority(
  ContaReceber c, {
  DateTime? confirmedAt,
  String? terminalState,
}) {
  c.remoteAuthorityConfirmed = true;
  c.remoteConfirmedAtMs =
      (confirmedAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
  c.remoteTerminalState =
      (terminalState ?? classifyContaReceberRemoteTerminalState(c)).trim();
  if (c.remoteTerminalState.isEmpty) {
    c.remoteTerminalState = ContaReceberRemoteTerminalState.unknown;
  }
}

/// Local open/overdue may be shown as debt only when remote confirmed open/partial.
bool isTrustedRemoteOpenDebt(ContaReceber c) {
  if (!c.remoteAuthorityConfirmed) return false;
  final term = c.remoteTerminalState.trim().toLowerCase();
  if (term != ContaReceberRemoteTerminalState.open &&
      term != ContaReceberRemoteTerminalState.partial) {
    return false;
  }
  if (c.pago || c.saldoRestante < kContaReceberFinancialEpsilon) return false;
  return true;
}

/// Terminal watermark wins over stale local open flags.
bool isRemoteTerminalWatermarkBlockingOpen(ContaReceber c) {
  if (!c.remoteAuthorityConfirmed) return false;
  final term = c.remoteTerminalState.trim().toLowerCase();
  return term == ContaReceberRemoteTerminalState.paid ||
      term == ContaReceberRemoteTerminalState.cancelled ||
      term == ContaReceberRemoteTerminalState.deleted;
}

bool contaReceberAppearsLocallyOpen(ContaReceber c) {
  return !c.pago && c.saldoRestante >= kContaReceberFinancialEpsilon;
}

/// Active receivables list: exclude paid/cancelled watermark + local paid.
bool contaReceberVisibleInActiveReceivables(ContaReceber c) {
  if (isRemoteTerminalWatermarkBlockingOpen(c)) return false;
  final status = c.status.trim().toLowerCase();
  if (status == ContaReceberStatus.cancelada) return false;
  if (c.pago || c.saldoRestante < kContaReceberFinancialEpsilon) return false;
  return true;
}

class ContaReceberOverdueAlertDecision {
  const ContaReceberOverdueAlertDecision({
    required this.showDebtAlert,
    required this.showNeutralSyncWarning,
    required this.vencidas,
    required this.vencendo,
    required this.fingerprint,
    required this.authority,
  });

  final bool showDebtAlert;
  final bool showNeutralSyncWarning;
  final List<ContaReceber> vencidas;
  final List<ContaReceber> vencendo;
  final String fingerprint;
  final String authority; // REMOTE | TRUSTED_CACHE | UNCERTAIN | NONE

  double get totalPendente =>
      [...vencidas, ...vencendo].fold<double>(0, (s, c) => s + c.valor);
}

/// Pure alert policy used by Home (and tests).
ContaReceberOverdueAlertDecision decideContaReceberOverdueAlert({
  required Iterable<ContaReceber> contas,
  required String lojaId,
  required bool remoteRefreshOk,
  DateTime? now,
}) {
  final hoje = now ?? DateTime.now();
  final hojeBase = DateTime(hoje.year, hoje.month, hoje.day);

  bool isVencida(ContaReceber c) {
    final d = DateTime(
      c.dataVencimento.year,
      c.dataVencimento.month,
      c.dataVencimento.day,
    );
    return d.isBefore(hojeBase);
  }

  bool isVencendo(ContaReceber c) {
    final d = DateTime(
      c.dataVencimento.year,
      c.dataVencimento.month,
      c.dataVencimento.day,
    );
    final dias = d.difference(hojeBase).inDays;
    return dias >= 0 && dias <= 2;
  }

  final eligible = <ContaReceber>[];
  var uncertainOpen = false;

  for (final c in contas) {
    if (c.lojaId.trim().isNotEmpty &&
        c.lojaId.trim() != lojaId.trim() &&
        lojaId.trim().isNotEmpty) {
      continue;
    }
    if (isRemoteTerminalWatermarkBlockingOpen(c)) continue;
    if (!contaReceberAppearsLocallyOpen(c)) continue;

    if (remoteRefreshOk) {
      // After successful pull, local open is treated as current (watermark stamped).
      eligible.add(c);
      continue;
    }

    // Offline / failed remote: only trusted open/partial watermarks count as debt.
    if (isTrustedRemoteOpenDebt(c)) {
      eligible.add(c);
    } else {
      uncertainOpen = true;
    }
  }

  final vencidas = eligible.where(isVencida).toList();
  final vencendo = eligible.where(isVencendo).toList();

  final ids = [...vencidas, ...vencendo]
      .map((c) => (c.idFirebase ?? '').trim())
      .where((id) => id.isNotEmpty)
      .toList()
    ..sort();
  final total =
      [...vencidas, ...vencendo].fold<double>(0, (s, c) => s + c.valor);
  final fp =
      '${lojaId.trim()}|${ids.join(',')}|${total.toStringAsFixed(2)}|${vencidas.length}|${vencendo.length}';

  if (vencidas.isEmpty && vencendo.isEmpty) {
    return ContaReceberOverdueAlertDecision(
      showDebtAlert: false,
      showNeutralSyncWarning: !remoteRefreshOk && uncertainOpen,
      vencidas: const [],
      vencendo: const [],
      fingerprint: fp,
      authority: remoteRefreshOk
          ? 'REMOTE'
          : (uncertainOpen ? 'UNCERTAIN' : 'NONE'),
    );
  }

  return ContaReceberOverdueAlertDecision(
    showDebtAlert: true,
    showNeutralSyncWarning: false,
    vencidas: vencidas,
    vencendo: vencendo,
    fingerprint: fp,
    authority: remoteRefreshOk ? 'REMOTE' : 'TRUSTED_CACHE',
  );
}

/// Session-scoped reminder presentation (not financial state).
class ContaReceberAlertSessionGate {
  ContaReceberAlertSessionGate._();
  static final ContaReceberAlertSessionGate instance =
      ContaReceberAlertSessionGate._();

  String? _lastDebtFingerprint;
  String? _snoozedFingerprint;
  String? _lastNeutralFingerprint;
  bool _neutralShownThisSession = false;

  /// SNOOZE_POLICY=same_fingerprint_rest_of_session
  void snoozeDebtAlert(String fingerprint) {
    final fp = fingerprint.trim();
    if (fp.isEmpty) return;
    _snoozedFingerprint = fp;
    _lastDebtFingerprint = fp;
  }

  void markDebtAlertShown(String fingerprint) {
    final fp = fingerprint.trim();
    if (fp.isEmpty) return;
    _lastDebtFingerprint = fp;
  }

  void markNeutralShown(String fingerprint) {
    _neutralShownThisSession = true;
    _lastNeutralFingerprint = fingerprint.trim();
  }

  bool shouldShowDebtAlert(String fingerprint) {
    final fp = fingerprint.trim();
    if (fp.isEmpty) return false;
    if (_snoozedFingerprint == fp) return false;
    if (_lastDebtFingerprint == fp) return false;
    return true;
  }

  bool shouldShowNeutralWarning(String fingerprint) {
    if (_neutralShownThisSession) return false;
    final fp = fingerprint.trim();
    if (fp.isEmpty) return true;
    return _lastNeutralFingerprint != fp;
  }

  /// Test/reset hook.
  void debugReset() {
    _lastDebtFingerprint = null;
    _snoozedFingerprint = null;
    _lastNeutralFingerprint = null;
    _neutralShownThisSession = false;
  }
}
