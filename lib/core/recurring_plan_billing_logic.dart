// Pure helpers for recurring plan billing (testable, no Remote Config I/O).
library;

/// Parses CSV allowlist: trims entries, lowercases e-mails, keeps UIDs as-is.
Set<String> parseRecurringAllowlist(String raw) {
  final out = <String>{};
  for (final part in raw.split(',')) {
    final s = part.trim();
    if (s.isEmpty) continue;
    if (s.contains('@')) {
      out.add(s.toLowerCase());
    } else {
      out.add(s);
    }
  }
  return out;
}

/// Resolves whether recurring billing is enabled (global or allowlist).
bool isUserAllowedForRecurringBilling({
  required bool globalFromRemoteConfig,
  required Set<String> allowlist,
  required String uid,
  required String? email,
  required void Function(String reason) onLog,
}) {
  if (globalFromRemoteConfig) {
    onLog('global_remote_config');
    return true;
  }
  if (allowlist.isEmpty) {
    return false;
  }
  if (uid.isNotEmpty && allowlist.contains(uid)) {
    onLog('allowlist_uid');
    return true;
  }
  final e = (email ?? '').trim().toLowerCase();
  if (e.isNotEmpty && allowlist.contains(e)) {
    onLog('allowlist_email');
    return true;
  }
  return false;
}

String maskEmailForLog(String? email) {
  final s = (email ?? '').trim();
  if (s.isEmpty) return '—';
  if (!s.contains('@')) {
    if (s.length <= 3) return '***';
    return '${s.substring(0, 2)}***';
  }
  final at = s.indexOf('@');
  final local = s.substring(0, at);
  final domain = s.substring(at);
  if (local.length <= 1) {
    return '***$domain';
  }
  return '${local.substring(0, 1)}***$domain';
}
