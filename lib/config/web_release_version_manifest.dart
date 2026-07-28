// Contrato version.json Web — PackageInfo + metadados de deploy (R8.4.33).

import 'dart:convert';

import 'package:master_palm/config/mp_environment_config.dart';
import 'package:master_palm/core/produto_stock_write_enforcement.dart';

/// Manifesto publicado em build/web/version.json.
class WebReleaseVersionManifest {
  const WebReleaseVersionManifest({
    required this.appName,
    required this.version,
    required this.buildNumber,
    required this.packageName,
    required this.buildId,
    required this.gitCommit,
    required this.hostingTarget,
    required this.expectedDomain,
    this.siteId,
  });

  final String appName;
  final String version;
  final String buildNumber;
  final String packageName;
  final String buildId;
  final String gitCommit;
  final String hostingTarget;
  final String expectedDomain;
  final String? siteId;

  static const expectedHostingTarget = 'masterpalm-58c46';
  static const expectedDomainCanonical = 'app.mastepalm.com.br';

  factory WebReleaseVersionManifest.fromPubspecAndGit({
    required String pubspecVersionLine,
    required String buildId,
    required String gitCommit,
    String appName = 'master_palm',
    String packageName = 'master_palm',
    String hostingTarget = expectedHostingTarget,
    String expectedDomain = expectedDomainCanonical,
    String? siteId,
  }) {
    final parsed = parsePubspecVersion(pubspecVersionLine);
    return WebReleaseVersionManifest(
      appName: appName,
      version: parsed.version,
      buildNumber: parsed.buildNumber,
      packageName: packageName,
      buildId: buildId,
      gitCommit: gitCommit,
      hostingTarget: hostingTarget,
      expectedDomain: expectedDomain,
      siteId: siteId ?? hostingTarget,
    );
  }

  Map<String, dynamic> toJson() => {
        'app_name': appName,
        'version': version,
        'build_number': buildNumber,
        'package_name': packageName,
        'buildId': buildId,
        'gitCommit': gitCommit,
        'hostingTarget': hostingTarget,
        'siteId': siteId ?? hostingTarget,
        'expectedDomain': expectedDomain,
      };

  factory WebReleaseVersionManifest.fromJson(Map<String, dynamic> json) {
    return WebReleaseVersionManifest(
      appName: _req(json, 'app_name'),
      version: _req(json, 'version'),
      buildNumber: _req(json, 'build_number'),
      packageName: _req(json, 'package_name'),
      buildId: _req(json, 'buildId'),
      gitCommit: _req(json, 'gitCommit'),
      hostingTarget: _req(json, 'hostingTarget'),
      expectedDomain: _req(json, 'expectedDomain'),
      siteId: json['siteId']?.toString(),
    );
  }

  static String _req(Map<String, dynamic> json, String key) {
    final v = json[key]?.toString().trim() ?? '';
    if (v.isEmpty) {
      throw FormatException('version.json: campo obrigatório ausente: $key');
    }
    return v;
  }

  /// Falha se manifesto não atender PackageInfo + deploy.
  void validate({required String expectedGitCommit}) {
    if (appName.isEmpty || version.isEmpty || packageName.isEmpty) {
      throw FormatException('PackageInfo fields vazios');
    }
    final bn = int.tryParse(buildNumber);
    if (bn == null) {
      throw FormatException('build_number não é inteiro: $buildNumber');
    }
    MpEnvironmentConfig.assertBuildNumberCompatible(bn);
    if (gitCommit != expectedGitCommit) {
      throw FormatException(
        'gitCommit=$gitCommit != HEAD=$expectedGitCommit',
      );
    }
    if (hostingTarget != expectedHostingTarget) {
      throw FormatException('hostingTarget inválido: $hostingTarget');
    }
    if (expectedDomain != expectedDomainCanonical) {
      throw FormatException('expectedDomain inválido: $expectedDomain');
    }
    if (buildId.trim().isEmpty) {
      throw FormatException('buildId vazio');
    }
  }

  /// Detecta regressão: só metadados de deploy sem PackageInfo.
  static bool isDeployMetadataOnly(Map<String, dynamic> json) {
    final hasPackageInfo = json.containsKey('build_number') &&
        (json['build_number']?.toString().trim().isNotEmpty ?? false);
    final hasDeploy = json.containsKey('buildId') || json.containsKey('gitCommit');
    return hasDeploy && !hasPackageInfo;
  }

  String toJsonString() => '${jsonEncode(toJson())}\n';
}

/// Resultado do parse de `version: X+Y` no pubspec.
class PubspecAppVersion {
  const PubspecAppVersion({required this.version, required this.buildNumber});
  final String version;
  final String buildNumber;
}

PubspecAppVersion parsePubspecVersion(String pubspecContent) {
  final match = RegExp(
    r'^version:\s*([0-9.]+)\+([0-9]+)\s*$',
    multiLine: true,
  ).firstMatch(pubspecContent);
  if (match == null) {
    throw FormatException('pubspec.yaml: linha version inválida ou ausente');
  }
  final version = match.group(1)!;
  final buildNumber = match.group(2)!;
  if (version.isEmpty || buildNumber.isEmpty) {
    throw FormatException('pubspec version/build vazios');
  }
  final bn = int.tryParse(buildNumber);
  if (bn == null || bn <= 0) {
    throw FormatException('build_number pubspec inválido: $buildNumber');
  }
  MpEnvironmentConfig.assertBuildNumberCompatible(bn);
  return PubspecAppVersion(version: version, buildNumber: buildNumber);
}
