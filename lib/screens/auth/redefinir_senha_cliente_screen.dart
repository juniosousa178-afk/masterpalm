import 'package:flutter/material.dart';

import '../../themes/app_colors.dart';
import '../../services/cliente_auth_service.dart';

/// Tela para redefinir senha do cliente do cat�logo (esqueci a senha).
/// Fluxo: informar email ? receber c�digo por email ? informar c�digo + nova senha.
class RedefinirSenhaClienteScreen extends StatefulWidget {
  final String lojaId;

  const RedefinirSenhaClienteScreen({
    super.key,
    required this.lojaId,
  });

  @override
  State<RedefinirSenhaClienteScreen> createState() => _RedefinirSenhaClienteScreenState();
}

class _RedefinirSenhaClienteScreenState extends State<RedefinirSenhaClienteScreen> {
  final _emailController = TextEditingController();
  final _codigoController = TextEditingController();
  final _novaSenhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();

  bool _carregando = false;
  bool _codigoEnviado = false;
  bool _mostrarNovaSenha = false;
  bool _mostrarConfirmarSenha = false;

  static const _emailRegex = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';

  @override
  void dispose() {
    _emailController.dispose();
    _codigoController.dispose();
    _novaSenhaController.dispose();
    _confirmarSenhaController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_outline : Icons.error_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isSuccess ? const Color(0xFF22C55E) : (isError ? const Color(0xFFEF4444) : AppColors.primary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _enviarCodigo() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !RegExp(_emailRegex).hasMatch(email)) {
      _showSnackBar('Digite um email v�lido.', isError: true);
      return;
    }

    setState(() => _carregando = true);
    try {
      final resultado = await ClienteAuthService.solicitarRedefinicaoSenha(
        lojaId: widget.lojaId,
        email: email,
      );
      if (!mounted) return;

      if (resultado['success'] == true) {
        setState(() {
          _codigoEnviado = true;
          _carregando = false;
        });
        _showSnackBar('C�digo enviado para seu email. Verifique sua caixa de entrada.', isSuccess: true);
      } else {
        setState(() => _carregando = false);
        _showSnackBar(resultado['error'] ?? 'Erro ao enviar c�digo.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        _showSnackBar('Erro ao enviar. Tente novamente.', isError: true);
      }
    }
  }

  Future<void> _redefinirSenha() async {
    final email = _emailController.text.trim();
    final codigo = _codigoController.text.trim();
    final novaSenha = _novaSenhaController.text;
    final confirmar = _confirmarSenhaController.text;

    if (codigo.length != 6) {
      _showSnackBar('O c�digo deve ter 6 d�gitos.', isError: true);
      return;
    }
    if (novaSenha.length < 8) {
      _showSnackBar('A senha deve ter pelo menos 8 caracteres.', isError: true);
      return;
    }
    if (novaSenha != confirmar) {
      _showSnackBar('As senhas n�o conferem.', isError: true);
      return;
    }

    setState(() => _carregando = true);
    try {
      final resultado = await ClienteAuthService.redefinirSenhaComCodigo(
        lojaId: widget.lojaId,
        email: email,
        codigo: codigo,
        novaSenha: novaSenha,
      );
      if (!mounted) return;

      setState(() => _carregando = false);
      if (resultado['success'] == true) {
        _showSnackBar('Senha alterada com sucesso! Fa�a login com a nova senha.', isSuccess: true);
        Navigator.of(context).pop();
      } else {
        _showSnackBar(resultado['error'] ?? 'Erro ao redefinir senha.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        _showSnackBar('Erro ao redefinir. Tente novamente.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? null : AppColors.background,
      appBar: AppBar(
        title: const Text('Redefinir senha'),
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_reset_rounded,
                    size: 64,
                    color: theme.primaryColor,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _codigoEnviado ? 'Digite o c�digo e a nova senha' : 'Esqueceu sua senha?',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _codigoEnviado
                        ? 'Enviamos um c�digo de 6 d�gitos para seu email.'
                        : 'Informe seu email e enviaremos um c�digo para redefinir.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha:0.7),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
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
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          readOnly: _codigoEnviado,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email_outlined, size: 22),
                            filled: true,
                            fillColor: isDark ? null : Colors.grey.withValues(alpha:0.06),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Digite seu email';
                            if (!RegExp(_emailRegex).hasMatch(v.trim())) return 'Email inv�lido';
                            return null;
                          },
                        ),
                        if (!_codigoEnviado) ...[
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _carregando ? null : _enviarCodigo,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _carregando
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                    )
                                  : const Text('Enviar c�digo'),
                            ),
                          ),
                        ],
                        if (_codigoEnviado) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _codigoController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: InputDecoration(
                              labelText: 'C�digo de 6 d�gitos',
                              prefixIcon: const Icon(Icons.pin_rounded, size: 22),
                              filled: true,
                              fillColor: isDark ? null : Colors.grey.withValues(alpha:0.06),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _novaSenhaController,
                            obscureText: !_mostrarNovaSenha,
                            decoration: InputDecoration(
                              labelText: 'Nova senha',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 22),
                              suffixIcon: IconButton(
                                icon: Icon(_mostrarNovaSenha ? Icons.visibility_off : Icons.visibility, size: 22),
                                onPressed: () => setState(() => _mostrarNovaSenha = !_mostrarNovaSenha),
                              ),
                              filled: true,
                              fillColor: isDark ? null : Colors.grey.withValues(alpha:0.06),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmarSenhaController,
                            obscureText: !_mostrarConfirmarSenha,
                            decoration: InputDecoration(
                              labelText: 'Confirmar nova senha',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 22),
                              suffixIcon: IconButton(
                                icon: Icon(_mostrarConfirmarSenha ? Icons.visibility_off : Icons.visibility, size: 22),
                                onPressed: () => setState(() => _mostrarConfirmarSenha = !_mostrarConfirmarSenha),
                              ),
                              filled: true,
                              fillColor: isDark ? null : Colors.grey.withValues(alpha:0.06),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _carregando ? null : _redefinirSenha,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _carregando
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                    )
                                  : const Text('Redefinir senha'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _carregando
                                ? null
                                : () {
                                    setState(() {
                                      _codigoEnviado = false;
                                      _codigoController.clear();
                                      _novaSenhaController.clear();
                                      _confirmarSenhaController.clear();
                                    });
                                  },
                            child: const Text('Usar outro email'),
                          ),
                        ],
                      ],
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

