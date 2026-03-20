import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';

import '../widgets/input_field.dart';
import '../widgets/neon_button.dart';
import '../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nomeC = TextEditingController();
  final emailC = TextEditingController();
  final foneC = TextEditingController();
  final passC = TextEditingController();

  bool show = false;
  String? error;
  bool loading = false;

  @override
  void dispose() {
    nomeC.dispose();
    emailC.dispose();
    foneC.dispose();
    passC.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------
  /// ✅ PADRONIZADO: Gera slug baseado no email (igual natypolylopes1997@gmail.com)
  String _toSlug(String email) {
    var slug = email.toLowerCase().trim();
    // Pega apenas a parte antes do @
    slug = slug.split('@').first;
    // Remove caracteres especiais, mantém apenas letras, números e hífen
    slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    // Remove hífens duplicados
    slug = slug.replaceAll(RegExp(r'-{2,}'), '-');
    // Remove hífens no início e fim
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'minha-loja' : slug;
  }

  Future<String> _pickUniqueSlug(FirebaseFirestore db, String base) async {
    var candidate = base;
    var i = 0;
    while (true) {
      final snap = await db.collection('lojas').doc(candidate).get();
      if (!snap.exists) return candidate;
      i++;
      candidate = '$base-$i';
    }
  }

  Future<void> _cacheSlug(String slug) async {
    final cfg = await Hive.openBox('config');
    await cfg.put('loja_slug', slug);
    await cfg.put('store_slug', slug);
  }

  Future<void> _saveSessaoAsAdmin({
    required String email,
    required String lojaId,
  }) async {
    final box = await Hive.openBox('sessao');
    await box.put('usuario_logado', email);
    await box.put('usuario_logado_email', email);
    await box.put('tipo_usuario', 'admin');
    await box.put('loja_id', lojaId);
    await box.put('store_id', lojaId);
    await box.put('permissoes', {
      'estoque': true,
      'clientes': true,
      'relatorios': true,
      'vendas': true,
      'precificacao': true,
      'fornecedores': true,
      'usuarios': true,
      'configuracoes': true,
      'backup': true,
      'licenca': true,
    });
  }

  // ===============================================================
  // Após registro → cria admin + loja + plano trial de 7 dias
  // ===============================================================
  Future<void> _afterRegisterEnsureAdminAndStore({
    required String name,
    required String email,
    required String phone,
  }) async {
    final db = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado após registro.');
    }

    // Força renovação do token depois de criar a conta
    try {
      if (kDebugMode) {
        debugPrint('>>> [BOOTSTRAP] Forçando renovação do Token (UID: ${user.uid})');
      }
      await user.getIdToken(true);
      if (kDebugMode) {
        debugPrint('>>> [BOOTSTRAP] Token renovado. Iniciando escritas no Firestore.');
      }
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('>>> [BOOTSTRAP] Falha ao renovar token: ${e.code}');
      }
      rethrow;
    }

    if ((user.displayName ?? '').isEmpty && name.isNotEmpty) {
      await user.updateDisplayName(name);
    }

    // ---------- 1) Cria loja (se ainda não existir) ----------
    // ✅ PADRONIZADO: Usa slug baseado no email (igual natypolylopes1997@gmail.com)
    String lojaId;
    {
      final q = await db
          .collection('lojas')
          .where('ownerUid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (q.docs.isNotEmpty) {
        lojaId = q.docs.first.id;
      } else {
        // ✅ Gera slug baseado no EMAIL (padrão igual natypolylopes1997)
        final base = _toSlug(email);
        final slug = await _pickUniqueSlug(db, base);
        lojaId = slug;

        await db.collection('lojas').doc(slug).set({
          'id': slug,
          'lojaId': slug,
          'name': name.isNotEmpty ? name : 'Minha Loja',
          'nome': name.isNotEmpty ? name : 'Minha Loja',
          'slug': slug,
          'ownerUid': user.uid,
          'ownerEmail': email,
          'ativo': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'admins': {user.uid: true},
          'config': {
            'pedido_link_base': 'https://app.mastepalm.com.br/pedido',
          },
        });

        // ✅ Criar config e draft_config (padrão igual natypolylopes1997)
        await db.collection('lojas').doc(slug).collection('config').doc('config').set({
          'lojaId': slug,
          'slug': slug,
          'nome': name.isNotEmpty ? name : 'Minha Loja',
          'createdAt': FieldValue.serverTimestamp(),
        });

        await db.collection('lojas').doc(slug).collection('draft_config').doc('config').set({
          'lojaId': slug,
          'slug': slug,
          'nome': name.isNotEmpty ? name : 'Minha Loja',
          'createdAt': FieldValue.serverTimestamp(),
        });

        await db
            .collection('lojas')
            .doc(slug)
            .collection('members')
            .doc(user.uid)
            .set({
          'role': 'owner',
          'email': email,
          'joinedAt': FieldValue.serverTimestamp(),
        });

        await db
            .collection('lojas')
            .doc(slug)
            .collection('settings')
            .doc('general')
            .set({
          'whatsappE164': '',
          'theme': {
            'primary': '#00C853',
            'bg': '#FFFFFF',
            'text': '#111111',
          },
          'catalog': {'public': true},
        });
      }
    }

    // ---------- 2) Cria documento principal em "users/{uid}" ----------
    // ✅ PADRONIZADO: Inclui store_id (igual natypolylopes1997@gmail.com)
    final now = DateTime.now();
    final trialEnd = now.add(const Duration(days: 7));

    await db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': email,
      'nome': name,
      'telefone': phone,
      'role': 'admin',
      'emailVerificationRequired': true, // Nova conta: exige verificação
      'ownerId': user.uid,
      'lojaId': lojaId,
      'store_id': lojaId, // ✅ NOVO: store_id para consistência
      'ownerOf': lojaId,  // ✅ NOVO: indica que é dono da loja
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'plan': {
        'planId': 'free_trial',
        'status': 'trialing',
        'trialEndsAt': Timestamp.fromDate(trialEnd),
      },
    }, SetOptions(merge: true));

    // ---------- 3) Compat: "usuarios/{email}" ----------
    // Conta criada no login é SEMPRE admin. Vendedor é criado dentro da loja pelo admin.
    await db.collection('usuarios').doc(email).set({
      'authUid': user.uid,
      'email': email,
      'nome': name,
      'telefone': phone,
      'tipo': 'admin',
      'store_id': lojaId,     // ✅ NOVO: store_id para consistência
      'ownerStoreId': lojaId, // Mantido para compatibilidade
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // ---------- 4) Sessão + cache ----------
    await _cacheSlug(lojaId);
    await _saveSessaoAsAdmin(email: email, lojaId: lojaId);
  }

  String? _validateInputs() {
    final name = nomeC.text.trim();
    final email = emailC.text.trim().toLowerCase();
    final phone = foneC.text.trim();
    final pass = passC.text.trim();

    if (name.isEmpty) return 'Informe o nome';
    if (email.isEmpty) return 'Informe o e-mail';
    if (!email.contains('@') || !email.contains('.')) return 'E-mail inválido';
    if (phone.isEmpty) return 'Informe o telefone';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return 'Informe um telefone válido com DDD';
    if (pass.length < 6) return 'Senha: mínimo 6 caracteres';
    return null;
  }

  Future<void> _onCreateAccount() async {
    final msg = _validateInputs();
    if (msg != null) {
      setState(() => error = msg);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    AuthService? authSvc;
    try {
      authSvc = context.read<AuthService>();
    } catch (e) {
      setState(() => error = 'Erro de configuração. Reinicie o app.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro de configuração. Reinicie o app.')));
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    final name = nomeC.text.trim();
    final email = emailC.text.trim().toLowerCase();
    final phone = foneC.text.trim();
    final pass = passC.text.trim();

    try {
      // 1. Cria conta (Auth + usuarios/{email} interno do AuthService)
      final err = await authSvc.register(
        name: name,
        email: email,
        phone: phone,
        pass: pass,
      );

      if (err != null) {
        setState(() => error = err);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
        return;
      }

      // 2. Cria loja + users/{uid} + compat usuarios/{email} + sessão
      await _afterRegisterEnsureAdminAndStore(
        name: name,
        email: email,
        phone: phone,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/verify_email',
        arguments: {'nextRoute': '/onboarding_loja'},
      );
    } catch (e) {
      setState(() => error = 'Erro ao criar conta. Tente novamente.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao criar conta. Tente novamente.')));
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    'CADASTRE-SE PREENCHENDO OS CAMPOS ABAIXO',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  InputField(controller: nomeC, hint: 'Nome completo'),
                  const SizedBox(height: 12),
                  InputField(
                    controller: emailC,
                    hint: 'E-mail',
                    keyboard: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  InputField(
                    controller: foneC,
                    hint: 'Telefone',
                    keyboard: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  InputField(
                    controller: passC,
                    hint: 'Senha',
                    obscure: !show,
                    suffix: IconButton(
                      icon: Icon(
                        show ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => show = !show),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 20),
                  loading
                      ? const CircularProgressIndicator()
                      : NeonButton(
                          label: 'Criar conta',
                          onPressed: _onCreateAccount,
                          secondary: true,
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
