import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

// Projeto
import 'package:master_palm/firebase_options.dart';
import '../models/usuario.dart';

class CadastroUsuariosScreen extends StatefulWidget {
  const CadastroUsuariosScreen({super.key});

  @override
  State<CadastroUsuariosScreen> createState() => _CadastroUsuariosScreenState();
}

class _CadastroUsuariosScreenState extends State<CadastroUsuariosScreen>
    with TickerProviderStateMixin {
  // Cores do tema moderno
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _secondaryColor = Color(0xFF8B5CF6);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _surfaceColor = Color(0xFFF8FAFC);

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _senhaController = TextEditingController();

  bool _carregando = false;
  bool _obscureSenha = true;
  String _usuarioAtual = '';
  String _tipoUsuarioAtual = 'vendedor';
  String _tipoSelecionado = 'vendedor';
  String _storeIdDoAdmin = '';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _carregarSessao();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nomeController.dispose();
    _emailController.dispose();
    _telefoneController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _showModernSnackBar(String message, {bool isError = false, bool isWarning = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : isWarning ? Icons.warning_amber : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? _errorColor : isWarning ? _warningColor : _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _carregarSessao() async {
    final box = await Hive.openBox('sessao');
    String storeId = (box.get('store_id') ?? '').toString().trim();

    if (storeId.isEmpty) {
      try {
        if (!Hive.isBoxOpen('config')) {
          await Hive.openBox('config');
        }
        final configBox = Hive.box('config');
        storeId = (configBox.get('store_id') ?? '').toString().trim();
      } catch (_) {}
    }

    if (storeId.isEmpty) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('usuarios')
              .where('authUid', isEqualTo: uid)
              .limit(1)
              .get();
          if (userDoc.docs.isNotEmpty) {
            storeId = (userDoc.docs.first.data()['store_id'] ?? '').toString().trim();
          }
        }
      } catch (_) {}
    }

    setState(() {
      _usuarioAtual = box.get('usuario_logado', defaultValue: '');
      _tipoUsuarioAtual = box.get('tipo_usuario', defaultValue: 'vendedor');
      _storeIdDoAdmin = storeId;
      _tipoSelecionado = 'vendedor';
    });
    _animationController.forward();
  }

  List<DropdownMenuItem<String>> _buildTipoItems() {
    if (_tipoUsuarioAtual == 'programador') {
      return const [
        DropdownMenuItem(value: 'programador', child: Text('Programador')),
        DropdownMenuItem(value: 'admin', child: Text('Administrador')),
        DropdownMenuItem(value: 'vendedor', child: Text('Vendedor')),
      ];
    }
    if (_tipoUsuarioAtual == 'admin') {
      return const [
        DropdownMenuItem(value: 'vendedor', child: Text('Vendedor')),
      ];
    }
    return const [];
  }

  Future<FirebaseApp> _ensureSecondaryApp() async {
    try {
      return Firebase.app('secondary');
    } catch (_) {
      return Firebase.initializeApp(
        name: 'secondary',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  Future<void> _ativarAppCheckNoSecundario(FirebaseApp app) async {
    final appCheck = FirebaseAppCheck.instanceFor(app: app);
    await appCheck.activate(
      androidProvider:
          kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
      appleProvider:
          kReleaseMode ? AppleProvider.appAttest : AppleProvider.debug,
    );
    await appCheck.setTokenAutoRefreshEnabled(true);
  }

  Future<void> _cadastrarUsuario() async {
    if (!_formKey.currentState!.validate()) return;

    if (_tipoUsuarioAtual == 'vendedor') {
      _showModernSnackBar('Vendedor não pode criar usuários.', isError: true);
      return;
    }
    if (_tipoUsuarioAtual == 'admin' && _tipoSelecionado != 'vendedor') {
      _showModernSnackBar('Administrador só pode criar vendedores.', isWarning: true);
      return;
    }
    if (_tipoUsuarioAtual == 'admin' &&
        (_storeIdDoAdmin.isEmpty || _storeIdDoAdmin.trim().isEmpty)) {
      _showModernSnackBar(
          'Não foi possível identificar sua loja. Reabra o app e tente novamente.',
          isError: true);
      return;
    }

    setState(() => _carregando = true);

    final nome = _nomeController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final telefone = _telefoneController.text.trim();
    final senha = _senhaController.text.trim();

    final novoUsuario = Usuario(
      nome: nome,
      email: email,
      telefone: telefone,
      senha: senha,
      tipo: _tipoSelecionado,
      permissoes: Usuario.defaultPermissoes(_tipoSelecionado),
    );

    FirebaseApp? secApp;
    FirebaseAuth? secAuth;

    try {
      secApp = await _ensureSecondaryApp();
      await _ativarAppCheckNoSecundario(secApp);
      secAuth = FirebaseAuth.instanceFor(app: secApp);

      final cred = await secAuth.createUserWithEmailAndPassword(
        email: email,
        password: senha,
      );
      final uid = cred.user!.uid;

      final db = FirebaseFirestore.instance;
      final agora = DateTime.now();
      final trialEnd = agora.add(const Duration(days: 7));

      await db.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'nome': nome,
        'telefone': telefone,
        'role': _tipoSelecionado,
        'tipo': _tipoSelecionado,
        'ownerId': _tipoUsuarioAtual == 'admin'
            ? FirebaseAuth.instance.currentUser?.uid
            : null,
        'lojaId': _tipoUsuarioAtual == 'admin' ? _storeIdDoAdmin : null,
        // ✅ Garantir que storeId E store_id estejam preenchidos para vendedor
        'storeId': (_tipoUsuarioAtual == 'admin' && _tipoSelecionado == 'vendedor')
            ? _storeIdDoAdmin
            : null,
        'store_id': (_tipoUsuarioAtual == 'admin' && _tipoSelecionado == 'vendedor')
            ? _storeIdDoAdmin
            : null,
        'createdAt': FieldValue.serverTimestamp(),
        'plan': {
          'planId': 'free_trial',
          'status': 'trialing',
          'trialEndsAt': Timestamp.fromDate(trialEnd),
        },
      }, SetOptions(merge: true));

      await db.collection('usuarios').doc(email).set({
        'authUid': uid,
        'email': email,
        'nome': nome,
        'telefone': telefone,
        'senha': senha,
        'tipo': _tipoSelecionado,
        'ownerAdminEmail': _usuarioAtual.isEmpty ? null : _usuarioAtual,
        'ownerStoreId':
            _tipoUsuarioAtual == 'admin' ? _storeIdDoAdmin : null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (_tipoUsuarioAtual == 'admin' && _tipoSelecionado == 'vendedor') {
        final lojaRef = db.collection('lojas').doc(_storeIdDoAdmin);

        // ✅ Salvar em lojas/{storeId}/vendedores/{uid} (NOVO - com permissões)
        await lojaRef.collection('vendedores').doc(uid).set({
          'uid': uid,
          'email': email,
          'nome': nome,
          'telefone': telefone,
          'storeId': _storeIdDoAdmin,
          'adminUid': FirebaseAuth.instance.currentUser?.uid ?? '',
          'adminEmail': _usuarioAtual,
          'ativo': true,
          'permissoes': {
            'catalogo': false,
            'vendas': false,
            'estoque': false,
            'clientes': false,
            'historico_cliente': false,
            'meu_perfil': true,
            'minhas_comissoes': true,
            'meu_link': true,
          },
          'comissaoPercentual': null, // Usa global da loja
          'role': 'vendedor',
          'tipo': 'vendedor',
          'criadoEm': FieldValue.serverTimestamp(),
          'atualizadoEm': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Manter compatibilidade com lojas/{storeId}/members (legado)
        await lojaRef.collection('members').doc(uid).set({
          'role': 'seller',
          'email': email,
          'name': nome,
          'joinedAt': FieldValue.serverTimestamp(),
          'createdBy': _usuarioAtual,
        }, SetOptions(merge: true));
      }

      final box = await Hive.openBox<Usuario>('usuarios');
      await box.put(email, novoUsuario);

      if (!mounted) return;
      setState(() => _carregando = false);

      _mostrarSucessoBottomSheet(email);

      _formKey.currentState!.reset();
      _nomeController.clear();
      _emailController.clear();
      _telefoneController.clear();
      _senhaController.clear();
    } on FirebaseAuthException catch (e) {
      setState(() => _carregando = false);
      _showModernSnackBar(
        e.code == 'email-already-in-use'
            ? 'Este e-mail já está em uso.'
            : 'Erro Firebase: ${e.code}',
        isError: true,
      );
    } catch (e) {
      setState(() => _carregando = false);
      _showModernSnackBar('Erro: $e', isError: true);
    } finally {
      try {
        await secAuth?.signOut();
      } catch (_) {}
    }
  }

  void _mostrarSucessoBottomSheet(String email) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _successColor.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, size: 64, color: _successColor),
            ),
            const SizedBox(height: 20),
            const Text(
              'Usuário Cadastrado!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'O vendedor foi criado com sucesso e já possui 7 dias de uso gratuito.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/permissoes', arguments: email);
                },
                icon: const Icon(Icons.security),
                label: const Text('Liberar Permissões'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Fechar', style: TextStyle(color: Colors.grey[600])),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? helperText,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: Icon(icon, color: _primaryColor),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _errorColor),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final podeEscolherTipo =
        _tipoUsuarioAtual == 'programador' || _tipoUsuarioAtual == 'admin';

    return Scaffold(
      backgroundColor: _surfaceColor,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 160,
              floating: false,
              pinned: true,
              backgroundColor: _primaryColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_primaryColor, _secondaryColor],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -50,
                        top: -50,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha:0.1),
                          ),
                        ),
                      ),
                      Positioned(
                        left: -30,
                        bottom: -30,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha:0.1),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cadastro de Usuários',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Adicione novos vendedores à sua equipe',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha:0.9),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info card do usuário logado
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha:0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _primaryColor.withValues(alpha:0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person, color: _primaryColor, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _usuarioAtual.isNotEmpty ? _usuarioAtual : 'Carregando...',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _successColor.withValues(alpha:0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _tipoUsuarioAtual.toUpperCase(),
                                        style: const TextStyle(
                                          color: _successColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (_storeIdDoAdmin.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Loja: $_storeIdDoAdmin',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Formulário
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha:0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.person_add, color: _primaryColor),
                                SizedBox(width: 8),
                                Text(
                                  'Dados do Novo Usuário',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            _buildModernTextField(
                              controller: _nomeController,
                              label: 'Nome completo',
                              icon: Icons.badge,
                              validator: (v) =>
                                  v == null || v.isEmpty ? 'Informe o nome' : null,
                            ),
                            const SizedBox(height: 16),

                            _buildModernTextField(
                              controller: _emailController,
                              label: 'E-mail',
                              icon: Icons.email,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) =>
                                  v == null || !v.contains('@') ? 'E-mail inválido' : null,
                            ),
                            const SizedBox(height: 16),

                            _buildModernTextField(
                              controller: _telefoneController,
                              label: 'Telefone',
                              icon: Icons.phone,
                              keyboardType: TextInputType.phone,
                              helperText: 'Ex: 5533999999999',
                              validator: (v) =>
                                  v == null || v.isEmpty ? 'Informe o telefone' : null,
                            ),
                            const SizedBox(height: 16),

                            _buildModernTextField(
                              controller: _senhaController,
                              label: 'Senha',
                              icon: Icons.lock,
                              obscureText: _obscureSenha,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureSenha ? Icons.visibility : Icons.visibility_off,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () =>
                                    setState(() => _obscureSenha = !_obscureSenha),
                              ),
                              validator: (v) => v == null || v.length < 4
                                  ? 'Mínimo 4 caracteres'
                                  : null,
                            ),
                            const SizedBox(height: 16),

                            if (podeEscolherTipo) ...[
                              DropdownButtonFormField<String>(
                                initialValue: _tipoSelecionado,
                                decoration: InputDecoration(
                                  labelText: 'Tipo de usuário',
                                  prefixIcon: const Icon(Icons.admin_panel_settings,
                                      color: _primaryColor),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide:
                                        const BorderSide(color: _primaryColor, width: 2),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                items: _buildTipoItems(),
                                onChanged: (v) => setState(() => _tipoSelecionado = v!),
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _surfaceColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.info_outline, color: _primaryColor),
                                    SizedBox(width: 12),
                                    Text('Tipo: Vendedor',
                                        style: TextStyle(fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 24),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _carregando ? null : _cadastrarUsuario,
                                icon: _carregando
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.person_add),
                                label: Text(
                                  _carregando ? 'Cadastrando...' : 'Cadastrar Usuário',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _successColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  disabledBackgroundColor: _successColor.withValues(alpha:0.6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Info card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _primaryColor.withValues(alpha:0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _primaryColor.withValues(alpha:0.2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: _primaryColor),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Novos usuários recebem 7 dias de acesso gratuito ao sistema.',
                              style: TextStyle(
                                color: _primaryColor,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

