import 'package:cloud_firestore/cloud_firestore.dart';

/// Piloto da visão financeira por loja. Não usa a flag do espelho de contas a pagar.
///
/// `readOnly` no documento é o alias legado de [dashboardReadOnly]: os cartões
/// e os gráficos não gravam. `operationalHubEnabled` só libera navegação para
/// telas que já gravam. Ausente ou falso mantém o painel sem o hub.
class FinancialDashboardPilot {
  const FinancialDashboardPilot({
    required this.enabled,
    required this.readOnly,
    this.operationalHubEnabled = false,
  });

  static const disabled = FinancialDashboardPilot(enabled: false, readOnly: true);

  static const documentId = 'dashboard';

  final bool enabled;

  /// Alias persistido de dashboardReadOnly. O painel não grava.
  final bool readOnly;

  /// Navegação para módulos operacionais existentes. Não é um writer novo.
  final bool operationalHubEnabled;

  bool get dashboardReadOnly => readOnly;

  bool get showReadOnlyDashboard => enabled && readOnly;

  bool get showOperationalHub => showReadOnlyDashboard && operationalHubEnabled;
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
  final hasDashboardReadOnly = data.containsKey('dashboardReadOnly');
  final hasLegacyReadOnly = data.containsKey('readOnly');
  if (hasDashboardReadOnly &&
      hasLegacyReadOnly &&
      ((data['dashboardReadOnly'] == true) != (data['readOnly'] == true))) {
    return FinancialDashboardPilot.disabled;
  }
  final dashboardReadOnly = hasDashboardReadOnly
      ? data['dashboardReadOnly'] == true
      : data['readOnly'] == true;
  if (!enabled || !dashboardReadOnly) return FinancialDashboardPilot.disabled;
  return FinancialDashboardPilot(
    enabled: true,
    readOnly: true,
    operationalHubEnabled: data['operationalHubEnabled'] == true,
  );
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
