import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('CloudDesignAdmissionGate', () {
    const evaluator = PersistentArtifactRealCloudAdapterAdmissionEvaluator();

    test('admission evaluator com critérios default permanece notEvaluated',
        () {
      final decision = evaluator.evaluate(
        criteria: const PersistentArtifactRealCloudAdapterAdmissionCriteria(),
      );
      expect(decision.status, RealCloudAdapterAdmissionStatus.notEvaluated);
      expect(decision.prototypeAdmissionGranted, isFalse);
      expect(decision.stagingApproved, isFalse);
      expect(decision.productionApproved, isFalse);
    });

    test('documentos draft não alteram critérios booleanos', () {
      const criteria = PersistentArtifactRealCloudAdapterAdmissionCriteria();
      expect(criteria.targetProviderSelected, isFalse);
      expect(criteria.officialSdkDecisionRecorded, isFalse);
      expect(criteria.allSatisfied, isFalse);
    });

    test('recommendation não produz approvedForPrototype sem manual approval',
        () {
      final decision = evaluator.evaluate(
        criteria: const PersistentArtifactRealCloudAdapterAdmissionCriteria(
          targetProviderSelected: true,
          protocolSpecificationReviewed: true,
        ),
      );
      expect(decision.status, RealCloudAdapterAdmissionStatus.incomplete);
      expect(decision.prototypeAdmissionGranted, isFalse);
    });

    test('staging e production permanecem bloqueados no environment gate', () {
      const gate = PersistentArtifactCloudEnvironmentGate();
      for (final env in [
        PersistentArtifactRuntimeEnvironment.staging,
        PersistentArtifactRuntimeEnvironment.production,
      ]) {
        final decision = gate.evaluate(
          backendId: 'b1',
          runtimeEnvironment: env,
          classification:
              PersistentArtifactCloudBridgeClassification.offlineSimulation,
        );
        expect(decision.allowed, isFalse);
      }
    });

    test('nenhum SDK cloud em pubspec.yaml', () {
      final content = File('pubspec.yaml').readAsStringSync().toLowerCase();
      for (final token in [
        'aws_',
        'amazon_',
        'google_cloud',
        'googleapis',
        'azure_storage',
        'minio',
        's3_',
      ]) {
        expect(content.contains(token), isFalse, reason: 'forbidden: $token');
      }
    });

    test('nenhuma dependência HTTP adicionada', () {
      final content = File('pubspec.yaml').readAsStringSync();
      expect(content.contains('http:'), isFalse);
      expect(content.contains('dio:'), isFalse);
    });

    test('nenhum adapter real em lib', () {
      final cloudLib = Directory('lib/persistent_artifacts/cloud');
      for (final file in cloudLib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final name = file.path.split(Platform.pathSeparator).last;
        expect(name.contains('s3_adapter'), isFalse);
        expect(name.contains('gcs_adapter'), isFalse);
        expect(name.contains('azure_adapter'), isFalse);
      }
    });

    test('fake bridge permanece somente em test/', () {
      final libHasFake = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .any((f) => f.path.contains('fake_persistent_artifact_cloud'));
      expect(libHasFake, isFalse);
      final testHasFake = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .any((f) => f.path.contains('fake_persistent_artifact_cloud'));
      expect(testHasFake, isTrue);
    });

    test('lib cloud sem HttpClient Socket ou credential loader', () {
      final dir = Directory('lib/persistent_artifacts/cloud');
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final content = file.readAsStringSync();
        expect(content.contains('HttpClient'), isFalse);
        expect(content.contains('dart:io'), isFalse);
        expect(content.contains('CredentialLoader'), isFalse);
      }
    });

    test('design docs existem sem alterar contratos lib', () {
      final docsDir = Directory(
        'docs/persistent_artifacts/cloud_adapter_framework',
      );
      expect(File('${docsDir.path}/provider_recommendation.md').existsSync(),
          isTrue);
      expect(File('${docsDir.path}/credential_architecture.md').existsSync(),
          isTrue);
      expect(
          File('${docsDir.path}/real_adapter_design_review_package.md')
              .existsSync(),
          isTrue);
    });

    test('closure gate mantém realAdapterWorkAuthorized false', () {
      const gate = CloudFrameworkClosureGate(
        platformFormatPassed: true,
        platformAnalyzePassed: true,
        platformCloudTestsPassed: true,
        platformPersistentArtifactTestsPassed: true,
        platformFullSuitePassed: true,
        guardianFormatPassed: true,
        guardianAnalyzePassed: true,
        guardianTestsPassed: true,
        guardianTargetedAnalysisPassed: true,
        guardianTargetedAnalysisComplete: true,
        guardianTargetedDeterministic: true,
        guardianTargetedFiles: 774,
        guardianTargetedUnresolved: 0,
        guardianTargetedFingerprint: 'fp',
        guardianRepositoryAnalysisStatus: 'attributed',
        repositoryFindingsAttributed: true,
        silentExclusionTestPassed: true,
        cloudBootstrapEmpty: true,
        realCloudBridgeAbsent: true,
        networkAbsent: true,
        sdkAbsent: true,
        credentialsAbsent: true,
        stagingBlocked: true,
        productionBlocked: true,
        admissionStatus: RealCloudAdapterAdmissionStatus.notEvaluated,
        manualApprovalReferencePresent: false,
        realAdapterWorkAuthorized: false,
      );
      expect(gate.realAdapterWorkAuthorized, isFalse);
      final validation =
          const CloudFrameworkClosureGateValidator().validate(gate);
      expect(validation.allowed, isTrue);
    });

    test('evaluator determinístico para input fixo', () {
      const criteria = PersistentArtifactRealCloudAdapterAdmissionCriteria(
        protocolSpecificationReviewed: true,
      );
      final a = evaluator.evaluate(criteria: criteria);
      final b = evaluator.evaluate(criteria: criteria);
      expect(a.toComparableJson(), b.toComparableJson());
    });
  });
}
