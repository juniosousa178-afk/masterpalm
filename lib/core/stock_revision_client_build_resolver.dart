// Resolvedor fail-closed do build do cliente para o gate de estoque (R8.4.6).

import 'package:flutter/foundation.dart';
import 'package:master_palm/core/produto_stock_write_enforcement.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Origem do build resolvido.
enum StockRevisionClientBuildSource {
  packageInfo,
  testOverride,
  uninitialized,
  invalid,
  error,
}

/// Status de compatibilidade para diagnóstico.
enum StockRevisionClientBuildStatus {
  compatible,
  updateRequired,
  unavailable,
  invalid,
}

/// Estado imutável da última resolução.
class StockRevisionClientBuildState {
  const StockRevisionClientBuildState({
    required this.source,
    this.rawBuildNumber,
    this.parsedBuildNumber,
    this.initializationError,
    this.initializedAt,
  });

  final String? rawBuildNumber;
  final int? parsedBuildNumber;
  final StockRevisionClientBuildSource source;
  final String? initializationError;
  final DateTime? initializedAt;

  factory StockRevisionClientBuildState.uninitialized() {
    return const StockRevisionClientBuildState(
      source: StockRevisionClientBuildSource.uninitialized,
    );
  }

  StockRevisionClientBuildStatus get status {
    switch (source) {
      case StockRevisionClientBuildSource.uninitialized:
      case StockRevisionClientBuildSource.error:
        return StockRevisionClientBuildStatus.unavailable;
      case StockRevisionClientBuildSource.invalid:
        return StockRevisionClientBuildStatus.invalid;
      case StockRevisionClientBuildSource.packageInfo:
      case StockRevisionClientBuildSource.testOverride:
        final parsed = parsedBuildNumber;
        if (parsed == null || parsed <= 0) {
          return StockRevisionClientBuildStatus.invalid;
        }
        if (parsed < kMinStockRevisionClientVersion) {
          return StockRevisionClientBuildStatus.updateRequired;
        }
        return StockRevisionClientBuildStatus.compatible;
    }
  }
}

/// Build ainda não inicializado ou indisponível.
class StockRevisionClientBuildUnavailableException implements Exception {
  StockRevisionClientBuildUnavailableException(this.message);

  final String message;

  static const String userMessage =
      'Não foi possível validar a versão do aplicativo. '
      'Feche e abra novamente. Se o problema continuar, atualize o MasterPalm.';

  @override
  String toString() =>
      'StockRevisionClientBuildUnavailableException: $message';
}

/// Build vazio, não numérico, zero ou negativo.
class StockRevisionClientBuildInvalidException implements Exception {
  StockRevisionClientBuildInvalidException(this.message);

  final String message;

  static const String userMessage = StockRevisionClientBuildUnavailableException.userMessage;

  @override
  String toString() => 'StockRevisionClientBuildInvalidException: $message';
}

/// Resolve e armazena o build real do cliente via PackageInfo.
class StockRevisionClientBuildResolver {
  StockRevisionClientBuildResolver._();

  static final StockRevisionClientBuildResolver instance =
      StockRevisionClientBuildResolver._();

  StockRevisionClientBuildState _state =
      StockRevisionClientBuildState.uninitialized();

  int? _testOverrideBuild;
  bool _testDefaultsEnabled = false;

  StockRevisionClientBuildState get currentState => _state;

  bool get isInitialized =>
      _state.source != StockRevisionClientBuildSource.uninitialized;

  /// Inicialização real do app — consulta PackageInfo.
  Future<void> initialize() async {
    if (_testOverrideBuild != null) {
      return;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      _storeRawBuild(
        info.buildNumber,
        StockRevisionClientBuildSource.packageInfo,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[StockRevisionClientBuild] PackageInfo falhou: $e\n$st',
        );
      }
      _state = StockRevisionClientBuildState(
        source: StockRevisionClientBuildSource.error,
        initializationError: e.runtimeType.toString(),
        initializedAt: DateTime.now(),
      );
    }
  }

  /// Retorna o build parseado ou lança fail-closed.
  int requireBuildNumber() {
    if (_testOverrideBuild != null) {
      return _testOverrideBuild!;
    }
    switch (_state.source) {
      case StockRevisionClientBuildSource.uninitialized:
        throw StockRevisionClientBuildUnavailableException(
          'Client build resolver not initialized',
        );
      case StockRevisionClientBuildSource.error:
        throw StockRevisionClientBuildUnavailableException(
          _state.initializationError ?? 'PackageInfo error',
        );
      case StockRevisionClientBuildSource.invalid:
        throw StockRevisionClientBuildInvalidException(
          'Invalid client build: raw=${_state.rawBuildNumber}',
        );
      case StockRevisionClientBuildSource.packageInfo:
      case StockRevisionClientBuildSource.testOverride:
        final parsed = _state.parsedBuildNumber;
        if (parsed == null || parsed <= 0) {
          throw StockRevisionClientBuildInvalidException(
            'Parsed build missing after resolution',
          );
        }
        return parsed;
    }
  }

  @visibleForTesting
  void enableTestDefaults() {
    _testDefaultsEnabled = true;
  }

  @visibleForTesting
  void setTestOverride(int buildNumber) {
    assert(buildNumber > 0, 'test override must be > 0');
    _testOverrideBuild = buildNumber;
    _storeRawBuild(
      buildNumber.toString(),
      StockRevisionClientBuildSource.testOverride,
    );
  }

  @visibleForTesting
  void initializeFromRawForTest(String rawBuildNumber) {
    _testOverrideBuild = null;
    _storeRawBuild(rawBuildNumber, StockRevisionClientBuildSource.packageInfo);
  }

  @visibleForTesting
  void resetForTest({bool leaveUninitialized = false}) {
    _testOverrideBuild = null;
    if (leaveUninitialized || !_testDefaultsEnabled) {
      _state = StockRevisionClientBuildState.uninitialized();
      return;
    }
    setTestOverride(285);
  }

  void _storeRawBuild(
    String raw,
    StockRevisionClientBuildSource source,
  ) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      _state = StockRevisionClientBuildState(
        source: StockRevisionClientBuildSource.invalid,
        rawBuildNumber: raw,
        initializedAt: DateTime.now(),
      );
      return;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed <= 0) {
      _state = StockRevisionClientBuildState(
        source: StockRevisionClientBuildSource.invalid,
        rawBuildNumber: raw,
        parsedBuildNumber: parsed,
        initializedAt: DateTime.now(),
      );
      return;
    }
    _state = StockRevisionClientBuildState(
      source: source,
      rawBuildNumber: raw,
      parsedBuildNumber: parsed,
      initializedAt: DateTime.now(),
    );
  }
}
