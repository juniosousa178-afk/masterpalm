import '../models/dashboard/dashboard_enums.dart';
import '../models/dashboard/dashboard_snapshot.dart';
import 'dashboard_canonical_serializer.dart';
import 'dashboard_snapshot_id_factory.dart';

/// Validates composed [DashboardSnapshot] invariants.
class DashboardValidator {
  const DashboardValidator({
    DashboardCanonicalSerializer? serializer,
    DashboardSnapshotIdFactory? idFactory,
  })  : _serializer = serializer ?? const DashboardCanonicalSerializer(),
        _idFactory = idFactory ?? const DashboardSnapshotIdFactory();

  final DashboardCanonicalSerializer _serializer;
  final DashboardSnapshotIdFactory _idFactory;

  DashboardValidationResult validate(DashboardSnapshot snapshot) {
    final errors = <String>[];
    final warnings = <String>[];
    final meta = snapshot.metadata;

    if (meta.dashboardSnapshotId.trim().isEmpty) {
      errors.add('dashboardSnapshotId must not be empty');
    }
    if (meta.projectId.trim().isEmpty) {
      errors.add('projectId must not be empty');
    }
    if (meta.queryFingerprint.trim().isEmpty) {
      errors.add('queryFingerprint must not be empty');
    }
    if (meta.dashboardFingerprint.trim().isEmpty) {
      errors.add('dashboardFingerprint must not be empty');
    }

    final sectionIds = snapshot.sections.map((s) => s.sectionId).toList();
    if (sectionIds.length != sectionIds.toSet().length) {
      errors.add('duplicate sectionId detected');
    }

    final widgetIds = <String>[];
    for (final section in snapshot.sections) {
      widgetIds.addAll(section.widgets.map((w) => w.widgetId));
      if (section.availability == DashboardAvailability.available &&
          section.widgets.isEmpty) {
        errors.add('available section ${section.sectionId} has no widgets');
      }
    }
    if (widgetIds.length != widgetIds.toSet().length) {
      errors.add('duplicate widgetId detected');
    }

    final refIds = snapshot.sourceReferences.map((r) => r.referenceId).toList();
    if (refIds.length != refIds.toSet().length) {
      errors.add('duplicate source reference detected');
    }

    for (final ref in snapshot.sourceReferences) {
      if (ref.projectId != meta.projectId) {
        errors.add('source reference projectId diverges from dashboard');
      }
      if (ref.artifactId.trim().isEmpty) {
        errors.add('source artifactId must not be empty');
      }
    }

    for (final section in snapshot.sections) {
      for (final widget in section.widgets) {
        if (widget.availability == DashboardAvailability.available &&
            widget.data == null) {
          errors.add('available widget ${widget.widgetId} has no data');
        }
        if (widget.availability == DashboardAvailability.unavailable &&
            widget.data != null) {
          errors.add('unavailable widget ${widget.widgetId} has data');
        }
      }
    }

    if (meta.sectionCount != snapshot.sections.length) {
      errors.add('sectionCount mismatch');
    }

    final totalWidgets =
        snapshot.sections.fold<int>(0, (sum, s) => sum + s.widgets.length);
    if (meta.widgetCount != totalWidgets) {
      errors.add('widgetCount mismatch');
    }

    if (meta.sourceArtifactCount != snapshot.sourceReferences.length) {
      errors.add('sourceArtifactCount mismatch');
    }

    if (meta.warningCount != snapshot.warnings.length) {
      errors.add('warningCount mismatch');
    }
    if (meta.errorCount != snapshot.errors.length) {
      errors.add('errorCount mismatch');
    }

    final expectedId = _idFactory.create(
      projectId: meta.projectId,
      queryFingerprint: meta.queryFingerprint,
      dashboardFingerprint: meta.dashboardFingerprint,
      schemaVersion: meta.dashboardSchemaVersion,
    );
    if (expectedId != meta.dashboardSnapshotId) {
      errors.add('dashboardSnapshotId does not match fingerprint inputs');
    }

    try {
      _serializer.canonicalizeSnapshot(snapshot);
    } on Exception catch (e) {
      errors.add('canonicalization failed: $e');
    }

    return DashboardValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }
}
