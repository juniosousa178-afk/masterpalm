import 'package:flutter/material.dart';

import '../services/pagamentos_service.dart';
import '../web/oauth_callback_guard.dart';
import 'mp_oauth_start_screen.dart';

Future<bool> _defaultHasRealSession() async =>
    mpOAuthIsRealUser(await mpOAuthRestoredUser());

enum _MpOAuthCallbackOutcome { loading, success, cancelled, info, failure }

/// Retorno do Mercado Pago em `/mp-oauth-callback`.
/// [params] vem da memória (o `index.html` já tirou code/state da URL); o state é opaco
/// e só é reenviado ao servidor, que decide a loja. Nada daqui grava credenciais no browser.
class MpOAuthCallbackScreen extends StatefulWidget {
  const MpOAuthCallbackScreen({
    super.key,
    required this.params,
    this.hasRealSession = _defaultHasRealSession,
    this.exchange = PagamentosService.finalizarOAuthNoBackend,
    this.markAttemptOnce = markOauthCallbackAttemptOnce,
  });

  final Map<String, String> params;
  final Future<bool> Function() hasRealSession;
  final Future<void> Function({required String code, required String state})
      exchange;
  final bool Function(String state) markAttemptOnce;

  @override
  State<MpOAuthCallbackScreen> createState() => _MpOAuthCallbackScreenState();
}

class _MpOAuthCallbackScreenState extends State<MpOAuthCallbackScreen> {
  _MpOAuthCallbackOutcome _outcome = _MpOAuthCallbackOutcome.loading;
  String _message = 'Conectando Mercado Pago...';
  bool _needsLogin = false;
  bool _exchanging = false;
  String _loginTitle =
      'Entre com a mesma conta que iniciou a conexão para concluir.';
  String _code = '';
  String _state = '';

  @override
  void initState() {
    super.initState();
    _finalizarOAuth();
  }

  void _show(_MpOAuthCallbackOutcome outcome, String message) {
    if (!mounted) return;
    setState(() {
      _outcome = outcome;
      _message = message;
      _needsLogin = false;
    });
  }

  Future<void> _finalizarOAuth() async {
    final p = widget.params;
    final error = (p['error'] ?? '').trim();
    final code = (p['code'] ?? '').trim();
    final state = (p['state'] ?? '').trim();

    if (error.isEmpty && code.isEmpty && state.isEmpty) {
      _show(
        _MpOAuthCallbackOutcome.info,
        'Não há conexão pendente nesta página. Confira o status em Configurações > Pagamentos.',
      );
      return;
    }

    if (error.isNotEmpty) {
      final cancelled = error == 'access_denied' || error == 'user_cancelled';
      _show(
        cancelled
            ? _MpOAuthCallbackOutcome.cancelled
            : _MpOAuthCallbackOutcome.failure,
        cancelled
            ? 'A autorização foi cancelada no Mercado Pago. Nenhuma alteração foi feita na loja.'
            : 'O Mercado Pago não concluiu a autorização. Nenhuma alteração foi feita na loja. Tente novamente pela tela de pagamentos.',
      );
      return;
    }

    if (code.isEmpty || state.isEmpty) {
      _show(
        _MpOAuthCallbackOutcome.failure,
        'Retorno incompleto do Mercado Pago. Refaça a conexão pela tela de pagamentos.',
      );
      return;
    }

    if (!widget.markAttemptOnce(state)) {
      _show(
        _MpOAuthCallbackOutcome.info,
        'Este retorno já foi processado. Confira o status em Configurações > Pagamentos.',
      );
      return;
    }

    _code = code;
    _state = state;
    final hasSession = await widget.hasRealSession();
    if (!mounted) return;
    if (!hasSession) {
      setState(() => _needsLogin = true);
      return;
    }
    await _trocarCodigo();
  }

  Future<void> _trocarCodigo() async {
    if (_exchanging) return;
    _exchanging = true;
    setState(() {
      _needsLogin = false;
      _outcome = _MpOAuthCallbackOutcome.loading;
    });
    try {
      await widget.exchange(code: _code, state: _state);
      _show(
        _MpOAuthCallbackOutcome.success,
        'Mercado Pago conectado com sucesso. A tela de pagamentos atualiza sozinha.',
      );
    } on MpOAuthExchangeException catch (e) {
      final status = e.statusCode;
      if (status == 401) {
        _exchanging = false;
        if (!mounted) return;
        setState(() {
          _needsLogin = true;
          _loginTitle =
              'Sua sessão expirou. Entre com a mesma conta que iniciou a conexão para concluir.';
        });
        return;
      }
      if (status != null && status >= 400 && status < 500) {
        _show(_MpOAuthCallbackOutcome.failure, e.message);
      } else if (status == null) {
        _show(
          _MpOAuthCallbackOutcome.failure,
          'Sem resposta do servidor. Confira o status em Configurações > Pagamentos antes de tentar de novo.',
        );
      } else {
        _show(
          _MpOAuthCallbackOutcome.failure,
          'Falha de comunicação com o Mercado Pago. Confira o status em Configurações > Pagamentos e tente novamente.',
        );
      }
    } catch (_) {
      _show(
        _MpOAuthCallbackOutcome.failure,
        'Não foi possível concluir a conexão. Confira o status em Configurações > Pagamentos.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = _outcome == _MpOAuthCallbackOutcome.loading;
    final Widget icon;
    final String title;
    switch (_outcome) {
      case _MpOAuthCallbackOutcome.loading:
        icon = const SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(strokeWidth: 4),
        );
        title = 'Conectando Mercado Pago...';
      case _MpOAuthCallbackOutcome.success:
        icon = const Icon(Icons.check_circle, size: 72, color: Colors.green);
        title = 'Conexão concluída';
      case _MpOAuthCallbackOutcome.cancelled:
        icon =
            const Icon(Icons.cancel_outlined, size: 72, color: Colors.orange);
        title = 'Conexão cancelada';
      case _MpOAuthCallbackOutcome.info:
        icon = const Icon(Icons.info_outline, size: 72, color: Colors.blueGrey);
        title = 'Nada a concluir';
      case _MpOAuthCallbackOutcome.failure:
        icon = const Icon(Icons.error_outline, size: 72, color: Colors.red);
        title = 'Falha na conexão';
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _needsLogin
                  ? MpOAuthSignInPanel(
                      title: _loginTitle,
                      onSignedIn: _trocarCodigo,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        icon,
                        const SizedBox(height: 20),
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                        if (!loading) ...[
                          const SizedBox(height: 12),
                          Text(
                            _message,
                            style: Theme.of(context).textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
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
