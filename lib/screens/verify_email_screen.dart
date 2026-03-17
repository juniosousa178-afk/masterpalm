// lib/screens/verify_email_screen.dart
// Tela de verificação de e-mail (antifraude - sem custo)
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/neon_button.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String? email;
  final String nextRoute;

  const VerifyEmailScreen({
    super.key,
    this.email,
    this.nextRoute = '/onboarding_loja',
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _loading = false;
  bool _resending = false;
  String? _msg;

  String get _email =>
      widget.email ?? FirebaseAuth.instance.currentUser?.email ?? '';

  Future<void> _checkVerified() async {
    setState(() {
      _loading = true;
      _msg = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _msg = 'Sessão expirada. Faça login novamente.';
          _loading = false;
        });
        return;
      }
      await user.reload();
      final updated = FirebaseAuth.instance.currentUser;
      if (updated?.emailVerified == true) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, widget.nextRoute);
        return;
      }
      if (!mounted) return;
      setState(() {
        _msg = 'E-mail ainda não verificado. Clique no link enviado.';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Erro ao verificar. Verifique sua conexão e tente novamente.';
        _loading = false;
      });
    }
  }

  Future<void> _resendEmail() async {
    setState(() {
      _resending = true;
      _msg = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _msg = 'Sessão expirada. Faça login novamente.';
          _resending = false;
        });
        return;
      }
      await user.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('E-mail reenviado! Verifique sua caixa de entrada.'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() => _resending = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Erro ao reenviar. Tente novamente.';
        _resending = false;
      });
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Verifique seu e-mail'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mark_email_unread_outlined,
                    size: 80,
                    color: Colors.blue.shade300,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Quase lá!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enviamos um e-mail de confirmação para',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha:0.8),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _email,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Clique no link do e-mail para ativar sua conta e continuar.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha:0.7),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Não esqueça de verificar a pasta de spam.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha:0.5),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_msg != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha:0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _msg!,
                        style: const TextStyle(color: Colors.orange, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  NeonButton(
                    label: _loading ? 'Verificando...' : 'Já verifiquei',
                    onPressed: _loading ? () {} : () => _checkVerified(),
                    secondary: true,
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _resending ? null : _resendEmail,
                    icon: _resending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18, color: Colors.white70),
                    label: Text(
                      _resending ? 'Enviando...' : 'Reenviar e-mail',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _signOut,
                    child: const Text(
                      'Usar outra conta',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
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

