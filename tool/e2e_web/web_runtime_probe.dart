// Probe Web E2E — PackageInfo → bootstrap → resolver → gate (versionado R8.4.33).
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:master_palm/core/stock_revision_client_build_bootstrap.dart';
import 'package:master_palm/core/stock_revision_client_build_resolver.dart';
import 'package:master_palm/core/stock_revision_operation_gate.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<Map<String, Object?>> runWebRuntimeProbe() async {
  final info = await PackageInfo.fromPlatform();
  await StockRevisionClientBuildBootstrap.ensureInitialized();
  final state = StockRevisionClientBuildResolver.instance.currentState;
  final resolved = StockRevisionOperationGate.resolveClientBuildNumber();
  return {
    'version': info.version,
    'buildNumber': info.buildNumber,
    'rawBuildNumber': state.rawBuildNumber,
    'parsedBuildNumber': state.parsedBuildNumber,
    'source': state.source.name,
    'resolved': resolved,
  };
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WebRuntimeProbeApp());
}

class WebRuntimeProbeApp extends StatefulWidget {
  const WebRuntimeProbeApp({super.key});

  @override
  State<WebRuntimeProbeApp> createState() => _WebRuntimeProbeAppState();
}

class _WebRuntimeProbeAppState extends State<WebRuntimeProbeApp> {
  String _output = 'loading...';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final payload = await runWebRuntimeProbe();
      final json = jsonEncode(payload);
      html.window.console.log('R8433_WEB_PROBE_JSON=$json');
      if (mounted) setState(() => _output = json);
    } catch (e, st) {
      final err = 'ERR: $e\n$st';
      html.window.console.log('R8433_WEB_PROBE_ERROR=$err');
      if (mounted) setState(() => _output = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: SelectableText(_output, key: const Key('probe'))),
      ),
    );
  }
}
