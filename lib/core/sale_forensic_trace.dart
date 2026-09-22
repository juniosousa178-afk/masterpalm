// LOCAL-ONLY sale finalization forensic ring buffer.
// Never writes Firestore / Cloud Logging with PII.
// Does not flush pending, mutate stock, or change sale decisions.

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../models/produto.dart';
import 'client_build_identity.dart';
import 'produto_effective_stock.dart';
import 'produto_estoque_grade_snapshot.dart';

const int kSaleForensicMaxTraces = 20;
const String kSaleForensicHiveBox = 'sale_forensic_traces_v1';

/// Sensitive key substrings — values are redacted when serializing details.
const List<String> _kSecretKeyNeedles = [
  'authtoken',
  'refreshtoken',
  'apikey',
  'cookie',
  'password',
  'cliente',
  'customer',
  'cpf',
  'telefone',
  'phone',
  'pagamento',
  'payment',
  'card',
  'token',
];

/// Technical keys preserved in Firebase details when present.
const Set<String> _kTechnicalDetailKeys = {
  'reason',
  'productId',
  'code',
  'expectedRevision',
  'actualRevision',
  'stockKind',
  'variationKey',
  'size',
  'color',
  'availableQty',
  'requestedQty',
  'quantity',
  'operationId',
  'lojaId',
  'storeId',
  'stockRevision',
  'message',
};

/// Minimal stock snapshot for instance divergence (no PII).
Map<String, dynamic> produtoForensicMiniSnapshot(Produto p) {
  final cells =
      Map<String, int>.from(ProdutoEstoqueGradeSnapshot.fromProduto(p).cells);
  return {
    'productId': p.idFirebase,
    'qty': p.quantidade,
    'stockRevision': p.stockRevision,
    'stockOperationId': p.confirmedStockOperationId,
    'pendingOperationId': p.pendingStockOperationId,
    'stockKind': effectiveStockKindFromProduto(p).wire,
    'canonicalCells': cells,
  };
}

/// Sanitize Firebase / arbitrary details for local forensic storage.
dynamic sanitizeForensicDetails(dynamic raw) {
  if (raw == null) return null;
  if (raw is String) {
    return raw.length > 2000 ? '${raw.substring(0, 2000)}…' : raw;
  }
  if (raw is num || raw is bool) return raw;
  if (raw is List) {
    return raw.map(sanitizeForensicDetails).toList(growable: false);
  }
  if (raw is Map) {
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      final key = k.toString();
      final lower = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (_kSecretKeyNeedles.any(lower.contains)) {
        out[key] = 'REDACTED';
        return;
      }
      // Prefer technical allowlist when map looks like Firebase details;
      // still keep other non-secret keys for forensics.
      out[key] = sanitizeForensicDetails(v);
    });
    return out;
  }
  return raw.toString();
}

String forensicStackTop(StackTrace? st, {int maxLines = 8}) {
  if (st == null) return '';
  final lines = st
      .toString()
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .take(maxLines)
      .toList();
  return lines.join('\n');
}

/// One sale finalization attempt (ring-buffer entry).
class SaleForensicTrace {
  SaleForensicTrace({
    required this.saleTraceId,
    required this.startedAt,
    Map<String, dynamic>? buildProof,
    List<Map<String, dynamic>>? events,
  })  : buildProof = Map<String, dynamic>.from(
          buildProof ?? clientBuildProofMap(),
        ),
        events = List<Map<String, dynamic>>.from(events ?? const []);

  final String saleTraceId;
  final DateTime startedAt;
  final Map<String, dynamic> buildProof;
  final List<Map<String, dynamic>> events;

  String get shortCode {
    final id = saleTraceId.replaceAll('-', '');
    if (id.length <= 8) return id.toUpperCase();
    return id.substring(id.length - 8).toUpperCase();
  }

  void addEvent(String event, [Map<String, dynamic>? data]) {
    final row = <String, dynamic>{
      'event': event,
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    if (data != null) {
      final cleaned = sanitizeForensicDetails(data);
      if (cleaned is Map) {
        cleaned.forEach((k, v) {
          final key = k.toString();
          if (key == 'event' || key == 'at') return;
          row[key] = v;
        });
      }
    }
    events.add(row);
  }

  Map<String, dynamic> toJson() => {
        'SALE_TRACE_ID': saleTraceId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        ...buildProof,
        'events': List<Map<String, dynamic>>.from(events),
      };

  factory SaleForensicTrace.fromJson(Map<String, dynamic> json) {
    final eventsRaw = json['events'];
    final events = <Map<String, dynamic>>[];
    if (eventsRaw is List) {
      for (final e in eventsRaw) {
        if (e is Map) {
          events.add(Map<String, dynamic>.from(e));
        }
      }
    }
    final proof = <String, dynamic>{};
    for (final k in [
      'CLIENT_BUILD_ID',
      'CLIENT_GIT_COMMIT',
      'APP_VERSION',
    ]) {
      if (json[k] != null) proof[k] = json[k];
    }
    return SaleForensicTrace(
      saleTraceId: (json['SALE_TRACE_ID'] ?? '').toString(),
      startedAt: DateTime.tryParse((json['startedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      buildProof: proof.isEmpty ? null : proof,
      events: events,
    );
  }
}

/// Process + Hive-backed ring of the last [kSaleForensicMaxTraces] attempts.
class SaleForensicTraceStore {
  SaleForensicTraceStore._();

  static final Map<String, SaleForensicTrace> _byId = {};
  static final List<String> _order = [];
  static String? _activeTraceId;
  static bool _hiveHydrated = false;
  static bool _hiveReady = false;

  /// When true, skip Hive I/O (unit tests without Hive.init).
  @visibleForTesting
  static bool disableHive = false;

  /// Active attempt (UI → prep → callable).
  static String? get activeTraceId => _activeTraceId;

  static SaleForensicTrace? get active =>
      _activeTraceId == null ? null : _byId[_activeTraceId!];

  @visibleForTesting
  static void clearAll() {
    _byId.clear();
    _order.clear();
    _activeTraceId = null;
    _hiveHydrated = false;
    _hiveReady = false;
  }

  static Future<void> ensureHydrated() async {
    if (_hiveHydrated) return;
    _hiveHydrated = true;
    if (disableHive) return;
    try {
      if (!Hive.isBoxOpen(kSaleForensicHiveBox)) {
        await Hive.openBox(kSaleForensicHiveBox);
      }
      final box = Hive.box(kSaleForensicHiveBox);
      _hiveReady = true;
      final raw = box.get('traces');
      if (raw is List) {
        for (final item in raw) {
          Map<String, dynamic>? map;
          if (item is Map) {
            map = Map<String, dynamic>.from(item);
          } else if (item is String) {
            final decoded = jsonDecode(item);
            if (decoded is Map) map = Map<String, dynamic>.from(decoded);
          }
          if (map == null) continue;
          final t = SaleForensicTrace.fromJson(map);
          if (t.saleTraceId.isEmpty) continue;
          _upsertMemory(t);
        }
      }
    } catch (e) {
      _hiveReady = false;
      debugPrint(
        '[SALE-FORENSIC] hive hydrate skipped type=${e.runtimeType}',
      );
    }
  }

  static Future<void> _persist() async {
    if (disableHive || !_hiveReady) return;
    try {
      if (!Hive.isBoxOpen(kSaleForensicHiveBox)) {
        await Hive.openBox(kSaleForensicHiveBox);
      }
      final box = Hive.box(kSaleForensicHiveBox);
      final list = tracesNewestFirst
          .map((t) => t.toJson())
          .toList(growable: false);
      await box.put('traces', list);
    } catch (e) {
      debugPrint(
        '[SALE-FORENSIC] hive persist skipped type=${e.runtimeType}',
      );
    }
  }

  static void _upsertMemory(SaleForensicTrace t) {
    final id = t.saleTraceId;
    if (!_byId.containsKey(id)) {
      _order.add(id);
    }
    _byId[id] = t;
    while (_order.length > kSaleForensicMaxTraces) {
      final drop = _order.removeAt(0);
      _byId.remove(drop);
    }
  }

  /// Starts a new attempt. Dedupes by [saleTraceId] if provided again.
  static Future<SaleForensicTrace> start({
    String? saleTraceId,
    Map<String, dynamic>? initialPrep,
  }) async {
    await ensureHydrated();
    final id = (saleTraceId ?? '').trim().isEmpty
        ? const Uuid().v4()
        : saleTraceId!.trim();
    final existing = _byId[id];
    if (existing != null) {
      _activeTraceId = id;
      if (initialPrep != null) {
        existing.addEvent('SALE_PREP_START', initialPrep);
        await _persist();
      }
      return existing;
    }
    final t = SaleForensicTrace(
      saleTraceId: id,
      startedAt: DateTime.now().toUtc(),
    );
    if (initialPrep != null) {
      t.addEvent('SALE_PREP_START', initialPrep);
    } else {
      t.addEvent('SALE_TRACE_START');
    }
    _upsertMemory(t);
    _activeTraceId = id;
    await _persist();
    return t;
  }

  static void endActive() {
    _activeTraceId = null;
  }

  static void append(String event, [Map<String, dynamic>? data]) {
    final t = active;
    if (t == null) return;
    t.addEvent(event, data);
    // Fire-and-forget persist; failures are non-fatal.
    // ignore: discarded_futures
    _persist();
  }

  /// Captures raw callable failure BEFORE UX mapping.
  static void captureRawCallableError({
    required Object error,
    StackTrace? stack,
    required String errorCaughtAt,
  }) {
    final t = active;
    if (t == null) return;
    final payload = <String, dynamic>{
      'ERROR_CAUGHT_AT': errorCaughtAt,
      'RAW_ERROR_RUNTIME_TYPE': error.runtimeType.toString(),
      'STACK_TOP': forensicStackTop(stack),
      'SALE_COMMAND_SUCCESS': false,
    };
    if (error is FirebaseFunctionsException) {
      payload['RAW_FIREBASE_CODE'] = error.code;
      payload['RAW_FIREBASE_MESSAGE'] = error.message;
      payload['RAW_FIREBASE_DETAILS_SANITIZED'] =
          sanitizeForensicDetails(error.details);
    } else {
      // FirebaseException / others — best-effort mirror of code/message.
      try {
        final dyn = error as dynamic;
        final code = dyn.code;
        final message = dyn.message;
        if (code != null) payload['RAW_FIREBASE_CODE'] = code.toString();
        if (message != null) {
          payload['RAW_FIREBASE_MESSAGE'] = message.toString();
        }
        try {
          payload['RAW_FIREBASE_DETAILS_SANITIZED'] =
              sanitizeForensicDetails(dyn.details);
        } catch (_) {}
      } catch (_) {
        payload['RAW_ERROR_TO_STRING'] =
            sanitizeForensicDetails(error.toString());
      }
    }
    t.addEvent('SALE_COMMAND_ERROR', payload);
    // ignore: discarded_futures
    _persist();
  }

  static void captureSaleCommandSuccess(Map<String, dynamic> response) {
    final t = active;
    if (t == null) return;
    final out = <String, dynamic>{
      'SALE_COMMAND_SUCCESS': true,
    };
    for (final k in [
      'operationId',
      'returnedOperationId',
      'stockRevision',
      'revision',
      'returnedRevision',
      'quantidade',
      'qty',
      'returnedQty',
    ]) {
      if (response.containsKey(k) && response[k] != null) {
        out[k] = response[k];
      }
    }
    // Prefer explicit returned* aliases when nested results exist.
    final results = response['results'];
    if (results is List && results.isNotEmpty && results.first is Map) {
      final first = Map<String, dynamic>.from(results.first as Map);
      if (first['stockRevision'] != null) {
        out['returnedRevision'] = first['stockRevision'];
      }
      if (first['quantidade'] != null) {
        out['returnedQty'] = first['quantidade'];
      }
      if (first['stockOperationId'] != null) {
        out['returnedOperationId'] = first['stockOperationId'];
      }
    }
    if (response['operationId'] != null) {
      out.putIfAbsent('returnedOperationId', () => response['operationId']);
    }
    t.addEvent('SALE_COMMAND_SUCCESS', out);
    // ignore: discarded_futures
    _persist();
  }

  /// Immediately before stockCatalogCommand sale callable.
  static void captureSalePayload({
    required String storeId,
    required String operationId,
    required List<Map<String, dynamic>> items,
  }) {
    final t = active;
    if (t == null) return;
    final sanitizedItems = <Map<String, dynamic>>[];
    for (final item in items) {
      sanitizedItems.add({
        'productId': item['productId'],
        'productCode': item['productCode'] ?? item['code'],
        'saleQty': item['quantity'] ?? item['qty'] ?? item['saleQty'],
        'size': item['size'] ?? item['tamanho'],
        'color': item['color'] ?? item['cor'],
        if (item['variationKey'] != null) 'variationKey': item['variationKey'],
        if (item['stockKind'] != null) 'stockKind': item['stockKind'],
      });
    }
    t.addEvent('SALE_PAYLOAD', {
      'COMMAND_NAME': 'stockCatalogCommand',
      'COMMAND_KIND': 'sale',
      'storeId': storeId,
      'operationId': operationId,
      'items': sanitizedItems,
    });
    // ignore: discarded_futures
    _persist();
  }

  static List<SaleForensicTrace> get tracesNewestFirst {
    final ids = _order.reversed.toList(growable: false);
    return [
      for (final id in ids)
        if (_byId[id] != null) _byId[id]!,
    ];
  }

  /// Export section — READ ONLY (no mutations).
  static Map<String, dynamic> toDiagnosticSection() {
    final proof = clientBuildProofMap();
    return {
      'clientBuildId': proof['CLIENT_BUILD_ID'],
      'clientGitCommit': proof['CLIENT_GIT_COMMIT'],
      'appVersion': proof['APP_VERSION'],
      'READ_ONLY_EXPORT': true,
      'traceCount': _byId.length,
      'traces': tracesNewestFirst.map((t) => t.toJson()).toList(growable: false),
    };
  }

  /// Appends diagnostic short code to a friendly UX message (no stack).
  static String appendDiagnosticCodeToUserMessage(String friendly) {
    final t = active;
    if (t == null) return friendly;
    final code = t.shortCode;
    if (friendly.contains(code)) return friendly;
    return '$friendly\n\nCódigo de diagnóstico: $code';
  }
}

/// Prefer technical keys when present (for tests / documentation).
@visibleForTesting
Set<String> get forensicTechnicalDetailKeys => _kTechnicalDetailKeys;
