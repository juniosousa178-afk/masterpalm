// Fiado / contas a receber — remote authority contract.
//
// INVARIANT:
// Firestore is authoritative for persisted financial state.
// Hive is CACHE / offline-derived projection and must NEVER silently
// regress a stronger/newer remote settlement via generic upsert.
//
// Terminal remote states (protected against generic Hive publish):
// - status=paga | pago=true | saldoAtual<=epsilon
// - status=cancelada | cancelada=true | deletedAt!=null
//
// status=estornada is NOT terminal for the title (dedicated estorno path
// may reopen saldo). Generic upsert must not emulate estorno.
//
// Legal financial transitions only via dedicated operations:
// registrarBaixa / registrarBaixaRemota, marcarCanceladaRemota,
// estornarBaixaRemota.

const double kContaReceberFinancialEpsilon = 0.01;

/// Result of a guarded generic upsert (Hive → Firestore).
enum ContaReceberUpsertDecision {
  applied,
  skippedRemoteStronger,
  conflictRejected,
  noChange,
}

/// Snapshot used for monotonic financial comparison (no PII).
class ContaReceberFinancialSnapshot {
  const ContaReceberFinancialSnapshot({
    required this.pago,
    required this.status,
    required this.saldo,
    required this.valorPago,
    required this.cancelada,
    required this.baixaIds,
  });

  final bool pago;
  final String status;
  final double saldo;
  final double valorPago;
  final bool cancelada;
  final Set<String> baixaIds;

  bool get isPaidTerminal =>
      pago ||
      status == 'paga' ||
      saldo < kContaReceberFinancialEpsilon;

  bool get isCancelledTerminal =>
      cancelada || status == 'cancelada';

  /// Protected against silent reopen by generic upsert.
  bool get isTerminalProtected => isPaidTerminal || isCancelledTerminal;
}

ContaReceberFinancialSnapshot snapshotFromMaps({
  required bool pago,
  required String status,
  required double saldo,
  required double valorPago,
  bool cancelada = false,
  Iterable<Map<String, dynamic>> historico = const [],
}) {
  final ids = <String>{};
  for (final h in historico) {
    final id = (h['baixaId'] ?? '').toString().trim();
    if (id.isNotEmpty) ids.add(id);
  }
  return ContaReceberFinancialSnapshot(
    pago: pago,
    status: status.trim().toLowerCase(),
    saldo: saldo,
    valorPago: valorPago,
    cancelada: cancelada,
    baixaIds: ids,
  );
}

/// True when applying [incoming] via generic upsert would regress [remote].
bool wouldRegressRemoteFinancialState({
  required ContaReceberFinancialSnapshot remote,
  required ContaReceberFinancialSnapshot incoming,
}) {
  // Cancelled remote cannot be reopened by generic publish.
  if (remote.isCancelledTerminal && !incoming.isCancelledTerminal) {
    return true;
  }

  // Paid / zero-balance remote cannot be reopened.
  if (remote.isPaidTerminal && !incoming.isPaidTerminal) {
    return true;
  }

  // valorPago must be monotonic (generic path cannot decrease).
  if (incoming.valorPago + kContaReceberFinancialEpsilon < remote.valorPago) {
    return true;
  }

  // Remaining balance must not increase (would undo settlement).
  if (incoming.saldo > remote.saldo + kContaReceberFinancialEpsilon) {
    return true;
  }

  // Payment history must be monotonic by baixaId — never drop remote entries.
  if (remote.baixaIds.difference(incoming.baixaIds).isNotEmpty) {
    return true;
  }

  return false;
}

/// Financially equivalent for skip-write (NO_CHANGE).
bool financiallyEquivalent({
  required ContaReceberFinancialSnapshot a,
  required ContaReceberFinancialSnapshot b,
}) {
  if (a.cancelada != b.cancelada) return false;
  if (a.pago != b.pago) return false;
  if (a.status != b.status) return false;
  if ((a.saldo - b.saldo).abs() > kContaReceberFinancialEpsilon) return false;
  if ((a.valorPago - b.valorPago).abs() > kContaReceberFinancialEpsilon) {
    return false;
  }
  if (a.baixaIds.length != b.baixaIds.length) return false;
  if (!a.baixaIds.containsAll(b.baixaIds)) return false;
  return true;
}

/// Decide generic upsert outcome before writing Firestore.
///
/// Business-state invariants win over client `updatedAt`.
/// A stale client must not win merely because device clock is ahead.
ContaReceberUpsertDecision decideGenericUpsert({
  required ContaReceberFinancialSnapshot? remote,
  required ContaReceberFinancialSnapshot incoming,
  required bool remoteDocExists,
}) {
  if (!remoteDocExists || remote == null) {
    // Create-only path for new titles (Policy A / first publish).
    if (incoming.isCancelledTerminal) {
      // Cancelling must use dedicated cancel path, not generic create-as-cancel.
      return ContaReceberUpsertDecision.conflictRejected;
    }
    return ContaReceberUpsertDecision.applied;
  }

  if (financiallyEquivalent(a: remote, b: incoming)) {
    return ContaReceberUpsertDecision.noChange;
  }

  if (wouldRegressRemoteFinancialState(remote: remote, incoming: incoming)) {
    return ContaReceberUpsertDecision.skippedRemoteStronger;
  }

  // Incoming claims stronger settlement without dedicated baixa path:
  // fail closed — generic upsert must not invent payments.
  if (incoming.valorPago > remote.valorPago + kContaReceberFinancialEpsilon ||
      incoming.saldo + kContaReceberFinancialEpsilon < remote.saldo ||
      incoming.baixaIds.difference(remote.baixaIds).isNotEmpty) {
    return ContaReceberUpsertDecision.conflictRejected;
  }

  // Non-regressing, non-settlement delta (e.g. lembrete flag) — allow.
  return ContaReceberUpsertDecision.applied;
}

/// Documented conflict policy for timestamps.
///
/// UPDATED_AT_CONFLICT_POLICY:
/// Business financial invariants first. Client-generated updatedAt never
/// authorizes regressing pago/valorPago/saldo/historico. When a write is
/// applied, Firestore serverTimestamp is used. Pull uses remote updatedAt
/// only as a cache hint, overridden when remote valorPago↑ or saldo↓.
const String kContaReceberUpdatedAtConflictPolicy =
    'BUSINESS_STATE_FIRST; serverTimestamp_on_write; '
    'client_updatedAt_never_wins_over_settlement';

/// Terminal remote states protected from generic reopen.
const List<String> kContaReceberTerminalRemoteStates = [
  'paga',
  'pago=true',
  'saldoAtual<=epsilon',
  'cancelada',
  'cancelada=true',
  'deletedAt!=null',
];

/// Transitions reversible only via dedicated operations.
const List<String> kContaReceberReversibleOnlyViaExplicitOperation = [
  'registrarBaixa/registrarBaixaRemota',
  'marcarCanceladaRemota',
  'estornarBaixaRemota',
];
