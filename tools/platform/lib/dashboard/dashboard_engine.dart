import '../models/dashboard/dashboard_enums.dart';
import '../models/dashboard/dashboard_request.dart';
import '../models/dashboard/dashboard_snapshot.dart';
import 'dashboard_canonical_serializer.dart';
import 'dashboard_compatibility_checker.dart';
import 'dashboard_composer.dart';
import 'dashboard_exceptions.dart';
import 'dashboard_freshness_evaluator.dart';
import 'dashboard_registry.dart';
import 'dashboard_request_validator.dart';
import 'dashboard_snapshot_id_factory.dart';
import 'dashboard_source_resolver.dart';
import 'dashboard_validator.dart';

/// Stateless dashboard composition engine.
class DashboardEngine {
  DashboardEngine({
    required DashboardSourceResolver sourceResolver,
    required DashboardRegistry registry,
    DashboardRequestValidator? requestValidator,
    DashboardValidator? snapshotValidator,
    DashboardCompatibilityChecker? compatibilityChecker,
    DashboardFreshnessEvaluator? freshnessEvaluator,
    DashboardCanonicalSerializer? serializer,
    DashboardSnapshotIdFactory? idFactory,
  })  : _sourceResolver = sourceResolver,
        _composer = DashboardComposer(registry: registry),
        _registry = registry,
        _requestValidator =
            requestValidator ?? const DashboardRequestValidator(),
        _snapshotValidator = snapshotValidator ?? const DashboardValidator(),
        _compatibilityChecker =
            compatibilityChecker ?? const DashboardCompatibilityChecker(),
        _freshnessEvaluator =
            freshnessEvaluator ?? const DashboardFreshnessEvaluator(),
        _serializer = serializer ?? const DashboardCanonicalSerializer(),
        _idFactory = idFactory ?? const DashboardSnapshotIdFactory();

  final DashboardSourceResolver _sourceResolver;
  final DashboardComposer _composer;
  final DashboardRegistry _registry;
  final DashboardRequestValidator _requestValidator;
  final DashboardValidator _snapshotValidator;
  final DashboardCompatibilityChecker _compatibilityChecker;
  final DashboardFreshnessEvaluator _freshnessEvaluator;
  final DashboardCanonicalSerializer _serializer;
  final DashboardSnapshotIdFactory _idFactory;

  Future<DashboardResult> build(DashboardRequest request) async {
    final validation = _requestValidator.validate(request);
    if (!validation.isValid) {
      return DashboardResult(
        status: DashboardStatus.failure,
        errors: validation.errors
            .map((e) => DashboardError(code: 'request.invalid', message: e))
            .toList(),
      );
    }

    try {
      final sources = await _sourceResolver.resolve(request);
      final compatibility = _compatibilityChecker.evaluate(sources);

      if (request.strictCompatibility &&
          compatibility == DashboardCompatibility.incompatible) {
        return DashboardResult(
          status: DashboardStatus.incompatible,
          errors: [
            const DashboardError(
              code: 'compatibility.incompatible',
              message: 'Sources are incompatible in strict mode',
            ),
          ],
        );
      }

      final freshness = _freshnessEvaluator.evaluate(
        request: request,
        sources: sources,
      );

      final sections = _composer.compose(
        request: request,
        sources: sources,
        compatibility: compatibility,
        freshness: freshness,
      );

      final layoutId = request.layoutId ?? 'dashboard-foundation-v1';
      final layout = _registry.layout(layoutId);

      final availableWidgets = sections
          .expand((s) => s.widgets)
          .where((w) => w.availability == DashboardAvailability.available)
          .length;
      final unavailableWidgets = sections
          .expand((s) => s.widgets)
          .where((w) => w.availability == DashboardAvailability.unavailable)
          .length;
      final totalWidgets = availableWidgets + unavailableWidgets;

      final sourceTimestamps = sources.references
          .where((r) => r.createdAt.isNotEmpty)
          .map((r) => r.createdAt)
          .toList()
        ..sort();

      final queryFingerprint = _serializer.queryFingerprint(
        projectId: request.projectId,
        branch: request.branch,
        gitRef: request.gitRef,
        timeRangeFrom: request.timeRange?.from,
        timeRangeTo: request.timeRange?.to,
        filters: request.filters.map((f) => '${f.key}=${f.value}').toList(),
        requestedSections:
            (request.requestedSections ?? DashboardSectionType.values)
                .map((s) => s.wireName)
                .toList(),
        requestedWidgetIds: request.requestedWidgetIds?.toList() ?? const [],
        sourceArtifactIds: {
          if (request.metricsSnapshotId != null)
            'metrics': request.metricsSnapshotId!,
          if (request.historySnapshotId != null)
            'history': request.historySnapshotId!,
          if (request.scoreSnapshotId != null)
            'score': request.scoreSnapshotId!,
          if (request.mesSnapshotId != null) 'mes': request.mesSnapshotId!,
          if (request.qualityGateSnapshotId != null)
            'qualityGate': request.qualityGateSnapshotId!,
        },
        layoutId: layoutId,
        useLatest: request.useLatest,
        strictCompatibility: request.strictCompatibility,
        comparisonMode: request.comparisonMode.wireName,
        baselineSnapshotId: request.baselineSnapshotId,
      );

      final dashboardFingerprint = _serializer.dashboardFingerprint(
        sourceFingerprints: sources.references
            .map((r) => r.fingerprint)
            .where((f) => f.isNotEmpty)
            .toList(),
        sectionIds: sections.map((s) => s.sectionId).toList(),
        widgetIds:
            sections.expand((s) => s.widgets.map((w) => w.widgetId)).toList(),
        availabilitySummary: '$availableWidgets:$unavailableWidgets',
        compatibility: compatibility.wireName,
        freshness: freshness.wireName,
        layoutId: layoutId,
        schemaVersion: DashboardMetadata.currentSchemaVersion,
        calculationVersion: DashboardMetadata.currentCalculationVersion,
        canonicalizationVersion:
            DashboardMetadata.currentCanonicalizationVersion,
      );

      final snapshotId = _idFactory.create(
        projectId: request.projectId,
        queryFingerprint: queryFingerprint,
        dashboardFingerprint: dashboardFingerprint,
      );

      final status = _resolveStatus(
        sections: sections,
        compatibility: compatibility,
        request: request,
      );

      final warnings = <DashboardWarning>[];
      if (request.includeWarnings) {
        warnings.addAll(
          validation.warnings.map(
              (w) => DashboardWarning(code: 'request.warning', message: w)),
        );
        warnings.addAll(
          sections.expand((s) => s.warnings).map(
              (w) => DashboardWarning(code: 'section.warning', message: w)),
        );
      }

      final limitations = sources.limitations
          .map(
              (l) => DashboardLimitation(code: 'source.limitation', message: l))
          .toList();

      final snapshot = DashboardSnapshot(
        metadata: DashboardMetadata(
          dashboardSnapshotId: snapshotId,
          dashboardSchemaVersion: DashboardMetadata.currentSchemaVersion,
          dashboardCalculationVersion:
              DashboardMetadata.currentCalculationVersion,
          dashboardCanonicalizationVersion:
              DashboardMetadata.currentCanonicalizationVersion,
          projectId: request.projectId,
          createdAt: request.createdAt,
          branch: request.branch,
          gitRef: request.gitRef,
          queryFingerprint: queryFingerprint,
          dashboardFingerprint: dashboardFingerprint,
          status: status,
          freshness: freshness,
          compatibility: compatibility,
          sectionCount: sections.length,
          widgetCount: totalWidgets,
          availableWidgetCount: availableWidgets,
          unavailableWidgetCount: unavailableWidgets,
          warningCount: warnings.length,
          errorCount: 0,
          sourceArtifactCount: sources.references.length,
          oldestSourceCreatedAt:
              sourceTimestamps.isEmpty ? null : sourceTimestamps.first,
          newestSourceCreatedAt:
              sourceTimestamps.isEmpty ? null : sourceTimestamps.last,
        ),
        sections: sections,
        sourceReferences:
            request.includeSourceReferences ? sources.references : const [],
        layout: layout,
        warnings: warnings,
        errors: const [],
        limitations: request.includeLimitations ? limitations : const [],
        filters: request.filters.map((f) => '${f.key}=${f.value}').toList(),
      );

      final snapshotValidation = _snapshotValidator.validate(snapshot);
      if (!snapshotValidation.isValid) {
        return DashboardResult(
          status: DashboardStatus.failure,
          errors: snapshotValidation.errors
              .map((e) => DashboardError(code: 'snapshot.invalid', message: e))
              .toList(),
        );
      }

      return DashboardResult(
          status: status, snapshot: snapshot, warnings: warnings);
    } on DashboardException catch (e) {
      return DashboardResult(
        status: DashboardStatus.failure,
        errors: [DashboardError(code: 'dashboard.error', message: e.message)],
      );
    } catch (e) {
      return DashboardResult(
        status: DashboardStatus.failure,
        errors: [DashboardError(code: 'dashboard.unexpected', message: '$e')],
      );
    }
  }

  DashboardStatus _resolveStatus({
    required List<DashboardSection> sections,
    required DashboardCompatibility compatibility,
    required DashboardRequest request,
  }) {
    if (compatibility == DashboardCompatibility.incompatible) {
      return DashboardStatus.incompatible;
    }

    final hasAvailable = sections.any(
      (s) => s.availability != DashboardAvailability.unavailable,
    );
    if (!hasAvailable) return DashboardStatus.unavailable;

    final requested = request.requestedSections;
    if (requested != null && requested.isNotEmpty) {
      final built = sections.map((s) => s.type).toSet();
      final missingRequired = requested.where((r) {
        final section = sections.where((s) => s.type == r).toList();
        return section.isEmpty ||
            section.first.availability == DashboardAvailability.unavailable;
      });
      if (missingRequired.isNotEmpty) {
        return DashboardStatus.partial;
      }
      if (!requested.every(built.contains)) {
        return DashboardStatus.partial;
      }
    }

    final anyPartial = sections.any(
      (s) => s.availability == DashboardAvailability.partial,
    );
    final anyUnavailable = sections.any(
      (s) => s.availability == DashboardAvailability.unavailable,
    );
    if (anyPartial || anyUnavailable) return DashboardStatus.partial;

    if (compatibility == DashboardCompatibility.partiallyCompatible) {
      return DashboardStatus.partial;
    }

    return DashboardStatus.success;
  }
}
