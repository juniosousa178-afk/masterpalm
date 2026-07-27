// M2.3-R8.4.26 — probe PackageInfo + resolver em runtime de teste (pubspec 285).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/stock_revision_client_build_resolver.dart';
import 'package:master_palm/core/stock_revision_operation_gate.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const packageInfoChannel =
      MethodChannel('dev.fluttercommunity.plus/package_info');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, (call) async {
      return <String, dynamic>{
        'appName': 'MasterPalm',
        'packageName': 'com.masterpalm.app',
        'version': '1.0.80',
        'buildNumber': '285',
        'buildSignature': '',
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, null);
    StockRevisionOperationGate.resetDebugOverrides();
  });

  test('PACKAGEINFO_RUNTIME_BUILD_NUMBER_285_CONFIRMED via PackageInfo', () async {
    final info = await PackageInfo.fromPlatform();
    expect(info.version, '1.0.80');
    expect(info.buildNumber, '285');

    StockRevisionClientBuildResolver.instance.resetForTest(
      leaveUninitialized: true,
    );
    await StockRevisionClientBuildResolver.instance.initialize();

    expect(
      StockRevisionClientBuildResolver.instance.requireBuildNumber(),
      285,
    );
    expect(
      StockRevisionClientBuildResolver.instance.currentState.source,
      StockRevisionClientBuildSource.packageInfo,
    );
    expect(
      () => StockRevisionOperationGate.assertAllowed(
        StockRevisionOperationKind.venda,
      ),
      returnsNormally,
    );
  });

  test('REAL_BUILD_95_BLOCKED_BY_GATE', () {
    StockRevisionClientBuildResolver.instance.initializeFromRawForTest('95');
    expect(
      StockRevisionClientBuildResolver.instance.requireBuildNumber(),
      95,
    );
    expect(
      () => StockRevisionOperationGate.assertAllowed(
        StockRevisionOperationKind.venda,
      ),
      throwsA(isA<StockRevisionUpdateRequiredException>()),
    );
  });
}
