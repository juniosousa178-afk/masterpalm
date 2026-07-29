// Marcador QA 1×1 com ValueKey estável — integration_test (R8.4.42).

import 'package:flutter/material.dart';

import '../config/mp_environment_config.dart';

/// Widget invisível exposto na árvore com [ValueKey] para integration_test.
class MpQaKeyedMarker extends StatelessWidget {
  const MpQaKeyedMarker({
    super.key,
    required this.markerKey,
  });

  final String markerKey;

  @override
  Widget build(BuildContext context) {
    if (!MpEnvironmentConfig.isQa) return const SizedBox.shrink();
    return SizedBox(
      key: ValueKey<String>(markerKey),
      width: 1,
      height: 1,
    );
  }
}
