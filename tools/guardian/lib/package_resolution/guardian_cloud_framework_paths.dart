import 'guardian_cryptographic_adapter_paths.dart';

/// Normative cloud, filesystem and integration paths for Sprint 05.3.2 closure.
///
/// Used to ensure framework components are not silently excluded from analysis.
class GuardianCloudFrameworkPaths {
  const GuardianCloudFrameworkPaths._();

  static const cloudOperationalPaths = <String>[
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_backend_bridge.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_backend_registration.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_backend_registration_handle.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_backend_policy_evaluator.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_bridge_classification.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_capability.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_environment_gate.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_fingerprint.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_operation_models.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_operation_status.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_operations_provider.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_operations_service.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_retry_classifier.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_staging_governance_evaluator.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_status_mapper.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_cloud_validators.dart',
    'lib/persistent_artifacts/cloud/persistent_artifact_real_cloud_adapter_admission_evaluator.dart',
  ];

  static const cloudModelPaths = <String>[
    'lib/models/persistent_artifacts/cloud/persistent_artifact_cloud_enums.dart',
    'lib/models/persistent_artifacts/cloud/persistent_artifact_cloud_models.dart',
    'lib/models/persistent_artifacts/cloud/persistent_artifact_real_cloud_adapter_admission.dart',
  ];

  static const filesystemAdapterPaths = <String>[
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_artifact_backend.dart',
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_backend_config.dart',
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_backend_factory.dart',
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_backend_result.dart',
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_content_handle.dart',
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_content_store.dart',
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_location_resolver.dart',
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_manifest_store.dart',
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_path_resolver.dart',
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_physical_backend_bridge.dart',
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_quarantine_provider.dart',
    'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_recovery_inspector.dart',
  ];

  static const integrationPaths = <String>[
    'lib/persistent_artifacts/persistent_artifact_backend_registry_impl.dart',
    'lib/persistent_artifacts/composition/persistent_artifact_local_reference_composition.dart',
    'lib/providers/platform_persistent_artifact_provider.dart',
  ];

  static const cloudPathPrefixes = <String>[
    'lib/persistent_artifacts/cloud/',
    'lib/models/persistent_artifacts/cloud/',
  ];

  static const filesystemPathPrefix =
      'lib/persistent_artifacts/adapters/filesystem/';

  static const cryptographicTrustPathPrefix = 'lib/cryptographic_trust/';

  static List<String> get allRequiredPaths => [
        ...cloudOperationalPaths,
        ...cloudModelPaths,
        ...filesystemAdapterPaths,
        ...integrationPaths,
        ...GuardianCryptographicAdapterPaths.adapterRelativePaths,
      ];
}
