import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'config/mp_environment_config.dart';
import 'firebase_options.dart' show DefaultFirebaseOptions;

/// Opções usadas em `Firebase.initializeApp` no bootstrap.
FirebaseOptions firebaseOptionsForInit() {
  MpEnvironmentConfig.assertProductionBuildSafe();

  if (kIsWeb && MpEnvironmentConfig.isQa) {
    return FirebaseOptions(
      apiKey: 'qa-fake-api-key',
      appId: '1:qa:web:r8433',
      messagingSenderId: '000000000000',
      projectId: MpEnvironmentConfig.qaProjectId,
      authDomain: 'localhost',
      storageBucket: '${MpEnvironmentConfig.qaProjectId}.appspot.com',
    );
  }

  if (kIsWeb) {
    return safeWebFirebaseOptions();
  }
  return DefaultFirebaseOptions.currentPlatform;
}

/// `FirebaseOptions` da consola (Web) — produção.
FirebaseOptions safeWebFirebaseOptions() => DefaultFirebaseOptions.web;

/// Cópia estática do bloco `web` de [lib/firebase_options.dart] — netTest 4c.
const FirebaseOptions kExplicitWebBootstrapFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBPRazC3wOs-x7IdatMy26Dr81pEi4Xz44',
  appId: '1:950139833317:web:4f94d4108daf8ab31ebd0c',
  messagingSenderId: '950139833317',
  projectId: 'masterpalm-58c46',
  authDomain: 'masterpalm-58c46.firebaseapp.com',
  storageBucket: 'masterpalm-58c46.firebasestorage.app',
  measurementId: 'G-0F0ZRT1S6G',
);
