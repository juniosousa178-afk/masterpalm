import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/pagamentos_service.dart';

/// Espera a sessão Firebase restaurada no browser (web) antes de decidir se pede login.
Future<User?> mpOAuthRestoredUser() async {
  try {
    return await FirebaseAuth.instance
        .authStateChanges()
        .first
        .timeout(const Duration(seconds: 8));
  } catch (_) {
    return FirebaseAuth.instance.currentUser;
  }
}

bool mpOAuthIsRealUser(User? u) => u != null && !u.isAnonymous;

/// Login mínimo (e-mail/senha ou Google) para concluir a conexão MP no browser.
class MpOAuthSignInPanel extends StatefulWidget {
  const MpOAuthSignInPanel({super.key, required this.onSignedIn, this.title});

  final VoidCallback onSignedIn;
  final String? title;

  @override
  State<MpOAuthSignInPanel> createState() => _MpOAuthSignInPanelState();
}

class _MpOAuthSignInPanelState extends State<MpOAuthSignInPanel> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _busy = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _erro = null;
    });
    try {
      await action();
      if (mpOAuthIsRealUser(FirebaseAuth.instance.currentUser)) {
        widget.onSignedIn();
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _erro = e.code == 'user-disabled'
          ? 'Conta desativada.'
          : 'Não foi possível entrar. Confira e-mail e senha.');
    } catch (_) {
      setState(() => _erro = 'Não foi possível entrar. Tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title ??
                'Entre com a conta da loja para conectar o Mercado Pago.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-mail'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _senha,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Senha'),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 8),
            Text(_erro!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => FirebaseAuth.instance.signInWithEmailAndPassword(
                            email: _email.text.trim(),
                            password: _senha.text,
                          )),
              child: const Text('Entrar'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => FirebaseAuth.instance
                      .signInWithPopup(GoogleAuthProvider())),
              child: const Text('Entrar com Google'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> _defaultHasRealSession() async =>
    mpOAuthIsRealUser(await mpOAuthRestoredUser());

Future<bool> _defaultLaunchAuthUrl(Uri url) =>
    launchUrl(url, webOnlyWindowName: '_self');

Future<void> _defaultSignOut() => FirebaseAuth.instance.signOut();

/// `/mp-oauth-start?lojaId=…` — exige login e pede ao servidor a URL de autorização do MP.
/// O lojaId da URL é só o pedido: o servidor valida se o utilizador administra a loja
/// e devolve uma URL com state opaco, que o cliente não lê nem altera.
class MpOAuthStartScreen extends StatefulWidget {
  const MpOAuthStartScreen({
    super.key,
    required this.uri,
    this.hasRealSession = _defaultHasRealSession,
    this.createAuthUrl = PagamentosService.criarAutorizacaoOAuth,
    this.launchAuthUrl = _defaultLaunchAuthUrl,
    this.signOut = _defaultSignOut,
  });

  final Uri uri;
  final Future<bool> Function() hasRealSession;
  final Future<String> Function(String lojaId) createAuthUrl;
  final Future<bool> Function(Uri url) launchAuthUrl;
  final Future<void> Function() signOut;

  @override
  State<MpOAuthStartScreen> createState() => _MpOAuthStartScreenState();
}

class _MpOAuthStartScreenState extends State<MpOAuthStartScreen> {
  bool _loading = true;
  bool _needsLogin = false;
  bool _starting = false;
  bool _redirected = false;
  String? _erro;

  String get _lojaId => (widget.uri.queryParameters['lojaId'] ?? '').trim();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (_lojaId.isEmpty) {
      setState(() {
        _loading = false;
        _erro =
            'Loja não informada. Abra a conexão pelo app em Configurações > Pagamentos.';
      });
      return;
    }
    final hasSession = await widget.hasRealSession();
    if (!mounted) return;
    if (!hasSession) {
      setState(() {
        _loading = false;
        _needsLogin = true;
      });
      return;
    }
    await _start();
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    setState(() {
      _loading = true;
      _needsLogin = false;
      _redirected = false;
      _erro = null;
    });
    try {
      final authUrl = await widget.createAuthUrl(_lojaId);
      final launched = await widget.launchAuthUrl(Uri.parse(authUrl));
      if (!launched) {
        _falhar('Não foi possível abrir o Mercado Pago. Tente novamente.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _redirected = true;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      if (e.code == 'unauthenticated') {
        _starting = false;
        setState(() {
          _loading = false;
          _needsLogin = true;
        });
        return;
      }
      _falhar(_mensagemErroInicio(e.code, e.message));
    } catch (_) {
      _falhar('Não foi possível iniciar a conexão. Tente novamente.');
    }
  }

  String _mensagemErroInicio(String code, String? serverMessage) {
    switch (code) {
      case 'permission-denied':
        return 'Esta conta não administra a loja "$_lojaId". Entre com a conta do dono ou de um administrador. Nenhuma alteração foi feita.';
      case 'invalid-argument':
        return serverMessage ?? 'Pedido de conexão inválido.';
      case 'resource-exhausted':
        return 'Muitas tentativas seguidas. Aguarde um minuto e tente novamente.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Sem resposta do servidor. Verifique a internet e tente novamente.';
      default:
        return 'Não foi possível iniciar a conexão. Tente novamente.';
    }
  }

  void _tentarNovamente() {
    if (!_redirected) return;
    _redirected = false;
    _starting = false;
    _start();
  }

  void _falhar(String mensagem) {
    _starting = false;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _erro = mensagem;
    });
  }

  Future<void> _trocarConta() async {
    await widget.signOut();
    if (!mounted) return;
    setState(() {
      _erro = null;
      _needsLogin = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Preparando conexão com o Mercado Pago...'),
        ],
      );
    } else if (_needsLogin) {
      body = MpOAuthSignInPanel(onSignedIn: _start);
    } else if (_redirected) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.open_in_new, size: 56, color: Color(0xFF009EE3)),
          const SizedBox(height: 12),
          const Text(
            'Abrindo o Mercado Pago... Se a página não abrir, tente novamente.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _tentarNovamente,
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 12),
          Text(_erro ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (_lojaId.isNotEmpty)
            OutlinedButton(
                onPressed: _trocarConta,
                child: const Text('Entrar com outra conta')),
        ],
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24), child: body),
          ),
        ),
      ),
    );
  }
}
