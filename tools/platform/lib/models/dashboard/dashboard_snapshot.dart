import 'dashboard_enums.dart';
import 'dashboard_widgets.dart';

/// Reference to an artifact used by the dashboard.
class DashboardSourceReference {
  const DashboardSourceReference({
    required this.referenceId,
    required this.sourceType,
    required this.providerType,
    required this.artifactId,
    required this.projectId,
    required this.createdAt,
    required this.fingerprint,
    required this.availability,
    required this.compatibility,
    required this.resolutionMode,
    this.schemaVersion,
    this.calculationVersion,
    this.canonicalizationVersion,
    this.branch,
    this.gitRef,
    this.isPrimary = false,
    this.limitations = const [],
  });

  final String referenceId;
  final DashboardSourceType sourceType;
  final DashboardProviderType providerType;
  final String artifactId;
  final String projectId;
  final int? schemaVersion;
  final int? calculationVersion;
  final int? canonicalizationVersion;
  final String createdAt;
  final String? branch;
  final String? gitRef;
  final String fingerprint;
  final DashboardAvailability availability;
  final DashboardCompatibility compatibility;
  final DashboardSourceResolutionMode resolutionMode;
  final bool isPrimary;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'referenceId': referenceId,
        'sourceType': sourceType.wireName,
        'providerType': providerType.wireName,
        'artifactId': artifactId,
        'projectId': projectId,
        if (schemaVersion != null) 'schemaVersion': schemaVersion,
        if (calculationVersion != null)
          'calculationVersion': calculationVersion,
        if (canonicalizationVersion != null)
          'canonicalizationVersion': canonicalizationVersion,
        'createdAt': createdAt,
        if (branch != null) 'branch': branch,
        if (gitRef != null) 'gitRef': gitRef,
        'fingerprint': fingerprint,
        'availability': availability.wireName,
        'compatibility': compatibility.wireName,
        'resolutionMode': resolutionMode.wireName,
        'isPrimary': isPrimary,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory DashboardSourceReference.fromJson(Map<String, dynamic> json) {
    return DashboardSourceReference(
      referenceId: json['referenceId'] as String,
      sourceType:
          DashboardSourceTypeX.fromWireName(json['sourceType'] as String),
      providerType:
          DashboardProviderTypeX.fromWireName(json['providerType'] as String),
      artifactId: json['artifactId'] as String,
      projectId: json['projectId'] as String,
      schemaVersion: json['schemaVersion'] as int?,
      calculationVersion: json['calculationVersion'] as int?,
      canonicalizationVersion: json['canonicalizationVersion'] as int?,
      createdAt: json['createdAt'] as String,
      branch: json['branch'] as String?,
      gitRef: json['gitRef'] as String?,
      fingerprint: json['fingerprint'] as String,
      availability: DashboardAvailabilityX.fromWireName(
        json['availability'] as String,
      ),
      compatibility: DashboardCompatibilityX.fromWireName(
        json['compatibility'] as String,
      ),
      resolutionMode: DashboardSourceResolutionModeX.fromWireName(
        json['resolutionMode'] as String,
      ),
      isPrimary: json['isPrimary'] as bool? ?? false,
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Semantic dashboard section.
class DashboardSection {
  const DashboardSection({
    required this.sectionId,
    required this.type,
    required this.title,
    required this.order,
    required this.availability,
    required this.widgets,
    this.description,
    this.sourceReferenceIds = const [],
    this.limitations = const [],
    this.warnings = const [],
  });

  final String sectionId;
  final DashboardSectionType type;
  final String title;
  final String? description;
  final int order;
  final DashboardAvailability availability;
  final List<DashboardWidget> widgets;
  final List<String> sourceReferenceIds;
  final List<String> limitations;
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
        'sectionId': sectionId,
        'type': type.wireName,
        'title': title,
        if (description != null) 'description': description,
        'order': order,
        'availability': availability.wireName,
        'widgets': widgets.map((w) => w.toJson()).toList(),
        'sourceReferenceIds': sourceReferenceIds,
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (warnings.isNotEmpty) 'warnings': warnings,
      };

  factory DashboardSection.fromJson(Map<String, dynamic> json) {
    return DashboardSection(
      sectionId: json['sectionId'] as String,
      type: DashboardSectionTypeX.fromWireName(json['type'] as String),
      title: json['title'] as String,
      description: json['description'] as String?,
      order: json['order'] as int? ?? 0,
      availability: DashboardAvailabilityX.fromWireName(
        json['availability'] as String,
      ),
      widgets: (json['widgets'] as List<dynamic>)
          .map((e) => DashboardWidget.fromJson(e as Map<String, dynamic>))
          .toList(),
      sourceReferenceIds: (json['sourceReferenceIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Semantic layout item.
class DashboardLayoutItem {
  const DashboardLayoutItem({
    required this.sectionId,
    required this.order,
    this.group,
    this.priority = 0,
    this.visibility = true,
    this.spanHint,
    this.presentationHint = DashboardPresentationHint.primary,
  });

  final String sectionId;
  final int order;
  final String? group;
  final int priority;
  final bool visibility;
  final String? spanHint;
  final DashboardPresentationHint presentationHint;

  Map<String, dynamic> toJson() => {
        'sectionId': sectionId,
        'order': order,
        if (group != null) 'group': group,
        'priority': priority,
        'visibility': visibility,
        if (spanHint != null) 'spanHint': spanHint,
        'presentationHint': presentationHint.wireName,
      };

  factory DashboardLayoutItem.fromJson(Map<String, dynamic> json) {
    return DashboardLayoutItem(
      sectionId: json['sectionId'] as String,
      order: json['order'] as int? ?? 0,
      group: json['group'] as String?,
      priority: json['priority'] as int? ?? 0,
      visibility: json['visibility'] as bool? ?? true,
      spanHint: json['spanHint'] as String?,
      presentationHint: DashboardPresentationHintX.fromWireName(
        json['presentationHint'] as String? ?? 'primary',
      ),
    );
  }
}

/// Semantic dashboard layout.
class DashboardLayout {
  const DashboardLayout({
    required this.layoutId,
    required this.version,
    required this.items,
    this.sectionOrder = const [],
  });

  final String layoutId;
  final int version;
  final List<DashboardLayoutItem> items;
  final List<String> sectionOrder;

  Map<String, dynamic> toJson() => {
        'layoutId': layoutId,
        'version': version,
        'items': items.map((i) => i.toJson()).toList(),
        'sectionOrder': sectionOrder,
      };

  factory DashboardLayout.fromJson(Map<String, dynamic> json) {
    return DashboardLayout(
      layoutId: json['layoutId'] as String,
      version: json['version'] as int? ?? 1,
      items: (json['items'] as List<dynamic>)
          .map((e) => DashboardLayoutItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      sectionOrder: (json['sectionOrder'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Structured dashboard limitation.
class DashboardLimitation {
  const DashboardLimitation({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, dynamic> toJson() => {'code': code, 'message': message};

  factory DashboardLimitation.fromJson(Map<String, dynamic> json) {
    return DashboardLimitation(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

class DashboardWarning {
  const DashboardWarning({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, dynamic> toJson() => {'code': code, 'message': message};

  factory DashboardWarning.fromJson(Map<String, dynamic> json) {
    return DashboardWarning(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

class DashboardError {
  const DashboardError({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, dynamic> toJson() => {'code': code, 'message': message};

  factory DashboardError.fromJson(Map<String, dynamic> json) {
    return DashboardError(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

/// Freshness policy for dashboard sources.
class DashboardFreshnessPolicy {
  const DashboardFreshnessPolicy({
    this.currentMaxAgeHours = 1,
    this.recentMaxAgeHours = 24,
    this.staleAfterHours = 72,
    this.maxSourceSkewHours = 24,
  });

  final int currentMaxAgeHours;
  final int recentMaxAgeHours;
  final int staleAfterHours;
  final int maxSourceSkewHours;

  Map<String, dynamic> toJson() => {
        'currentMaxAgeHours': currentMaxAgeHours,
        'recentMaxAgeHours': recentMaxAgeHours,
        'staleAfterHours': staleAfterHours,
        'maxSourceSkewHours': maxSourceSkewHours,
      };

  factory DashboardFreshnessPolicy.fromJson(Map<String, dynamic> json) {
    return DashboardFreshnessPolicy(
      currentMaxAgeHours: json['currentMaxAgeHours'] as int? ?? 1,
      recentMaxAgeHours: json['recentMaxAgeHours'] as int? ?? 24,
      staleAfterHours: json['staleAfterHours'] as int? ?? 72,
      maxSourceSkewHours: json['maxSourceSkewHours'] as int? ?? 24,
    );
  }
}

/// Dashboard snapshot metadata.
class DashboardMetadata {
  const DashboardMetadata({
    required this.dashboardSnapshotId,
    required this.dashboardSchemaVersion,
    required this.dashboardCalculationVersion,
    required this.dashboardCanonicalizationVersion,
    required this.projectId,
    required this.createdAt,
    required this.queryFingerprint,
    required this.dashboardFingerprint,
    required this.status,
    required this.freshness,
    required this.compatibility,
    required this.sectionCount,
    required this.widgetCount,
    required this.availableWidgetCount,
    required this.unavailableWidgetCount,
    required this.warningCount,
    required this.errorCount,
    required this.sourceArtifactCount,
    this.branch,
    this.gitRef,
    this.oldestSourceCreatedAt,
    this.newestSourceCreatedAt,
  });

  static const int currentSchemaVersion = 1;
  static const int currentCalculationVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String dashboardSnapshotId;
  final int dashboardSchemaVersion;
  final int dashboardCalculationVersion;
  final int dashboardCanonicalizationVersion;
  final String projectId;
  final String createdAt;
  final String? branch;
  final String? gitRef;
  final String queryFingerprint;
  final String dashboardFingerprint;
  final DashboardStatus status;
  final DashboardFreshness freshness;
  final DashboardCompatibility compatibility;
  final int sectionCount;
  final int widgetCount;
  final int availableWidgetCount;
  final int unavailableWidgetCount;
  final int warningCount;
  final int errorCount;
  final int sourceArtifactCount;
  final String? oldestSourceCreatedAt;
  final String? newestSourceCreatedAt;

  Map<String, dynamic> toJson() => {
        'dashboardSnapshotId': dashboardSnapshotId,
        'dashboardSchemaVersion': dashboardSchemaVersion,
        'dashboardCalculationVersion': dashboardCalculationVersion,
        'dashboardCanonicalizationVersion': dashboardCanonicalizationVersion,
        'projectId': projectId,
        'createdAt': createdAt,
        if (branch != null) 'branch': branch,
        if (gitRef != null) 'gitRef': gitRef,
        'queryFingerprint': queryFingerprint,
        'dashboardFingerprint': dashboardFingerprint,
        'status': status.wireName,
        'freshness': freshness.wireName,
        'compatibility': compatibility.wireName,
        'sectionCount': sectionCount,
        'widgetCount': widgetCount,
        'availableWidgetCount': availableWidgetCount,
        'unavailableWidgetCount': unavailableWidgetCount,
        'warningCount': warningCount,
        'errorCount': errorCount,
        'sourceArtifactCount': sourceArtifactCount,
        if (oldestSourceCreatedAt != null)
          'oldestSourceCreatedAt': oldestSourceCreatedAt,
        if (newestSourceCreatedAt != null)
          'newestSourceCreatedAt': newestSourceCreatedAt,
      };

  factory DashboardMetadata.fromJson(Map<String, dynamic> json) {
    return DashboardMetadata(
      dashboardSnapshotId: json['dashboardSnapshotId'] as String,
      dashboardSchemaVersion:
          json['dashboardSchemaVersion'] as int? ?? currentSchemaVersion,
      dashboardCalculationVersion:
          json['dashboardCalculationVersion'] as int? ??
              currentCalculationVersion,
      dashboardCanonicalizationVersion:
          json['dashboardCanonicalizationVersion'] as int? ??
              currentCanonicalizationVersion,
      projectId: json['projectId'] as String,
      createdAt: json['createdAt'] as String,
      branch: json['branch'] as String?,
      gitRef: json['gitRef'] as String?,
      queryFingerprint: json['queryFingerprint'] as String,
      dashboardFingerprint: json['dashboardFingerprint'] as String,
      status: DashboardStatusX.fromWireName(json['status'] as String),
      freshness: DashboardFreshnessX.fromWireName(json['freshness'] as String),
      compatibility: DashboardCompatibilityX.fromWireName(
        json['compatibility'] as String,
      ),
      sectionCount: json['sectionCount'] as int,
      widgetCount: json['widgetCount'] as int,
      availableWidgetCount: json['availableWidgetCount'] as int,
      unavailableWidgetCount: json['unavailableWidgetCount'] as int,
      warningCount: json['warningCount'] as int,
      errorCount: json['errorCount'] as int,
      sourceArtifactCount: json['sourceArtifactCount'] as int,
      oldestSourceCreatedAt: json['oldestSourceCreatedAt'] as String?,
      newestSourceCreatedAt: json['newestSourceCreatedAt'] as String?,
    );
  }
}

/// Immutable dashboard snapshot.
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.metadata,
    required this.sections,
    required this.sourceReferences,
    required this.layout,
    required this.warnings,
    required this.errors,
    required this.limitations,
    this.filters = const [],
  });

  final DashboardMetadata metadata;
  final List<DashboardSection> sections;
  final List<DashboardSourceReference> sourceReferences;
  final DashboardLayout layout;
  final List<DashboardWarning> warnings;
  final List<DashboardError> errors;
  final List<DashboardLimitation> limitations;
  final List<String> filters;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'sections': sections.map((s) => s.toJson()).toList(),
        'sourceReferences': sourceReferences.map((r) => r.toJson()).toList(),
        'layout': layout.toJson(),
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
        'limitations': limitations.map((l) => l.toJson()).toList(),
        'filters': filters,
      };

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    return DashboardSnapshot(
      metadata:
          DashboardMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
      sections: (json['sections'] as List<dynamic>)
          .map((e) => DashboardSection.fromJson(e as Map<String, dynamic>))
          .toList(),
      sourceReferences: (json['sourceReferences'] as List<dynamic>)
          .map(
            (e) => DashboardSourceReference.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      layout: DashboardLayout.fromJson(json['layout'] as Map<String, dynamic>),
      warnings: (json['warnings'] as List<dynamic>)
          .map((e) => DashboardWarning.fromJson(e as Map<String, dynamic>))
          .toList(),
      errors: (json['errors'] as List<dynamic>)
          .map((e) => DashboardError.fromJson(e as Map<String, dynamic>))
          .toList(),
      limitations: (json['limitations'] as List<dynamic>)
          .map((e) => DashboardLimitation.fromJson(e as Map<String, dynamic>))
          .toList(),
      filters: (json['filters'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    final sections = (json['sections'] as List<dynamic>)
      ..sort((a, b) => (a as Map)['sectionId']
          .toString()
          .compareTo((b as Map)['sectionId'].toString()));
    json['sections'] = sections;
    final refs = (json['sourceReferences'] as List<dynamic>)
      ..sort((a, b) => (a as Map)['referenceId']
          .toString()
          .compareTo((b as Map)['referenceId'].toString()));
    json['sourceReferences'] = refs;
    final meta = Map<String, dynamic>.from(json['metadata'] as Map);
    meta.remove('createdAt');
    json['metadata'] = meta;
    return json;
  }
}

class DashboardValidationResult {
  const DashboardValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
}
