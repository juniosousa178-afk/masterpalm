// M3.8 HOTFIX-VENDEDOR-R2-FIX — orquestração do cadastro (testável).

import 'package:flutter/foundation.dart';

/// Resultado da confirmação pós-write.
class VendorCreateRefreshResult {
  const VendorCreateRefreshResult({
    required this.beforeCount,
    required this.afterCount,
    required this.vendorVisible,
  });

  final int beforeCount;
  final int afterCount;
  final bool vendorVisible;

  bool get grew => afterCount >= beforeCount + 1;
  bool get ok => grew && vendorVisible;
}

/// Helpers puros do fluxo de cadastro de vendedor.
abstract final class VendorCreateFlow {
  static const logTag = '[M38-VENDOR]';

  static const stageForm = 'form';
  static const stageAuth = 'auth';
  static const stageUsers = 'users';
  static const stageUsuarios = 'usuarios';
  static const stageVendedores = 'vendedores';
  static const stageMembers = 'members';
  static const stageHive = 'hive';
  static const stageRefresh = 'refresh';
  static const stageSuccess = 'success';
  static const stageError = 'error';

  /// Payload Firestore `usuarios/{email}` — nunca inclui senha.
  static Map<String, dynamic> usuariosDocPayload({
    required String uid,
    required String email,
    required String nome,
    required String telefone,
    required String ownerAdminEmail,
    required String storeId,
    required Object createdAt,
    required Object updatedAt,
  }) {
    return {
      'authUid': uid,
      'email': email,
      'nome': nome,
      'telefone': telefone,
      'tipo': 'vendedor',
      'ownerAdminEmail': ownerAdminEmail,
      'ownerStoreId': storeId,
      'store_id': storeId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  static bool payloadContainsPassword(Map<String, dynamic> data) {
    if (!data.containsKey('senha') && !data.containsKey('password')) {
      return false;
    }
    final s = data['senha'] ?? data['password'];
    if (s == null) return false;
    final t = s.toString().trim();
    return t.isNotEmpty;
  }

  /// Hive: senha do modelo é obrigatória no tipo; grava string vazia (não a senha real).
  static String hivePasswordPlaceholder() => '';

  static VendorCreateRefreshResult evaluateRefresh({
    required int beforeCount,
    required int afterCount,
    required bool vendorUidInList,
  }) {
    return VendorCreateRefreshResult(
      beforeCount: beforeCount,
      afterCount: afterCount,
      vendorVisible: vendorUidInList,
    );
  }

  /// Snack/pop só após refresh OK.
  static bool mayShowSuccessAndPop(VendorCreateRefreshResult r) => r.ok;

  static bool mayCloseModalOnError() => false;

  static String failureMessage({
    required String code,
    required String stage,
  }) {
    return 'Falha ao criar vendedor.\nCódigo:\n$code\n\nStage:\n$stage';
  }

  /// SnackBar detalhado — nunca só "unknown".
  static String detailedFailureMessage({
    required VendorAuthErrorDiag diag,
    required String stage,
  }) {
    final code = diag.displayCode();
    final msg = (diag.firebaseAuthMessage ??
            diag.firebaseMessage ??
            diag.platformMessage ??
            diag.message ??
            diag.toStringValue)
        .trim();
    final step = (diag.authStep ?? '').trim();
    final buf = StringBuffer('Falha ao criar vendedor.');
    buf.writeln();
    buf.writeln('Stage:');
    buf.writeln(step.isEmpty ? stage : '$stage / $step');
    buf.writeln();
    buf.writeln('Código:');
    buf.writeln(code);
    if (msg.isNotEmpty) {
      buf.writeln();
      buf.writeln('Mensagem:');
      buf.writeln(_sanitizeDiagLine(msg));
    }
    return buf.toString();
  }

  /// App Check no secondary NÃO deve bloquear createUser (alinhado ao soft-fail do main).
  static bool appCheckFailureBlocksCreate() => false;

  static String appCheckSoftFailLogLine(Object error) {
    final t = error.runtimeType.toString();
    String code = '';
    try {
      final c = (error as dynamic).code;
      if (c is String) code = c;
    } catch (_) {}
    return '$logTag authStep=app-check warning=soft-fail-continue '
        'runtimeType=$t code=${code.isEmpty ? '(none)' : code}';
  }

  static String refreshMissMessage() =>
      'O vendedor não apareceu após atualização.';

  static String successMessage() => 'Vendedor cadastrado com sucesso.';

  /// Auth secondary isolada: primary não pode virar o novo uid.
  static bool primarySessionStillAdmin({
    required String? adminUidBefore,
    required String? primaryUidAfterSecondaryCreate,
    required String newVendorUid,
  }) {
    if (adminUidBefore == null || adminUidBefore.isEmpty) return false;
    if (primaryUidAfterSecondaryCreate == null) return false;
    return primaryUidAfterSecondaryCreate == adminUidBefore &&
        primaryUidAfterSecondaryCreate != newVendorUid;
  }

  static String redactUid(String? uid) {
    final u = (uid ?? '').trim();
    if (u.length < 8) return u.isEmpty ? '-' : '***';
    return '${u.substring(0, 4)}…${u.substring(u.length - 4)}';
  }

  static void log(String stage, {String? code, String? uid, int? count}) {
    final buf = StringBuffer('$logTag stage=$stage');
    if (uid != null) buf.write(' uid=${redactUid(uid)}');
    if (code != null) buf.write(' code=$code');
    if (count != null) buf.write(' count=$count');
    final line = buf.toString();
    assert(!line.toLowerCase().contains('password'));
    assert(!RegExp(r'senha\s*=').hasMatch(line.toLowerCase()));
    debugPrint(line);
  }

  static void logAuthStep(String step) {
    debugPrint('$logTag authStep=$step');
  }

  /// Diagnóstico R3.1 — preserva TODOS os campos tipados da exceção original.
  static VendorAuthErrorDiag captureAuthError(
    Object error, {
    StackTrace? stack,
    String? authStep,
    String? firstCatchSite,
  }) {
    String? firebaseCode;
    String? firebaseMessage;
    String? firebaseAuthCode;
    String? firebaseAuthMessage;
    String? platformCode;
    String? platformMessage;
    String? typedCode;
    String? typedMessage;

    try {
      final dyn = error as dynamic;
      // FirebaseException / FirebaseAuthException / PlatformException: .code/.message
      final c = dyn.code;
      if (c is String && c.trim().isNotEmpty) typedCode = c.trim();
      final m = dyn.message;
      if (m is String && m.trim().isNotEmpty) typedMessage = m.trim();
    } catch (_) {}

    final typeName = error.runtimeType.toString();
    // Classificar por nome (evita import forte no core; still captura os campos).
    if (typeName.contains('FirebaseAuthException')) {
      firebaseAuthCode = typedCode;
      firebaseAuthMessage = typedMessage;
      firebaseCode = typedCode;
      firebaseMessage = typedMessage;
    } else if (typeName.contains('FirebaseException')) {
      firebaseCode = typedCode;
      firebaseMessage = typedMessage;
    } else if (typeName.contains('PlatformException')) {
      platformCode = typedCode;
      platformMessage = typedMessage;
    }

    final asText = _redactPii(error.toString());
    final extracted = _codeFromText(asText);
    final resolved = () {
      if (typedCode != null &&
          typedCode.isNotEmpty &&
          typedCode.toLowerCase() != 'unknown') {
        return typedCode;
      }
      if (extracted.isNotEmpty && extracted.toLowerCase() != 'unknown') {
        return extracted;
      }
      if (typedCode != null && typedCode.isNotEmpty) return typedCode;
      return extracted;
    }();

    final stackFull = (stack ?? StackTrace.current).toString();
    final stackShort = stackFull
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(8)
        .map(_redactPii)
        .join(' | ');

    return VendorAuthErrorDiag(
      errorRuntimeType: typeName,
      code: resolved,
      typedCode: typedCode,
      message: typedMessage,
      firebaseCode: firebaseCode,
      firebaseMessage: firebaseMessage,
      firebaseAuthCode: firebaseAuthCode,
      firebaseAuthMessage: firebaseAuthMessage,
      platformCode: platformCode,
      platformMessage: platformMessage,
      toStringValue: asText,
      stackShort: stackShort,
      authStep: authStep,
      firstCatchSite: firstCatchSite,
    );
  }

  /// Primeiro catch que recebe a exceção — NUNCA omitir campos.
  static void logAuthErrorDiag(VendorAuthErrorDiag d, {required String stage}) {
    debugPrint('$logTag stage=$stage');
    if (d.firstCatchSite != null) {
      debugPrint('$logTag firstCatch=${d.firstCatchSite}');
    }
    if (d.authStep != null) {
      debugPrint('$logTag authStep=${d.authStep}');
    }
    debugPrint('$logTag runtimeType=${d.errorRuntimeType}');
    debugPrint('$logTag firebaseCode=${d.firebaseCode ?? '(null)'}');
    debugPrint('$logTag firebaseMessage=${_sanitizeDiagLine(d.firebaseMessage ?? '(null)')}');
    debugPrint('$logTag firebaseAuthCode=${d.firebaseAuthCode ?? '(null)'}');
    debugPrint(
      '$logTag firebaseAuthMessage=${_sanitizeDiagLine(d.firebaseAuthMessage ?? '(null)')}',
    );
    debugPrint('$logTag platformCode=${d.platformCode ?? '(null)'}');
    debugPrint(
      '$logTag platformMessage=${_sanitizeDiagLine(d.platformMessage ?? '(null)')}',
    );
    debugPrint('$logTag resolvedCode=${d.code}');
    debugPrint('$logTag toString=${_sanitizeDiagLine(d.toStringValue)}');
    debugPrint('$logTag stack=${_sanitizeDiagLine(d.stackShort)}');
    debugPrint('$logTag unknownOrigin=${d.unknownOriginHint()}');
  }

  static String _redactPii(String s) {
    var t = s;
    t = t.replaceAllMapped(
      RegExp(r'(password|senha)\s*[:=]\s*\S+', caseSensitive: false),
      (m) => '${m.group(1)}=***',
    );
    // e-mail completo → partial
    t = t.replaceAllMapped(
      RegExp(r'([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})'),
      (m) {
        final local = m.group(1)!;
        final domain = m.group(2)!;
        final head = local.length <= 2 ? '**' : local.substring(0, 2);
        return '$head***@$domain';
      },
    );
    // telefone: sequências longas de dígitos
    t = t.replaceAllMapped(RegExp(r'\b(\d{2})(\d{4,})(\d{2})\b'), (m) {
      return '${m.group(1)}****${m.group(3)}';
    });
    return t;
  }

  static String _sanitizeDiagLine(String s) {
    var t = _redactPii(s).replaceAll('\n', ' | ');
    if (t.length > 900) t = '${t.substring(0, 900)}…';
    return t;
  }

  static String extractFirebaseCode(Object error) {
    if (error is String) {
      return _codeFromText(error);
    }
    // Preferir propriedade .code tipada (FirebaseAuthException / FirebaseException).
    try {
      final dyn = error as dynamic;
      final c = dyn.code;
      if (c is String && c.trim().isNotEmpty && c.toLowerCase() != 'unknown') {
        return c.trim();
      }
    } catch (_) {}
    return _codeFromText(error.toString());
  }

  static String _codeFromText(String s) {
    // Formato plugin Flutter: [firebase_auth/email-already-in-use]
    final m = RegExp(
      r'\[(?:firebase_auth|cloud_firestore|firebase)\/([a-z0-9-]+)\]',
      caseSensitive: false,
    ).firstMatch(s);
    if (m != null) return m.group(1) ?? 'unknown';
    // Formato JS / web: Firebase: Error (auth/email-already-in-use).
    final js = RegExp(
      r'\((?:auth|firebase_auth)\/([a-z0-9-]+)\)',
      caseSensitive: false,
    ).firstMatch(s);
    if (js != null) return js.group(1) ?? 'unknown';
    // Texto plano auth/code
    final plain = RegExp(
      r'(?:^|[\s/(])(?:auth|firebase_auth)\/([a-z0-9-]+)',
      caseSensitive: false,
    ).firstMatch(s);
    if (plain != null) return plain.group(1) ?? 'unknown';
    final known = RegExp(
      r'(email-already-in-use|weak-password|permission-denied|invalid-email|unauthenticated|failed-precondition|operation-not-allowed|too-many-requests|network-request-failed|app-not-authorized|internal-error|invalid-api-key|admin-restricted-operation)',
      caseSensitive: false,
    ).firstMatch(s);
    if (known != null) return known.group(1)!.toLowerCase();
    return 'unknown';
  }
}

/// Snapshot imutável do erro Auth para logs / SnackBar (R3.1-DIAG).
class VendorAuthErrorDiag {
  const VendorAuthErrorDiag({
    required this.errorRuntimeType,
    required this.code,
    required this.typedCode,
    required this.message,
    required this.firebaseCode,
    required this.firebaseMessage,
    required this.firebaseAuthCode,
    required this.firebaseAuthMessage,
    required this.platformCode,
    required this.platformMessage,
    required this.toStringValue,
    required this.stackShort,
    required this.authStep,
    required this.firstCatchSite,
  });

  final String errorRuntimeType;
  final String code;
  final String? typedCode;
  final String? message;
  final String? firebaseCode;
  final String? firebaseMessage;
  final String? firebaseAuthCode;
  final String? firebaseAuthMessage;
  final String? platformCode;
  final String? platformMessage;
  final String toStringValue;
  final String stackShort;
  final String? authStep;
  final String? firstCatchSite;

  /// Onde o literal "unknown" pode ter nascido.
  String unknownOriginHint() {
    if (firebaseCode == 'unknown' || firebaseAuthCode == 'unknown') {
      return 'FirebaseException.code default (plugin: code ?? "unknown")';
    }
    if (platformCode == 'unknown') {
      return 'PlatformException.code == unknown';
    }
    if (code == 'unknown') {
      return 'VendorCreateFlow._codeFromText fallback return "unknown"';
    }
    return 'n/a (resolvedCode!=unknown)';
  }

  /// Texto do SnackBar: código real + dicas (nunca só "unknown" se houver contexto).
  String snackCode() => displayCode();

  /// Código legível para UI — nunca retorna apenas "unknown".
  String displayCode() {
    final parts = <String>[];
    if (firebaseAuthCode != null &&
        firebaseAuthCode!.isNotEmpty &&
        firebaseAuthCode!.toLowerCase() != 'unknown') {
      parts.add(firebaseAuthCode!);
    } else if (firebaseCode != null &&
        firebaseCode!.isNotEmpty &&
        firebaseCode!.toLowerCase() != 'unknown') {
      parts.add(firebaseCode!);
    } else if (platformCode != null && platformCode!.isNotEmpty) {
      parts.add('platform:$platformCode');
    } else if (code.isNotEmpty && code.toLowerCase() != 'unknown') {
      parts.add(code);
    }

    if (parts.isEmpty) {
      parts.add(errorRuntimeType);
      final snippet = toStringValue.length > 100
          ? '${toStringValue.substring(0, 100)}…'
          : toStringValue;
      if (snippet.trim().isNotEmpty) parts.add(snippet);
      parts.add('(resolved=unknown)');
    }
    return parts.join(' | ');
  }
}
