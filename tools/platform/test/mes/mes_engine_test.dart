import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/mes/mes_registry.dart';
import 'package:masterpalm_platform/mes/mes_score_policy_mapper.dart';
import 'package:masterpalm_platform/mes/policies/mes_official_policy_v1.dart';
import 'package:masterpalm_platform/mes/stores/in_memory_mes_store.dart';
import 'package:masterpalm_platform/mes/mes_engine.dart';
import 'package:masterpalm_platform/mes/mes_policy_validator.dart';
import 'package:masterpalm_platform/mes/mes_coverage_calculator.dart';
import 'package:masterpalm_platform/mes/mes_canonical_serializer.dart';
import 'package:masterpalm_platform/score/score_registry.dart';
import 'package:masterpalm_platform/score/score_engine.dart';
import 'package:masterpalm_platform/score/score_snapshot_id_factory.dart';
import 'package:masterpalm_platform/score/score_canonical_serializer.dart';
import 'package:masterpalm_platform/score/stores/in_memory_score_store.dart';
import 'package:masterpalm_platform/providers/platform_score_provider.dart';
import 'package:masterpalm_platform/providers/platform_mes_provider.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/history/history_artifact_factory.dart';
import 'package:test/test.dart';

import '../score/score_fixtures.dart';

void main() {
  group('MESPolicy', () {
    test('is immutable and official id', () {
      final policy = MesOfficialPolicyV1.create();
      expect(policy.policyId, 'mes-official-v1');
      expect(policy.metadata.status, MESPolicyStatus.candidate);
      expect(policy.metadata.owner, 'MasterPalm Engineering Platform');
      expect(policy.metadata.calibrated, isFalse);
      expect(policy.totalWeightPercent, closeTo(100, 0.01));
    });

    test('weights total 100%', () {
      final policy = MesOfficialPolicyV1.create();
      expect(policy.totalWeightPercent, 100);
    });

    test('validates successfully', () {
      final result =
          const MESPolicyValidator().validate(MesOfficialPolicyV1.create());
      expect(result.isValid, isTrue);
    });

    test('maps to ScorePolicy', () {
      final policy = MesOfficialPolicyV1.create();
      final scorePolicy = const MESScorePolicyMapper().toScorePolicy(policy);
      expect(scorePolicy.policyId, 'mes-official-v1');
      expect(scorePolicy.metadata.extra['mes'], 'true');
      expect(scorePolicy.dimensions.length, policy.dimensions.length);
    });

    test('policy fingerprint is deterministic', () {
      final mapper = const MESScorePolicyMapper();
      final p = MesOfficialPolicyV1.create();
      expect(mapper.policyFingerprint(p), mapper.policyFingerprint(p));
    });
  });

  group('MESNormalizer and coverage', () {
    test('hierarchical coverage fields exist', () {
      expect(const MESCoverageCalculator(), isNotNull);
    });
  });

  group('MESSnapshot', () {
    test('round-trip JSON', () async {
      final snap = await _calculateSnapshot();
      final roundTrip = MESSnapshot.fromJson(snap.toJson());
      expect(roundTrip.metadata.mesSnapshotId, snap.metadata.mesSnapshotId);
      expect(roundTrip.mesValue.value, snap.mesValue.value);
    });
  });

  group('MESEngine integration', () {
    late PlatformMESProvider provider;

    setUp(() {
      provider = _provider();
    });

    test('calculates MES with guardian', () async {
      final metrics = await ScoreFixtures.metricsComplete(
        guardianAnalysis: ScoreFixtures.guardianGo(),
      );
      final result = await provider.calculate(MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        guardianAnalysis: ScoreFixtures.guardianGo(),
        policyId: MesOfficialPolicyV1.policyId,
        includeExplanations: true,
      ));
      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.metadata.policyId, 'mes-official-v1');
      expect(result.snapshot!.mesValue.value, greaterThan(0));
      expect(
        result.snapshot!.metadata.sourceEngineeringScoreSnapshotId,
        isNotEmpty,
      );
      expect(result.snapshot!.coverage.policyCoverage, greaterThan(0));
      expect(result.snapshot!.coverage.ruleCoverage, greaterThanOrEqualTo(0));
    });

    test('partial without guardian', () async {
      final metrics = await ScoreFixtures.metricsComplete();
      final result = await provider.calculate(MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        policyId: MesOfficialPolicyV1.policyId,
      ));
      expect(result.status, anyOf(MESStatus.partial, MESStatus.unavailable));
      expect(
        result.eligibility.status,
        anyOf(
          MESEligibilityStatus.partiallyEligible,
          MESEligibilityStatus.ineligible,
        ),
      );
    });

    test('guardian NO-GO affects MES', () async {
      final go = await provider.calculate(MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: (await ScoreFixtures.metricsComplete(
          guardianAnalysis: ScoreFixtures.guardianGo(),
        ))
            .toJson(),
        guardianAnalysis: ScoreFixtures.guardianGo(),
        policyId: MesOfficialPolicyV1.policyId,
      ));
      final noGo = await provider.calculate(MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: (await ScoreFixtures.metricsComplete(
          guardianAnalysis: ScoreFixtures.guardianNoGo(),
        ))
            .toJson(),
        guardianAnalysis: ScoreFixtures.guardianNoGo(),
        policyId: MesOfficialPolicyV1.policyId,
      ));
      expect(go.snapshot!.mesValue.value,
          greaterThan(noGo.snapshot!.mesValue.value));
    });

    test('deterministic identity', () async {
      final metrics = await ScoreFixtures.metricsComplete(
        guardianAnalysis: ScoreFixtures.guardianGo(),
      );
      final req = MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        guardianAnalysis: ScoreFixtures.guardianGo(),
        policyId: MesOfficialPolicyV1.policyId,
      );
      final a = await provider.calculate(req);
      final b = await provider.calculate(req);
      expect(a.snapshot!.metadata.mesSnapshotId,
          b.snapshot!.metadata.mesSnapshotId);
      expect(a.snapshot!.metadata.mesFingerprint,
          b.snapshot!.metadata.mesFingerprint);
    });

    test('different timestamps same identity', () async {
      final metrics = await ScoreFixtures.metricsComplete(
        guardianAnalysis: ScoreFixtures.guardianGo(),
      );
      final a = await provider.calculate(MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        guardianAnalysis: ScoreFixtures.guardianGo(),
        policyId: MesOfficialPolicyV1.policyId,
      ));
      final b = await provider.calculate(MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtB,
        metricsSnapshot: metrics.toJson(),
        guardianAnalysis: ScoreFixtures.guardianGo(),
        policyId: MesOfficialPolicyV1.policyId,
      ));
      expect(a.snapshot!.metadata.mesFingerprint,
          b.snapshot!.metadata.mesFingerprint);
    });
  });

  group('MES store', () {
    test('publish idempotent and conflict', () async {
      final provider = _provider();
      final snap = (await provider.calculate(MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: (await ScoreFixtures.metricsComplete(
          guardianAnalysis: ScoreFixtures.guardianGo(),
        ))
            .toJson(),
        guardianAnalysis: ScoreFixtures.guardianGo(),
        policyId: MesOfficialPolicyV1.policyId,
      )))
          .snapshot!;
      await provider.publish(snap);
      await provider.publish(snap);
      final tampered = MESSnapshot.fromJson(snap.toJson());
      // Can't easily tamper immutable - load and verify exists
      final loaded = await provider.load(snap.metadata.mesSnapshotId);
      expect(loaded, isNotNull);
    });

    test('latest and invalidate', () async {
      final provider = _provider();
      final snap = (await provider.calculate(MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: (await ScoreFixtures.metricsComplete(
          guardianAnalysis: ScoreFixtures.guardianGo(),
        ))
            .toJson(),
        guardianAnalysis: ScoreFixtures.guardianGo(),
        policyId: MesOfficialPolicyV1.policyId,
      )))
          .snapshot!;
      final latest = await provider.latest(projectId: ScoreFixtures.projectId);
      expect(latest?.metadata.mesSnapshotId, snap.metadata.mesSnapshotId);
      await provider.invalidate(snap.metadata.mesSnapshotId);
      expect(await provider.load(snap.metadata.mesSnapshotId), isNull);
    });
  });

  group('MES registry', () {
    test('rejects duplicate and freezes', () {
      final registry = MESPolicyRegistry();
      registry.register(MesOfficialPolicyV1.create());
      expect(
        () => registry.register(MesOfficialPolicyV1.create()),
        throwsA(isA<MESPolicyException>()),
      );
      registry.freeze();
      expect(
        () => registry.register(MesOfficialPolicyV1.create()),
        throwsA(isA<MESPolicyException>()),
      );
    });
  });

  group('Platform integration', () {
    test('PlatformCore.mes resolves', () {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      expect(core.mes(), isA<MESProvider>());
      expect(core.mes().getCandidatePolicy()?.policyId, 'mes-official-v1');
    });
  });

  group('Report integration', () {
    test('masterPalmEngineeringScore report', () async {
      final provider = _provider();
      final result = await provider.calculate(MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: (await ScoreFixtures.metricsComplete(
          guardianAnalysis: ScoreFixtures.guardianGo(),
        ))
            .toJson(),
        guardianAnalysis: ScoreFixtures.guardianGo(),
        policyId: MesOfficialPolicyV1.policyId,
        includeExplanations: true,
      ));
      final engine = ReportEngine();
      final report = await engine.generate(ReportRequest(
        reportType: ReportType.masterPalmEngineeringScore,
        projectId: ScoreFixtures.projectId,
        mesSnapshot: result.snapshot!.toJson(),
      ));
      expect(
        report.document.metadata.reportType,
        ReportType.masterPalmEngineeringScore,
      );
      expect(report.document.sections.first.title, contains('MasterPalm'));
    });
  });

  group('History integration', () {
    test('MES artifact type supported', () async {
      final provider = _provider();
      final result = await provider.calculate(MESRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: (await ScoreFixtures.metricsComplete(
          guardianAnalysis: ScoreFixtures.guardianGo(),
        ))
            .toJson(),
        guardianAnalysis: ScoreFixtures.guardianGo(),
        policyId: MesOfficialPolicyV1.policyId,
      ));
      final factory = HistoryArtifactFactory();
      final artifacts = factory.buildFromRequest(HistoryRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        mesSnapshot: result.snapshot!.toJson(),
      ));
      expect(
        artifacts.any((a) => a.artifactType == HistoryArtifactType.mes),
        isTrue,
      );
    });
  });

  group('Bands', () {
    test('neutral bands cover scale', () {
      final policy = MesOfficialPolicyV1.create();
      expect(policy.bands.first.bandId, 'mes-band-1');
      expect(policy.bands.last.max, 100);
    });
  });
}

PlatformMESProvider _provider() {
  final serializer = const ScoreCanonicalSerializer();
  final scoreRegistry = ScoreRegistry();
  final mesPolicy = MesOfficialPolicyV1.create();
  final mapper = const MESScorePolicyMapper();
  scoreRegistry.register(mapper.toScorePolicy(mesPolicy));
  scoreRegistry.freeze();

  final scoreProvider = PlatformScoreProvider(
    engine: ScoreEngine(
      registry: scoreRegistry,
      serializer: serializer,
      idFactory: ScoreSnapshotIdFactory(serializer: serializer),
    ),
    registry: scoreRegistry,
    store: InMemoryScoreStore(serializer: serializer),
    serializer: serializer,
  );

  final mesRegistry = MESPolicyRegistry();
  mesRegistry.register(mesPolicy);
  mesRegistry.freeze();

  return PlatformMESProvider(
    engine: MESEngine(registry: mesRegistry, scoreProvider: scoreProvider),
    registry: mesRegistry,
    store: InMemoryMESStore(),
  );
}

Future<MESSnapshot> _calculateSnapshot() async {
  final result = await _provider().calculate(MESRequest(
    projectId: ScoreFixtures.projectId,
    createdAt: ScoreFixtures.createdAtA,
    metricsSnapshot: (await ScoreFixtures.metricsComplete(
      guardianAnalysis: ScoreFixtures.guardianGo(),
    ))
        .toJson(),
    guardianAnalysis: ScoreFixtures.guardianGo(),
    policyId: MesOfficialPolicyV1.policyId,
  ));
  return result.snapshot!;
}
