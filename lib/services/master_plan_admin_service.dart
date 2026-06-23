import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/master_plan_access_models.dart';
import '../core/master_plan_admin_messages.dart';

typedef MasterPlanCallableInvoker = Future<dynamic> Function(
  String name,
  Map<String, dynamic> data,
);

/// Serviço da Tela Mestre — somente Cloud Functions (sem escrita direta no Firestore).
class MasterPlanAdminService {
  MasterPlanAdminService({
    MasterPlanCallableInvoker? callFunction,
  }) : _callFunction = callFunction ?? _defaultCallFunction;

  final MasterPlanCallableInvoker _callFunction;
  static const _region = 'southamerica-east1';

  static Future<dynamic> _defaultCallFunction(
    String name,
    Map<String, dynamic> data,
  ) async {
    final functions = FirebaseFunctions.instanceFor(region: _region);
    final callable = functions.httpsCallable(name);
    final result = await callable.call<Map<String, dynamic>>(data);
    return result.data;
  }

  static String newRequestId() {
    return const Uuid().v4().replaceAll('-', '');
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  Future<MasterPlanAccessSummary> fetchSummary() async {
    try {
      final map = _asMap(await _callFunction('masterGetPlanAccessSummary', {}));
      return MasterPlanAccessSummary.fromMap(map);
    } catch (e, st) {
      debugPrint('[MasterPlanAdmin] fetchSummary $e $st');
      throw masterPlanAdminErrorMessage(e);
    }
  }

  Future<({List<MasterPlanUserRow> users, String? nextPageToken, bool hasMore})>
      listUsers({
    int pageSize = 25,
    String? pageToken,
  }) async {
    try {
      final map = _asMap(await _callFunction('masterListUsersPlanAccess', {
        'pageSize': pageSize,
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      }));
      final usersRaw = map['users'];
      final users = <MasterPlanUserRow>[];
      if (usersRaw is List) {
        for (final item in usersRaw) {
          if (item is Map) {
            users.add(MasterPlanUserRow.fromMap(Map<String, dynamic>.from(item)));
          }
        }
      }
      return (
        users: users,
        nextPageToken: map['nextPageToken']?.toString(),
        hasMore: map['hasMore'] == true,
      );
    } catch (e, st) {
      debugPrint('[MasterPlanAdmin] listUsers $e $st');
      throw masterPlanAdminErrorMessage(e);
    }
  }

  Future<Map<String, dynamic>> fetchUserDetails({
    String? targetUid,
    String? targetEmail,
  }) async {
    try {
      return _asMap(await _callFunction('masterGetUserPlanDetails', {
        if (targetUid != null && targetUid.isNotEmpty) 'targetUid': targetUid,
        if (targetEmail != null && targetEmail.isNotEmpty)
          'targetEmail': targetEmail.trim().toLowerCase(),
      }));
    } catch (e, st) {
      debugPrint('[MasterPlanAdmin] fetchUserDetails $e $st');
      throw masterPlanAdminErrorMessage(e);
    }
  }

  Future<List<MasterPlanAuditAction>> listAuditActions({
    required String targetUid,
    int pageSize = 25,
    String? pageToken,
  }) async {
    try {
      final map = _asMap(await _callFunction('masterListPlanAuditActions', {
        'targetUid': targetUid,
        'pageSize': pageSize,
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      }));
      final actionsRaw = map['actions'];
      final actions = <MasterPlanAuditAction>[];
      if (actionsRaw is List) {
        for (final item in actionsRaw) {
          if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            actions.add(
              MasterPlanAuditAction.fromMap(
                m['actionId']?.toString() ?? '',
                m,
              ),
            );
          }
        }
      }
      return actions;
    } catch (e, st) {
      debugPrint('[MasterPlanAdmin] listAuditActions $e $st');
      throw masterPlanAdminErrorMessage(e);
    }
  }

  Future<EffectivePlanAccessDto> grantCourtesy({
    required String targetUid,
    required String planId,
    required String type,
    DateTime? expiresAt,
    required String reason,
    String? requestId,
  }) async {
    try {
      final map = _asMap(await _callFunction('masterGrantCourtesyAccess', {
        'targetUid': targetUid,
        'planId': planId,
        'type': type,
        'reason': reason,
        'requestId': requestId ?? newRequestId(),
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
      }));
      final pa = map['planAccess'];
      if (pa is Map) {
        return EffectivePlanAccessDto.fromMap(Map<String, dynamic>.from(pa));
      }
      throw 'Resposta inválida do servidor.';
    } catch (e, st) {
      debugPrint('[MasterPlanAdmin] grantCourtesy $e $st');
      throw masterPlanAdminErrorMessage(e);
    }
  }

  Future<EffectivePlanAccessDto> extendCourtesy({
    required String targetUid,
    required DateTime expiresAt,
    required String reason,
    String? requestId,
  }) async {
    try {
      final map = _asMap(await _callFunction('masterUpdateCourtesyAccess', {
        'targetUid': targetUid,
        'expiresAt': expiresAt.toIso8601String(),
        'reason': reason,
        'requestId': requestId ?? newRequestId(),
      }));
      final pa = map['planAccess'];
      if (pa is Map) {
        return EffectivePlanAccessDto.fromMap(Map<String, dynamic>.from(pa));
      }
      throw 'Resposta inválida do servidor.';
    } catch (e, st) {
      debugPrint('[MasterPlanAdmin] extendCourtesy $e $st');
      throw masterPlanAdminErrorMessage(e);
    }
  }

  Future<EffectivePlanAccessDto> revokeCourtesy({
    required String targetUid,
    required String reason,
    String? requestId,
  }) async {
    try {
      final map = _asMap(await _callFunction('masterRevokeCourtesyAccess', {
        'targetUid': targetUid,
        'reason': reason,
        'requestId': requestId ?? newRequestId(),
      }));
      final pa = map['planAccess'];
      if (pa is Map) {
        return EffectivePlanAccessDto.fromMap(Map<String, dynamic>.from(pa));
      }
      throw 'Resposta inválida do servidor.';
    } catch (e, st) {
      debugPrint('[MasterPlanAdmin] revokeCourtesy $e $st');
      throw masterPlanAdminErrorMessage(e);
    }
  }
}

/// Leitura do acesso efetivo do usuário autenticado.
class MyPlanEffectiveAccessService {
  MyPlanEffectiveAccessService({
    MasterPlanCallableInvoker? callFunction,
  }) : _callFunction = callFunction ?? MasterPlanAdminService._defaultCallFunction;

  final MasterPlanCallableInvoker _callFunction;

  Future<EffectivePlanAccessDto?> fetchMyEffectiveAccess() async {
    try {
      final map = await _callFunction('getMyPlanEffectiveAccess', {});
      if (map is! Map) return null;
      final m = Map<String, dynamic>.from(map);
      if (m['ok'] != true) return null;
      final pa = m['planAccess'];
      if (pa is! Map) return null;
      return EffectivePlanAccessDto.fromMap(Map<String, dynamic>.from(pa));
    } catch (e, st) {
      debugPrint('[MyPlanEffectiveAccess] fetch failed $e $st');
      return null;
    }
  }
}
