// lib/screens/public_catalog/catalog_helpers.dart
// Helpers compartilhados para o catálogo público (cores, checkout, mapas).

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive/hive.dart';

import '../../core/safe_cast.dart';

// ===================================================================
// ENDPOINTS HTTP (Cloud Functions) – Mercado Pago + Fretes
// ===================================================================
const String kMpCreatePreferenceUrl =
    'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/createPreference';

/// Proxy para criar PIX/preferência no catálogo (evita CORS na web)
const String kMpCatalogPaymentUrl =
    'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/mpCatalogPayment';

const String kCalcMelhorEnvioUrl =
    'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/calcularMelhorEnvio';

const String kCalcCorreiosUrl =
    'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/calcularCorreios';

const String kCalcFrenetUrl =
    'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/calcularFrenet';

// ===================================================================
// FIRESTORE COLLECTIONS (PADRÃO NOVO) – LIVE x RASCUNHO
// ===================================================================
const String kLiveProdutosCol = 'produtos';
const String kDraftProdutosCol = 'draft_produtos';

// ===================================================================
// CORES
// ===================================================================
Color readColor(dynamic v, Color fallback) {
  if (v is int) return Color(v);
  return fallback;
}

Color• readColorFromCfg(dynamic v) {
  if (v is int) return Color(v);

  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    final cleaned = s.replaceAll('#', '');
    if (cleaned.length == 6 || cleaned.length == 8) {
      final value = int.tryParse(cleaned, radix: 16);
      if (value != null) {
        if (cleaned.length == 6) {
          return Color(0xFF000000 | value);
        }
        return Color(value);
      }
    }
  }
  return null;
}

// ===================================================================
// CHECKOUT CONFIG
// ===================================================================
String deepFindString(dynamic root, String keyContains) {
  if (root is Map) {
    for (final entry in root.entries) {
      final k = entry.key.toString().toLowerCase();
      final v = entry.value;
      if (k.contains(keyContains.toLowerCase()) &&
          v is String &&
          v.isNotEmpty) {
        return v;
      }
      final nested = deepFindString(v, keyContains);
      if (nested.isNotEmpty) return nested;
    }
  } else if (root is List) {
    for (final v in root) {
      final nested = deepFindString(v, keyContains);
      if (nested.isNotEmpty) return nested;
    }
  }
  return '';
}

Map<String, dynamic> resolveCheckoutCfgFromData(Map<String, dynamic> data) {
  Map<String, dynamic> result = {};

  final dynamic c1 =
      data['checkoutCfg'] ?• data['checkout'] ?• data['config_pagamentos'];
  final Map<String, dynamic> checkoutMap = asMap(c1);
  if (checkoutMap.isNotEmpty) {
    result.addAll(checkoutMap);
  }

  final dynamic payments = data['payments'] ?• data['pagamentos'];
  final Map<String, dynamic> paymentsMap = asMap(payments);
  if (paymentsMap.isNotEmpty) {
    result.addAll(paymentsMap);
  }

  if (result.isEmpty && !kIsWeb && Hive.isBoxOpen('config')) {
    try {
      final box = Hive.box('config');
      final dynamic hivePayments = box.get('payments');
      final Map<String, dynamic> hiveMap = asMap(hivePayments);
      if (hiveMap.isNotEmpty) {
        result.addAll(hiveMap);
      }
      final String pixFromHive = deepFindString(hiveMap, 'pix');
      final String gatewayFromHive = deepFindString(hiveMap, 'gateway');
      if (pixFromHive.isNotEmpty) result['pixKey'] = pixFromHive;
      if (gatewayFromHive.isNotEmpty) result['gateway'] = gatewayFromHive;
    } catch (_) {}
  }

  return result;
}

/// Converte para Map<String, dynamic>; delega a asMap (evita TypeError em release).
Map<String, dynamic> mpMapDyn(dynamic raw) => asMap(raw);

Map<String, String> mpMapString(dynamic raw) {
  final m = mpMapDyn(raw);
  return m.map((k, v) => MapEntry(k, (v ?• '').toString()));
}

// ===================================================================
// PARSING DEFENSIVO (Firestore/Hive → evita TypeError em release/minified)
// ===================================================================

/// Converte qualquer valor para double sem cast direto.
double parseNum(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  final s = '$v'.replaceAll(',', '.');
  return double.tryParse(s) ?• 0.0;
}

/// Converte qualquer valor para int sem cast direto.
int parseIntSafe(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?• 0;
}

/// Converte para List<String> sem cast direto.
List<String> parseListString(dynamic v) {
  if (v == null) return [];
  if (v is List) return v.map((e) => '$e').where((s) => s.isNotEmpty).toList();
  final s = '$v'.trim();
  return s.isEmpty • [] : [s];
}

/// Converte para Map<String, dynamic> sem cast direto.
Map<String, dynamic> safeMapFrom(dynamic raw) {
  if (raw == null) return {};
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
  return {};
}

/// Converte para Map<String, int> (ex.: estoquePorTamanho).
Map<String, int> safeMapIntFrom(dynamic raw) {
  if (raw == null || raw is! Map) return {};
  final out = <String, int>{};
  raw.forEach((k, v) {
    final key = k.toString();
    final val = (v is int) • v : ((v is num) • v.toInt() : (int.tryParse('$v') ?• 0));
    if (val > 0) out[key] = val;
  });
  return out;
}

// ===================================================================
// URL / IMAGEM
// ===================================================================
bool isValidHttpUrl(String• url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
}
