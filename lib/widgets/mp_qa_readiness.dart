// Marcadores de prontidão para Web UI E2E (R8.4.39) — somente MP_ENVIRONMENT=qa.

import 'package:flutter/material.dart';

import '../config/mp_environment_config.dart';

/// Labels invisíveis (1×1) representando estado real da aplicação.
class MpQaReadinessMarkers extends StatelessWidget {
  const MpQaReadinessMarkers({
    super.key,
    required this.authenticated,
    required this.companyLoaded,
    required this.navigationReady,
    this.loading = false,
    this.error = false,
  });

  final bool authenticated;
  final bool companyLoaded;
  final bool navigationReady;
  final bool loading;
  final bool error;

  bool get _homeReady =>
      authenticated &&
      companyLoaded &&
      navigationReady &&
      !loading &&
      !error;

  @override
  Widget build(BuildContext context) {
    if (!MpEnvironmentConfig.isQa) return const SizedBox.shrink();
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
            if (loading)
              Semantics(label: 'loading', child: const SizedBox(width: 1, height: 1)),
            if (error)
              Semantics(label: 'visible-error', child: const SizedBox(width: 1, height: 1)),
            if (authenticated)
              Semantics(
                label: 'app-authenticated',
                child: const SizedBox(width: 1, height: 1),
              ),
            if (companyLoaded)
              Semantics(
                label: 'company-loaded',
                child: const SizedBox(width: 1, height: 1),
              ),
            if (navigationReady)
              Semantics(
                label: 'navigation-ready',
                child: const SizedBox(width: 1, height: 1),
              ),
            if (_homeReady)
              Semantics(
                label: 'home-ready',
                child: const SizedBox(width: 1, height: 1),
              ),
          ],
        ),
      ),
    );
  }
}
