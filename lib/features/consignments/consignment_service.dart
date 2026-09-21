import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'consignment_eligibility.dart';
import 'consignment_errors.dart';
import 'consignment_models.dart';
import 'consignment_validation.dart';

class ConsignmentService {
  ConsignmentService._();

  @visibleForTesting
  static Future<Map<String, dynamic>> Function(
      String name, Map<String, dynamic> data)? debugTransport;

  @visibleForTesting
  static Future<List<ConnectivityResult>> Function()? debugConnectivity;

  @visibleForTesting
  static FirebaseFirestore? debugFirestore;

  @visibleForTesting
  static List<ConsignmentPickerItem>? debugPickerItems;

  static bool _issueInFlight = false;
  static bool _settleInFlight = false;
  static bool _addItemsInFlight = false;

  static bool get issueInFlight => _issueInFlight;
  static bool get settleInFlight => _settleInFlight;
  static bool get addItemsInFlight => _addItemsInFlight;

  static FirebaseFirestore get _db =>
      debugFirestore ?? FirebaseFirestore.instance;

  static Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    if (debugTransport != null) return debugTransport!(name, data);
    final result =
        await FirebaseFunctions.instanceFor(region: 'southamerica-east1')
            .httpsCallable(name)
            .call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data);
  }

  static Future<void> _requireOnline() async {
    try {
      final result = debugConnectivity != null
          ? await debugConnectivity!()
          : await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.none) || result.isEmpty) {
        throw ConsignmentException.network();
      }
    } on ConsignmentException {
      rethrow;
    } catch (_) {
      // Connectivity plugin failure is not proof of being online; issue/settle still require the callable.
    }
  }

  static Future<Map<String, dynamic>> command({
    required String lojaId,
    required String operation,
    required String operationId,
    String? consignmentId,
    Map<String, dynamic> payload = const {},
    bool requireOnline = false,
  }) async {
    if (requireOnline) await _requireOnline();
    final raw = <String, dynamic>{
      'protocolVersion': 1,
      'lojaId': lojaId.trim(),
      'operation': operation,
      'operationId': operationId.trim(),
      if (consignmentId != null) 'consignmentId': consignmentId.trim(),
      'payload': payload,
    };
    final payloadSafe =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)) as Map);
    try {
      return await _call('consignmentCommand', payloadSafe);
    } on FirebaseFunctionsException catch (e) {
      throw ConsignmentException.fromCallable(e.code, e.message, e.details);
    }
  }

  static String newId() => const Uuid().v4();

  static Future<Map<String, dynamic>> createReseller({
    required String lojaId,
    required String displayName,
    String notes = '',
    String phone = '',
  }) {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      throw const ConsignmentException(
          'INVALID_ARGUMENT', 'Informe o nome do revendedor.');
    }
    final id = newId();
    return command(
      lojaId: lojaId,
      operation: 'createReseller',
      operationId: 'reseller_$id',
      payload: {
        'resellerId': id,
        'displayName': trimmed,
        'notes': notes.trim(),
        if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      },
    );
  }

  static Future<Map<String, dynamic>> createDraft({
    required String lojaId,
    required String consignmentId,
    required String resellerId,
    required List<ConsignmentDraftLine> lines,
    String notes = '',
  }) {
    return command(
      lojaId: lojaId,
      operation: 'createDraft',
      operationId: 'draft_$consignmentId',
      consignmentId: consignmentId,
      payload: {
        'resellerId': resellerId,
        'notes': notes,
        'lines': lines.map((e) => e.toPayload()).toList(),
      },
    );
  }

  static Future<Map<String, dynamic>> updateDraft({
    required String lojaId,
    required String consignmentId,
    required String resellerId,
    required List<ConsignmentDraftLine> lines,
    String notes = '',
  }) {
    return command(
      lojaId: lojaId,
      operation: 'updateDraft',
      operationId: 'upd_${newId()}',
      consignmentId: consignmentId,
      payload: {
        'resellerId': resellerId,
        'notes': notes,
        'lines': lines.map((e) => e.toPayload()).toList(),
      },
    );
  }

  static Future<Map<String, dynamic>> cancelDraft({
    required String lojaId,
    required String consignmentId,
  }) {
    return command(
      lojaId: lojaId,
      operation: 'cancelDraft',
      operationId: 'cancel_$consignmentId',
      consignmentId: consignmentId,
    );
  }

  static Future<Map<String, dynamic>> issue({
    required String lojaId,
    required String consignmentId,
    String? operationId,
  }) async {
    if (_issueInFlight) {
      throw const ConsignmentException(
          'IN_FLIGHT', 'Aguarde a confirmação da saída em consignação.');
    }
    _issueInFlight = true;
    try {
      return await command(
        lojaId: lojaId,
        operation: 'issue',
        operationId: (operationId ?? 'issue_$consignmentId').trim(),
        consignmentId: consignmentId,
        requireOnline: true,
      );
    } finally {
      _issueInFlight = false;
    }
  }

  static Future<Map<String, dynamic>> settle({
    required String lojaId,
    required String consignmentId,
    required List<Map<String, dynamic>> lines,
    String? operationId,
  }) async {
    if (_settleInFlight) {
      throw const ConsignmentException(
          'IN_FLIGHT', 'Aguarde a confirmação do acerto.');
    }
    _settleInFlight = true;
    try {
      return await command(
        lojaId: lojaId,
        operation: 'settle',
        operationId: (operationId ?? 'settle_$consignmentId').trim(),
        consignmentId: consignmentId,
        payload: {'lines': lines},
        requireOnline: true,
      );
    } finally {
      _settleInFlight = false;
    }
  }

  static Future<Map<String, dynamic>> addItems({
    required String lojaId,
    required String consignmentId,
    required int expectedRevision,
    required List<ConsignmentDraftLine> lines,
    String? operationId,
  }) async {
    if (_addItemsInFlight) {
      throw const ConsignmentException(
          'IN_FLIGHT', 'Aguarde a confirmação do acréscimo.');
    }
    _addItemsInFlight = true;
    try {
      return await command(
        lojaId: lojaId,
        operation: 'addItems',
        operationId: (operationId ?? 'add_${newId()}').trim(),
        consignmentId: consignmentId,
        payload: {
          'expectedRevision': expectedRevision,
          'lines': lines.map((e) => e.toPayload()).toList(),
        },
        requireOnline: true,
      );
    } finally {
      _addItemsInFlight = false;
    }
  }

  static Stream<List<ConsignmentDoc>> watchConsignments(String lojaId) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('consignments')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => ConsignmentDoc.fromMap(d.id, d.data()))
          .where((c) => c.storeId == lojaId || c.storeId.isEmpty)
          .toList();
      list.sort((a, b) {
        final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db_ = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db_.compareTo(da);
      });
      return list;
    });
  }

  static Future<ConsignmentDoc?> getConsignment(String lojaId, String id) async {
    final snap = await _db
        .collection('lojas')
        .doc(lojaId)
        .collection('consignments')
        .doc(id)
        .get();
    if (!snap.exists) return null;
    return ConsignmentDoc.fromMap(snap.id, snap.data() ?? {});
  }

  static Future<List<ConsignmentPickerItem>> loadPickerProducts(String lojaId) async {
    if (debugPickerItems != null) return List.of(debugPickerItems!);
    final res = await command(
      lojaId: lojaId,
      operation: 'listEligibleProducts',
      operationId: 'picker_${newId()}',
      requireOnline: true,
    );
    final raw = res['products'];
    if (raw is! List) return const [];
    final items = raw.whereType<Map>().map((row) {
      final data = Map<String, dynamic>.from(row);
      final variacoes = data['variacoes'] is Map
          ? Map<String, dynamic>.from(data['variacoes'] as Map)
          : <String, dynamic>{};
      final eligible = data['eligible'] != false;
      final productCode = (data['productCode'] ??
              data['codigoBarras'] ??
              data['sku'] ??
              '')
          .toString()
          .trim();
      return ConsignmentPickerItem(
        productId: (data['productId'] ?? '').toString(),
        name: (data['name'] ?? data['productId'] ?? '').toString(),
        productCode: productCode,
        price: (data['price'] is num) ? (data['price'] as num).toDouble() : 0,
        availableQty: data['availableQty'] is num ? (data['availableQty'] as num).toInt() : 0,
        stockKind: (data['stockKind'] ?? 'simple').toString(),
        variacoes: variacoes,
        eligible: eligible,
        unavailableReason: eligible
            ? ''
            : (data['unavailableReason'] ?? '0 disponíveis para consignação').toString(),
      );
    }).where((e) => e.productId.isNotEmpty).toList();
    return _enrichPickerProductCodes(lojaId, items);
  }

  /// Fills missing codes from authoritative stock `codigoBarras` (search UX).
  static Future<List<ConsignmentPickerItem>> _enrichPickerProductCodes(
    String lojaId,
    List<ConsignmentPickerItem> items,
  ) async {
    if (items.isEmpty) return items;
    if (items.every((e) => e.productCode.trim().isNotEmpty)) return items;
    try {
      final snap =
          await _db.collection('lojas').doc(lojaId).collection('estoque_produtos').get();
      final codes = <String, String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final code = consignmentProductCodeFromMaps(null, data);
        if (code.isNotEmpty) codes[doc.id] = code;
      }
      return items
          .map((e) {
            if (e.productCode.trim().isNotEmpty) return e;
            final code = codes[e.productId];
            if (code == null || code.isEmpty) return e;
            return e.copyWith(productCode: code);
          })
          .toList();
    } catch (_) {
      return items;
    }
  }

  static Stream<List<ConsignmentReseller>> watchResellers(String lojaId) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('consignment_resellers')
        .snapshots()
        .map((snap) => consignmentActiveResellersForStore(
              lojaId: lojaId,
              items: snap.docs
                  .map((d) => ConsignmentReseller.fromMap(d.id, d.data()))
                  .toList(),
            ));
  }
}
