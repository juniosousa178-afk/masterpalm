// Coordenação remota de intenção de venda (M3.2-A) — sem baixa de estoque.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Status persistido em `lojas/{lojaId}/sale_intents/{saleIntentId}`.
enum SaleIntentStatus {
  reserved('reserved'),
  stockApplied('stock_applied'),
  salePersisted('sale_persisted'),
  completed('completed'),
  reverted('reverted'),
  critical('critical');

  const SaleIntentStatus(this.wireValue);
  final String wireValue;

  static SaleIntentStatus? parse(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    for (final s in SaleIntentStatus.values) {
      if (s.wireValue == v) return s;
    }
    return null;
  }

  bool get isTerminal =>
      this == completed || this == reverted || this == critical;
}

enum SaleIntentReserveStatus {
  created,
  joined,
}

/// Origens allowlisted (callers reais).
abstract final class SaleIntentOrigins {
  static const pdvManual = 'pdv_manual';
  static const orderReview = 'order_review';
  static const prePedido = 'pre_pedido';

  static const allowlist = <String>{
    pdvManual,
    orderReview,
    prePedido,
  };
}

class SaleIntentReservation {
  const SaleIntentReservation({
    required this.saleIntentId,
    required this.operationId,
    required this.stockEffectHash,
    required this.origin,
    required this.status,
    required this.reserveStatus,
    required this.lojaId,
  });

  final String saleIntentId;
  final String operationId;
  final String stockEffectHash;
  final String origin;
  final SaleIntentStatus status;
  final SaleIntentReserveStatus reserveStatus;
  final String lojaId;
}

class SaleIntentIdentityConflictException implements Exception {
  SaleIntentIdentityConflictException(this.message);
  final String message;
  @override
  String toString() => 'SaleIntentIdentityConflictException: $message';
}

class SaleIntentInvalidStateTransitionException implements Exception {
  SaleIntentInvalidStateTransitionException(this.message);
  final String message;
  @override
  String toString() =>
      'SaleIntentInvalidStateTransitionException: $message';
}

class SaleIntentInvalidSchemaException implements Exception {
  SaleIntentInvalidSchemaException(this.message);
  final String message;
  @override
  String toString() => 'SaleIntentInvalidSchemaException: $message';
}

class SaleIntentCriticalStateException implements Exception {
  SaleIntentCriticalStateException(this.message);
  final String message;
  @override
  String toString() => 'SaleIntentCriticalStateException: $message';
}

abstract final class SaleIntentService {
  SaleIntentService._();

  static const protocolVersion = 1;

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  @visibleForTesting
  static void debugClearOverride() {
    debugFirestoreOverride = null;
    debugThrowOnComplete = false;
  }

  @visibleForTesting
  static bool debugThrowOnComplete = false;

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _intentRef(
    String lojaId,
    String saleIntentId,
  ) {
    return _db
        .collection('lojas')
        .doc(lojaId.trim())
        .collection('sale_intents')
        .doc(saleIntentId.trim());
  }

  static void _validateInputs({
    required String lojaId,
    required String saleIntentId,
    required String origin,
    required String stockEffectHash,
  }) {
    if (lojaId.trim().isEmpty) {
      throw ArgumentError.value(lojaId, 'lojaId', 'obrigatório');
    }
    if (saleIntentId.trim().isEmpty) {
      throw ArgumentError.value(saleIntentId, 'saleIntentId', 'obrigatório');
    }
    if (!SaleIntentOrigins.allowlist.contains(origin.trim())) {
      throw ArgumentError.value(origin, 'origin', 'origem não allowlisted');
    }
    if (stockEffectHash.trim().isEmpty) {
      throw ArgumentError.value(
        stockEffectHash,
        'stockEffectHash',
        'obrigatório',
      );
    }
  }

  static SaleIntentReservation _parseReservation({
    required Map<String, dynamic> data,
    required String lojaId,
    required String saleIntentId,
    required SaleIntentReserveStatus reserveStatus,
  }) {
    final protocol = (data['protocolVersion'] as num?)?.toInt();
    if (protocol != protocolVersion) {
      throw SaleIntentInvalidSchemaException(
        'protocolVersion inválido para $saleIntentId.',
      );
    }
    final docLoja = (data['lojaId'] ?? '').toString().trim();
    final docIntent = (data['saleIntentId'] ?? '').toString().trim();
    final opId = (data['operationId'] ?? '').toString().trim();
    final hash = (data['stockEffectHash'] ?? '').toString().trim();
    final origin = (data['origin'] ?? '').toString().trim();
    final status = SaleIntentStatus.parse(data['status']?.toString());
    if (docLoja != lojaId.trim() ||
        docIntent != saleIntentId.trim() ||
        opId.isEmpty ||
        hash.isEmpty ||
        origin.isEmpty ||
        status == null) {
      throw SaleIntentInvalidSchemaException(
        'Schema remoto inválido para saleIntentId=$saleIntentId.',
      );
    }
    return SaleIntentReservation(
      saleIntentId: docIntent,
      operationId: opId,
      stockEffectHash: hash,
      origin: origin,
      status: status,
      reserveStatus: reserveStatus,
      lojaId: docLoja,
    );
  }

  static void _assertJoinCompatible({
    required Map<String, dynamic> data,
    required String lojaId,
    required String saleIntentId,
    required String origin,
    required String stockEffectHash,
  }) {
    final reservation = _parseReservation(
      data: data,
      lojaId: lojaId,
      saleIntentId: saleIntentId,
      reserveStatus: SaleIntentReserveStatus.joined,
    );
    if (reservation.stockEffectHash != stockEffectHash.trim()) {
      throw SaleIntentIdentityConflictException(
        'stockEffectHash divergente para saleIntentId=$saleIntentId.',
      );
    }
    if (reservation.origin != origin.trim()) {
      throw SaleIntentIdentityConflictException(
        'origin divergente para saleIntentId=$saleIntentId.',
      );
    }
    if (reservation.status == SaleIntentStatus.critical) {
      throw SaleIntentCriticalStateException(
        'saleIntentId=$saleIntentId está em estado critical.',
      );
    }
  }

  /// Reserva remota ou junta intent existente compatível. Transacional.
  static Future<SaleIntentReservation> reserveOrJoin({
    required String lojaId,
    required String saleIntentId,
    required String origin,
    required String stockEffectHash,
  }) async {
    _validateInputs(
      lojaId: lojaId,
      saleIntentId: saleIntentId,
      origin: origin,
      stockEffectHash: stockEffectHash,
    );

    final loja = lojaId.trim();
    final intentId = saleIntentId.trim();
    final originNorm = origin.trim();
    final hashNorm = stockEffectHash.trim();
    final ref = _intentRef(loja, intentId);

    return _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      if (!snap.exists) {
        final operationId = const Uuid().v4();
        final payload = <String, dynamic>{
          'protocolVersion': protocolVersion,
          'saleIntentId': intentId,
          'lojaId': loja,
          'origin': originNorm,
          'operationId': operationId,
          'status': SaleIntentStatus.reserved.wireValue,
          'stockEffectHash': hashNorm,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        transaction.set(ref, payload);
        return SaleIntentReservation(
          saleIntentId: intentId,
          operationId: operationId,
          stockEffectHash: hashNorm,
          origin: originNorm,
          status: SaleIntentStatus.reserved,
          reserveStatus: SaleIntentReserveStatus.created,
          lojaId: loja,
        );
      }

      final data = snap.data() ?? {};
      _assertJoinCompatible(
        data: data,
        lojaId: loja,
        saleIntentId: intentId,
        origin: originNorm,
        stockEffectHash: hashNorm,
      );
      final parsed = _parseReservation(
        data: data,
        lojaId: loja,
        saleIntentId: intentId,
        reserveStatus: SaleIntentReserveStatus.joined,
      );
      if (parsed.status == SaleIntentStatus.reverted) {
        transaction.update(ref, {
          'status': SaleIntentStatus.reserved.wireValue,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return SaleIntentReservation(
          saleIntentId: intentId,
          operationId: parsed.operationId,
          stockEffectHash: hashNorm,
          origin: originNorm,
          status: SaleIntentStatus.reserved,
          reserveStatus: SaleIntentReserveStatus.joined,
          lojaId: loja,
        );
      }
      return parsed;
    });
  }

  static const _allowedTransitions = <SaleIntentStatus, Set<SaleIntentStatus>>{
    SaleIntentStatus.reserved: {
      SaleIntentStatus.stockApplied,
      SaleIntentStatus.reverted,
      SaleIntentStatus.critical,
    },
    SaleIntentStatus.stockApplied: {
      SaleIntentStatus.salePersisted,
      SaleIntentStatus.reverted,
      SaleIntentStatus.critical,
    },
    SaleIntentStatus.salePersisted: {
      SaleIntentStatus.completed,
      SaleIntentStatus.critical,
    },
  };

  static Future<SaleIntentReservation> _transition({
    required String lojaId,
    required String saleIntentId,
    required String expectedOperationId,
    required SaleIntentStatus targetStatus,
  }) async {
    final loja = lojaId.trim();
    final intentId = saleIntentId.trim();
    final opExpected = expectedOperationId.trim();
    if (loja.isEmpty || intentId.isEmpty || opExpected.isEmpty) {
      throw ArgumentError('lojaId, saleIntentId e operationId obrigatórios.');
    }

    final ref = _intentRef(loja, intentId);
    return _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      if (!snap.exists) {
        throw SaleIntentInvalidSchemaException(
          'saleIntentId=$intentId não encontrado.',
        );
      }
      final data = snap.data() ?? {};
      final current = _parseReservation(
        data: data,
        lojaId: loja,
        saleIntentId: intentId,
        reserveStatus: SaleIntentReserveStatus.joined,
      );
      if (current.operationId != opExpected) {
        throw SaleIntentIdentityConflictException(
          'operationId divergente para saleIntentId=$intentId.',
        );
      }
      if (current.status.isTerminal) {
        throw SaleIntentInvalidStateTransitionException(
          'Transição proibida a partir de ${current.status.wireValue}.',
        );
      }
      final allowed = _allowedTransitions[current.status];
      if (allowed == null || !allowed.contains(targetStatus)) {
        throw SaleIntentInvalidStateTransitionException(
          'Transição ${current.status.wireValue} → ${targetStatus.wireValue} proibida.',
        );
      }

      final update = <String, dynamic>{
        'status': targetStatus.wireValue,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (targetStatus == SaleIntentStatus.completed) {
        update['completedAt'] = FieldValue.serverTimestamp();
      }
      transaction.update(ref, update);

      return SaleIntentReservation(
        saleIntentId: intentId,
        operationId: current.operationId,
        stockEffectHash: current.stockEffectHash,
        origin: current.origin,
        status: targetStatus,
        reserveStatus: SaleIntentReserveStatus.joined,
        lojaId: loja,
      );
    });
  }

  static Future<SaleIntentReservation> markStockApplied({
    required String lojaId,
    required String saleIntentId,
    required String operationId,
  }) =>
      _transition(
        lojaId: lojaId,
        saleIntentId: saleIntentId,
        expectedOperationId: operationId,
        targetStatus: SaleIntentStatus.stockApplied,
      );

  static Future<SaleIntentReservation> markSalePersisted({
    required String lojaId,
    required String saleIntentId,
    required String operationId,
  }) =>
      _transition(
        lojaId: lojaId,
        saleIntentId: saleIntentId,
        expectedOperationId: operationId,
        targetStatus: SaleIntentStatus.salePersisted,
      );

  static Future<SaleIntentReservation> complete({
    required String lojaId,
    required String saleIntentId,
    required String operationId,
  }) async {
    if (debugThrowOnComplete) {
      throw Exception('sale intent complete simulado para teste');
    }
    return _transition(
      lojaId: lojaId,
      saleIntentId: saleIntentId,
      expectedOperationId: operationId,
      targetStatus: SaleIntentStatus.completed,
    );
  }

  static Future<SaleIntentReservation> revert({
    required String lojaId,
    required String saleIntentId,
    required String operationId,
  }) =>
      _transition(
        lojaId: lojaId,
        saleIntentId: saleIntentId,
        expectedOperationId: operationId,
        targetStatus: SaleIntentStatus.reverted,
      );

  static Future<SaleIntentReservation> markCritical({
    required String lojaId,
    required String saleIntentId,
    required String operationId,
  }) =>
      _transition(
        lojaId: lojaId,
        saleIntentId: saleIntentId,
        expectedOperationId: operationId,
        targetStatus: SaleIntentStatus.critical,
      );
}
