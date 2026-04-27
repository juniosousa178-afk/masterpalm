import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firebase_options.dart' show DefaultFirebaseOptions;

/// Opções usadas em `Firebase.initializeApp` no **bootstrap** (não no netTest 4b).
/// No Web: mesmas constantes que [DefaultFirebaseOptions.web], visto por [safeWebFirebaseOptions],
/// em vez de passar `currentPlatform` (netTest 4a/4b ainda o testam em separado).
FirebaseOptions firebaseOptionsForInit() {
  if (kIsWeb) {
    return safeWebFirebaseOptions();
  }
  return DefaultFirebaseOptions.currentPlatform;
}

/// `FirebaseOptions` da consola (Web) — fonte explícita para o init fora do netTest.
FirebaseOptions safeWebFirebaseOptions() => DefaultFirebaseOptions.web;

/// Cópia estática do bloco `web` de [lib/firebase_options.dart] (mesmos valores) —
/// netTest passo 4c, para validar se o `initializeApp` falha só com `currentPlatform`.
const FirebaseOptions kExplicitWebBootstrapFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBPRazC3wOs-x7IdatMy26Dr81pEi4Xz44',
  appId: '1:950139833317:web:4f94d4108daf8ab31ebd0c',
  messagingSenderId: '950139833317',
  projectId: 'masterpalm-58c46',
  authDomain: 'masterpalm-58c46.firebaseapp.com',
  storageBucket: 'masterpalm-58c46.firebasestorage.app',
  measurementId: 'G-0F0ZRT1S6G',
);
