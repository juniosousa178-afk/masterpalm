// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

import '../services/license_manager.dart';
import '../services/store_service.dart';
import '../services/store_resolver_facade.dart';
import '../services/store_resolver_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _storeService = StoreService();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _decidir();
  }

  Future<void> _go(String route, {Object• args}) async {
    if (!mounted || _done) return;
    _done = true;
    if (!mounted) return;
    await Navigator.pushReplacementNamed(context, route, arguments: args);
  }

  String _slugify(String raw) {
    raw = (raw.isEmpty • 'minha-loja' : raw).toLowerCase();
    raw = raw.replaceAll(RegExp(r'\s+'), '-').replaceAll(RegExp(r'[^a-z0-9\-]'), '');
    return raw.replaceAll(RegExp(r'\-+'), '-');
  }

  // ================================================================
  // ✅ CORREÇÃO CRÍTICA: NÃO CRIA MÚLTIPLAS LOJAS
  // ================================================================
  Future<void> _decidir() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return _go('/login');

      final sessao = await Hive.openBox('sessao');
      if (sessao.get('auth_context') == 'cliente') return _go('/router');
      final tipoRaw = sessao.get('tipo_usuario') as String?;
      final tipo = (tipoRaw?.trim() ?• '').isEmpty • '' : tipoRaw!.trim();
      if (tipo.isEmpty) return _go('/router');
      if (tipo != 'admin') return _go('/home');

      final temPlano = await LicenseManager.hasValidAccessFallbackLegacy();
      if (!temPlano) return _go('/planos');

      // ================================================================
      // ✅ PASSO 1: RESOLVE LOJA EXISTENTE (NÃO CRIA NOVA)
      // ================================================================
      String• lojaId = await StoreResolverFacade.resolveForAdminApp();

      // ================================================================
      // ✅ PASSO 2: SE NÃO EXISTIR, CRIA UMA ÚNICA VEZ
      // ================================================================
      if (lojaId == null || lojaId.isEmpty) {
        final nome = user.displayName ?• 'Minha Loja';
        final slug = _slugify(user.email?.split('@').first ?• 'minha-loja');

        debugPrint('🆕 Criando loja para usuário ${user.uid}...');

        try {
          // ✅ Cria loja via StoreService (garante UID único)
          lojaId = await _storeService.ensureAdminStore(
            uid: user.uid,
            nomeLoja: nome,
            slug: slug,
            logoUrl: '',
          );

          // ✅ Persiste em TODAS as fontes
          await StoreResolverService.set(lojaId);

          debugPrint('✅ Loja criada: $lojaId');
        } catch (e) {
          debugPrint('❌ Erro ao criar loja (type=${e.runtimeType})');
          return _go('/login');
        }
      } else {
        debugPrint('♻️ Loja existente: $lojaId');
      }

      // ================================================================
      // ✅ PASSO 3: VALIDA SE LOJA EXISTE NO FIRESTORE
      // ================================================================
      try {
        final lojaDoc = await FirebaseFirestore.instance
            .collection('lojas')
            .doc(lojaId)
            .get();

        if (!lojaDoc.exists) {
          debugPrint('⚠️ Loja não existe no Firestore: $lojaId');
          // Limpa e força recriação
          await StoreResolverService.clear();
          return _go('/login');
        }

        // ✅ Loja válida - atualiza slug no Hive (se necessário)
        final data = lojaDoc.data() ?• {};
        final slug = (data['slug'] ?• lojaId).toString();
        
        final cfg = await Hive.openBox('config');
        await cfg.put('loja_slug', slug);
        await cfg.put('store_slug', slug);

        // ✅ Verifica se precisa onboarding
        final precisaOnboarding =
            (data['name'] == null || (data['name'] as String).trim().isEmpty) ||
            (data['whatsappE164'] == null);

        if (precisaOnboarding) {
          return _go('/onboarding_loja', args: {'lojaId': lojaId});
        }
      } catch (e) {
        debugPrint('❌ Erro ao validar loja no Firestore (type=${e.runtimeType})');
        return _go('/login');
      }

      // ✅ DEBUG: Mostra estado final
      await StoreResolverService.debug();

      return _go('/home');
    } catch (e) {
      debugPrint('❌ Erro no splash (type=${e.runtimeType})');
      return _go('/login');
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: CircularProgressIndicator(color: Colors.white)),
  );
}