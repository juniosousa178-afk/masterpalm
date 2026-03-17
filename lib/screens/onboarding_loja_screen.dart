// lib/screens/onboarding_loja_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import '../services/store_resolver_service.dart';

class OnboardingLojaScreen extends StatefulWidget {
  const OnboardingLojaScreen({super.key});

  @override
  State<OnboardingLojaScreen> createState() => _OnboardingLojaScreenState();
}

class _OnboardingLojaScreenState extends State<OnboardingLojaScreen> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _whats = TextEditingController();
  final _cidade = TextEditingController();
  final _lojaIdCtrl = TextEditingController();

  bool _salvando = false;

  // UI de disponibilidade
  bool? _slugDisponivel; // null=desconhecido, true=ok, false=ocupado
  String _slugMsg = '';
  Timer? _debounce;

  // ---------- Utils ----------

  String _slugify(String s) {
    var base = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.isEmpty) base = 'minha-loja';
    if (base.length < 3) base = base.padRight(3, 'x');
    return base;
  }

  // Normalização simples de WhatsApp → E.164 (+55...)
  String _normalizeWhatsapp(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length >= 12 && digits.startsWith('55')) return '+$digits';
    if (digits.length == 11) return '+55$digits';
    return raw.startsWith('+') ? raw : '+$digits';
  }

  Future<void> _checkDisponibilidadeDebounced(String value) async {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _checkDisponibilidade(value);
    });
  }

  Future<void> _checkDisponibilidade(String value) async {
    final id = _slugify(value);
    _lojaIdCtrl.value = _lojaIdCtrl.value.copyWith(
      text: id,
      selection: TextSelection.collapsed(offset: id.length),
    );

    if (id.isEmpty) {
      if (!mounted) return;
      setState(() {
        _slugDisponivel = null;
        _slugMsg = '';
      });
      return;
    }

    final db = FirebaseFirestore.instance;
    final doc = await db.collection('lojas').doc(id).get();

    if (!mounted) return;

    if (!doc.exists) {
      setState(() {
        _slugDisponivel = true;
        _slugMsg = 'Disponível';
      });
      return;
    }

    // Se já existe, checa se o owner é o próprio usuário
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ownerUid = (doc.data()?['ownerUid'] ?? '').toString();

    if (uid != null && uid == ownerUid) {
      setState(() {
        _slugDisponivel = true;
        _slugMsg = 'Este ID já é seu. Vamos apenas atualizar sua loja.';
      });
    } else {
      setState(() {
        _slugDisponivel = false;
        _slugMsg = 'Já existe uma loja com esse ID.';
      });
    }
  }

  Future<void> _gerarIdDoNome() async {
    final id = _slugify(_nome.text);
    _lojaIdCtrl.text = id;
    await _checkDisponibilidade(id);
  }

  /// Cria/atualiza a loja escolhida garantindo unicidade e ownership.
  Future<void> _criarOuAtualizarLoja({
    required String lojaId,
    required String nome,
    required String whatsE164,
    required String cidade,
  }) async {
    final db = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }
    final uid = user.uid;

    await db.runTransaction((tx) async {
      final lojaRef = db.collection('lojas').doc(lojaId);
      final snap = await tx.get(lojaRef);

      if (!snap.exists) {
        // Criar nova loja com ownership do usuário logado
        tx.set(lojaRef, <String, dynamic>{
          'id': lojaId,
          'name': nome.isEmpty ? 'Minha Loja' : nome,
          'slug': lojaId,
          'ownerUid': uid,
          'owner': {
            'uid': uid,
            'email': user.email,
          },
          'whatsappE164': whatsE164,
          'cidade': cidade,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'hostingStatus': 'PENDING',
        });

        final memberRef = lojaRef.collection('members').doc(uid);
        tx.set(memberRef, <String, dynamic>{
          'role': 'admin',
          'joinedAt': FieldValue.serverTimestamp(),
        });

        final settingsRef = lojaRef.collection('settings').doc('general');
        tx.set(settingsRef, <String, dynamic>{
          'whatsappE164': whatsE164,
          'theme': {'primary': '#00C853'},
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Já existe. Só permite atualizar se for do próprio owner
        final data = snap.data() as Map<String, dynamic>;
        final ownerUid = (data['ownerUid'] ?? '').toString();
        if (ownerUid != uid) {
          throw StateError('Este ID já pertence a outra loja.');
        }

        tx.set(
          lojaRef,
          <String, dynamic>{
            'name': nome.isEmpty ? (data['name'] ?? 'Minha Loja') : nome,
            'whatsappE164': whatsE164,
            'cidade': cidade,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });

    // ⚠️ MUITO IMPORTANTE:
    // Vincula esse lojaId ao usuário (isolamento total entre lojas)
    await db
        .collection('users')
        .doc(uid)
        .set({'store_id': lojaId}, SetOptions(merge: true));
  }

  Future<void> _persistirTenantLocal(String lojaId) async {
    // box config (legado)
    final cfg = await Hive.openBox('config');
    await cfg.put('store_id', lojaId);
    await cfg.put('store_slug', lojaId);
    await cfg.put('loja_slug', lojaId);

    // fixa o tenant ativo para o app inteiro (serviços legados)
await StoreResolverService.set(lojaId);
    // fixa também na sessão atual (novo fluxo)
await StoreResolverService.set(lojaId);  }

  // ---------- Lifecycle ----------
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<dynamic, dynamic>?;
    final passedId = (args?['lojaId'] as String?)?.trim();
    if (passedId != null && passedId.isNotEmpty) {
      _lojaIdCtrl.text = passedId;
      _checkDisponibilidade(passedId);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nome.dispose();
    _whats.dispose();
    _cidade.dispose();
    _lojaIdCtrl.dispose();
    super.dispose();
  }

  // ---------- Actions ----------
  Future<void> _salvar() async {
    if (_salvando) return;
    if (!_form.currentState!.validate()) return;

    final chosen = _slugify(_lojaIdCtrl.text);
    if (chosen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o ID da loja (mín. 3 caracteres).'),
        ),
      );
      return;
    }

    if (_slugDisponivel == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_slugMsg.isEmpty ? 'ID indisponível' : _slugMsg),
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final nome = _nome.text.trim();
      final whatsE164 = _normalizeWhatsapp(_whats.text);
      final cidade = _cidade.text.trim();

      await _criarOuAtualizarLoja(
        lojaId: chosen,
        nome: nome,
        whatsE164: whatsE164,
        cidade: cidade,
      );

      await _persistirTenantLocal(chosen);

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // ---------- UI ----------
  Widget _tile(
    String label,
    TextEditingController c, {
    TextInputType type = TextInputType.text,
    String? hint,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      validator:
          validator ?? (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dispColor = _slugDisponivel == null
        ? Colors.white38
        : _slugDisponivel == true
            ? const Color(0xFF00FFA3)
            : const Color(0xFFFF6B6B);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Bem-vindo! Vamos criar sua loja'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/login',
              (route) => false,
            );
          },
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Card(
                        color: const Color(0xFF121212),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 8,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Form(
                            key: _form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Dados básicos da sua loja',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                _tile(
                                  'Nome da loja',
                                  _nome,
                                  hint: 'Ex.:MasterPalm',
                                  onChanged: (v) {
                                    if (_lojaIdCtrl.text.trim().isEmpty) {
                                      _checkDisponibilidadeDebounced(
                                        _slugify(v),
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),

                                _tile(
                                  'WhatsApp (com DDD)',
                                  _whats,
                                  type: TextInputType.phone,
                                  hint: 'Ex.: (33) 99111-4341',
                                ),

                                const SizedBox(height: 20),

                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'ID da loja (o que vai para seu catálogo web)',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),

                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _lojaIdCtrl,
                                        style:
                                            const TextStyle(color: Colors.white),
                                        onChanged: (v) =>
                                            _checkDisponibilidadeDebounced(v),
                                        validator: (v) {
                                          final id = _slugify(v ?? '');
                                          if (id.length < 3) {
                                            return 'Mínimo 3 caracteres';
                                          }
                                          return null;
                                        },
                                        decoration: InputDecoration(
                                          hintText: 'ex: masterPalm',
                                          hintStyle: const TextStyle(
                                            color: Colors.white38,
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFF1A1A1A),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: _gerarIdDoNome,
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: Color(0xFF00A8FF)),
                                        foregroundColor:
                                            const Color(0xFF00A8FF),
                                      ),
                                      child: const Text('Gerar do nome'),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 6),
                                if (_slugMsg.isNotEmpty)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _slugMsg,
                                      style: TextStyle(color: dispColor),
                                    ),
                                  ),

                                const SizedBox(height: 20),

                                SizedBox(
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _salvando ? null : _salvar,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF30CEF5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: _salvando
                                        ? const CircularProgressIndicator(
                                            color: Colors.white,
                                          )
                                        : const Text(
                                            'Continuar',
                                            style: TextStyle(fontSize: 16),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Sua loja começa zerada para você configurar do seu jeito.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}