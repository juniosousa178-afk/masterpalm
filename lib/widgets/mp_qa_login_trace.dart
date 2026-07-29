// Marcadores QA-only do fluxo login → Auth (R8.4.41). Sem credenciais.

import 'package:flutter/material.dart';

import '../config/mp_environment_config.dart';
import 'mp_qa_keyed_marker.dart';

/// Estado observável dos marcadores QA de login (somente leitura na UI).
class MpQaLoginTraceState extends ChangeNotifier {
  MpQaLoginTraceState._();
  static final MpQaLoginTraceState instance = MpQaLoginTraceState._();

  final Set<String> _markers = {};
  String? _errorCode;

  Set<String> get markers => Set.unmodifiable(_markers);
  String? get errorCode => _errorCode;

  void mark(String label) {
    if (!MpEnvironmentConfig.isQa) return;
    if (_markers.add(label)) notifyListeners();
  }

  void markError(String sanitizedCode) {
    if (!MpEnvironmentConfig.isQa) return;
    _errorCode = sanitizedCode;
    _markers.add('qa-login-error-$sanitizedCode');
    _markers.add('qa-auth-request-failed');
    notifyListeners();
  }

  void reset() {
    _markers.clear();
    _errorCode = null;
    notifyListeners();
  }
}

/// Expõe marcadores QA na árvore (Keys + Semantics).
class MpQaLoginTraceMarkers extends StatelessWidget {
  const MpQaLoginTraceMarkers({
    super.key,
    required this.formReady,
    required this.loading,
  });

  final bool formReady;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!MpEnvironmentConfig.isQa) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: MpQaLoginTraceState.instance,
      builder: (context, _) {
        final state = MpQaLoginTraceState.instance;
        final labels = <String>{
          if (formReady) 'qa-login-form-ready',
          if (loading) 'qa-login-loading',
          ...state.markers,
        };

        return Positioned(
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final label in labels) ...[
                  MpQaKeyedMarker(markerKey: label),
                  Semantics(
                    label: label,
                    child: const SizedBox(width: 1, height: 1),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

void mpQaLoginMark(String label) => MpQaLoginTraceState.instance.mark(label);

void mpQaLoginMarkError(String sanitizedCode) =>
    MpQaLoginTraceState.instance.markError(sanitizedCode);

String mpQaSanitizeAuthErrorCode(String code) =>
    code.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
