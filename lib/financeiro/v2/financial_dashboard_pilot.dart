import 'package:cloud_firestore/cloud_firestore.dart';

/// Piloto da visão financeira por loja. Não usa a flag do espelho de contas a pagar.
class FinancialDashboardPilot {
  const FinancialDashboardPilot({
    required this.enabled,
    required this.readOnly,
  });

  static const disabled = FinancialDashboardPilot(enabled: false, readOnly: true);

  static const documentId = 'dashboard';

  final bool enabled;
  final bool readOnly;

  bool get showReadOnlyDashboard => enabled && readOnly;
}

/// Documento ausente, loja diferente ou leitura que não é só de leitura
/// mantêm o Financeiro antigo.
FinancialDashboardPilot financialDashboardPilotFromMap({
  required String storeId,
  Map<String, dynamic>? data,
}) {
  final expected = storeId.trim();
  if (expected.isEmpty || data == null) return FinancialDashboardPilot.disabled;
  final docStore = (data['storeId'] ?? '').toString().trim();
  if (docStore != expected) return FinancialDashboardPilot.disabled;
  final enabled = data['financialV2Enabled'] == true;
  final readOnly = data['readOnly'] == true;
  if (!enabled || !readOnly) return FinancialDashboardPilot.disabled;
  return const FinancialDashboardPilot(enabled: true, readOnly: true);
}

Future<FinancialDashboardPilot> readFinancialDashboardPilot({
  required String storeId,
  required Future<Map<String, dynamic>?> Function() load,
  Duration timeout = const Duration(seconds: 4),
}) async {
  try {
    final data = await load().timeout(timeout);
    return financialDashboardPilotFromMap(storeId: storeId, data: data);
  } catch (_) {
    return FinancialDashboardPilot.disabled;
  }
}

abstract class FinancialDashboardPilotSource {
  Future<FinancialDashboardPilot> read(String storeId);
}

class FirestoreFinancialDashboardPilotSource
    implements FinancialDashboardPilotSource {
  FirestoreFinancialDashboardPilotSource({
    FirebaseFirestore? firestore,
    this.timeout = const Duration(seconds: 4),
  }) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final Duration timeout;

  @override
  Future<FinancialDashboardPilot> read(String storeId) {
    final db = _firestore ?? FirebaseFirestore.instance;
    return readFinancialDashboardPilot(
      storeId: storeId,
      timeout: timeout,
      load: () async {
        final snap = await db
            .collection('lojas')
            .doc(storeId)
            .collection('financial_v2_pilot')
            .doc(FinancialDashboardPilot.documentId)
            .get();
        if (!snap.exists) return null;
        return snap.data();
      },
    );
  }
}
