import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../themes/app_colors.dart';
import '../../services/cliente_auth_service.dart';
import 'login_screen_cliente.dart';

/// Tela de Cadastro EXCLUSIVA para clientes do cat�logo
/// N�O afeta o login do aplicativo da loja
class CadastroScreenCliente extends StatefulWidget {
  final String lojaId;

  const CadastroScreenCliente({
    super.key,
    required this.lojaId,
  });

  @override
  State<CadastroScreenCliente> createState() => _CadastroScreenClienteState();
}

class _CadastroScreenClienteState extends State<CadastroScreenCliente> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();
  final _telefoneController = TextEditingController();
  bool _carregando = false;
  bool _mostrarSenha = false;
  bool _mostrarConfirmarSenha = false;

  static const _emailRegex = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';

  void _showSnackBar(String message,
      {bool isError = false, bool isSuccess = false, bool isWarning = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_outline : (isWarning ? Icons.warning_amber : Icons.error_outline),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isSuccess
            ? const Color(0xFF22C55E)
            : (isWarning ? const Color(0xFFF59E0B) : (isError ? const Color(0xFFEF4444) : AppColors.primary)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    _telefoneController.dispose();
    super.dispose();
  }

  Future<void> _fazerCadastro() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _carregando = true);

    try {
      final resultado = await ClienteAuthService.cadastrar(
        lojaId: widget.lojaId,
        nome: _nomeController.text.trim(),
        email: _emailController.text.trim(),
        senha: _senhaController.text,
        telefone: _telefoneController.text.trim(),
      );

      if (!mounted) return;

      if (resultado['success'] == true) {
        _showSnackBar('Bem-vindo, ${resultado['nome']}!', isSuccess: true);
        Navigator.of(context).pop();
      } else {
        _showSnackBar(resultado['error'] ?? 'Erro ao cadastrar', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Erro inesperado. Tente novamente.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: isDark ? null : AppColors.background,
        appBar: AppBar(
          title: const Text('Cadastrar'),
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
                        Icons.person_add_rounded,
                        size: 72,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Criar Conta',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Preencha os dados para se cadastrar',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha:0.6),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Card do formul�rio
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark ? theme.cardTheme.color : AppColors.card,
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
                              controller: _nomeController,
                              textCapitalization: TextCapitalization.words,
                              autofillHints: const [AutofillHints.name],
                              decoration: InputDecoration(
                                labelText: 'Nome Completo',
                                hintText: 'Seu nome',
                                prefixIcon: const Icon(Icons.person_outline_rounded, size: 22),
                                filled: true,
                                fillColor: isDark ? null : Colors.grey.withValues(alpha:0.06),
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
                                if (value == null || value.trim().isEmpty) return 'Digite seu nome';
                                if (value.trim().length < 3) return 'Nome muito curto';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
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
                                fillColor: isDark ? null : Colors.grey.withValues(alpha:0.06),
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
                                if (!RegExp(_emailRegex).hasMatch(value.trim())) return 'Email inv�lido';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _telefoneController,
                              keyboardType: TextInputType.phone,
                              autofillHints: const [AutofillHints.telephoneNumber],
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(11),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Telefone (opcional)',
                                hintText: '(11) 99999-9999',
                                prefixIcon: const Icon(Icons.phone_outlined, size: 22),
                                filled: true,
                                fillColor: isDark ? null : Colors.grey.withValues(alpha:0.06),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: theme.primaryColor, width: 2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _senhaController,
                              obscureText: !_mostrarSenha,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: 'Senha',
                                hintText: '��������',
                                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 22),
                                filled: true,
                                fillColor: isDark ? null : Colors.grey.withValues(alpha:0.06),
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
                                    _mostrarSenha ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                    size: 22,
                                  ),
                                  onPressed: () => setState(() => _mostrarSenha = !_mostrarSenha),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Digite uma senha';
                                if (value.length < 8) return 'Senha deve ter pelo menos 8 caracteres';
                                if (!RegExp(r'[A-Za-z]').hasMatch(value)) return 'Senha deve conter letras';
                                if (!RegExp(r'[0-9]').hasMatch(value)) return 'Senha deve conter n�meros';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmarSenhaController,
                              obscureText: !_mostrarConfirmarSenha,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: 'Confirmar Senha',
                                hintText: '��������',
                                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 22),
                                filled: true,
                                fillColor: isDark ? null : Colors.grey.withValues(alpha:0.06),
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
                                    _mostrarConfirmarSenha ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                    size: 22,
                                  ),
                                  onPressed: () => setState(() => _mostrarConfirmarSenha = !_mostrarConfirmarSenha),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Confirme sua senha';
                                if (value != _senhaController.text) return 'As senhas n�o conferem';
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _carregando ? null : _fazerCadastro,
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
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        'Cadastrar',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha:0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.primaryColor.withValues(alpha:0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: theme.primaryColor,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Seus dados s�o protegidos e usados apenas para sua conta.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha:0.8),
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => LoginScreenCliente(lojaId: widget.lojaId),
                            ),
                          );
                        },
                        child: Text(
                          'J� tem conta? Fa�a login',
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

