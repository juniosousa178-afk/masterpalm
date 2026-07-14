// Classificação de erros Firestore no client (M3.8 S2-R2).
// Sem alterar Rules ou engines.

import 'package:cloud_firestore/cloud_firestore.dart';

enum FirestoreClientErrorKind {
  permissionDenied,
  failedPrecondition,
  unavailable,
  other,
}

FirestoreClientErrorKind classifyFirestoreClientError(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return FirestoreClientErrorKind.permissionDenied;
      case 'failed-precondition':
        return FirestoreClientErrorKind.failedPrecondition;
      case 'unavailable':
        return FirestoreClientErrorKind.unavailable;
      default:
        return FirestoreClientErrorKind.other;
    }
  }
  final s = error.toString().toLowerCase();
  if (s.contains('permission-denied') ||
      s.contains('permission_denied') ||
      s.contains('insufficient permissions')) {
    return FirestoreClientErrorKind.permissionDenied;
  }
  if (s.contains('failed-precondition') || s.contains('failed_precondition')) {
    return FirestoreClientErrorKind.failedPrecondition;
  }
  if (s.contains('unavailable')) {
    return FirestoreClientErrorKind.unavailable;
  }
  return FirestoreClientErrorKind.other;
}

bool isFirestorePermissionDenied(Object error) =>
    classifyFirestoreClientError(error) ==
    FirestoreClientErrorKind.permissionDenied;

bool isFirestoreFailedPrecondition(Object error) =>
    classifyFirestoreClientError(error) ==
    FirestoreClientErrorKind.failedPrecondition;

bool isFirestoreUnavailable(Object error) =>
    classifyFirestoreClientError(error) == FirestoreClientErrorKind.unavailable;
