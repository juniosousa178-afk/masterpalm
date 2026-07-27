import '../core/provider_registry.dart';
import '../interfaces/cicd_integration_provider.dart';
import '../interfaces/release_evidence_provider.dart';
import '../interfaces/release_supply_chain_provider.dart';
import '../providers/platform_cicd_integration_provider.dart';
import 'cicd_integration_policy_registry.dart';
import 'cicd_integration_source_resolver.dart';
import 'policies/deployment_integration_policy_v1.dart';
import 'policies/pipeline_execution_policy_v1.dart';
import 'policies/pipeline_integration_policy_v1.dart';
import 'stores/in_memory_cicd_integration_store.dart';

/// Composition root for CI/CD Integration.
class CicdIntegrationPlatformBootstrap {
  const CicdIntegrationPlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    CicdIntegrationProvider? cicdIntegrationProvider,
    InMemoryCicdIntegrationStore? store,
    PipelineIntegrationPolicyRegistry? pipelineIntegrationPolicyRegistry,
    PipelineExecutionPolicyRegistry? pipelineExecutionPolicyRegistry,
    DeploymentIntegrationPolicyRegistry? deploymentIntegrationPolicyRegistry,
  }) {
    if (registry.isRegistered<CicdIntegrationProvider>()) return;

    if (!registry.isRegistered<ReleaseEvidenceProvider>()) {
      throw StateError(
        'ReleaseEvidenceProvider must be registered before CicdIntegrationProvider',
      );
    }
    if (!registry.isRegistered<ReleaseSupplyChainProvider>()) {
      throw StateError(
        'ReleaseSupplyChainProvider must be registered before CicdIntegrationProvider',
      );
    }

    final pipelineIntegrationPolicies = pipelineIntegrationPolicyRegistry ??
        PipelineIntegrationPolicyRegistry();
    if (!pipelineIntegrationPolicies.isFrozen) {
      pipelineIntegrationPolicies
          .register(PipelineIntegrationPolicyV1.create());
      pipelineIntegrationPolicies.freeze();
    }

    final pipelineExecutionPolicies =
        pipelineExecutionPolicyRegistry ?? PipelineExecutionPolicyRegistry();
    if (!pipelineExecutionPolicies.isFrozen) {
      pipelineExecutionPolicies.register(PipelineExecutionPolicyV1.create());
      pipelineExecutionPolicies.freeze();
    }

    final deploymentIntegrationPolicies = deploymentIntegrationPolicyRegistry ??
        DeploymentIntegrationPolicyRegistry();
    if (!deploymentIntegrationPolicies.isFrozen) {
      deploymentIntegrationPolicies.register(
        DeploymentIntegrationPolicyV1.create(),
      );
      deploymentIntegrationPolicies.freeze();
    }

    final sourceResolver = CicdIntegrationSourceResolver(
      releaseEvidenceProvider: registry.resolve<ReleaseEvidenceProvider>(),
      releaseSupplyChainProvider:
          registry.resolve<ReleaseSupplyChainProvider>(),
      pipelineIntegrationPolicyRegistry: pipelineIntegrationPolicies,
      pipelineExecutionPolicyRegistry: pipelineExecutionPolicies,
      deploymentIntegrationPolicyRegistry: deploymentIntegrationPolicies,
    );

    registry.registerInstance<CicdIntegrationProvider>(
      cicdIntegrationProvider ??
          PlatformCicdIntegrationProvider(
            sourceResolver: sourceResolver,
            pipelineIntegrationPolicyRegistry: pipelineIntegrationPolicies,
            pipelineExecutionPolicyRegistry: pipelineExecutionPolicies,
            deploymentIntegrationPolicyRegistry: deploymentIntegrationPolicies,
            store: store ?? InMemoryCicdIntegrationStore(),
          ),
    );
  }
}
