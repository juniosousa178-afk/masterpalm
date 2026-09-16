// lib/services/sync_queue_recovery_mode.dart
//
// Session-scoped QUEUE RECOVERY MODE.
// Default OFF. Explicit opt-in only. Performs no queue mutation by itself.
// Must be activated before SyncQueue bootstrap / automatic processPending.

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Explicit local recovery / diagnostic mode for the offline sync queue.
///
/// When active:
/// - automatic [processPending] paths become no-ops;
/// - legacy [retryItem] is blocked;
/// - recovery tooling uses metadata inventory / backup / processOneById.
///
/// Does **not** grant cross-store access, remote admin rights, or payload
/// visibility beyond what the authenticated browser profile already holds.
class SyncQueueRecoveryMode {
  SyncQueueRecoveryMode._();

  static bool _active = false;
  static String? _activationSource;
  static DateTime? _activatedAt;

  /// Query / fragment token (no credentials). Example:
  /// `?mpQueueRecovery=1` or `#mpQueueRecovery=1`
  static const String activationQueryKey = 'mpQueueRecovery';
  static const String activationQueryValue = '1';

  static bool get isActive => _active;

  static bool get isInactive => !_active;

  static String? get activationSource => _activationSource;

  static DateTime? get activatedAt => _activatedAt;

  /// Default for normal production sessions.
  static bool get defaultsToOff => true;

  /// Whether automatic queue processing (processPending / scheduled sync) may run.
  static bool get allowsAutomaticQueueProcessing => !_active;

  /// Activate for this browser/app session only (in-memory).
  /// Safe to call repeatedly. Does not touch the queue.
  static void activateForSession({String source = 'explicit'}) {
    _active = true;
    _activationSource = source;
    _activatedAt = DateTime.now().toUtc();
  }

  /// Deactivate (tests / leaving recovery). Does not process the queue.
  static void deactivateForSession() {
    _active = false;
    _activationSource = null;
    _activatedAt = null;
  }

  /// Resolve from URI before any SyncQueue bootstrap.
  /// Returns true if recovery mode became (or already was) active.
  static bool resolveFromUri(Uri? uri) {
    if (uri == null) return _active;
    if (_uriRequestsRecovery(uri)) {
      activateForSession(source: 'uri');
      return true;
    }
    return _active;
  }

  static bool _uriRequestsRecovery(Uri uri) {
    final q = uri.queryParameters[activationQueryKey]?.trim();
    if (q == activationQueryValue) return true;

    // Fragment may be `mpQueueRecovery=1` or `foo&mpQueueRecovery=1`
    final frag = uri.fragment.trim();
    if (frag.isEmpty) return false;
    if (frag == '$activationQueryKey=$activationQueryValue') return true;
    try {
      final fake = Uri.parse('https://local/?$frag');
      return fake.queryParameters[activationQueryKey]?.trim() ==
          activationQueryValue;
    } catch (_) {
      return frag.contains('$activationQueryKey=$activationQueryValue');
    }
  }

  @visibleForTesting
  static void resetForTests() {
    deactivateForSession();
  }
}
