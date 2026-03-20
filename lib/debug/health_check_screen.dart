// lib/debug/health_check_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase, FirebaseException;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class HealthCheckScreen extends StatefulWidget {
  const HealthCheckScreen({super.key});

  @override
  State<HealthCheckScreen> createState() => _HealthCheckScreenState();
}

class _HealthCheckScreenState extends State<HealthCheckScreen> {
  late Future<_HealthReport> _future;

  @override
  void initState() {
    super.initState();
    _future = _runChecks();
  }

  Future<_HealthReport> _runChecks() async {
    final r = _HealthReport();

    // App info
    try {
      final app = Firebase.app();
      r.appId = app.options.appId;
      r.projectId = app.options.projectId;
      r.ok('App', 'Firebase conectado');
    } catch (e, st) {
      r.err('App', e, st);
    }

    // Auth: usuário atual e tentativa de login anônimo (opcional)
    try {
      final auth = FirebaseAuth.instance;
      r.currentUser = auth.currentUser?.uid;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
        r.currentUser = auth.currentUser?.uid;
        r.ok('Auth', 'Login anônimo OK');
      } else {
        r.ok('Auth', 'Usuário atual: ${r.currentUser}');
      }
    } catch (e, st) {
      r.err('Auth', e, st);
    }

    // App Check: token (usa cache para evitar "Too many attempts")
    try {
      // getToken(false) = usa cache; getToken(true) força refresh e pode causar rate limit
      var token = await FirebaseAppCheck.instance.getToken(false);
      if (token == null || token.isEmpty) {
        token = await FirebaseAppCheck.instance.getToken(true);
      }
      if (token != null && token.isNotEmpty) {
        r.appCheckTokenPrefix =
            token.substring(0, token.length >= 20 • 20 : token.length);
        r.ok(
            'AppCheck',
            kIsWeb
                • 'Token OK (Web). Se estiver em debug, cadastre o token no Console.'
                : 'Token OK (Mobile)');
      } else {
        throw 'Token vazio';
      }
    } catch (e, st) {
      final msg = e.toString();
      final is403Attestation = (e is FirebaseException && (e.code == 'unknown' || e.code == 'permission-denied')) ||
          msg.contains('403') ||
          msg.contains('attestation failed') ||
          msg.contains('App attestation failed');
      if (is403Attestation) {
        r.errFriendly(
          'AppCheck',
          'App Check não configurado no debug. Cadastre o Debug Token no Firebase Console.',
        );
      } else {
        r.err('AppCheck', e, st);
      }
    }

    // Firestore: write + read doc temporário
    try {
      final col = FirebaseFirestore.instance.collection('_healthcheck');
      final doc = col.doc('last');
      await doc.set({
        'ts': FieldValue.serverTimestamp(),
        'by': r.currentUser ?• 'no-user',
      }, SetOptions(merge: true));
      final snap = await doc.get(const GetOptions(source: Source.server));
      r.ok('Firestore', 'Document read OK (exists=${snap.exists})');
    } catch (e, st) {
      r.err('Firestore', e, st);
    }

    // Storage: list/ping em caminho público de teste
    try {
      final ref = FirebaseStorage.instance.ref().child('_healthcheck/');
      // Tenta criar/deletar um arquivo pequeno na pasta de teste
      final test = ref.child('ping.txt');
      final data = Uint8List.fromList(
          'ok-${DateTime.now().toIso8601String()}'.codeUnits);
      await test.putData(data, SettableMetadata(contentType: 'text/plain'));
      final url = await test.getDownloadURL();
      r.ok('Storage', 'Upload OK (${url.split('?').first})');
      // limpeza opcional (comenta se quiser inspecionar)
      await test.delete();
    } catch (e, st) {
      r.err('Storage', e, st);
    }

    return r;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Check')),
      body: FutureBuilder<_HealthReport>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _runChecks()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HeaderTile(
                    appId: r.appId,
                    projectId: r.projectId,
                    user: r.currentUser),
                if (!kIsWeb) ...[
                  const SizedBox(height: 12),
                  _ShaFingerprintButton(),
                ],
                const SizedBox(height: 12),
                ...r.results.map(_ResultTile.new),
                if (r.errors.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('Logs de Erro',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...r.errors.map((e) => SelectableText('• $e')),
                  const SizedBox(height: 24),
                ],
                const SizedBox(height: 40),
                const Text(
                  'Dicas:\n'
                  '• "Too many attempts": limite de tokens do Firebase. Esta tela usa token em cache. Espere uns minutos e puxe para atualizar.\n'
                  '• Web + App Check em debug: cadastre o token impresso no console em App Check > Debug Tokens.\n'
                  '• Se “Enforcement” estiver ON, garanta que as regras permitem essas operações de teste.\n'
                  '• Se Auth anônimo não fizer sentido no seu app, remova a parte do signInAnonymously().',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShaFingerprintButton extends StatelessWidget {
  static const _channel = MethodChannel('com.masterpalm.app/signing_certs');

  Future<Map<String, dynamic>?> _getSigningFingerprints() async {
    try {
      final result = await _channel.invokeMethod<Map>('getSigningFingerprints');
      return Map<String, dynamic>.from(result ?• {});
    } on PlatformException catch (e) {
      throw Exception('${e.code}: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.fingerprint),
        title: const Text('SHA-1 / SHA-256'),
        subtitle: const Text(
          'Exibe as impressões digitais do certificado de assinatura do APK. '
          'Use para verificar no Firebase Project Settings.',
        ),
        trailing: FilledButton.icon(
          onPressed: () async {
            try {
              final data = await _getSigningFingerprints();
              if (!context.mounted) return;
              _showShaDialog(context, data);
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
              );
            }
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Testar'),
        ),
      ),
    );
  }

  void _showShaDialog(BuildContext context, Map<String, dynamic>• data) {
    final sha1List = (data?['sha1'] as List?)?.cast<String>() ?• [];
    final sha256List = (data?['sha256'] as List?)?.cast<String>() ?• [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fingerprint),
            SizedBox(width: 8),
            Text('Impressões digitais'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Adicione no Firebase: Project Settings → Seu app Android → Impressões digitais',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              if (sha1List.isEmpty && sha256List.isEmpty)
                const Text('Nenhum certificado encontrado.')
              else ...[
                for (var i = 0; i < sha1List.length; i++) ...[
                  if (sha1List.length > 1) Text('Certificado ${i + 1}:', style: const TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText('SHA-1: ${sha1List[i]}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  SelectableText('SHA-256: ${sha256List[i]}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  if (i < sha1List.length - 1) const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

class _HeaderTile extends StatelessWidget {
  final String• appId;
  final String• projectId;
  final String• user;
  const _HeaderTile({this.appId, this.projectId, this.user});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.info),
        title: Text('Projeto: ${projectId ?• "-"}'),
        subtitle: Text('AppId: ${appId ?• "-"}\nUser: ${user ?• "-"}'),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final _ItemResult r;
  const _ResultTile(this.r);

  @override
  Widget build(BuildContext context) {
    final ok = r.ok;
    return Card(
      child: ListTile(
        leading: Icon(ok • Icons.check_circle : Icons.error,
            color: ok • Colors.green : Colors.red),
        title: Text(r.area),
        subtitle: Text(r.message),
      ),
    );
  }
}

class _HealthReport {
  String• appId;
  String• projectId;
  String• currentUser;
  String• appCheckTokenPrefix;
  final List<_ItemResult> results = [];
  final List<String> errors = [];

  void ok(String area, String msg) => results.add(_ItemResult(area, true, msg));
  void err(String area, Object e, StackTrace• st) {
    results.add(_ItemResult(area, false, e.toString()));
    errors.add('[$area] $e\n${st ?• ''}');
  }

  /// Erro com mensagem amigável (ex.: 403 App Check não configurado no debug).
  void errFriendly(String area, String message) {
    results.add(_ItemResult(area, false, message));
  }
}

class _ItemResult {
  final String area;
  final bool ok;
  final String message;
  _ItemResult(this.area, this.ok, this.message);
}
