// lib/services/auth_session.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'session_sanity.dart';
import 'planos_service.dart';

class AuthSession {
  /// Faz signOut no Firebase, limpa caixas locais e volta ao /login
  static Future<void> signOutAndGoToLogin(BuildContext context) async {
    // Tenta deslogar do Firebase
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('[AuthSession] Erro ao fazer signOut (type=${e.runtimeType})');
    }

    // ✅ CRÍTICO: Limpar cache de loja para evitar mistura multi-tenant
    await SessionSanity.clearAllStoreCache();
    PlanosService().clearEffectivePlanCache();

    // Fecha e limpa caixas locais principais
    for (final boxName in ['sessao', 'config', 'licenca']) {
      try {
        if (!Hive.isBoxOpen(boxName)) await Hive.openBox(boxName);
        await Hive.box(boxName).clear();
      } catch (e) {
        debugPrint('[AuthSession] Erro ao limpar box $boxName (type=${e.runtimeType})');
      }
    }

    // Retorna para tela de login (limpando histórico)
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
    }
  }
}
