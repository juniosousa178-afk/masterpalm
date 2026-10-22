// Smoke da página pública do pedido num browser real, contra o emulador do Firestore.
// Mesmo despacho de `lib/main.dart` (PublicOrderLink + PublicOrderWebApp); só o init do
// Firebase aponta para um projeto demo no emulador.
//
// flutter build web --release -t test/public_order_link/support/public_order_web_smoke_main.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:master_palm/catalog/public_order_link.dart';
import 'package:master_palm/screens/public_order_web_app.dart';
import 'package:master_palm/url_strategy_stub.dart'
    if (dart.library.html) 'package:master_palm/url_strategy_web.dart'
    as url_strategy;

const String _emulatorHost =
    String.fromEnvironment('FIRESTORE_EMULATOR_HOST', defaultValue: '127.0.0.1');
const int _emulatorPort =
    int.fromEnvironment('FIRESTORE_EMULATOR_PORT', defaultValue: 8187);

Future<bool> _initEmulatorFirebase() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'demo-api-key',
        appId: '1:000000000000:web:0000000000000000000000',
        messagingSenderId: '000000000000',
        projectId: 'demo-masterpalm-public-order',
      ),
    );
    FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, _emulatorPort);
  }
  return true;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  url_strategy.usePathUrlStrategy();
  final uri = Uri.base;
  if (!PublicOrderLink.isPublicOrderPath(uri)) {
    runApp(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('smoke: abra /pedido/{id}?loja={lojaId}')),
    ));
    return;
  }
  runApp(PublicOrderWebApp(
    ref: PublicOrderLink.parse(uri),
    routeName: PublicOrderLink.routeName(uri),
    initFirebase: _initEmulatorFirebase,
  ));
}
