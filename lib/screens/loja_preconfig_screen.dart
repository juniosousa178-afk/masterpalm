// lib/screens/loja_preconfig_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/neon_button.dart';
import '../services/tenant_service.dart';

class LojaPreconfigScreen extends StatefulWidget {
  const LojaPreconfigScreen({super.key});

  @override
  State<LojaPreconfigScreen> createState() => _LojaPreconfigScreenState();
}

class _LojaPreconfigScreenState extends State<LojaPreconfigScreen> {
  final nomeC = TextEditingController();
  final foneC = TextEditingController();
  final docC = TextEditingController();
  final cidadeC = TextEditingController();

  bool loading = false;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TenantService _tenant = TenantService();

  @override
  void dispose() {
    nomeC.dispose();
    foneC.dispose();
    docC.dispose();
    cidadeC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar Loja')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nomeC,
              decoration:
                  const InputDecoration(hintText: 'Nome da loja'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: foneC,
              decoration: const InputDecoration(
                hintText: 'Telefone/WhatsApp',
                helperText: 'Ex: 5533999999999',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: docC,
              decoration:
                  const InputDecoration(hintText: 'CNPJ/CPF (opcional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cidadeC,
              decoration:
                  const InputDecoration(hintText: 'Cidade/UF'),
            ),
            const SizedBox(height: 16),
            loading
                ? const CircularProgressIndicator()
                : NeonButton(
                    label: 'Concluir configurações',
                    secondary: true,
                    onPressed: () async {
                      setState(() => loading = true);

                      final user =
                          FirebaseAuth.instance.currentUser;
                      if (user == null) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Usuário não autenticado. Faça login novamente.'),
                          ),
                        );
                        setState(() => loading = false);
                        return;
                      }

                      final uid = user.uid;

                      // garante loja única para esse usuário
                      final lojaId =
                          await _tenant.ensureTenantForUser(uid);

                      await _db.collection('lojas').doc(lojaId).set(
                        {
                          'nome': nomeC.text.trim(),
                          'fone': foneC.text.trim(),
                          'doc': docC.text.trim(),
                          'cidade': cidadeC.text.trim(),
                          'updatedAt':
                              FieldValue.serverTimestamp(),
                        },
                        SetOptions(merge: true),
                      );

                      if (!mounted) return;
                      setState(() => loading = false);

                      if (!context.mounted) return;
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/home',
                        (_) => false,
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}