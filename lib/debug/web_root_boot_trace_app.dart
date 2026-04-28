import 'dart:async' show unawaited;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:master_palm/catalog/catalog_initial_web_route.dart';
import 'package:master_palm/web/platform_stub.dart' if (dart.library.html) 'package:master_palm/web/platform_web.dart' as web_plat;

/// Diagnóstico leve na **raiz do web app** (`?diag=1&bootTrace=1` + decisão [appRoot]).
///
/// **“iPhone” aqui = Safari / Chrome / WebView (ex.: WhatsApp) a abrir
/// `https://app.mastepalm.com.br` — Flutter Web, não app iOS nativo.**
///
/// **Não lê [Firebase.apps] no `build` nem antes de um [Firebase.initializeApp] bem-sucedido.**
class WebRootBootTraceApp extends StatefulWidget {
  const WebRootBootTraceApp({
    super.key,
    required this.initialUri,
    required this.routeDecision,
    required this.isPublicCatalogPath,
    required this.isAppHost,
    required this.buildId,
    required this.initFirebase,
    required this.onContinue,
  });

  final Uri initialUri;
  final CatalogRouteDecision routeDecision;
  final bool isPublicCatalogPath;
  final bool isAppHost;
  final String buildId;
  final Future<bool> Function() initFirebase;
  final VoidCallback onContinue;

  @override
  State<WebRootBootTraceApp> createState() => _WebRootBootTraceState();
}

class _WebRootBootTraceState extends State<WebRootBootTraceApp> {
  String _provenanceText = 'netTestBuildProvenance=(aguardar...)';
  String _versionJsonText = 'version.json=(aguardar...)';
  String _firebaseText = 'firebase=(aguardar; sem Firebase.apps no build)';

  Uri _versionUri() {
    final u = widget.initialUri;
    if (u.hasScheme && u.hasAuthority) {
      return Uri(
        scheme: u.scheme,
        host: u.host,
        port: u.hasPort ? u.port : null,
        path: '/version.json',
      );
    }
    return Uri.parse('https://app.mastepalm.com.br/version.json');
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      unawaited(_loadProvenanceAndVersion());
      // Primeiro frame sem tocar no Firebase: depois tenta init (via [initFirebase]).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_tryFirebase());
        }
      });
    } else {
      setState(() {
        _provenanceText = 'netTestBuildProvenance=non-web';
        _versionJsonText = 'version.json=non-web';
        _firebaseText = 'firebase=n/a';
      });
    }
  }

  Future<void> _loadProvenanceAndVersion() async {
    final buf = <String>[];

    if (kIsWeb) {
      try {
        final p = await web_plat.Web.netTestBuildProvenance();
        buf.add('netTestBuildProvenance=$p');
      } on Object catch (e, st) {
        buf.add('netTestBuildProvenanceError=$e\n$st');
      }
    } else {
      buf.add('netTestBuildProvenance=skipped');
    }

    try {
      final url = _versionUri();
      final r = await http
          .get(url)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final preview = r.body.length > 1200
            ? '${r.body.substring(0, 1200)}…'
            : r.body;
        buf.add('versionJson.fetched=ok status=${r.statusCode} url=$url\n$preview');
      } else {
        buf.add(
            'versionJson.fetched=fail status=${r.statusCode} url=$url bodyLen=${r.body.length}');
      }
    } on Object catch (e, st) {
      buf.add('versionJson.fetched=error $e $st');
    }

    if (!mounted) return;
    setState(() {
      _provenanceText = buf[0];
      if (buf.length > 1) {
        _versionJsonText = buf.sublist(1).join('\n\n');
      }
    });
  }

  /// Só chama [Firebase.apps] após [Firebase.initializeApp] (via [initFirebase]) com sucesso.
  Future<void> _tryFirebase() async {
    try {
      final ok = await widget
          .initFirebase()
          .timeout(const Duration(seconds: 25), onTimeout: () => false);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _firebaseText =
              'firebaseInit.ok=false\nfirebase.appsCount=(não lido, init OFFLINE/timeout)\n';
        });
        return;
      }
      var line = 'firebaseInit.ok=true\n';
      try {
        line += 'firebase.appsCount=${Firebase.apps.length}\n';
      } on Object catch (e, st) {
        line += 'firebase.appsCount=erro_apos_init($e)\n$st\n';
      }
      if (mounted) {
        setState(() => _firebaseText = line);
      }
    } on Object catch (e, st) {
      if (mounted) {
        setState(() {
          _firebaseText = 'firebaseInit.caught=$e\n$st\n';
        });
      }
    }
  }

  bool get _shouldOpenAppRoot =>
      widget.routeDecision.kind == CatalogInitialRouteKind.appRoot;

  @override
  Widget build(BuildContext context) {
    final d = widget.routeDecision;
    final staticLines = <String>[
      '=== Web root boot trace (não carrega PublicCatalogScreen) ===',
      'buildId=${widget.buildId}',
      'host=${widget.initialUri.host}',
      'path=${widget.initialUri.path}',
      'query=${widget.initialUri.query}',
      'userAgent=${web_plat.Web.userAgent()}',
      'routeDecision.kind=${d.kind.name}',
      'routeDecision.extractedSlugOrId=${d.extractedSlugOrId ?? ""}',
      'isAppHost=${widget.isAppHost}',
      'isPublicCatalogPath=${widget.isPublicCatalogPath}',
      'shouldOpenAppRoot=$_shouldOpenAppRoot',
    ];

    final text = <String>[
      staticLines.join('\n'),
      '',
      _provenanceText,
      '',
      _versionJsonText,
      '',
      _firebaseText,
    ].join('\n');

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Boot trace (raiz do app)')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SelectableText(text),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: widget.onContinue,
              child: const Text('Abrir app MasterPalm'),
            ),
          ],
        ),
      ),
    );
  }
}
