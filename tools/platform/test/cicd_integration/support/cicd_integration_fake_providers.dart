import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_query.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_request.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_query.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_request.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_result.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_snapshot.dart';

/// Fake release evidence provider that tracks upstream evaluate calls.
///
/// Must never be invoked during CI/CD source resolution when artifacts are injected.
class FakeReleaseEvidenceProviderForCicd implements ReleaseEvidenceProvider {
  FakeReleaseEvidenceProviderForCicd({this.loaded, this.latestBundle});

  ReleaseEvidenceBundle? loaded;
  ReleaseEvidenceBundle? latestBundle;
  int loadCalls = 0;
  int latestCalls = 0;
  int evaluateCalls = 0;
  int evaluateAndPublishCalls = 0;
  int publishCalls = 0;

  @override
  Future<ReleaseEvidenceResult> evaluate(ReleaseEvidenceRequest request) async {
    evaluateCalls++;
    throw StateError('ReleaseEvidenceProvider.evaluate must not be called');
  }

  @override
  Future<ReleaseEvidenceResult> evaluateAndPublish(
    ReleaseEvidenceRequest request,
  ) async {
    evaluateAndPublishCalls++;
    throw StateError(
      'ReleaseEvidenceProvider.evaluateAndPublish must not be called',
    );
  }

  @override
  Future<void> publish(ReleaseEvidenceBundle bundle) async {
    publishCalls++;
    throw StateError('ReleaseEvidenceProvider.publish must not be called');
  }

  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async {
    latestCalls++;
    return latestBundle;
  }

  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) async =>
      const [];

  @override
  Future<void> invalidate(String bundleId) async {}
}

/// Fake release supply chain provider that tracks upstream evaluate calls.
///
/// Must never be invoked during CI/CD source resolution when artifacts are injected.
class FakeReleaseSupplyChainProviderForCicd
    implements ReleaseSupplyChainProvider {
  FakeReleaseSupplyChainProviderForCicd({this.loaded, this.latestSnapshot});

  ReleaseSupplyChainSnapshot? loaded;
  ReleaseSupplyChainSnapshot? latestSnapshot;
  int loadCalls = 0;
  int latestCalls = 0;
  int evaluateCalls = 0;
  int evaluateAndPublishCalls = 0;
  int publishCalls = 0;

  @override
  Future<ReleaseSupplyChainResult> evaluate(
    ReleaseSupplyChainRequest request,
  ) async {
    evaluateCalls++;
    throw StateError('ReleaseSupplyChainProvider.evaluate must not be called');
  }

  @override
  Future<ReleaseSupplyChainResult> evaluateAndPublish(
    ReleaseSupplyChainRequest request,
  ) async {
    evaluateAndPublishCalls++;
    throw StateError(
      'ReleaseSupplyChainProvider.evaluateAndPublish must not be called',
    );
  }

  @override
  Future<void> publish(ReleaseSupplyChainSnapshot snapshot) async {
    publishCalls++;
    throw StateError('ReleaseSupplyChainProvider.publish must not be called');
  }

  @override
  Future<ReleaseSupplyChainSnapshot?> load(String snapshotId) async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<ReleaseSupplyChainSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? supplyChainPolicyId,
  }) async {
    latestCalls++;
    return latestSnapshot;
  }

  @override
  Future<List<ReleaseSupplyChainSnapshot>> query(
    ReleaseSupplyChainQuery query,
  ) async =>
      const [];

  @override
  Future<void> invalidate(String snapshotId) async {}
}
