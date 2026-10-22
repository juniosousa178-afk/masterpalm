// Smoke do catálogo público (prévia de variações nos cards) num browser real,
// contra o emulador do Firestore. Renderiza o PublicCatalogScreen de produção;
// só o init do Firebase aponta para um projeto demo no emulador.
//
// flutter build web --release -t test/public_catalog/support/catalog_variation_web_smoke_main.dart
// Abrir /?loja=loja-smoke-classico ou /?loja=loja-smoke-minimal

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:master_palm/screens/public_catalog_screen.dart';

const String _emulatorHost = String.fromEnvironment('FIRESTORE_EMULATOR_HOST',
    defaultValue: '127.0.0.1');
const int _emulatorPort =
    int.fromEnvironment('FIRESTORE_EMULATOR_PORT', defaultValue: 8187);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'demo-api-key',
      appId: '1:000000000000:web:0000000000000000000000',
      messagingSenderId: '000000000000',
      projectId: 'demo-masterpalm-catalog-variations',
    ),
  );
  FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, _emulatorPort);
  final loja = Uri.base.queryParameters['loja'] ?? 'loja-smoke-classico';
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smoke variações',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR'), Locale('en', 'US')],
      theme: ThemeData(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        scaffoldBackgroundColor: const Color(0xFFE8E8E8),
      ),
      home: PublicCatalogScreen(lojaId: loja),
    ),
  );
}
