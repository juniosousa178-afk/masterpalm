import 'package:cloud_firestore/cloud_firestore.dart';

/// Flag server-authoritative. Default false. Não libera globalmente.
class ConsignmentFeatureFlag {
  ConsignmentFeatureFlag._();

  static FirebaseFirestore? debugFirestore;

  static Future<bool> isEnabled(String lojaId) async {
    final id = lojaId.trim();
    if (id.isEmpty) return false;
    try {
      final db = debugFirestore ?? FirebaseFirestore.instance;
      final snap = await db
          .collection('lojas')
          .doc(id)
          .collection('consignment_control')
          .doc('state')
          .get();
      final data = snap.data();
      return snap.exists &&
          data?['moduleEnabled'] == true &&
          data?['protocolVersion'] == 1;
    } catch (_) {
      return false;
    }
  }
}
