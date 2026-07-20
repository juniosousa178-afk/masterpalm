// Gate de alerta visual para venda cancelada/excluída.
// Separado de: persistência, badge "lida" e SoftDelete.
// Não importa NotificacaoVendasService (evita ciclo).

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Decide se o aviso visual deve aparecer — sem usar "lida" como "já exibido".
class VendaCanceladaAlertaGate {
  static const _prefsPrefix = 'm39_alerta_exibido_v1_';
  static const tipoVendaCancelada = 'vendaCancelada';

  /// IDs já apresentados nesta sessão (memória).
  final Set<String> sessionShown;

  /// IDs presentes no primeiro snapshot (não alertar como "novos").
  final Set<String> baselineIds;

  bool baselineSeeded;

  VendaCanceladaAlertaGate({
    Set<String>? sessionShown,
    Set<String>? baselineIds,
    this.baselineSeeded = false,
  })  : sessionShown = sessionShown ?? <String>{},
        baselineIds = baselineIds ?? <String>{};

  static void trace(String stage, Map<String, Object?> fields) {
    final parts =
        fields.entries.map((e) => '${e.key}=${e.value ?? ''}').join(' ');
    debugPrint('[M39-ALERTA-CANCELAMENTO] $stage $parts');
  }

  static String prefsKey(String storeId, String uid) =>
      '$_prefsPrefix${storeId.trim()}_${uid.trim()}';

  static Future<Set<String>> loadPersistedDisplayed({
    required String storeId,
    required String uid,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(prefsKey(storeId, uid)) ?? const [];
      return raw.where((e) => e.trim().isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> persistDisplayed({
    required String storeId,
    required String uid,
    required String notificationId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefsKey(storeId, uid);
      final list = List<String>.from(prefs.getStringList(key) ?? const []);
      if (!list.contains(notificationId)) {
        list.add(notificationId);
        while (list.length > 200) {
          list.removeAt(0);
        }
        await prefs.setStringList(key, list);
      }
    } catch (_) {}
  }

  @visibleForTesting
  static Future<void> clearPersistedForTest({
    required String storeId,
    required String uid,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey(storeId, uid));
  }

  /// Primeira carga da sessão: marca IDs atuais como baseline (sem alertar).
  void seedBaseline(Iterable<String> ids) {
    if (baselineSeeded) return;
    baselineIds.addAll(ids.where((e) => e.trim().isNotEmpty));
    baselineSeeded = true;
    trace('baseline_seeded', {'count': baselineIds.length});
  }

  /// Retorna true se deve mostrar o alerta uma vez.
  bool shouldShow({
    required String notificationId,
    required String sessionUid,
    required String destinatarioUid,
    required String tipoName,
    Set<String> persistedDisplayed = const {},
  }) {
    final id = notificationId.trim();
    final uid = sessionUid.trim();
    final dest = destinatarioUid.trim();
    final tipo = tipoName.trim();

    if (tipo != tipoVendaCancelada) {
      trace('skip_tipo', {'notification_id': id, 'tipo': tipo});
      return false;
    }
    if (uid.isEmpty || dest.isEmpty || dest != uid) {
      trace('skip_destinatario', {
        'notification_id': id,
        'current_uid': uid,
        'destinatario_uid': dest,
      });
      return false;
    }
    if (id.isEmpty) return false;

    if (sessionShown.contains(id)) {
      trace('dedupe_hit', {
        'notification_id': id,
        'scope': 'session',
      });
      return false;
    }
    if (persistedDisplayed.contains(id)) {
      trace('dedupe_hit', {
        'notification_id': id,
        'scope': 'persisted',
      });
      return false;
    }
    if (baselineSeeded && baselineIds.contains(id)) {
      trace('skip_baseline', {'notification_id': id});
      return false;
    }

    trace('is_new', {
      'notification_id': id,
      'destinatario_uid': dest,
      'is_new': true,
    });
    return true;
  }

  void markShown(String notificationId) {
    final id = notificationId.trim();
    if (id.isEmpty) return;
    sessionShown.add(id);
    baselineIds.add(id);
  }

  static String buildTitulo() => 'Venda cancelada';

  static String buildMensagem({
    required String vendaId,
    String? motivo,
  }) {
    final label = vendaId.trim().isEmpty ? '—' : vendaId.trim();
    final motivoTrim = (motivo ?? '').trim();
    final buf = StringBuffer(
      'A venda $label foi cancelada pelo administrador.',
    );
    if (motivoTrim.isNotEmpty) {
      buf.write('\nMotivo: $motivoTrim');
    }
    return buf.toString();
  }
}
