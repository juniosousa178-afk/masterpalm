// lib/screens/login_screen.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/usuario.dart';
import '../utils/last_route_observer.dart';
import '../widgets/google_sign_in_button_platform.dart';
import '../services/store_resolver_facade.dart';
import '../services/store_resolver_service.dart';
import '../services/auto_sync_service.dart';
import '../utils/role_utils.dart';
import '../config/mp_environment_config.dart';
import '../widgets/mp_qa_semantics.dart';
import '../widgets/mp_qa_login_trace.dart';
import '../widgets/qa_web_text_input_sync.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  // Modern color scheme
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _surfaceColor = Color(0xFF1E293B);

  static final RegExp _emailRegex = RegExp(
    r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$',
  );

  static String _slugLoja(String s) {
    final x = s.trim().toLowerCase();
    final replaced = x
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_@.\-]'), '');
    return replaced.isEmpty ? 'anon' : replaced;
  }

  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();
  final FocusNode _loginFocusNode = FocusNode();
  final FocusNode _senhaFocusNode = FocusNode();

  bool _carregando = false;
  bool _mostrarSenha = false;
  bool _manterLogado = false;
  bool _navLocked = false;

  GoogleSignIn? _googleSignInWeb;
  StreamSubscription<GoogleSignInAccount?>? _googleUserSub;
  DateTime? _googleInitAt;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _shakeController;
  bool _formReady = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _animController.forward();
    if (MpEnvironmentConfig.isQa && kIsWeb) {
      mpQaEnsureSemanticsTree();
    }
    // Google Sign-In web: inicializar antes do primeiro build (plugin exige init antes de renderButton).
    if (kIsWeb) _initGoogleSignInWeb();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Se já está logado (ex.: abriu /login por engano ou volta do router), vai direto para o app
      var current = FirebaseAuth.instance.currentUser;
      if (current != null && !current.isAnonymous && mounted) {
        _safeReplaceNamed('/router');
        return;
      }
      // Web: Auth pode demorar a restaurar da persistência; aguardar um pouco antes de mostrar formulário
      if (kIsWeb && current == null) {
        try {
          await FirebaseAuth.instance.authStateChanges()
              .where((u) => u != null && !u.isAnonymous)
              .first
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
          current = FirebaseAuth.instance.currentUser;
          if (current != null && mounted) {
            _safeReplaceNamed('/router');
            return;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      await _carregarPreferenciaManterLogado();
      if (mounted) _verificarLoginSalvo();
      if (mounted) {
        setState(() => _formReady = true);
        mpQaLoginMark('qa-login-form-ready');
      }
    });
  }

  /// Ponto único de submit (botão, Enter, semântica) — converge para [_login].
  Future<void> _submitLogin() async {
    if (_carregando) return;
    mpQaLoginMark('qa-login-submit-dispatched');
    if (mounted) setState(() {});
    if (MpEnvironmentConfig.isQa && kIsWeb) {
      qaWebSyncLoginControllersIfNeeded(
        login: _loginController,
        senha: _senhaController,
      );
    }
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    await _login();
  }

  void _initGoogleSignInWeb() {
    if (_googleSignInWeb != null) return;
    _googleInitAt = DateTime.now();
    _googleSignInWeb = GoogleSignIn(clientId: _webGoogleClientId);
    _googleUserSub = _googleSignInWeb!.onCurrentUserChanged.listen((account) async {
      if (account == null || !mounted || _navLocked) return;
      final elapsed = DateTime.now().difference(_googleInitAt!).inMilliseconds;
      if (elapsed < 1500) return;

      final email = account.email.trim().toLowerCase();
      if (email.isEmpty) return;

      final box = await _openBoxSafe('sessao');
      final manter = box.get('manter_logado', defaultValue: false) as bool;
      final cachedUser = (box.get('usuario_logado') ?? '').toString().trim().toLowerCase();

      if (manter && cachedUser == email) {
        _safeReplaceNamed('/router');
        return;
      }
      if (mounted && !_navLocked) _handleGoogleUser(account);
    });
  }

  Future<void> _carregarPreferenciaManterLogado() async {
    try {
      final box = await _openBoxSafe('sessao');
      final manter = box.get('manter_logado', defaultValue: false) as bool;
      if (mounted) setState(() => _manterLogado = manter);
    } catch (_) {}
  }

  @override
  void dispose() {
    _googleUserSub?.cancel();
    _loginController.dispose();
    _senhaController.dispose();
    _loginFocusNode.dispose();
    _senhaFocusNode.dispose();
    _animController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _playShakeAnimation() async {
    if (_shakeController.isAnimating) return;
    _shakeController.reset();
    await _shakeController.forward();
  }

  Future<Box<T>> _openBoxSafe<T>(String name) async {
    if (!Hive.isBoxOpen(name)) {
      return await Hive.openBox<T>(name);
    }
    return Hive.box<T>(name);
  }

  void _safeReplaceNamed(String route, {Object? args}) {
    if (!mounted || _navLocked) return;
    _navLocked = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await Navigator.pushReplacementNamed(context, route, arguments: args);
      } finally {
        _navLocked = false;
      }
    });
  }

  /// Única fonte de decisão para restauração de sessão (evita race com onCurrentUserChanged).
  Future<void> _verificarLoginSalvo() async {
    final box = await _openBoxSafe('sessao');
    final manter = box.get('manter_logado', defaultValue: false) as bool;
    final cachedUser = (box.get('usuario_logado') ?? '').toString().trim().toLowerCase();
    final tipo = box.get('tipo_usuario');

    if (!manter || cachedUser.isEmpty || tipo == null) return;

    try {
      await FirebaseAuth.instance.authStateChanges()
          .where((u) => u != null && (u.email ?? '').trim().toLowerCase() == cachedUser)
          .map((u) => u!)
          .first
          .timeout(const Duration(seconds: 3));
      if (!mounted || _navLocked) return;
      _safeReplaceNamed('/router');
    } on TimeoutException {
      // Auth não restaurou a tempo
    } catch (_) {}
  }

  Map<String, dynamic>? _dadosExtrasUsuario;

  Future<Usuario?> _carregarUsuarioDoFirestore({
    required String uid,
    required String email,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[LOGIN-DIAG] Firestore lookup coleção=usuarios | kIsWeb=$kIsWeb | '
        'email_chave=$email | uid=$uid (sem senha)',
      );
    }
    final col = FirebaseFirestore.instance.collection('usuarios');
    Map<String, dynamic>? d;

    // Web: alinhado ao Android — doc(email) → doc(uid) → query authUid; users só em diagnóstico (debug).
    if (kIsWeb) {
      final emailKey = email.toLowerCase().trim();

      try {
        if (kDebugMode) {
          debugPrint('[LOGIN-DIAG] Web: (1) usuarios.doc("$emailKey").get()');
        }
        final byEmailDoc = await col.doc(emailKey).get();
        if (kDebugMode) {
          debugPrint(
            '[LOGIN-DIAG] Web: (1) usuarios/$emailKey exists=${byEmailDoc.exists}',
          );
        }
        if (byEmailDoc.exists) d = byEmailDoc.data();
      } catch (e) {
        debugPrint('[_carregarUsuarioDoFirestore] Web (1) email doc (type=${e.runtimeType})');
        if (kDebugMode) {
          debugPrint('[LOGIN-DIAG] Web: (1) exceção: $e');
        }
      }

      if (d == null) {
        try {
          if (kDebugMode) {
            debugPrint('[LOGIN-DIAG] Web: (2) usuarios.doc("$uid").get()');
          }
          final byUidDoc = await col.doc(uid).get();
          if (kDebugMode) {
            debugPrint(
              '[LOGIN-DIAG] Web: (2) usuarios/$uid exists=${byUidDoc.exists}',
            );
          }
          if (byUidDoc.exists) d = byUidDoc.data();
        } catch (e) {
          debugPrint('[_carregarUsuarioDoFirestore] Web (2) uid doc (type=${e.runtimeType})');
          if (kDebugMode) {
            debugPrint('[LOGIN-DIAG] Web: (2) exceção: $e');
          }
        }
      }

      if (d == null) {
        try {
          if (kDebugMode) {
            debugPrint(
              '[LOGIN-DIAG] Web: (3) query usuarios where authUid == "$uid"',
            );
          }
          final byUidQuery = await col
              .where('authUid', isEqualTo: uid)
              .limit(1)
              .get();
          if (kDebugMode) {
            debugPrint(
              '[LOGIN-DIAG] Web: (3) authUid query count=${byUidQuery.docs.length}',
            );
          }
          if (byUidQuery.docs.isNotEmpty) {
            d = byUidQuery.docs.first.data();
          }
        } catch (e) {
          debugPrint('[_carregarUsuarioDoFirestore] Web (3) authUid (type=${e.runtimeType})');
          if (kDebugMode) {
            debugPrint('[LOGIN-DIAG] Web: (3) exceção: $e');
          }
        }
      }

      if (d == null && kDebugMode) {
        try {
          debugPrint('[LOGIN-DIAG] Web: (4) diagnóstico users/$uid (não usado para sessão)');
          final userProf =
              await FirebaseFirestore.instance.collection('users').doc(uid).get();
          debugPrint(
            '[LOGIN-DIAG] Web: (4) users/$uid exists=${userProf.exists} '
            '(só diagnóstico; login continua exigindo usuarios/)',
          );
        } catch (e) {
          debugPrint('[LOGIN-DIAG] Web: (4) users diagnóstico erro: $e');
        }
      }
    } else {
      try {
        if (kDebugMode) {
          debugPrint('[LOGIN-DIAG] Native: usuarios.doc("$uid").get()');
        }
        final byUid = await col.doc(uid).get();
        if (kDebugMode) {
          debugPrint('[LOGIN-DIAG] Native: usuarios/$uid exists=${byUid.exists}');
        }
        if (byUid.exists) d = byUid.data();
      } catch (e) {
        debugPrint('[_carregarUsuarioDoFirestore] Erro ao buscar por uid (type=${e.runtimeType})');
      }

      if (d == null) {
        try {
          if (kDebugMode) {
            debugPrint('[LOGIN-DIAG] Native: usuarios.doc("$email").get()');
          }
          final byEmail = await col.doc(email).get();
          if (kDebugMode) {
            debugPrint(
              '[LOGIN-DIAG] Native: usuarios/$email exists=${byEmail.exists}',
            );
          }
          if (byEmail.exists) d = byEmail.data();
        } catch (e) {
          debugPrint('[_carregarUsuarioDoFirestore] Erro ao buscar por email (type=${e.runtimeType})');
        }
      }
    }

    if (d == null) {
      if (kDebugMode) {
        debugPrint(
          '[LOGIN-DIAG] usuarios: documento NÃO encontrado após tentativas '
          '(Web: doc email → doc uid → query authUid; ver users/$uid no debug). '
          'Auth costuma estar OK.',
        );
      }
      return null;
    }

    _dadosExtrasUsuario = d;

    final rawPerm = d['permissoes'];
    final Map<String, bool> permissoes = {};
    if (rawPerm is Map) {
      rawPerm.forEach((key, value) {
        if (value is bool) permissoes[key.toString()] = value;
      });
    }

    // ✅ ROOT override: forçar tipo programador (lista canônica: RoleUtils / rootAccounts)
    // ✅ Conta criada no login (Google ou criar conta) tem tipo explícito 'admin'. Vendedor é criado dentro da loja pelo admin.
    final emailLower = email.toLowerCase().trim();
    final tipo = RoleUtils.isRootEmail(emailLower)
        ? 'programador'
        : (d['tipo'] ?? 'vendedor').toString();

    return Usuario(
      nome: (d['nome'] ?? '').toString(),
      email: (d['email'] ?? email).toString(),
      telefone: (d['telefone'] ?? '').toString(),
      senha: (d['senha'] ?? '').toString(),
      tipo: tipo,
      permissoes: permissoes,
    );
  }

  Usuario? _buscarUsuarioLocal(
    Box<Usuario> usuariosBox,
    bool isEmail,
    String login,
    String loginRaw,
    String senhaDigitada,
  ) {
    for (final u in usuariosBox.values) {
      final bool matchLogin =
          isEmail ? (u.email == login) : (u.telefone == loginRaw);
      if (matchLogin && u.senha == senhaDigitada) {
        return u;
      }
    }
    return null;
  }

  void _showModernSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isError ? Icons.error_outline :
                isSuccess ? Icons.check_circle_outline : Icons.info_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _errorColor : isSuccess ? _successColor : _primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _login() async {
    if (_carregando) return;
    setState(() => _carregando = true);

    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (kDebugMode) {
      debugPrint('[LOGIN-ANDROID] Início login manual. isAndroid=$isAndroid');
    }

    final loginRaw = _loginController.text.trim();
    final login = loginRaw.toLowerCase();
    final senhaDigitada = _senhaController.text.trim();

    if (login.isEmpty || senhaDigitada.isEmpty) {
      setState(() => _carregando = false);
      HapticFeedback.lightImpact();
      _playShakeAnimation();
      _showModernSnackBar('Preencha todos os campos', isError: true);
      return;
    }

    if (login.contains('@') && !_emailRegex.hasMatch(login)) {
      setState(() => _carregando = false);
      HapticFeedback.lightImpact();
      _playShakeAnimation();
      _showModernSnackBar('Informe um e-mail válido', isError: true);
      return;
    }

    mpQaLoginMark('qa-login-validation-passed');

    try {
    final usuariosBox = await _openBoxSafe<Usuario>('usuarios');
    final sessao = await _openBoxSafe<dynamic>('sessao');

    Usuario? usuario;
    final bool isEmail = login.contains('@');

    try {
      if (isEmail) {
        // Até 2 tentativas: evita bloquear cliente quando reCAPTCHA/400 falha com credenciais corretas
        UserCredential? cred;
        for (int attempt = 1; attempt <= 2; attempt++) {
          if (kDebugMode) debugPrint('[LOGIN-FIREBASE] signInWithEmailAndPassword tentativa $attempt');
          try {
            mpQaLoginMark('qa-auth-request-started');
            cred = await FirebaseAuth.instance
                .signInWithEmailAndPassword(email: login, password: senhaDigitada)
                .timeout(const Duration(seconds: 20), onTimeout: () {
              throw TimeoutException('Login demorou demais. Verifique a conexão.');
            });
            break;
          } on FirebaseAuthException catch (e) {
            final code = e.code.toLowerCase();
            // Erro de credencial: não retentar, mensagem clara
            if (code == 'wrong-password' ||
                code == 'invalid-credential' ||
                code == 'invalid-login-credentials' ||
                code == 'user-not-found') {
              rethrow;
            }
            // 400 / reCAPTCHA: retentar uma vez antes de mostrar mensagem
            if (attempt < 2 &&
                (code == 'captcha-check-failed' ||
                    code == 'app-not-authorized' ||
                    code == 'too-many-requests' ||
                    (e.message ?? '').toLowerCase().contains('400') ||
                    (e.message ?? '').toLowerCase().contains('bad request'))) {
              if (kDebugMode) debugPrint('[LOGIN-FIREBASE] 400/reCAPTCHA, aguardando e retentando...');
              await Future<void>.delayed(const Duration(milliseconds: 1500));
              continue;
            }
            rethrow;
          } catch (e) {
            final errStr = e.toString().toLowerCase();
            if (attempt < 2 &&
                (errStr.contains('400') ||
                    errStr.contains('bad request') ||
                    errStr.contains('identitytoolkit') ||
                    errStr.contains('recaptcha') ||
                    errStr.contains('captcha'))) {
              if (kDebugMode) debugPrint('[LOGIN-FIREBASE] Erro verificação, aguardando e retentando...');
              await Future<void>.delayed(const Duration(milliseconds: 1500));
              continue;
            }
            rethrow;
          }
        }

        final uid = cred?.user?.uid ?? '';
        if (uid.isEmpty) throw Exception("UID vazio");

        mpQaLoginMark('qa-auth-request-succeeded');
        mpQaLoginMark('qa-app-authenticated');

        if (kDebugMode) {
          final authEmail =
              (cred?.user?.email ?? '').trim().toLowerCase();
          debugPrint(
            '[LOGIN-DIAG] signInWithEmailAndPassword OK | email_campo=$login | '
            'firebaseAuth.user.email=$authEmail | uid=$uid',
          );
          if (authEmail.isNotEmpty && authEmail != login) {
            debugPrint(
              '[LOGIN-DIAG] Atenção: e-mail do Auth difere do campo (normalização). '
              'Firestore usuarios usa o e-mail do login: $login',
            );
          }
        }

        usuario = await _carregarUsuarioDoFirestore(uid: uid, email: login);

        if (usuario == null) {
          setState(() => _carregando = false);
          if (!mounted) return;
          _showModernSnackBar(
            'Usuario nao encontrado no sistema. Verifique seu cadastro.',
            isError: true,
          );
          return;
        }

        await usuariosBox.put(usuario.email, usuario);
      } else {
        usuario = _buscarUsuarioLocal(
          usuariosBox,
          isEmail,
          login,
          loginRaw,
          senhaDigitada,
        );

        // Login por telefone/usuário local precisa materializar sessão no Firebase.
        // Sem isso, o AppStartRouter recebe currentUser == null e volta para /login.
        if (usuario != null) {
          final emailLocal = usuario.email.trim().toLowerCase();
          if (emailLocal.isEmpty || !emailLocal.contains('@')) {
            throw Exception(
              'Conta local sem e-mail válido para autenticação no servidor.',
            );
          }

          final cred = await FirebaseAuth.instance
              .signInWithEmailAndPassword(
                email: emailLocal,
                password: senhaDigitada,
              )
              .timeout(const Duration(seconds: 20), onTimeout: () {
            throw TimeoutException('Login demorou demais. Verifique a conexão.');
          });

          final uid = cred.user?.uid ?? '';
          if (uid.isNotEmpty) {
            final usuarioFirestore = await _carregarUsuarioDoFirestore(
              uid: uid,
              email: emailLocal,
            );
            if (usuarioFirestore != null) {
              usuario = usuarioFirestore;
              await usuariosBox.put(usuario.email, usuario);
            }
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      mpQaLoginMarkError(mpQaSanitizeAuthErrorCode(e.code));
      if (kDebugMode) {
        debugPrint('[LOGIN-FIREBASE] FirebaseAuthException: code=${e.code} message=${e.message}');
      }
      final msg = (e.message ?? '').toLowerCase();
      final code = e.code.toLowerCase();

      // 1) Credenciais inválidas — única vez que falamos em senha incorreta
      if (code == 'wrong-password' ||
          code == 'invalid-credential' ||
          code == 'invalid-login-credentials') {
        setState(() => _carregando = false);
        if (!mounted) return;
        final isRoot = RoleUtils.isRootEmail(login);
        _showModernSnackBar(
          isRoot
              ? 'E-mail ou senha incorretos. Contas programador: use "Entrar com Google" ou defina senha no Firebase Console.'
              : 'E-mail ou senha incorretos.',
          isError: true,
        );
        return;
      }
      if (code == 'user-not-found') {
        setState(() => _carregando = false);
        if (!mounted) return;
        _showModernSnackBar('Usuário não encontrado. Verifique o e-mail.', isError: true);
        return;
      }

      // 2) Erro de verificação (reCAPTCHA/400) — NUNCA dizer que a senha está errada
      if (code == 'captcha-check-failed' ||
          code == 'app-not-authorized' ||
          code == 'too-many-requests' ||
          msg.contains('400') ||
          msg.contains('bad request') ||
          msg.contains('expired') ||
          msg.contains('malformed')) {
        setState(() => _carregando = false);
        if (!mounted) return;
        _showModernSnackBar(
          'Verificação não concluída. Aguarde um instante e tente novamente.',
          isError: true,
        );
        return;
      }

      usuario = _buscarUsuarioLocal(
        usuariosBox,
        isEmail,
        login,
        loginRaw,
        senhaDigitada,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LOGIN-FIREBASE] Erro (type=${e.runtimeType}): $e');
      }
      final errStr = e.toString().toLowerCase();
      if (e is TimeoutException || errStr.contains('timeout') || errStr.contains('demorou')) {
        setState(() => _carregando = false);
        if (!mounted) return;
        _showModernSnackBar(
          'Login demorou. Verifique a conexão e tente novamente.',
          isError: true,
        );
        return;
      }
      // 400 / identitytoolkit / captcha — NUNCA acusar senha errada; incentivar nova tentativa
      if (errStr.contains('400') ||
          errStr.contains('bad request') ||
          errStr.contains('identitytoolkit') ||
          errStr.contains('recaptcha') ||
          errStr.contains('captcha')) {
        setState(() => _carregando = false);
        if (!mounted) return;
        _showModernSnackBar(
          'Verificação não concluída. Aguarde um instante e tente novamente.',
          isError: true,
        );
        return;
      }
      // Login por e-mail usa só Firebase; não buscar no Hive (evita "inválidos" para programador/Google)
      if (!isEmail) {
        usuario = _buscarUsuarioLocal(
          usuariosBox,
          isEmail,
          login,
          loginRaw,
          senhaDigitada,
        );
      }
    }

    if (usuario == null) {
      setState(() => _carregando = false);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _playShakeAnimation();
      final isRootEmail = RoleUtils.isRootEmail(login);
      _showModernSnackBar(
        isRootEmail
            ? 'Use o botão "Entrar com Google" para acessar com masterpalm26@gmail.com (ou verifique a senha no Firebase Console).'
            : (isEmail ? 'E-mail ou senha incorretos. Tente novamente ou use o botão Google.' : 'Usuário ou senha inválidos.'),
        isError: true,
      );
      return;
    }

    // ✅ ROOT override ANTES da lógica de vendedor
    final isRoot = RoleUtils.isRootEmail(usuario.email);
    if (isRoot) {
      usuario = Usuario(
        nome: usuario.nome,
        email: usuario.email,
        telefone: usuario.telefone,
        senha: usuario.senha,
        tipo: 'programador',
        permissoes: usuario.permissoes,
      );
    }

    String? lojaId;
    try {
      if (!isRoot && usuario.tipo == 'vendedor') {
        final ownerStoreId = (_dadosExtrasUsuario?['store_id'] ??
                             _dadosExtrasUsuario?['lojaId'] ??
                             _dadosExtrasUsuario?['ownerStoreId'] ?? '').toString().trim();

        if (ownerStoreId.isEmpty) {
          setState(() => _carregando = false);
          if (!mounted) return;
          _showModernSnackBar(
            'Vendedor sem loja vinculada. Peça ao administrador para vincular você à loja.',
            isError: true,
          );
          return;
        }

        lojaId = ownerStoreId;
        debugPrint('✅ Vendedor logado - usando loja do admin: $lojaId');
        await sessao.put('store_id', lojaId);
      } else {
        lojaId = await StoreResolverFacade.resolveForAdminApp();

        if (lojaId == null || lojaId.isEmpty) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null && uid.isNotEmpty) {
            lojaId = 'loja_uid_$uid';
          } else if (usuario.email.isNotEmpty) {
            lojaId = 'loja_email_${_slugLoja(usuario.email)}';
          } else {
            lojaId = 'loja_tel_${_slugLoja(usuario.telefone)}';
          }
          debugPrint('Nova loja criada para admin: $lojaId');
        } else {
          debugPrint('Loja existente reutilizada: $lojaId');
        }
      }

      await StoreResolverService.debug();
      AutoSyncService.syncEmBackground();
    } catch (e) {
      debugPrint('ERRO ao definir loja do usuario (type=${e.runtimeType})');
      setState(() => _carregando = false);
      if (!mounted) return;
      _showModernSnackBar(
        'Erro ao carregar dados da loja. Verifique sua conexão e tente novamente.',
        isError: true,
      );
      return;
    }

    if (lojaId.isEmpty) {
      setState(() => _carregando = false);
      if (!mounted) return;
      _showModernSnackBar(
        'Não foi possível identificar sua loja. Tente novamente.',
        isError: true,
      );
      return;
    }

    await sessao.put('store_id', lojaId);

    await sessao.put('usuario_logado', usuario.email);

    if (isRoot) {
      await sessao.put('tipo_usuario', 'programador');
      await sessao.put('is_root', true);
      await sessao.put('role', 'programador');
      debugPrint('🔑 ROOT USER: ${usuario.email} - acesso total ativado');

      // ✅ Corrigir Firestore se estiver com tipo errado (await para evitar crash)
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        try {
          await RoleUtils.migrateIfNeeded(uid: uid, email: usuario.email);
        } catch (e) {
          debugPrint('⚠️ [LOGIN] Erro ao migrar role (não bloqueia) (type=${e.runtimeType})');
        }
      }
    } else {
      await sessao.put('tipo_usuario', usuario.tipo);
      await sessao.put('is_root', false);
    }

    await sessao.put('manter_logado', _manterLogado);
    await sessao.put('auth_context', 'admin');

    await LastRouteObserver.clearLastRoute();

    final lic = await _openBoxSafe('licenca');
    await lic.clear();

    setState(() => _carregando = false);
    if (!mounted) return;

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      setState(() => _carregando = false);
      _showModernSnackBar(
        'Sessão não iniciada no servidor. Tente entrar com e-mail e senha.',
        isError: true,
      );
      return;
    }

    _safeReplaceNamed('/router');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('❌ [LOGIN] Erro crítico (type=${e.runtimeType})');
        debugPrint('$st');
      }
      if (!mounted) return;
      setState(() => _carregando = false);
      final errStr = e.toString().toLowerCase();
      String msg = 'Erro ao fazer login. Tente novamente.';
      if (errStr.contains('socket') || errStr.contains('network') || errStr.contains('connection') || errStr.contains('timeout') || errStr.contains('failed host lookup')) {
        msg = 'Sem conexão. Verifique a internet e tente novamente.';
      } else if (errStr.contains('permission-denied') || errStr.contains('permission_denied')) {
        msg = 'Sem permissão para acessar os dados. Tente novamente.';
      } else if (errStr.contains('store') || errStr.contains('loja')) {
        msg = 'Não foi possível carregar a loja. Verifique sua conexão.';
      }
      _showModernSnackBar(msg, isError: true);
    }
  }

  /// Client ID do tipo "Aplicativo da Web" (igual ao meta em web/index.html).
  static const String _webGoogleClientId =
      '950139833317-u4t79d3g5mq4oqmd0psia0dkeq9gokmb.apps.googleusercontent.com';

  /// Web: usa renderButton + onCurrentUserChanged (não chama signIn).
  /// Mobile: fluxo tradicional com signIn().
  Future<void> _loginWithGoogle() async {
    if (kIsWeb) return; // No web o botão é renderButton e o listener trata
    if (_carregando) return;
    setState(() => _carregando = true);

    if (kDebugMode) debugPrint('[LOGIN-GOOGLE] Início login Google (mobile).');

    try {
      final GoogleSignIn googleSignIn =
          GoogleSignIn(serverClientId: _webGoogleClientId);
      await googleSignIn.signOut();
      // Timeout evita travamento quando DEVELOPER_ERROR ou Play Services falha
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn().timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          throw TimeoutException(
            'Login com Google demorou demais. Tente usar e-mail e senha.',
          );
        },
      );
      if (googleUser == null) {
        if (kDebugMode) debugPrint('[LOGIN-GOOGLE] Usuário cancelou ou null.');
        setState(() => _carregando = false);
        return;
      }
      if (kDebugMode) debugPrint('[LOGIN-GOOGLE] Conta obtida: ${googleUser.email}');
      await _handleGoogleUser(googleUser);
    } on FirebaseAuthException catch (e) {
      _handleGoogleAuthError(e);
    } on PlatformException catch (e) {
      _handleGooglePlatformError(e);
    } catch (e, st) {
      _handleGoogleGenericError(e, st);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _handleGoogleUser(GoogleSignInAccount googleUser) async {
    if (_carregando) return;
    setState(() => _carregando = true);

    try {
      if (kDebugMode) debugPrint('[LOGIN-GOOGLE] Obtendo authentication...');
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      if (kDebugMode) {
        debugPrint('[LOGIN-GOOGLE] idToken=${googleAuth.idToken != null ? "ok" : "null"} accessToken=${googleAuth.accessToken != null ? "ok" : "null"}');
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      if (kDebugMode) debugPrint('[LOGIN-FIREBASE] Chamando signInWithCredential...');
      final cred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = cred.user;
      if (user == null || user.uid.isEmpty) {
        throw Exception('Falha ao obter dados do usuário Google');
      }

      final email = (user.email ?? '').trim().toLowerCase();
      if (email.isEmpty) {
        setState(() => _carregando = false);
        if (!mounted) return;
        _showModernSnackBar(
          'Conta Google sem e-mail. Use e-mail e senha.',
          isError: true,
        );
        return;
      }

      Usuario? usuario = await _carregarUsuarioDoFirestore(uid: user.uid, email: email);
      usuario ??= await _criarUsuarioGoogle(
        uid: user.uid,
        email: email,
        nome: user.displayName ?? email.split('@').first,
      );

      if (usuario == null) {
        setState(() => _carregando = false);
        if (!mounted) return;
        _showModernSnackBar('Erro ao criar conta. Tente novamente.', isError: true);
        return;
      }

      final usuariosBox = await _openBoxSafe<Usuario>('usuarios');
      final sessao = await _openBoxSafe<dynamic>('sessao');
      await usuariosBox.put(usuario.email, usuario);

      final isRoot = RoleUtils.isRootEmail(usuario.email);
      Usuario usuarioFinal = usuario;
      if (isRoot) {
        usuarioFinal = Usuario(
          nome: usuario.nome,
          email: usuario.email,
          telefone: usuario.telefone,
          senha: usuario.senha,
          tipo: 'programador',
          permissoes: usuario.permissoes,
        );
      }

      String? lojaId;
      if (!isRoot && usuarioFinal.tipo == 'vendedor') {
        final ownerStoreId = (_dadosExtrasUsuario?['store_id'] ??
                _dadosExtrasUsuario?['lojaId'] ??
                _dadosExtrasUsuario?['ownerStoreId'] ?? '')
            .toString()
            .trim();
        if (ownerStoreId.isEmpty) {
          setState(() => _carregando = false);
          if (!mounted) return;
          _showModernSnackBar(
            'Vendedor sem loja vinculada. Peça ao administrador.',
            isError: true,
          );
          return;
        }
        lojaId = ownerStoreId;
        await sessao.put('store_id', lojaId);
      } else {
        lojaId = await StoreResolverFacade.resolveForAdminApp();
        if (lojaId == null || lojaId.isEmpty) {
          lojaId = (_dadosExtrasUsuario?['store_id'] ?? 'loja_uid_${user.uid}').toString();
          await sessao.put('store_id', lojaId);
          debugPrint('Nova loja criada para admin Google: $lojaId');
        }
      }

      await StoreResolverService.debug();
      debugPrint('🔄 [LOGIN GOOGLE] Sincronização automática em background...');
      AutoSyncService.syncEmBackground();

      await sessao.put('usuario_logado', usuarioFinal.email);
      if (isRoot) {
        await sessao.put('tipo_usuario', 'programador');
        await sessao.put('is_root', true);
        await sessao.put('role', 'programador');
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        if (uid.isNotEmpty) {
          try {
            await RoleUtils.migrateIfNeeded(uid: uid, email: usuarioFinal.email);
          } catch (e) {
            debugPrint('⚠️ [LOGIN GOOGLE] Erro migrar role (type=${e.runtimeType})');
          }
        }
      } else {
        await sessao.put('tipo_usuario', usuarioFinal.tipo);
        await sessao.put('is_root', false);
      }
      await sessao.put('manter_logado', _manterLogado);
      await sessao.put('auth_context', 'admin');

      await LastRouteObserver.clearLastRoute();

      final lic = await _openBoxSafe('licenca');
      await lic.clear();

      setState(() => _carregando = false);
      if (!mounted) return;
      _safeReplaceNamed('/router');
    } on FirebaseAuthException catch (e) {
      _handleGoogleAuthError(e);
    } catch (e, st) {
      _handleGoogleGenericError(e, st);
    }
  }

  void _handleGoogleAuthError(FirebaseAuthException e) {
    if (kDebugMode) {
      debugPrint('[LOGIN-GOOGLE] FirebaseAuthException: code=${e.code} message=${e.message}');
      debugPrint('[LOGIN-TOKEN] Erro na credencial Firebase.');
    }
    setState(() => _carregando = false);
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _playShakeAnimation();
    String msg = 'Erro ao entrar com Google. Tente novamente.';
    if (e.code == 'account-exists-with-different-credential') {
      msg = 'Este e-mail já está cadastrado com outro método. Use e-mail e senha.';
    } else if (e.code == 'invalid-credential' ||
        e.code == 'invalid-id-token' ||
        e.code == 'app-not-authorized') {
      msg = 'Credencial inválida. Adicione o SHA-1 do app na Firebase Console (Android).';
    } else if (e.code == 'network-request-failed') {
      msg = 'Sem conexão. Verifique a internet e tente novamente.';
    }
    _showModernSnackBar(msg, isError: true);
  }

  void _handleGooglePlatformError(PlatformException e) {
    if (kDebugMode) {
      debugPrint('[LOGIN-GOOGLE] PlatformException: ${e.code} ${e.message}');
    }
    setState(() => _carregando = false);
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _playShakeAnimation();
    final code = e.code.toLowerCase();
    final msg = (e.message ?? '').toLowerCase();
    final isDeveloperError = code.contains('developer_error') ||
        code.contains('sign_in_failed') ||
        msg.contains('developer_error') ||
        msg.contains('12501') ||
        msg.contains('unknown calling package') ||
        msg.contains('sha-1') ||
        msg.contains('signature');
    String userMsg = 'Erro ao entrar com Google. Tente novamente.';
    if (isDeveloperError) {
      userMsg = 'Configuração do Google incompleta. Execute o script '
          'atualizar-firebase.ps1 e use login com e-mail e senha.';
    } else if (msg.contains('network') || msg.contains('connection')) {
      userMsg = 'Sem conexão. Verifique a internet.';
    }
    _showModernSnackBar(userMsg, isError: true);
  }

  void _handleGoogleGenericError(Object e, StackTrace st) {
    if (kDebugMode) {
      debugPrint('[LOGIN-GOOGLE] Erro genérico (type=${e.runtimeType}): $e');
      debugPrint('[LOGIN-TOKEN] Stack: $st');
    }
    setState(() => _carregando = false);
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _playShakeAnimation();
    final msg = e.toString().toLowerCase();
    String userMsg = 'Erro ao entrar com Google. Tente novamente.';
    if (e is TimeoutException || msg.contains('timeout') || msg.contains('demorou')) {
      userMsg = 'Login com Google demorou. Use e-mail e senha ou tente novamente.';
    } else if (msg.contains('403') || msg.contains('access_denied')) {
      userMsg = 'Google bloqueou o acesso. Ative o People API em Google Cloud Console.';
    } else if (msg.contains('developer_error') || msg.contains('sha-1') || msg.contains('signature')) {
      userMsg = 'Configuração incompleta. Execute atualizar-firebase.ps1 e use e-mail e senha.';
    }
    _showModernSnackBar(userMsg, isError: true);
  }

  /// Cria usuário + loja quando login com Google (conta nova).
  /// Regra: conta criada no login é SEMPRE adm. Vendedor é criado dentro da loja pelo admin.
  Future<Usuario?> _criarUsuarioGoogle({
    required String uid,
    required String email,
    required String nome,
  }) async {
    final db = FirebaseFirestore.instance;
    final base = email.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'-{2,}'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    String slug = base.isEmpty ? 'minha-loja' : base;
    int i = 0;
    while (true) {
      final snap = await db.collection('lojas').doc(slug).get();
      if (!snap.exists) break;
      i++;
      slug = '$base-$i';
    }

    try {
      await db.collection('lojas').doc(slug).set({
        'id': slug,
        'lojaId': slug,
        'name': nome.isNotEmpty ? nome : 'Minha Loja',
        'nome': nome.isNotEmpty ? nome : 'Minha Loja',
        'slug': slug,
        'ownerUid': uid,
        'ownerEmail': email,
        'ativo': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'admins': {uid: true},
      });

      await db.collection('lojas').doc(slug).collection('config').doc('config').set({
        'lojaId': slug,
        'slug': slug,
        'nome': nome.isNotEmpty ? nome : 'Minha Loja',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await db.collection('lojas').doc(slug).collection('members').doc(uid).set({
        'role': 'owner',
        'email': email,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      // users/{uid} para o router encontrar role ao recarregar
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'nome': nome,
        'role': 'admin',
        'store_id': slug,
        'storeId': slug,
        'lojaId': slug,
        'ownerOf': slug,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final permissoes = Usuario.defaultPermissoes('admin');
      await db.collection('usuarios').doc(email).set({
        'authUid': uid,
        'nome': nome,
        'email': email,
        'telefone': '',
        'tipo': 'admin',
        'store_id': slug,
        'ownerStoreId': slug,
        'permissoes': permissoes,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _dadosExtrasUsuario = {
        'store_id': slug,
        'ownerStoreId': slug,
        'tipo': 'admin',
      };

      return Usuario(
        nome: nome,
        email: email,
        telefone: '',
        senha: '',
        tipo: 'admin',
        permissoes: permissoes,
      );
    } catch (e) {
      debugPrint('[_criarUsuarioGoogle] Erro (type=${e.runtimeType})');
      return null;
    }
  }

  Future<void> _recuperarSenha() async {
    final email = _loginController.text.trim();
    if (email.isEmpty) {
      _showModernSnackBar('Informe seu e-mail para recuperar a senha', isError: true);
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      _showModernSnackBar('Informe um e-mail válido', isError: true);
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      _showRecoveryBottomSheet();
    } on FirebaseAuthException catch (e) {
      debugPrint('[_recuperarSenha] FirebaseAuthException: ${e.code} - ${e.message}');
      if (!mounted) return;
      String msg = 'Erro ao enviar e-mail de recuperação. Tente novamente.';
      if (e.code == 'user-not-found') {
        msg = 'Nenhuma conta encontrada com este e-mail.';
      } else if (e.code == 'invalid-email') {
        msg = 'E-mail inválido.';
      } else if (e.code == 'too-many-requests') {
        msg = 'Muitas tentativas. Aguarde alguns minutos.';
      }
      _showModernSnackBar(msg, isError: true);
    } catch (e) {
      debugPrint('[_recuperarSenha] Erro (type=${e.runtimeType})');
      if (!mounted) return;
      _showModernSnackBar('Erro ao enviar e-mail de recuperação. Tente novamente.', isError: true);
    }
  }

  void _showRecoveryBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _successColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.email_outlined, size: 48, color: _successColor),
            ),
            const SizedBox(height: 16),
            const Text(
              'Verifique seu e-mail!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _surfaceColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enviamos um link de recuperacao de senha para o seu e-mail.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                child: const Text('Entendi', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disableNav = _carregando || _navLocked;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: Stack(
          children: [
            Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _surfaceColor,
                Color(0xFF0F172A),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Logo e Header
                          _buildHeader(),
                          const SizedBox(height: 40),
                          // Login Card
                          _buildLoginCard(disableNav),
                          const SizedBox(height: 24),
                          // Footer Links
                          _buildFooterLinks(disableNav),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
            MpQaLoginTraceMarkers(
              formReady: _formReady,
              loading: _carregando,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Logo Container
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/logo_masterpalm.png',
            height: 60,
            errorBuilder: (_, __, ___) => Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primaryColor, _primaryColor.withOpacity(0.7)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.store_outlined,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'MasterPalm',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1,
            shadows: [
              Shadow(
                color: _primaryColor.withOpacity(0.5),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Gerencie seu negocio com facilidade',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard(bool disableNav) {
    final shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 8, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 6, end: -6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.linear));

    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(shakeAnimation.value, 0),
          child: child,
        );
      },
      child: Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          const Text(
            'Entrar',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Faca login para continuar',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),

          // Email/Phone Field
          _buildModernTextField(
            controller: _loginController,
            focusNode: _loginFocusNode,
            label: 'E-mail ou telefone',
            semanticsLabel: 'login-email',
            icon: Icons.person_outline,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            onTap: () {
              if (!_loginFocusNode.hasFocus) {
                _loginFocusNode.requestFocus();
              }
            },
            onSubmitted: (_) => _senhaFocusNode.requestFocus(),
          ),
          const SizedBox(height: 16),

          // Password Field
          _buildModernTextField(
            controller: _senhaController,
            focusNode: _senhaFocusNode,
            label: 'Senha',
            semanticsLabel: 'login-password',
            icon: Icons.lock_outline,
            obscureText: !_mostrarSenha,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submitLogin(),
            onEditingComplete: _submitLogin,
            suffixIcon: IconButton(
              icon: Icon(
                _mostrarSenha ? Icons.visibility : Icons.visibility_off,
                color: Colors.white.withOpacity(0.6),
              ),
              onPressed: () => setState(() => _mostrarSenha = !_mostrarSenha),
            ),
          ),
          const SizedBox(height: 16),

          // Keep Logged In
          InkWell(
            onTap: () => setState(() => _manterLogado = !_manterLogado),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _manterLogado ? _primaryColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _manterLogado ? _primaryColor : Colors.white.withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                    child: _manterLogado
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Manter conectado',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Login Button — semântica única + Actions para ativação acessível/Playwright
          Actions(
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (ActivateIntent intent) {
                  if (_carregando || disableNav) return null;
                  _submitLogin();
                  return null;
                },
              ),
            },
            child: Semantics(
            identifier: 'login-submit',
            label: 'login-submit',
            button: true,
            enabled: !(_carregando || disableNav),
            onTap: (_carregando || disableNav) ? null : _submitLogin,
            child: ExcludeSemantics(
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: (_carregando || disableNav) ? null : _submitLogin,
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_primaryColor, _primaryColor.withOpacity(0.8)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _primaryColor.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _carregando
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.login, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'Entrar',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
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
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    String? semanticsLabel,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Iterable<String>? autofillHints,
    bool autofocus = false,
    VoidCallback? onTap,
    ValueChanged<String>? onSubmitted,
    VoidCallback? onEditingComplete,
  }) {
    final field = Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        autofocus: autofocus,
        onTap: onTap,
        onSubmitted: onSubmitted,
        onEditingComplete: onEditingComplete,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 14,
          ),
          prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.6), size: 22),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
    if (semanticsLabel == null) return field;
    return mpQaSemantics(semanticsLabel, field, textField: true);
  }

  Widget _buildFooterLinks(bool disableNav) {
    return Column(
      children: [
        // Divider
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'ou',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
          ],
        ),
        const SizedBox(height: 20),

        // Google Sign-In Button
        kIsWeb
            ? IgnorePointer(
                ignoring: disableNav || _carregando,
                child: Opacity(
                  opacity: (disableNav || _carregando) ? 0.5 : 1,
                  child: buildGoogleSignInButtonWeb(),
                ),
              )
            : SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: disableNav || _carregando
                      ? null
                      : () {
                          FocusScope.of(context).unfocus();
                          HapticFeedback.selectionClick();
                          _loginWithGoogle();
                        },
                  icon: const FaIcon(FontAwesomeIcons.google, size: 20),
                  label: const Text(
                    'Entrar com Google',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.08),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
        const SizedBox(height: 16),

        // Create Account Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: disableNav
                ? null
                : () => Navigator.pushNamed(context, '/register'),
            icon: const Icon(Icons.person_add_outlined, color: _successColor),
            label: const Text(
              'Criar nova conta',
              style: TextStyle(
                color: _successColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _successColor.withOpacity(0.5)),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Forgot Password
        TextButton(
          onPressed: disableNav ? null : _recuperarSenha,
          child: Text(
            'Esqueci minha senha',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

