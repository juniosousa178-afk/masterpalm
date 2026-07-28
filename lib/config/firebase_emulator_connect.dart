// Conexão Firebase Emulator — somente MP_ENVIRONMENT=qa (R8.4.33).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'mp_environment_config.dart';

/// Conecta emuladores após [Firebase.initializeApp], se configurado em compile-time.
Future<void> connectFirebaseEmulatorsIfConfigured() async {
  if (!MpEnvironmentConfig.useFirebaseEmulators) return;
  if (!MpEnvironmentConfig.isQa) {
    throw StateError(
      'Emulators só permitidos com ambiente qa',
    );
  }

  final projectId = Firebase.app().options.projectId;
  MpEnvironmentConfig.assertQaProjectSafe(projectId);

  void connectHost(String raw, void Function(String host, int port) connect) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final parts = trimmed.split(':');
    if (parts.length != 2) {
      throw FormatException('Host emulator inválido: $raw');
    }
    final host = parts[0];
    final port = int.tryParse(parts[1]);
    if (port == null) {
      throw FormatException('Porta emulator inválida: $raw');
    }
    connect(host, port);
  }

  connectHost(MpEnvironmentConfig.authEmulatorHost, (h, p) {
    FirebaseAuth.instance.useAuthEmulator(h, p, automaticHostMapping: false);
  });

  connectHost(MpEnvironmentConfig.firestoreEmulatorHost, (h, p) {
    FirebaseFirestore.instance.useFirestoreEmulator(h, p);
  });

  connectHost(MpEnvironmentConfig.storageEmulatorHost, (h, p) {
    FirebaseStorage.instance.useStorageEmulator(h, p);
  });

  if (kDebugMode) {
    debugPrint(
      '[MpEnvironment] Firebase emulators conectados (projectId=$projectId)',
    );
  }
}
