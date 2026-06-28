// Snapshot sanitizado de relações de identidade de loja (sem IDs brutos).

/// Relação entre duas fontes de loja, sem expor valores.
enum StoreIdentityRelation {
  matchCanonical,
  matchLegacy,
  mismatch,
  unavailable,
  notApplicable,
}

/// Origem da loja ativa operacional no dispositivo.
enum StoreIdentityResolutionSource {
  sessionStoreId,
  profileStoreId,
  profileOwnerOf,
  legacyLojaId,
  legacyOwnerStoreId,
  fallback,
  unavailable,
}

/// Completude dos dados usados no diagnóstico.
enum StoreIdentityDiagnosticCompleteness {
  full,
  partial,
  unavailable,
}

/// Snapshot imutável — contém apenas relações e flags, nunca IDs completos.
class StoreIdentityDiagnosticSnapshot {
  const StoreIdentityDiagnosticSnapshot({
    required this.capturedAtUtc,
    required this.activeStoreResolutionSource,
    required this.profileCanonicalStoreAvailable,
    required this.profileHasLegacyConflict,
    required this.sessionVsCanonical,
    required this.sessionVsLegacy,
    required this.resolvedVsCanonical,
    required this.resolvedVsLegacy,
    required this.sessionEqualsResolved,
    required this.activeStoreMatchesCanonical,
    required this.activeStoreMatchesLegacy,
    required this.profileStoreIdAvailable,
    required this.profileOwnerOfAvailable,
    required this.profileLojaIdLegacyAvailable,
    required this.legacyOwnerStoreIdAvailable,
    required this.diagnosticDataCompleteness,
  });

  final DateTime capturedAtUtc;
  final StoreIdentityResolutionSource activeStoreResolutionSource;
  final bool profileCanonicalStoreAvailable;
  final bool profileHasLegacyConflict;
  final StoreIdentityRelation sessionVsCanonical;
  final StoreIdentityRelation sessionVsLegacy;
  final StoreIdentityRelation resolvedVsCanonical;
  final StoreIdentityRelation resolvedVsLegacy;
  final StoreIdentityRelation sessionEqualsResolved;
  final StoreIdentityRelation activeStoreMatchesCanonical;
  final StoreIdentityRelation activeStoreMatchesLegacy;
  final bool profileStoreIdAvailable;
  final bool profileOwnerOfAvailable;
  final bool profileLojaIdLegacyAvailable;
  final bool legacyOwnerStoreIdAvailable;
  final StoreIdentityDiagnosticCompleteness diagnosticDataCompleteness;

  Map<String, dynamic> toSanitizedMap() => {
        'capturedAtUtc': capturedAtUtc.toIso8601String(),
        'activeStoreResolutionSource': activeStoreResolutionSource.name,
        'profileCanonicalStoreAvailable': profileCanonicalStoreAvailable,
        'profileHasLegacyConflict': profileHasLegacyConflict,
        'sessionVsCanonical': sessionVsCanonical.name,
        'sessionVsLegacy': sessionVsLegacy.name,
        'resolvedVsCanonical': resolvedVsCanonical.name,
        'resolvedVsLegacy': resolvedVsLegacy.name,
        'sessionEqualsResolved': sessionEqualsResolved.name,
        'activeStoreMatchesCanonical': activeStoreMatchesCanonical.name,
        'activeStoreMatchesLegacy': activeStoreMatchesLegacy.name,
        'profileStoreIdAvailable': profileStoreIdAvailable,
        'profileOwnerOfAvailable': profileOwnerOfAvailable,
        'profileLojaIdLegacyAvailable': profileLojaIdLegacyAvailable,
        'legacyOwnerStoreIdAvailable': legacyOwnerStoreIdAvailable,
        'diagnosticDataCompleteness': diagnosticDataCompleteness.name,
      };

  /// Rótulo curto para UI/relatório (sem IDs).
  static String relationLabel(StoreIdentityRelation relation) {
    switch (relation) {
      case StoreIdentityRelation.matchCanonical:
        return 'sim (canônica)';
      case StoreIdentityRelation.matchLegacy:
        return 'sim (legado)';
      case StoreIdentityRelation.mismatch:
        return 'não';
      case StoreIdentityRelation.unavailable:
        return 'indisponível';
      case StoreIdentityRelation.notApplicable:
        return 'n/a';
    }
  }

  static String yesNoUnavailable(StoreIdentityRelation relation) {
    switch (relation) {
      case StoreIdentityRelation.matchCanonical:
      case StoreIdentityRelation.matchLegacy:
        return 'sim';
      case StoreIdentityRelation.mismatch:
        return 'não';
      case StoreIdentityRelation.unavailable:
        return 'indisponível';
      case StoreIdentityRelation.notApplicable:
        return 'n/a';
    }
  }

  static String sourceLabel(StoreIdentityResolutionSource source) {
    switch (source) {
      case StoreIdentityResolutionSource.sessionStoreId:
        return 'sessao.store_id';
      case StoreIdentityResolutionSource.profileStoreId:
        return 'users.store_id';
      case StoreIdentityResolutionSource.profileOwnerOf:
        return 'users.ownerOf';
      case StoreIdentityResolutionSource.legacyLojaId:
        return 'users.lojaId (legado)';
      case StoreIdentityResolutionSource.legacyOwnerStoreId:
        return 'usuarios.ownerStoreId (legado)';
      case StoreIdentityResolutionSource.fallback:
        return 'fallback';
      case StoreIdentityResolutionSource.unavailable:
        return 'indisponível';
    }
  }

  static String completenessLabel(StoreIdentityDiagnosticCompleteness c) {
    switch (c) {
      case StoreIdentityDiagnosticCompleteness.full:
        return 'completo';
      case StoreIdentityDiagnosticCompleteness.partial:
        return 'parcial';
      case StoreIdentityDiagnosticCompleteness.unavailable:
        return 'indisponível';
    }
  }

  String buildReportSection() {
    final buffer = StringBuffer();
    buffer.writeln('--- Identidade da loja (sanitizado) ---');
    buffer.writeln(
      'Origem da loja ativa: ${sourceLabel(activeStoreResolutionSource)}',
    );
    buffer.writeln(
      'Loja canônica do perfil: ${profileCanonicalStoreAvailable ? 'disponível' : 'indisponível'}',
    );
    buffer.writeln(
      'Conflito remoto de perfil: ${_conflictLabel(profileHasLegacyConflict)}',
    );
    buffer.writeln(
      'Sessão vs canônica: ${relationLabel(sessionVsCanonical)}',
    );
    buffer.writeln('Sessão vs legado: ${relationLabel(sessionVsLegacy)}');
    buffer.writeln(
      'Resolvida vs canônica: ${relationLabel(resolvedVsCanonical)}',
    );
    buffer.writeln(
      'Resolvida vs legado: ${relationLabel(resolvedVsLegacy)}',
    );
    buffer.writeln(
      'Sessão = resolvida: ${yesNoUnavailable(sessionEqualsResolved)}',
    );
    buffer.writeln(
      'Loja ativa vs canônica: ${relationLabel(activeStoreMatchesCanonical)}',
    );
    buffer.writeln(
      'Loja ativa vs legado: ${relationLabel(activeStoreMatchesLegacy)}',
    );
    buffer.writeln(
      'Completude: ${completenessLabel(diagnosticDataCompleteness)}',
    );
    buffer.writeln('Captura: ${capturedAtUtc.toIso8601String()}');
    return buffer.toString().trim();
  }

  static String _conflictLabel(bool? conflict) {
    if (conflict == null) return 'indisponível';
    return conflict ? 'sim' : 'não';
  }
}
