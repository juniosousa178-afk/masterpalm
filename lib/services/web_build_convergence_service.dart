// Web build convergence: detect stale main bundle vs Hosting /version.json.
// Does not reopen Firestore writes. Safe reload only when no PDV mutation in flight.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../web/platform_stub.dart'
    if (dart.library.html) '../web/platform_web.dart' as web_plat;

/// Tracks whether a sale/stock mutation is in flight (blocks forced reload).
class PdvMutationGate {
  PdvMutationGate._();
  static int _depth = 0;
  static bool get isMutationInFlight => _depth > 0;

  static Future<T> run<T>(Future<T> Function() body) async {
    _depth++;
    try {
      return await body();
    } finally {
      _depth--;
    }
  }
}

class WebBuildConvergenceResult {
  const WebBuildConvergenceResult({
    required this.localBuildId,
    required this.remoteBuildId,
    required this.mismatch,
    required this.shouldPromptReload,
    this.error,
  });

  final String localBuildId;
  final String remoteBuildId;
  final bool mismatch;
  final bool shouldPromptReload;
  final String? error;
}

/// Fetches `/version.json` with cache-bust; compares to dart-define build id.
class WebBuildConvergenceService {
  WebBuildConvergenceService({
    http.Client? client,
    this.localBuildId = const String.fromEnvironment(
      'CATALOG_BUILD_ID',
      defaultValue: 'dev',
    ),
    /// When true, run version check even off-web (unit tests / injected client).
    this.forceVersionCheck = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String localBuildId;
  final bool forceVersionCheck;

  static const _reloadGuardKey = 'mp_web_build_reload_guard';

  /// version.json schema: { buildId, gitCommit?, builtAtUtc?, ... }
  Future<WebBuildConvergenceResult> check({Uri? baseUri}) async {
    if (!kIsWeb && !forceVersionCheck) {
      return WebBuildConvergenceResult(
        localBuildId: localBuildId,
        remoteBuildId: localBuildId,
        mismatch: false,
        shouldPromptReload: false,
      );
    }
    final uri = baseUri ?? Uri.base;
    final origin = uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')
        ? uri.origin
        : '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    final versionUri = Uri.parse('$origin/version.json').replace(
      queryParameters: <String, String>{
        'v': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    try {
      final response = await _client.get(versionUri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        return WebBuildConvergenceResult(
          localBuildId: localBuildId,
          remoteBuildId: '',
          mismatch: false,
          shouldPromptReload: false,
          error: 'http_${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      final remote = decoded is Map
          ? (decoded['buildId'] ?? '').toString().trim()
          : '';
      if (remote.isEmpty) {
        return WebBuildConvergenceResult(
          localBuildId: localBuildId,
          remoteBuildId: '',
          mismatch: false,
          shouldPromptReload: false,
          error: 'missing_buildId',
        );
      }
      final mismatch = remote != localBuildId && localBuildId != 'dev';
      final alreadyReloadedFor = web_plat.Web.localStorageGet(_reloadGuardKey) ?? '';
      // Prevent infinite reload loop for the same remote build.
      final shouldPrompt = mismatch &&
          alreadyReloadedFor != remote &&
          !PdvMutationGate.isMutationInFlight;
      return WebBuildConvergenceResult(
        localBuildId: localBuildId,
        remoteBuildId: remote,
        mismatch: mismatch,
        shouldPromptReload: shouldPrompt,
      );
    } catch (e) {
      return WebBuildConvergenceResult(
        localBuildId: localBuildId,
        remoteBuildId: '',
        mismatch: false,
        shouldPromptReload: false,
        error: e.runtimeType.toString(),
      );
    }
  }

  /// Marks that we are about to reload for [remoteBuildId], then reloads.
  void convergeNow(String remoteBuildId) {
    if (!kIsWeb) return;
    if (PdvMutationGate.isMutationInFlight) return;
    web_plat.Web.localStorageSet(_reloadGuardKey, remoteBuildId);
    web_plat.Web.locationReload();
  }

  /// After successful boot on matching build, clear loop guard.
  void clearReloadGuardIfMatched(String remoteBuildId) {
    if (!kIsWeb) return;
    if (remoteBuildId.isNotEmpty && remoteBuildId == localBuildId) {
      web_plat.Web.localStorageRemove(_reloadGuardKey);
    }
  }
}
