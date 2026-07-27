import 'dart:async';

import 'package:master_palm/core/stock_revision_client_build_resolver.dart';

/// Default compatible client build for stock-domain tests (R8.4.6).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  StockRevisionClientBuildResolver.instance.enableTestDefaults();
  StockRevisionClientBuildResolver.instance.setTestOverride(285);
  await testMain();
}
