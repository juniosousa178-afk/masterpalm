// lib/core/feature_flags.dart
// Flags de feature para integrações opt-in. Default OFF.

import 'package:flutter/foundation.dart' show kDebugMode;

/// Em produção (release): false — fallback por nome continua funcionando, com logs.
/// Em dev/homolog (debug): true — ao resolver produto por NOME, loga e opcionalmente lança exceção controlada.
/// Objetivo: endurecer fluxos ID-first em homolog sem quebrar produção.
bool get kStrictProductResolution => kDebugMode;

/// Habilita integração CatalogoVendaService em FirestoreCatalogOrderSink.
/// Quando true: após gravar pedido em Firestore, dispara notificação admin.
/// Quando false: comportamento 100% igual ao anterior (sem mudanças).
const bool kEnableCatalogoVendaService = false;

/// Habilita UserProfileResolver no router (perfil de users/usuarios unificado).
/// Quando false: fluxo atual (fetchRoleAndStore). Quando true: resolver híbrido com preferência users.
const bool kEnableUnifiedUserProfileResolver = false;

/// Sanitiza config do catálogo antes de gravar no disco (remove chaves sensíveis).
/// Quando false: comportamento idêntico ao atual (persiste tudo como hoje).
/// Quando true: remove access_token, api_key, secret, etc. apenas no disco.
const bool kEnableCatalogDiskCacheSanitize = false;

/// Logs de auditoria do cache em disco (read/write). Apenas em debug; OFF por padrão. ETAPA 22A.
const bool kEnableCatalogDiskCacheAuditLogs = false;
