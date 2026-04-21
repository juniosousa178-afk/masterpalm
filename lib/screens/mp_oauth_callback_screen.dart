import 'package:flutter/material.dart';

import '../services/pagamentos_service.dart';
import '../web/oauth_callback_guard.dart';

class MpOAuthCallbackScreen extends StatefulWidget {
  const MpOAuthCallbackScreen({super.key, required this.uri});

  final Uri uri;

  @override
  State<MpOAuthCallbackScreen> createState() => _MpOAuthCallbackScreenState();
}

class _MpOAuthCallbackScreenState extends State<MpOAuthCallbackScreen> {
  bool _loading = true;
  bool _success = false;
  String _message = 'Conectando Mercado Pago...';
  bool _processed = false;

  @override
  void initState() {
    super.initState();
    _finalizarOAuth();
  }

  Future<void> _finalizarOAuth() async {
    if (_processed) return;
    _processed = true;

    final error = (widget.uri.queryParameters['error'] ?? '').trim();
    final errorDescription =
        (widget.uri.queryParameters['error_description'] ?? '').trim();
    final code = (widget.uri.queryParameters['code'] ?? '').trim();
    final state = (widget.uri.queryParameters['state'] ?? '').trim();

    final guardKey = state.isNotEmpty ? state : widget.uri.toString();
    final canProcess = markOauthCallbackAttemptOnce(guardKey);
    if (!canProcess) {
      setState(() {
        _loading = false;
        _success = false;
        _message =
            'Este retorno OAuth já foi processado. Volte para a tela de pagamentos para conferir o status.';
      });
      return;
    }

    if (error.isNotEmpty) {
      final isCancelled = error == 'access_denied' ||
          error == 'user_cancelled' ||
          errorDescription.toLowerCase().contains('cancel');
      setState(() {
        _loading = false;
        _success = false;
        _message = isCancelled
            ? 'Conexão cancelada pelo usuário no Mercado Pago.'
            : (errorDescription.isNotEmpty
                ? 'Não foi possível conectar: $errorDescription'
                : 'Não foi possível conectar: $error');
      });
      return;
    }

    if (code.isEmpty || state.isEmpty) {
      setState(() {
        _loading = false;
        _success = false;
        _message = code.isEmpty
            ? 'Código de autorização não recebido.'
            : 'State inválido ou expirado.';
      });
      return;
    }

    try {
      await PagamentosService.finalizarOAuthNoBackend(code: code, state: state);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
        _message = 'Mercado Pago conectado com sucesso.';
      });
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final isState = msg.contains('state inválido') ||
          msg.contains('state invalido') ||
          msg.contains('state');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _message = isState
            ? 'State inválido ou expirado. Refaça a conexão pelo botão de pagamentos.'
            : 'Falha de comunicação com o backend/Mercado Pago. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _loading
        ? const SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(strokeWidth: 4),
          )
        : Icon(
            _success ? Icons.check_circle : Icons.error_outline,
            size: 72,
            color: _success ? Colors.green : Colors.red,
          );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(height: 20),
                  Text(
                    _loading
                        ? 'Conectando Mercado Pago...'
                        : (_success ? 'Conexão concluída' : 'Falha na conexão'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _message,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (!_loading) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Você já pode fechar esta aba e voltar ao MasterPalm.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
