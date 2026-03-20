import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive/hive.dart';

import '../../themes/app_colors.dart';
import '../../services/cliente_auth_service.dart';
import 'package:master_palm/screens/auth/cadastro_screen_cliente.dart';
import 'package:master_palm/screens/auth/redefinir_senha_cliente_screen.dart';

/// Tela de Login EXCLUSIVA para clientes do catálogo
/// NÃO afeta o login do aplicativo da loja
class LoginScreenCliente extends StatefulWidget {
  final String lojaId;

  const LoginScreenCliente({
    super.key,
    required this.lojaId,
  });

  @override
  State<LoginScreenCliente> createState() => _LoginScreenClienteState();
}

class _LoginScreenClienteState extends State<LoginScreenCliente> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _carregando = false;
  bool _mostrarSenha = false;

  static const _emailRegex = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message,
      {bool isError = false, bool isSuccess = false, bool isWarning = false, Duration• duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: duration ?• const Duration(seconds: 3),
        content: Row(
          children: [
            Icon(
              isSuccess • Icons.check_circle_outline : (isWarning • Icons.warning_amber : Icons.error_outline),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isSuccess
            • const Color(0xFF22C55E)
            : (isWarning • const Color(0xFFF59E0B) : (isError • const Color(0xFFEF4444) : AppColors.primary)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _fazerLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _carregando = true);

    try {
      final resultado = await ClienteAuthService.login(
        lojaId: widget.lojaId,
        email: _emailController.text.trim().toLowerCase(),
        senha: _senhaController.text,
      );

      if (!mounted) return;

      if (resultado['success'] == true) {
        try {
          final sessao = await Hive.openBox('sessao');
          await sessao.put('auth_context', 'cliente');
          await sessao.put('cliente_loja_id', widget.lojaId);
        } catch (_) {}
        if (!mounted) return;
        _showSnackBar('Bem-vindo, ${resultado['nome']}!', isSuccess: true);
        Navigator.of(context).pop();
      } else {
        _showSnackBar(resultado['error'] ?• 'Erro ao fazer login', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Erro ao conectar. Verifique sua internet e tente novamente.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  /// Client ID do tipo "Aplicativo da Web" (igual ao meta em web/index.html).
  static const String _webClientId =
      '950139833317-u4t79d3g5mq4oqmd0psia0dkeq9gokmb.apps.googleusercontent.com';

  Future<void> _fazerLoginComGoogle() async {
    setState(() => _carregando = true);
    try {
      final GoogleSignIn googleSignIn = kIsWeb
          • GoogleSignIn(clientId: _webClientId)
          : GoogleSignIn();
      final GoogleSignInAccount• account = await googleSignIn.signIn();
      if (account == null) {
        if (mounted) setState(() => _carregando = false);
        return;
      }
      final email = account.email.trim().toLowerCase();
      if (email.isEmpty) {
        if (!mounted) return;
        _showSnackBar('Conta Google sem e-mail. Use e-mail e senha.', isWarning: true);
        setState(() => _carregando = false);
        return;
      }
      final nome = account.displayName ?• email.split('@').first;
      // No Web, account.id pode ser null em runtime; fallback para o service identificar por email
      // ignore: dead_null_aware_expression
      final googleUid = account.id ?• '';

      final resultado = await ClienteAuthService.loginComGoogle(
        lojaId: widget.lojaId,
        email: email,
        nome: nome,
        googleUid: googleUid,
      );

      if (!mounted) return;

      if (resultado['success'] == true) {
        try {
          final sessao = await Hive.openBox('sessao');
          await sessao.put('auth_context', 'cliente');
          await sessao.put('cliente_loja_id', widget.lojaId);
        } catch (_) {}
        if (!mounted) return;
        _showSnackBar('Bem-vindo, ${resultado['nome']}!', isSuccess: true);
        Navigator.of(context).pop();
      } else {
        _showSnackBar(resultado['error'] ?• 'Erro ao entrar com Google', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[Google] Erro (type=${e.runtimeType})');
      final msg = e.toString().replaceFirst('Exception: ', '');
      // 403/access_denied = conferir People API e Origens autorizadas no Console
      final isPopup = msg.contains('popup_closed') || msg.contains('popup');
      final is403 = msg.contains('403') || msg.contains('access_denied') || msg.contains('Access denied');
      String userMsg;
      if (isPopup) {
        userMsg = 'Login cancelado ou popup bloqueado. Tente novamente.';
      } else if (is403) {
        userMsg = 'Google bloqueou o acesso. Ative o People API e confira as origens em Google Cloud Console.';
      } else {
        userMsg = msg.length > 80 • 'Erro ao conectar com Google. Tente novamente.' : msg;
      }
      _showSnackBar(userMsg, isError: true, duration: const Duration(seconds: 5));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _recuperarSenha() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RedefinirSenhaClienteScreen(lojaId: widget.lojaId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: isDark • null : AppColors.background,
        appBar: AppBar(
          title: const Text('Entrar'),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: theme.colorScheme.onSurface,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.shopping_bag_rounded,
                        size: 72,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Bem-vindo de volta!',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Faça login para continuar',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha:0.6),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Card do formulário
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark • theme.cardTheme.color : AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha:0.06),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.email],
                              decoration: InputDecoration(
                                labelText: 'Email',
                                hintText: 'seu@email.com',
                                prefixIcon: const Icon(Icons.email_outlined, size: 22),
                                filled: true,
                                fillColor: isDark • null : Colors.grey.withValues(alpha:0.06),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: theme.primaryColor, width: 2),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFEF4444)),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) return 'Digite seu email';
                                if (!RegExp(_emailRegex).hasMatch(value.trim())) return 'Email inválido';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _senhaController,
                              obscureText: !_mostrarSenha,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: 'Senha',
                                hintText: '********',
                                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 22),
                                filled: true,
                                fillColor: isDark • null : Colors.grey.withValues(alpha:0.06),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: theme.primaryColor, width: 2),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFEF4444)),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _mostrarSenha • Icons.visibility_off_rounded : Icons.visibility_rounded,
                                    size: 22,
                                  ),
                                  onPressed: () => setState(() => _mostrarSenha = !_mostrarSenha),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Digite sua senha';
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _recuperarSenha,
                                child: Text(
                                  'Esqueceu a senha?',
                                  style: TextStyle(
                                    color: theme.primaryColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _carregando • null : _fazerLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(12)),
                                  ),
                                ),
                                child: _carregando
                                    • const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        'Entrar',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: Divider(color: theme.colorScheme.outline.withValues(alpha:0.5))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'ou',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha:0.6),
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: theme.colorScheme.outline.withValues(alpha:0.5))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 52,
                              child: OutlinedButton.icon(
                                onPressed: _carregando • null : _fazerLoginComGoogle,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.onSurface,
                                  side: BorderSide(color: theme.colorScheme.outline),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(12)),
                                  ),
                                ),
                                icon: Icon(Icons.g_mobiledata_rounded, size: 28, color: theme.colorScheme.primary),
                                label: const Text(
                                  'Entrar com Google',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => CadastroScreenCliente(lojaId: widget.lojaId),
                            ),
                          );
                        },
                        child: Text(
                          'Não tem conta• Cadastre-se',
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
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
    );
  }
}

