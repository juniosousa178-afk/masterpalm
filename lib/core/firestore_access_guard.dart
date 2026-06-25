// Bloqueio defensivo de acesso Firestore (testes de importação offline).

import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreAccessGuard {
  FirestoreAccessGuard._();

  static bool forbidAccess = false;
  static int accessCount = 0;

  static void resetForTests() {
    forbidAccess = false;
    accessCount = 0;
  }

  static FirebaseFirestore resolve({
    FirebaseFirestore? override,
    FirebaseFirestore? fallback,
  }) {
    if (forbidAccess) {
      throw StateError('Firestore proibido neste fluxo');
    }
    accessCount++;
    return override ?? fallback ?? FirebaseFirestore.instance;
  }
}
