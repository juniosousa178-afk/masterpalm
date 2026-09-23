import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:cloud_functions/cloud_functions.dart';
import 'diagnostic_enums.dart';
import 'diagnostic_user_messages.dart';

class ClassifiedDiagnosticError {
  ClassifiedDiagnosticError({
    required this.classification,
    required this.severity,
    required this.rootCauseStatus,
    required this.userTitle,
    required this.userMessage,
    required this.safeNextAction,
    this.technicalMessage,
    this.firebaseCode,
    this.httpCode,
    this.functionName,
  });

  final String classification;
  final DiagnosticSeverity severity;
  final DiagnosticRootCauseStatus rootCauseStatus;
  final String userTitle;
  final String userMessage;
  final String safeNextAction;
  final String? technicalMessage;
  final String? firebaseCode;
  final int? httpCode;
  final String? functionName;
}

/// Maps exceptions / anomaly codes → structured classification.
/// CONFIRMED only when deterministic evidence exists in the error itself.
class DiagnosticErrorClassifier {
  DiagnosticErrorClassifier._();

  static ClassifiedDiagnosticError classify(
    Object error, {
    StackTrace? stack,
    String? hintClassification,
    bool online = true,
  }) {
    if (hintClassification != null &&
        DiagnosticClassification.allKnown.contains(hintClassification)) {
      return _fromCode(hintClassification, error);
    }

    if (!online) {
      return _fromCode(DiagnosticClassification.networkOffline, error);
    }

    if (error is FirebaseFunctionsException) {
      final code = error.code;
      final details = error.details;
      if (code == 'permission-denied') {
        return _fromCode(
          DiagnosticClassification.firebasePermissionDenied,
          error,
          firebaseCode: code,
          confirmed: true,
        );
      }
      if (code == 'failed-precondition') {
        final detailStr = details?.toString() ?? error.message ?? '';
        if (detailStr.toLowerCase().contains('already') &&
            detailStr.toLowerCase().contains('restor')) {
          return _fromCode(
            DiagnosticClassification.saleRestoreAlreadyApplied,
            error,
            firebaseCode: code,
            confirmed: true,
          );
        }
        return _fromCode(
          DiagnosticClassification.firebaseFailedPrecondition,
          error,
          firebaseCode: code,
          confirmed: true,
        );
      }
      if (code == 'unavailable' || code == 'deadline-exceeded') {
        return _fromCode(
          code == 'deadline-exceeded'
              ? DiagnosticClassification.functionTimeout
              : DiagnosticClassification.firebaseUnavailable,
          error,
          firebaseCode: code,
          confirmed: true,
        );
      }
      return _fromCode(
        DiagnosticClassification.unknownError,
        error,
        firebaseCode: code,
        confirmed: false,
      );
    }

    if (error is FirebaseException) {
      final code = error.code;
      if (code == 'permission-denied') {
        return _fromCode(
          DiagnosticClassification.firebasePermissionDenied,
          error,
          firebaseCode: code,
          confirmed: true,
        );
      }
      if (code == 'unavailable') {
        return _fromCode(
          DiagnosticClassification.firebaseUnavailable,
          error,
          firebaseCode: code,
          confirmed: true,
        );
      }
      if (code == 'failed-precondition') {
        return _fromCode(
          DiagnosticClassification.firebaseFailedPrecondition,
          error,
          firebaseCode: code,
          confirmed: true,
        );
      }
    }

    final msg = error.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused')) {
      return _fromCode(
        DiagnosticClassification.networkOffline,
        error,
        confirmed: true,
      );
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return _fromCode(
        DiagnosticClassification.functionTimeout,
        error,
        confirmed: false,
      );
    }

    return _fromCode(
      DiagnosticClassification.unknownError,
      error,
      confirmed: false,
    );
  }

  static ClassifiedDiagnosticError fromAnomalyCode(
    String classification, {
    String? technicalMessage,
    DiagnosticSeverity? severityOverride,
  }) {
    final base = _fromCode(classification, technicalMessage ?? classification);
    if (severityOverride != null) {
      return ClassifiedDiagnosticError(
        classification: base.classification,
        severity: severityOverride,
        rootCauseStatus: base.rootCauseStatus,
        userTitle: base.userTitle,
        userMessage: base.userMessage,
        safeNextAction: base.safeNextAction,
        technicalMessage: technicalMessage ?? base.technicalMessage,
        firebaseCode: base.firebaseCode,
        httpCode: base.httpCode,
        functionName: base.functionName,
      );
    }
    return base;
  }

  static ClassifiedDiagnosticError _fromCode(
    String code,
    Object error, {
    String? firebaseCode,
    bool confirmed = false,
  }) {
    final copy = DiagnosticUserMessages.forClassification(code);
    final root = confirmed
        ? DiagnosticRootCauseStatus.confirmed
        : (DiagnosticClassification.allKnown.contains(code) &&
                code != DiagnosticClassification.unknownError)
            ? DiagnosticRootCauseStatus.classifiedNotConfirmed
            : DiagnosticRootCauseStatus.unknown;

    DiagnosticSeverity severity = DiagnosticSeverity.warning;
    if (code == DiagnosticClassification.unknownError ||
        code == DiagnosticClassification.firebasePermissionDenied ||
        code == DiagnosticClassification.salePersistAfterStockFailure ||
        code == DiagnosticClassification.stockOrphanPending) {
      severity = DiagnosticSeverity.critical;
    }
    if (code == DiagnosticClassification.saleRestoreAlreadyApplied ||
        code == DiagnosticClassification.networkOffline) {
      severity = DiagnosticSeverity.warning;
    }

    return ClassifiedDiagnosticError(
      classification: code,
      severity: severity,
      rootCauseStatus: root,
      userTitle: copy.title,
      userMessage: copy.message,
      safeNextAction: copy.safeNextAction,
      technicalMessage: error.toString().length > 500
          ? '${error.toString().substring(0, 500)}…'
          : error.toString(),
      firebaseCode: firebaseCode,
    );
  }
}
