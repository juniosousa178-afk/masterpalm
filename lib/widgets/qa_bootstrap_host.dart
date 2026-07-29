// Host exclusivo QA Web — primeiro frame imediato + bootstrap fail-closed (R8.4.40).

import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../config/mp_environment_config.dart';
import '../config/qa_bootstrap_runner.dart';
import 'mp_qa_semantics.dart';

/// Monta UI de bootstrap imediatamente; executa [runBootstrap] e só então [mountApp].
class QaBootstrapHost extends StatefulWidget {
  const QaBootstrapHost({
    super.key,
    required this.runBootstrap,
    required this.mountApp,
    this.initFirebase,
  });

  /// `_bootstrapSafe` após Firebase/emulators QA prontos.
  final Future<void> Function() runBootstrap;

  /// Monta MyApp (ou equivalente) — só chamado após sucesso.
  final Future<void> Function() mountApp;

  /// Inicialização Firebase QA (pré-bootstrap).
  final Future<void> Function(QaBootstrapProgress progress)? initFirebase;

  @override
  State<QaBootstrapHost> createState() => _QaBootstrapHostState();
}

class _QaBootstrapHostState extends State<QaBootstrapHost> {
  final QaBootstrapProgress _progress = QaBootstrapProgress();
  bool _firstFrameMarked = false;
  bool _running = false;
  DateTime? _runAppAt;

  @override
  void initState() {
    super.initState();
    _progress.correlationId =
        'qa-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';
    _progress.mark(QaBootstrapStage.started);
    _runAppAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_firstFrameMarked) {
        _firstFrameMarked = true;
        if (kDebugMode) {
          debugPrint(
            '[QaBootstrap] qa-first-frame-rendered '
            'Δ=${DateTime.now().difference(_runAppAt!).inMilliseconds}ms',
          );
        }
        setState(() {});
      }
      if (!_running) _execute();
    });
  }

  Future<void> _execute() async {
    if (_running) return;
    _running = true;
    void bump() {
      if (mounted) setState(() {});
    }
    try {
      final init = widget.initFirebase ?? qaBootstrapInitFirebase;
      bump();
      await init(_progress);
      bump();
      await widget.runBootstrap();
      bump();
      _progress.mark(QaBootstrapStage.appMounting);
      bump();
      await widget.mountApp();
      _progress.mark(QaBootstrapStage.ready);
      bump();
      if (kDebugMode) {
        debugPrint('[QaBootstrap] qa-bootstrap-ready');
      }
    } catch (e, st) {
      _progress.mark(QaBootstrapStage.error);
      _progress.errorType = e.runtimeType.toString();
      _progress.errorMessage = sanitizeQaBootstrapError(e);
      if (kDebugMode) {
        debugPrint('[QaBootstrap] ERROR $_progress.errorType: $e\n$st');
      }
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_progress.current == QaBootstrapStage.error) {
      return _buildShell(
        extraLabels: const ['qa-bootstrap-error'],
        child: _errorBody(),
      );
    }

    final labels = <String>[
      'qa-bootstrap-started',
      _qaBootstrapSemanticLabel(_progress.current),
      _progress.stageLabel(),
      if (_firstFrameMarked) 'qa-first-frame-rendered',
    ];

    return _buildShell(
      extraLabels: labels,
      child: _loadingBody(),
    );
  }

  Widget _buildShell({
    required List<String> extraLabels,
    required Widget child,
  }) {
    Widget tree = MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Stack(
          children: [
            Center(child: child),
            // Texto estável para Playwright headless (fallback além de Semantics).
            Positioned(
              left: 8,
              bottom: 8,
              child: Text(
                _progress.stageLabel(),
                style: const TextStyle(
                  color: Color(0x01FFFFFF),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    for (final label in extraLabels.reversed) {
      tree = mpQaSemantics(label, tree, header: label.contains('error'));
    }
    return tree;
  }

  Widget _loadingBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: Color(0xFF6366F1)),
        const SizedBox(height: 20),
        const Text(
          'QA Bootstrap',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          _progress.current.name,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          '${_qaBootstrapSemanticLabel(_progress.current)} ${_progress.stageLabel()}',
          style: const TextStyle(color: Color(0x01FFFFFF), fontSize: 10),
        ),
      ],
    );
  }

  Widget _errorBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Bootstrap QA falhou',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Text(
            'Estágio: ${_progress.current.name}',
            style: const TextStyle(color: Colors.white70),
          ),
          if (_progress.errorType != null)
            Text(
              'Tipo: ${_progress.errorType}',
              style: const TextStyle(color: Colors.white70),
            ),
          if (_progress.errorMessage != null)
            Text(
              _progress.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          if (_progress.correlationId != null)
            Text(
              'ID: ${_progress.correlationId}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

String _qaBootstrapSemanticLabel(QaBootstrapStage stage) {
  switch (stage) {
    case QaBootstrapStage.started:
      return 'qa-bootstrap-started';
    case QaBootstrapStage.environmentValid:
      return 'qa-bootstrap-environment-valid';
    case QaBootstrapStage.firebaseInitializing:
      return 'qa-bootstrap-firebase-initializing';
    case QaBootstrapStage.firebaseReady:
      return 'qa-bootstrap-firebase-ready';
    case QaBootstrapStage.emulatorsConnecting:
      return 'qa-bootstrap-emulators-connecting';
    case QaBootstrapStage.emulatorsReady:
      return 'qa-bootstrap-emulators-ready';
    case QaBootstrapStage.authReady:
      return 'qa-bootstrap-auth-ready';
    case QaBootstrapStage.appMounting:
      return 'qa-bootstrap-app-mounting';
    case QaBootstrapStage.ready:
      return 'qa-bootstrap-ready';
    case QaBootstrapStage.error:
      return 'qa-bootstrap-error';
  }
}

/// Envolve o app montado com label `qa-bootstrap-ready` (somente QA).
Widget qaBootstrapReadyWrapper(Widget child) {
  if (!MpEnvironmentConfig.isQa) return child;
  return mpQaSemantics('qa-bootstrap-ready', child);
}
