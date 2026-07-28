// M2.3-R8.4.28 — probe Android real: PackageInfo + bootstrap + resolver (sem mock).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:master_palm/core/produto_stock_write_enforcement.dart';
import 'package:master_palm/core/stock_revision_client_build_bootstrap.dart';
import 'package:master_palm/core/stock_revision_client_build_resolver.dart';
import 'package:master_palm/core/stock_revision_operation_gate.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const expectedBuildRaw = String.fromEnvironment('R8428_EXPECTED_BUILD');

  testWidgets('R8428 client build runtime probe', (tester) async {
    expect(
      expectedBuildRaw,
      isNotEmpty,
      reason: 'R8428_EXPECTED_BUILD must be set via --dart-define',
    );
    final expectedBuild = int.tryParse(expectedBuildRaw);
    expect(expectedBuild, isNotNull, reason: 'R8428_EXPECTED_BUILD must parse');
    expect(expectedBuild!, greaterThan(0));

    StockRevisionClientBuildResolver.instance.resetForTest();

    final info = await PackageInfo.fromPlatform();
    expect(info.version, '1.0.80');
    expect(info.buildNumber, expectedBuildRaw);

    await StockRevisionClientBuildBootstrap.ensureInitialized();

    final resolver = StockRevisionClientBuildResolver.instance;
    final state = resolver.currentState;

    expect(state.rawBuildNumber, expectedBuildRaw);
    expect(state.parsedBuildNumber, expectedBuild);
    expect(state.source, StockRevisionClientBuildSource.packageInfo);
    expect(StockRevisionOperationGate.resolveClientBuildNumber(), expectedBuild);
    expect(expectedBuild, greaterThanOrEqualTo(kMinStockRevisionClientVersion));
  });
}
