// lib/debug/firebase_probe_screen.dart
import 'dart:async';
import 'dart:io' show InternetAddress;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase_options.dart';

class FirebaseProbeScreen extends StatefulWidget {
  const FirebaseProbeScreen({super.key});

  @override
  State<FirebaseProbeScreen> createState() => _FirebaseProbeScreenState();
}

class _FirebaseProbeScreenState extends State<FirebaseProbeScreen> {
  String _net = 'Pendente';
  String _init = 'Pendente';
  String _apps = 'Pendente';
  String _fs = 'Pendente';
  String _details = '';
  Duration _tNet = Duration.zero;
  Duration _tInit = Duration.zero;
  Duration _tFs = Duration.zero;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final buf = StringBuffer();

    // 1) Verifica DNS/rede (mobile/desktop). No Web, pula.
    if (!kIsWeb) {
      final sw = Stopwatch()..start();
      try {
        final result = await InternetAddress.lookup('www.google.com')
            .timeout(const Duration(seconds: 5));
        _tNet = sw.elapsed;
        _net = result.isNotEmpty ? 'OK' : 'Falhou';
      } catch (e) {
        _tNet = sw.elapsed;
        _net = 'Falhou';
        buf.writeln('NET: $e');
      }
      setState(() {});
    } else {
      _net = 'Ignorado no Web';
      setState(() {});
    }

    // 2) Firebase.initializeApp (sem timeout pra diagnosticar travas)
    final swInit = Stopwatch()..start();
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        _init = 'OK (initializeApp)';
      } else {
        // já havia app criado
        Firebase.app();
        _init = 'OK (app existente)';
      }
    } catch (e, st) {
      // tenta recuperar um app existente mesmo com erro
      try {
        Firebase.app();
        _init = 'OK (recuperado via Firebase.app)';
        buf.writeln('INIT WARN: $e');
        buf.writeln(st);
      } catch (e2, st2) {
        _init = 'Falhou';
        buf.writeln('INIT FAIL: $e2');
        buf.writeln(st2);
      }
    } finally {
      _tInit = swInit.elapsed;
      _apps = Firebase.apps.map((a) => a.name).join(', ').isEmpty
          ? '(nenhum)'
          : Firebase.apps.map((a) => a.name).join(', ');
      setState(() {});
    }

    // 3) Firestore “ping” (GET de um doc público/qualquer).
    // permission-denied ainda prova que o Core + rede estão ok.
    final swFs = Stopwatch()..start();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('__probe__')
          .doc('ping')
          .get();
      _fs = snap.exists ? 'OK (doc existe)' : 'OK (doc não existe)';
    } on FirebaseException catch (e) {
      _fs = 'Resp: ${e.code}';
      buf.writeln('FS: ${e.code} ${e.message}');
    } catch (e) {
      _fs = 'Falhou';
      buf.writeln('FS: $e');
    } finally {
      _tFs = swFs.elapsed;
      _details = buf.toString();
      setState(() {});
    }
  }

  Widget _row(String title, String value, Duration d) {
    final ok = value.startsWith('OK') || value.startsWith('Resp');
    return ListTile(
      leading: Icon(ok ? Icons.check_circle : Icons.error,
          color: ok ? Colors.green : Colors.red),
      title: Text(title),
      subtitle: Text(value),
      trailing: Text('${d.inMilliseconds} ms'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firebase Probe')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Diagnóstico rápido de inicialização',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _row('Rede/DNS', _net, _tNet),
          _row('Firebase Core init', _init, _tInit),
          ListTile(
            leading: const Icon(Icons.apps),
            title: const Text('Apps ativos'),
            subtitle: Text(_apps),
          ),
          _row('Firestore GET', _fs, _tFs),
          const SizedBox(height: 12),
          const Text('Detalhes', style: TextStyle(fontWeight: FontWeight.bold)),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _details.isEmpty ? '(sem avisos/erros)' : _details,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _run,
            icon: const Icon(Icons.refresh),
            label: const Text('Repetir teste'),
          ),
        ],
      ),
    );
  }
}
