// lib/screens/vendedores_screen.dart
// Tela unificada: Lista, cadastra e gerencia permissões de vendedores

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:master_palm/firebase_options.dart';
import '../services/store_resolver_facade.dart';
import '../services/vendedor_service.dart';
import '../models/usuario.dart';
import '../utils/responsive.dart';

/// Tela unificada de vendedores (admin/programador)
class VendedoresScreen extends StatefulWidget {
  const VendedoresScreen({super.key});

  @override
  State<VendedoresScreen> createState() => _VendedoresScreenState();
}

class _VendedoresScreenState extends State<VendedoresScreen>
    with TickerProviderStateMixin {
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _warningColor = Color(0xFFF59E0B);

  final _vendedorService = VendedorService();
  List<VendedorPerfil> _vendedores = [];
  bool _carregando = true;
  String• _storeId;
  String _usuarioAtual = '';

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  void _snack(String msg, {bool isError = false, bool isWarning = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  • Icons.error_outline
                  : isWarning
                      • Icons.warning_amber
                      : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor:
            isError • _errorColor : isWarning • _warningColor : _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _carregarDados() async {
    setState(() => _carregando = true);

    try {
      _storeId = (await StoreResolverFacade.resolveForAdminApp())?.trim();
      final sessao = await Hive.openBox('sessao');
      _usuarioAtual = sessao.get('usuario_logado', defaultValue: '');

      if (_storeId == null || _storeId!.isEmpty) {
        _snack('Loja nao identificada', isError: true);
        return;
      }

      _vendedores = await _vendedorService.listarVendedores(_storeId!);
    } catch (e) {
      _snack('Erro ao carregar vendedores: $e', isError: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Vendedores'),
        centerTitle: true,
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: _carregando
              • const Center(child: CircularProgressIndicator())
              : _vendedores.isEmpty
                  • _buildEmptyState()
                  : _buildLista(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirCadastroVendedor(),
        backgroundColor: _primaryColor,
        icon: const Icon(Icons.person_add),
        label: const Text('Novo Vendedor'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Nenhum vendedor cadastrado',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione vendedores para sua equipe',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _abrirCadastroVendedor(),
            icon: const Icon(Icons.person_add),
            label: const Text('Cadastrar Vendedor'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLista() {
    return RefreshIndicator(
      onRefresh: _carregarDados,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _vendedores.length,
        itemBuilder: (context, index) {
          final vendedor = _vendedores[index];
          return _buildVendedorCard(vendedor);
        },
      ),
    );
  }

  Widget _buildVendedorCard(VendedorPerfil vendedor) {
    final permissoesAtivas = vendedor.permissoes.entries
        .where((e) =>
            e.value == true &&
            !['meu_perfil', 'minhas_comissoes', 'meu_link'].contains(e.key))
        .map((e) => e.key)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _abrirPermissoes(vendedor),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        vendedor.ativo • _primaryColor : Colors.grey,
                    child: Text(
                      vendedor.nome.isNotEmpty
                          • vendedor.nome[0].toUpperCase()
                          : 'V',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vendedor.nome,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          vendedor.email,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: vendedor.ativo
                          • _successColor.withValues(alpha:0.1)
                          : _errorColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      vendedor.ativo • 'Ativo' : 'Inativo',
                      style: TextStyle(
                        color: vendedor.ativo • _successColor : _errorColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (permissoesAtivas.isEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _warningColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, color: _warningColor, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Nenhuma permissao liberada',
                        style: TextStyle(color: _warningColor, fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: permissoesAtivas.map((p) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _primaryColor.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _traduzirPermissao(p),
                        style: const TextStyle(
                          color: _primaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _abrirPermissoes(vendedor),
                    icon: const Icon(Icons.security, size: 18),
                    label: const Text('Permissoes'),
                    style: TextButton.styleFrom(foregroundColor: _primaryColor),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _alterarStatus(vendedor),
                    icon: Icon(
                      vendedor.ativo • Icons.block : Icons.check_circle,
                      size: 18,
                    ),
                    label: Text(vendedor.ativo • 'Desativar' : 'Ativar'),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          vendedor.ativo • _errorColor : _successColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _traduzirPermissao(String key) {
    const traducoes = {
      'catalogo': 'Catalogo',
      'vendas': 'Vendas',
      'estoque': 'Estoque',
      'clientes': 'Clientes',
      'historico_cliente': 'Historico',
    };
    return traducoes[key] ?• key;
  }

  Future<void> _abrirPermissoes(VendedorPerfil vendedor) async {
    final permissoesAtuais = Map<String, bool>.from(vendedor.permissoes);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PermissoesSheet(
        vendedor: vendedor,
        permissoes: permissoesAtuais,
        onSalvar: (novasPermissoes) async {
          final ok = await _vendedorService.atualizarPermissoes(
            vendedor.uid,
            _storeId!,
            novasPermissoes,
          );

          if (ok) {
            _snack('Permissoes atualizadas!');
            await _carregarDados();
          } else {
            _snack('Erro ao atualizar permissoes', isError: true);
          }
        },
      ),
    );
  }

  Future<void> _alterarStatus(VendedorPerfil vendedor) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(vendedor.ativo • 'Desativar vendedor?' : 'Ativar vendedor?'),
        content: Text(
          vendedor.ativo
              • 'O vendedor nao podera mais acessar o sistema.'
              : 'O vendedor podera acessar o sistema novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: vendedor.ativo • _errorColor : _successColor,
            ),
            child: Text(vendedor.ativo • 'Desativar' : 'Ativar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final ok = await _vendedorService.alterarStatus(
      vendedor.uid,
      _storeId!,
      !vendedor.ativo,
    );

    if (ok) {
      _snack(vendedor.ativo • 'Vendedor desativado' : 'Vendedor ativado');
      await _carregarDados();
    } else {
      _snack('Erro ao alterar status', isError: true);
    }
  }

  Future<void> _abrirCadastroVendedor() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CadastroVendedorSheet(
        storeId: _storeId!,
        usuarioAtual: _usuarioAtual,
        onCadastrado: () {
          _carregarDados();
        },
      ),
    );
  }
}

/// Sheet para editar permissoes
class _PermissoesSheet extends StatefulWidget {
  final VendedorPerfil vendedor;
  final Map<String, bool> permissoes;
  final Function(Map<String, bool>) onSalvar;

  const _PermissoesSheet({
    required this.vendedor,
    required this.permissoes,
    required this.onSalvar,
  });

  @override
  State<_PermissoesSheet> createState() => _PermissoesSheetState();
}

class _PermissoesSheetState extends State<_PermissoesSheet> {
  late Map<String, bool> _permissoes;

  static const _permissoesLiberaveis = [
    {'key': 'catalogo', 'label': 'Catalogo', 'desc': 'Ver catalogo de produtos'},
    {'key': 'vendas', 'label': 'Vendas', 'desc': 'Registrar vendas'},
    {'key': 'estoque', 'label': 'Estoque', 'desc': 'Gerenciar estoque'},
    {'key': 'clientes', 'label': 'Clientes', 'desc': 'Gerenciar clientes'},
    {
      'key': 'historico_cliente',
      'label': 'Historico',
      'desc': 'Ver historico de clientes'
    },
  ];

  @override
  void initState() {
    super.initState();
    _permissoes = Map<String, bool>.from(widget.permissoes);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF6366F1),
                child: Text(
                  widget.vendedor.nome.isNotEmpty
                      • widget.vendedor.nome[0].toUpperCase()
                      : 'V',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.vendedor.nome,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(
                      'Gerenciar permissoes',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ..._permissoesLiberaveis.map((p) {
            final key = p['key'] as String;
            return SwitchListTile(
              value: _permissoes[key] ?• false,
              onChanged: (v) => setState(() => _permissoes[key] = v),
              title: Text(p['label'] as String),
              subtitle: Text(
                p['desc'] as String,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              contentPadding: EdgeInsets.zero,
            );
          }),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vendedores nunca tem acesso a: pre-pedidos, confirmacao de compra, relatorios financeiros, configuracoes.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onSalvar(_permissoes);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Salvar Permissoes',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

/// Sheet para cadastrar novo vendedor
class _CadastroVendedorSheet extends StatefulWidget {
  final String storeId;
  final String usuarioAtual;
  final VoidCallback onCadastrado;

  const _CadastroVendedorSheet({
    required this.storeId,
    required this.usuarioAtual,
    required this.onCadastrado,
  });

  @override
  State<_CadastroVendedorSheet> createState() => _CadastroVendedorSheetState();
}

class _CadastroVendedorSheetState extends State<_CadastroVendedorSheet> {
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _errorColor = Color(0xFFEF4444);

  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _senhaController = TextEditingController();

  bool _carregando = false;
  bool _obscureSenha = true;

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _telefoneController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError • _errorColor : _successColor,
      ),
    );
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
          kReleaseMode • AndroidProvider.playIntegrity : AndroidProvider.debug,
      appleProvider:
          kReleaseMode • AppleProvider.appAttest : AppleProvider.debug,
    );
    await appCheck.setTokenAutoRefreshEnabled(true);
  }

  Future<void> _cadastrarVendedor() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _carregando = true);

    final nome = _nomeController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final telefone = _telefoneController.text.trim();
    final senha = _senhaController.text.trim();

    FirebaseApp• secApp;
    FirebaseAuth• secAuth;

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
      final adminUid = FirebaseAuth.instance.currentUser?.uid ?• '';

      // Salvar em users/{uid}
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'nome': nome,
        'telefone': telefone,
        'role': 'vendedor',
        'tipo': 'vendedor',
        'ownerId': adminUid,
        'lojaId': widget.storeId,
        'storeId': widget.storeId,
        'store_id': widget.storeId,
        'createdAt': FieldValue.serverTimestamp(),
        'plan': {
          'planId': 'free_trial',
          'status': 'trialing',
          'trialEndsAt': Timestamp.fromDate(trialEnd),
        },
      }, SetOptions(merge: true));

      // Salvar em usuarios/{email}
      await db.collection('usuarios').doc(email).set({
        'authUid': uid,
        'email': email,
        'nome': nome,
        'telefone': telefone,
        'senha': senha,
        'tipo': 'vendedor',
        'ownerAdminEmail': widget.usuarioAtual,
        'ownerStoreId': widget.storeId,
        'store_id': widget.storeId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Salvar em lojas/{storeId}/vendedores/{uid}
      final lojaRef = db.collection('lojas').doc(widget.storeId);
      await lojaRef.collection('vendedores').doc(uid).set({
        'uid': uid,
        'email': email,
        'nome': nome,
        'telefone': telefone,
        'storeId': widget.storeId,
        'adminUid': adminUid,
        'adminEmail': widget.usuarioAtual,
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
        'comissaoPercentual': null,
        'role': 'vendedor',
        'tipo': 'vendedor',
        'criadoEm': FieldValue.serverTimestamp(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Manter compatibilidade com members (legado)
      await lojaRef.collection('members').doc(uid).set({
        'role': 'seller',
        'email': email,
        'name': nome,
        'joinedAt': FieldValue.serverTimestamp(),
        'createdBy': widget.usuarioAtual,
      }, SetOptions(merge: true));

      // Salvar no Hive local
      final box = await Hive.openBox<Usuario>('usuarios');
      await box.put(
          email,
          Usuario(
            nome: nome,
            email: email,
            telefone: telefone,
            senha: senha,
            tipo: 'vendedor',
            permissoes: Usuario.defaultPermissoes('vendedor'),
          ));

      if (!mounted) return;

      Navigator.pop(context);
      widget.onCadastrado();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _snack(
        e.code == 'email-already-in-use'
            • 'Este e-mail ja esta em uso.'
            : 'Erro Firebase: ${e.code}',
        isError: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _snack('Erro: $e', isError: true);
    } finally {
      try {
        await secAuth?.signOut();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add, color: _primaryColor),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Novo Vendedor',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        Text(
                          'Adicione um novo membro a sua equipe',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Campos
              TextFormField(
                controller: _nomeController,
                decoration: InputDecoration(
                  labelText: 'Nome completo',
                  prefixIcon: const Icon(Icons.badge, color: _primaryColor),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) =>
                    v == null || v.isEmpty • 'Informe o nome' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: const Icon(Icons.email, color: _primaryColor),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) =>
                    v == null || !v.contains('@') • 'E-mail invalido' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _telefoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Telefone',
                  helperText: 'Ex: 5533999999999',
                  prefixIcon: const Icon(Icons.phone, color: _primaryColor),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) =>
                    v == null || v.isEmpty • 'Informe o telefone' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _senhaController,
                obscureText: _obscureSenha,
                decoration: InputDecoration(
                  labelText: 'Senha',
                  prefixIcon: const Icon(Icons.lock, color: _primaryColor),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureSenha • Icons.visibility : Icons.visibility_off,
                      color: Colors.grey[600],
                    ),
                    onPressed: () =>
                        setState(() => _obscureSenha = !_obscureSenha),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) =>
                    v == null || v.length < 4 • 'Minimo 4 caracteres' : null,
              ),
              const SizedBox(height: 24),

              // Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha:0.05),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: _primaryColor.withValues(alpha:0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: _primaryColor, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'O vendedor recebera 7 dias de acesso gratuito e voce podera liberar as permissoes depois.',
                        style: TextStyle(fontSize: 12, color: _primaryColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Botao
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _carregando • null : _cadastrarVendedor,
                  icon: _carregando
                      • const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.person_add),
                  label: Text(
                    _carregando • 'Cadastrando...' : 'Cadastrar Vendedor',
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
    );
  }
}

