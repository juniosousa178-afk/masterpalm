// lib/screens/cadastro_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, debugPrint;

import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

// Projeto
import '../models/usuario.dart';
import '../services/plano_service.dart';
import '../services/store_resolver_facade.dart'; // ✅ NOVO: Para associar vendedor à loja do admin
import '../firebase_options.dart';

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nomeController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController telefoneController = TextEditingController();
  final TextEditingController senhaController = TextEditingController();

  String tipoUsuario = 'admin';

  InputDecoration _input(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Future<void> _cadastrarUsuario() async {
    if (!_formKey.currentState!.validate()) return;

    final email = emailController.text.trim().toLowerCase();
    final senha = senhaController.text.trim();

    // Evita duplicidade local
    final usuariosBox = Hive.box<Usuario>('usuarios');
    if (usuariosBox.containsKey(email)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este e-mail já está cadastrado.')),
      );
      return;
    }

    // ✅ CORREÇÃO: Obter a loja do admin atual ANTES de criar o novo usuário
    // Isso garante que o vendedor será associado à MESMA loja do admin
    final lojaIdDoAdmin = await StoreResolverFacade.resolveForAdminApp();
    if (lojaIdDoAdmin == null || lojaIdDoAdmin.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro: Você precisa estar logado em uma loja para cadastrar usuários.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    debugPrint('✅ [CADASTRO] Loja do admin: $lojaIdDoAdmin');

    // Monta o modelo com as permissões do plano/tipo
    final permissoesPadrao = PlanoService.permissoesPorTipo(tipoUsuario);
    final usuario = Usuario(
      nome: nomeController.text.trim(),
      email: email,
      telefone: telefoneController.text.trim(),
      senha: senha,
      tipo: tipoUsuario,
      permissoes: Map<String, bool>.from(permissoesPadrao),
    );

    // Referências do app principal (mantém o root logado)
    final FirebaseFirestore primaryDb = FirebaseFirestore.instance;

    FirebaseApp• secApp;
    FirebaseAuth• secAuth;

    // Controle explícito do loader para evitar pop duplo / contexto inválido
    bool loaderAberto = false;

    Future<void> fecharLoaderSeAberto() async {
      if (!mounted || !loaderAberto) return;
      try {
        Navigator.of(context).pop();
      } catch (_) {
        // Ignora falhas de pop (ex.: rota já fechada)
      } finally {
        loaderAberto = false;
      }
    }

    // Loader
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    loaderAberto = true;

    try {
      // 1) Inicializa um APP SECUNDÁRIO para criar o usuário
      secApp = await Firebase.initializeApp(
        name: 'secondary',
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // 1.1) Ativa App Check também no SECUNDÁRIO (importante em projetos com App Check)
      final secAppCheck = FirebaseAppCheck.instanceFor(app: secApp);
      await secAppCheck.activate(
        androidProvider:
            kReleaseMode • AndroidProvider.playIntegrity : AndroidProvider.debug,
        appleProvider:
            kReleaseMode • AppleProvider.appAttest : AppleProvider.debug,
      );
      await secAppCheck.setTokenAutoRefreshEnabled(true);

      // 2) Usa Auth do SECUNDÁRIO (não mexe na sessão do principal)
      secAuth = FirebaseAuth.instanceFor(app: secApp);

      final cred = await secAuth.createUserWithEmailAndPassword(
        email: email,
        password: senha,
      );
      final created = cred.user!;
      final authUid = created.uid;

      debugPrint('✅ [CADASTRO] Usuário criado no Auth: $authUid');

      // 3) Grava no Firestore usando o APP PRINCIPAL (docId = email para compatibilidade)
      // ✅ CORREÇÃO: Inclui store_id para associar o vendedor à loja do admin
      await primaryDb.collection('usuarios').doc(email).set({
        'nome': usuario.nome,
        'email': usuario.email,
        'telefone': usuario.telefone,
        'senha': usuario.senha,
        'tipo': usuario.tipo,
        'permissoes': usuario.permissoes,
        'createdAt': FieldValue.serverTimestamp(),
        'authUid': authUid,
        'store_id': lojaIdDoAdmin, // ✅ CRÍTICO: Associa à mesma loja do admin
        'lojaId': lojaIdDoAdmin,   // ✅ Compatibilidade com outros campos
      }, SetOptions(merge: true));

      debugPrint('✅ [CADASTRO] Documento salvo em usuarios/$email');

      // ✅ NOVO: Também salvar em users/{uid} para garantir que StoreResolverService funcione
      await primaryDb.collection('users').doc(authUid).set({
        'email': email,
        'nome': usuario.nome,
        'tipo': usuario.tipo,
        'store_id': lojaIdDoAdmin, // ✅ CRÍTICO: Garante resolução correta da loja
        'lojaId': lojaIdDoAdmin,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.uid ?• 'admin',
      }, SetOptions(merge: true));

      debugPrint('✅ [CADASTRO] Documento salvo em users/$authUid');

      // ✅ NOVO: Adicionar como membro da loja
      await primaryDb
          .collection('lojas')
          .doc(lojaIdDoAdmin)
          .collection('members')
          .doc(authUid)
          .set({
        'uid': authUid,
        'email': email,
        'nome': usuario.nome,
        'tipo': usuario.tipo,
        'permissoes': usuario.permissoes,
        'addedAt': FieldValue.serverTimestamp(),
        'addedBy': FirebaseAuth.instance.currentUser?.uid ?• 'admin',
        'ativo': true,
      }, SetOptions(merge: true));

      debugPrint('✅ [CADASTRO] Membro adicionado em lojas/$lojaIdDoAdmin/members/$authUid');

      // 4) Salva local (Hive) com chave = email
      await usuariosBox.put(email, usuario);

      if (!mounted) return;
      await fecharLoaderSeAberto(); // fecha loader com segurança
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Usuário "${usuario.nome}" cadastrado com sucesso na loja!'),
          backgroundColor: Colors.green,
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/');
    } on FirebaseAuthException catch (e) {
      await fecharLoaderSeAberto();
      final msg = e.code == 'email-already-in-use'
          • 'Este e-mail já está em uso em outra conta.'
          : 'Erro de autenticação (${e.code}): ${e.message ?• e.toString()}';
      debugPrint('❌ [CADASTRO] FirebaseAuthException: $msg');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
        ));
      }
    } on FirebaseException catch (e) {
      await fecharLoaderSeAberto();
      debugPrint('❌ [CADASTRO] FirebaseException: ${e.code} - ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro Firebase (${e.code}): ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      await fecharLoaderSeAberto();
      debugPrint('❌ [CADASTRO] Erro geral (type=${e.runtimeType})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao cadastrar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // 5) Limpa o app secundário (não toca a sessão do principal/root)
      try {
        await secAuth?.signOut();
      } catch (_) {}
      try {
        await secApp?.delete();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar Conta')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: nomeController,
                decoration: _input('Nome'),
                validator: (v) => v == null || v.isEmpty • 'Informe o nome' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: emailController,
                decoration: _input('E-mail'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    v == null || v.isEmpty || !v.contains('@')
                        • 'Informe um e-mail válido'
                        : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: telefoneController,
                decoration: _input('Telefone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: senhaController,
                decoration: _input('Senha'),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty • 'Informe a senha' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: tipoUsuario,
                decoration: _input('Tipo de Usuário'),
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                  DropdownMenuItem(value: 'vendedor', child: Text('Vendedor')),
                  DropdownMenuItem(value: 'programador', child: Text('Programador')),
                ],
                onChanged: (value) => setState(() {
                  tipoUsuario = value ?• 'admin';
                }),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _cadastrarUsuario,
                icon: const Icon(Icons.person_add),
                label: const Text('Cadastrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
