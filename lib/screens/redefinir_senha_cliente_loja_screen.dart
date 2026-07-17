import 'package:flutter/material.dart';

import '../core/access_scope_service.dart';
import '../themes/app_colors.dart';
import '../services/cliente_auth_service.dart';
import '../services/store_resolver_facade.dart';

/// Tela para o dono da loja redefinir a senha de um cliente do catálogo
/// (quando o cliente esqueceu e a loja define uma nova).
class RedefinirSenhaClienteLojaScreen extends StatefulWidget {
  /// Email do cliente (opcional; se passado, o campo já vem preenchido).
  final String? emailCliente;

  const RedefinirSenhaClienteLojaScreen({super.key, this.emailCliente});

  @override
  State<RedefinirSenhaClienteLojaScreen> createState() =>
      _RedefinirSenhaClienteLojaScreenState();
}

class _RedefinirSenhaClienteLojaScreenState
    extends State<RedefinirSenhaClienteLojaScreen> {
  final _emailController = TextEditingController();
  final _novaSenhaController = TextEditingController();
  final _confirmarController = TextEditingController();

  bool _carregando = false;
  bool _mostrarNovaSenha = false;
  bool _mostrarConfirmar = false;
  String? _lojaId;

  static const _emailRegex =
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';

  @override
  void initState() {
    super.initState();
    if (widget.emailCliente != null &&
        widget.emailCliente!.trim().isNotEmpty) {
      _emailController.text = widget.emailCliente!.trim();
    }
    _enforceAdminAndResolveLoja();
  }

  Future<void> _enforceAdminAndResolveLoja() async {
    final scope = await AccessScopeService.loadIdentity();
    if (!AccessScopeService.canResetClienteCatalogPassword(scope)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Você não possui permissão para redefinir senha de clientes.',
          ),
        ),
      );
      Navigator.of(context).maybePop();
      return;
    }
    final id = await StoreResolverFacade.resolveForAdminApp();
    if (mounted) setState(() => _lojaId = id);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _novaSenhaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess
            ? const Color(0xFF22C55E)
            : (isError ? const Color(0xFFEF4444) : AppColors.primary),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _redefinir() async {
    final scope = await AccessScopeService.loadIdentity();
    if (!AccessScopeService.canResetClienteCatalogPassword(scope)) {
      _showSnack(
        'Você não possui permissão para redefinir senha de clientes.',
        isError: true,
      );
      return;
    }
    final email = _emailController.text.trim();
    final novaSenha = _novaSenhaController.text;
    final confirmar = _confirmarController.text;

    if (email.isEmpty || !RegExp(_emailRegex).hasMatch(email)) {
      _showSnack('Digite o email do cliente.', isError: true);
      return;
    }
    if (novaSenha.length < 8) {
      _showSnack('A nova senha deve ter pelo menos 8 caracteres.', isError: true);
      return;
    }
    if (novaSenha != confirmar) {
      _showSnack('As senhas não conferem.', isError: true);
      return;
    }
    if (_lojaId == null || _lojaId!.isEmpty) {
      _showSnack('Loja não identificada. Tente novamente.', isError: true);
      return;
    }

    setState(() => _carregando = true);
    try {
      final resultado = await ClienteAuthService.redefinirSenhaPelaLoja(
        lojaId: _lojaId!,
        email: email,
        novaSenha: novaSenha,
      );
      if (!mounted) return;

      setState(() => _carregando = false);
      if (resultado['success'] == true) {
        _showSnack('Senha alterada. O cliente já pode entrar no catálogo com a nova senha.',
            isSuccess: true);
        Navigator.of(context).pop();
      } else {
        _showSnack(resultado['error'] ?? 'Erro ao redefinir senha.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        _showSnack('Erro ao redefinir. Tente novamente.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Redefinir senha do cliente'),
        backgroundColor: isDark ? null : Colors.white,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Use esta tela quando um cliente do catálogo esqueceu a senha. '
                  'Informe o email dele e defina uma nova senha. Avise o cliente para que ele faça login com a nova senha.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email do cliente',
                    hintText: 'cliente@email.com',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _novaSenhaController,
                  obscureText: !_mostrarNovaSenha,
                  decoration: InputDecoration(
                    labelText: 'Nova senha',
                    hintText: 'Mínimo 8 caracteres',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _mostrarNovaSenha
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _mostrarNovaSenha = !_mostrarNovaSenha),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmarController,
                  obscureText: !_mostrarConfirmar,
                  decoration: InputDecoration(
                    labelText: 'Confirmar nova senha',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _mostrarConfirmar
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _mostrarConfirmar = !_mostrarConfirmar),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _carregando ? null : _redefinir,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _carregando
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          )
                        : const Text('Redefinir senha do cliente'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

