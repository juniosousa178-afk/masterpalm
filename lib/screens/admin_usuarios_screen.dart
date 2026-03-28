// lib/screens/admin_usuarios_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../themes/app_colors.dart';

/// Tela administrativa para gerenciar usuários e planos
/// Somente acessível por masterpalm26@gmail.com (root)
class AdminUsuariosScreen extends StatefulWidget {
  const AdminUsuariosScreen({super.key});

  @override
  State<AdminUsuariosScreen> createState() => _AdminUsuariosScreenState();
}

class _AdminUsuariosScreenState extends State<AdminUsuariosScreen> {
  static const _emailRegex = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';

  final _db = FirebaseFirestore.instance;
  final _searchController = TextEditingController();
  bool _loading = false;
  String _searchQuery = '';
  String _filterTipo = 'todos';
  String _ordenacao = 'email';

  String get _currentUserEmail =>
      FirebaseAuth.instance.currentUser?.email ?? 'masterpalm26@gmail.com';

  bool get _isRoot {
    try {
      final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim();
      if (email == 'masterpalm26@gmail.com' || email == 'masterpalm@gmail.com') return true;

      final tipo = Hive.box('sessao').get('tipo_usuario')?.toString();
      if (tipo == 'programador') return true;
    } catch (_) {}
    return false;
  }

  String _toCanonicalPlanId(String raw) {
    final p = raw.trim().toLowerCase();
    if (p == 'anual' || p == 'pro_yearly') return 'pro_yearly';
    if (p == 'mensal' || p == 'pro_monthly') return 'pro_monthly';
    if (p == 'trial_90d' || p == 'free_trial_90d') return 'free_trial_90d';
    if (p == 'lifetime') return 'lifetime';
    return p;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtrarEOrdenar(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var lista = docs;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      lista = lista.where((d) {
        final email = d.data()['email']?.toString().toLowerCase() ?? d.id.toLowerCase();
        return email.contains(q);
      }).toList();
    }
    if (_filterTipo != 'todos') {
      lista = lista.where((d) {
        final tipo = d.data()['tipo']?.toString() ?? 'vendedor';
        return tipo == _filterTipo;
      }).toList();
    }
    lista = List.from(lista);
    lista.sort((a, b) {
      final da = a.data();
      final db = b.data();
      final emailA = da['email']?.toString() ?? a.id;
      final emailB = db['email']?.toString() ?? b.id;
      final tipoA = da['tipo']?.toString() ?? '';
      final tipoB = db['tipo']?.toString() ?? '';
      final planoA = da['planoId']?.toString() ?? '';
      final planoB = db['planoId']?.toString() ?? '';
      switch (_ordenacao) {
        case 'tipo':
          final c = tipoA.compareTo(tipoB);
          return c != 0 ? c : emailA.compareTo(emailB);
        case 'plano':
          final c = planoA.compareTo(planoB);
          return c != 0 ? c : emailA.compareTo(emailB);
        default:
          return emailA.compareTo(emailB);
      }
    });
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRoot) {
      return Scaffold(
        appBar: AppBar(title: const Text('Acesso Negado')),
        body: const Center(
          child: Text(
            'Você não tem permissão para acessar esta tela.\nSomente o root (masterpalm26@gmail.com) pode gerenciar usuários.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? null
            : AppColors.background,
        appBar: AppBar(
        title: const Text('Admin - Gerenciar Usuários'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Adicionar novo usuário',
            onPressed: _loading ? null : () => _mostrarDialogNovoUsuario(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              setState(() {});
              await Future.delayed(const Duration(milliseconds: 300));
            },
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db.collection('usuarios').orderBy('email').limit(200).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  );
                }

                if (snapshot.hasError) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.3,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'Erro: ${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }

                final todosUsuarios = snapshot.data?.docs ?? [];
                final usuarios = _filtrarEOrdenar(todosUsuarios);

                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Buscar por e-mail...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                filled: true,
                                fillColor: Theme.of(context).brightness == Brightness.dark
                                    ? null
                                    : Colors.grey.withValues(alpha:0.08),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _filterTipo,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Theme.of(context).brightness == Brightness.dark
                                          ? null
                                          : Colors.grey.withValues(alpha:0.08),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'todos', child: Text('Todos os tipos')),
                                      DropdownMenuItem(value: 'programador', child: Text('Programador')),
                                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                                      DropdownMenuItem(value: 'vendedor', child: Text('Vendedor')),
                                    ],
                                    onChanged: (v) => setState(() => _filterTipo = v ?? 'todos'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _ordenacao,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Theme.of(context).brightness == Brightness.dark
                                          ? null
                                          : Colors.grey.withValues(alpha:0.08),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'email', child: Text('Ordenar: E-mail')),
                                      DropdownMenuItem(value: 'tipo', child: Text('Ordenar: Tipo')),
                                      DropdownMenuItem(value: 'plano', child: Text('Ordenar: Plano')),
                                    ],
                                    onChanged: (v) => setState(() => _ordenacao = v ?? 'email'),
                                  ),
                                ),
                              ],
                            ),
                            if (usuarios.length != todosUsuarios.length) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${usuarios.length} de ${todosUsuarios.length} usuários',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (usuarios.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                todosUsuarios.isEmpty
                                    ? 'Nenhum usuário cadastrado'
                                    : 'Nenhum resultado para a busca',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                              ),
                              if (todosUsuarios.isEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Clique em + para adicionar',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final doc = usuarios[index];
                              final data = doc.data();
                              final email = data['email']?.toString() ?? doc.id;
                              final tipo = data['tipo']?.toString() ?? 'vendedor';
                              // Modelo operacional legado/admin em `usuarios/{email}`.
                              // Fonte global canônica de assinatura permanece em `users/{uid}`.
                              final planoAtivo = data['planoAtivo'] ?? false;
                              final planoId = data['planoId']?.toString() ?? 'free';
                              final manualOverride = data['manualOverride'] ?? false;
                              final isLifetime = data['isLifetime'] ?? false;

                              DateTime? currentPeriodEnd;
                              if (data['currentPeriodEnd'] != null) {
                                final timestamp = data['currentPeriodEnd'];
                                if (timestamp is Timestamp) {
                                  currentPeriodEnd = timestamp.toDate();
                                }
                              }

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: Colors.grey.withValues(alpha:0.2)),
                                ),
                                child: ExpansionTile(
                                  leading: CircleAvatar(
                                    backgroundColor: planoAtivo
                                        ? const Color(0xFF22C55E)
                                        : Colors.grey,
                                    child: Icon(
                                      planoAtivo ? Icons.check : Icons.person_outline,
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Text(
                                    email,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Tipo: $tipo | Plano: $planoId'),
                                      if (manualOverride)
                                        const Text(
                                          'LIBERADO MANUALMENTE (sem pagamento)',
                                          style: TextStyle(color: Colors.orange, fontSize: 11),
                                        ),
                                      if (isLifetime)
                                        const Text(
                                          'ACESSO VITALÍCIO',
                                          style: TextStyle(color: Colors.purple, fontSize: 11),
                                        ),
                                      if (currentPeriodEnd != null && !isLifetime)
                                        Text(
                                          'Válido até: ${_formatDate(currentPeriodEnd)}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                    ],
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              ElevatedButton.icon(
                                                onPressed: _loading ? null : () => _liberarPlanoVitalicio(email),
                                                icon: const Icon(Icons.verified_user, size: 18),
                                                label: const Text('Liberar vitalício'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.purple,
                                                  foregroundColor: Colors.white,
                                                ),
                                              ),
                                              ElevatedButton.icon(
                                                onPressed: _loading ? null : () => _liberarPlano90Dias(email),
                                                icon: const Icon(Icons.calendar_today, size: 18),
                                                label: const Text('Liberar 90 dias'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.blue,
                                                ),
                                              ),
                                              ElevatedButton.icon(
                                                onPressed: _loading ? null : () => _liberarPlano1Ano(email),
                                                icon: const Icon(Icons.calendar_month, size: 18),
                                                label: const Text('Liberar 1 ano'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                ),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed: _loading ? null : () => _revogarPlano(email),
                                                icon: const Icon(Icons.block, size: 18),
                                                label: const Text('Revogar acesso'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.red,
                                                ),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed: _loading || _isRootOrCurrent(email)
                                                    ? null
                                                    : () => _confirmarExclusaoUsuario(
                                                          email: email,
                                                          authUid: data['authUid']?.toString(),
                                                        ),
                                                icon: const Icon(Icons.delete_forever, size: 18),
                                                label: const Text('Excluir conta'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.red.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Divider(height: 24),
                                          Row(
                                            children: [
                                              const Text('Tipo de usuário:'),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: DropdownButton<String>(
                                                  value: tipo,
                                                  isExpanded: true,
                                                  items: const [
                                                    DropdownMenuItem(
                                                      value: 'programador',
                                                      child: Text('Programador (full access)'),
                                                    ),
                                                    DropdownMenuItem(
                                                      value: 'admin',
                                                      child: Text('Admin'),
                                                    ),
                                                    DropdownMenuItem(
                                                      value: 'vendedor',
                                                      child: Text('Vendedor'),
                                                    ),
                                                  ],
                                                  onChanged: _loading
                                                      ? null
                                                      : (newTipo) {
                                                          if (newTipo != null) {
                                                            _alterarTipoUsuario(email, newTipo);
                                                          }
                                                        },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            childCount: usuarios.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (_loading)
            Container(
              color: Colors.black.withValues(alpha:0.3),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Processando...'),
                      ],
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _liberarPlanoVitalicio(String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Liberar acesso vitalício?'),
        content: Text(
          'Deseja liberar acesso vitalício (sem expiração) para $email?\n\n'
          'O usuário terá acesso permanente ao sistema sem precisar pagar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final grantedBy = FirebaseAuth.instance.currentUser?.email ?? 'masterpalm26@gmail.com';

      // ✅ Salvar na collection 'usuarios/{email}'
      await _db.collection('usuarios').doc(email).set({
        'email': email,
        'planoId': 'lifetime',
        'planoAtivo': true,
        'isLifetime': true,
        'manualOverride': true,
        'liberadoPor': grantedBy,
        'liberadoEm': FieldValue.serverTimestamp(),
        'currentPeriodEnd': null,
      }, SetOptions(merge: true));

      // ✅ Também salvar na collection 'users/{uid}' (usada pelo planos_service)
      try {
        final usersQuery = await _db.collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (usersQuery.docs.isNotEmpty) {
          await usersQuery.docs.first.reference.set({
            'currentPlanId': 'lifetime',
            'status': 'active',
            'trialing': false,
            'currentPeriodEnd': null,
            'manualOverride': {
              'enabled': true,
              'planId': 'lifetime',
              'grantedBy': grantedBy,
              'grantedAt': FieldValue.serverTimestamp(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}

      if (!mounted) return;
      _showSuccess('Acesso vitalício liberado para $email');
    } catch (e) {
      if (!mounted) return;
      _showError('Erro ao liberar plano: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _liberarPlano90Dias(String email) async {
    await _liberarPlanoPorPeriodo(email, 90, 'trial_90d');
  }

  Future<void> _liberarPlano1Ano(String email) async {
    await _liberarPlanoPorPeriodo(email, 365, 'anual');
  }

  Future<void> _liberarPlanoPorPeriodo(
    String email,
    int dias,
    String planoId,
  ) async {
    setState(() => _loading = true);
    try {
      final endDate = DateTime.now().add(Duration(days: dias));
      final grantedBy = FirebaseAuth.instance.currentUser?.email ?? 'masterpalm26@gmail.com';
      final canonicalPlanId = _toCanonicalPlanId(planoId);

      await _db.collection('usuarios').doc(email).set({
        'email': email,
        'planoId': planoId,
        'planoAtivo': true,
        'isLifetime': false,
        'manualOverride': true,
        'liberadoPor': grantedBy,
        'liberadoEm': FieldValue.serverTimestamp(),
        'currentPeriodEnd': Timestamp.fromDate(endDate),
      }, SetOptions(merge: true));

      // ✅ Espelhar na collection 'users/{uid}'
      try {
        final usersQuery = await _db.collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (usersQuery.docs.isNotEmpty) {
          await usersQuery.docs.first.reference.set({
            'currentPlanId': canonicalPlanId,
            'status': 'active',
            'trialing': false,
            'currentPeriodEnd': Timestamp.fromDate(endDate),
            'manualOverride': {
              'enabled': true,
              'planId': canonicalPlanId,
              'grantedBy': grantedBy,
              'grantedAt': FieldValue.serverTimestamp(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}

      if (!mounted) return;
      _showSuccess('Plano de $dias dias liberado para $email até ${_formatDate(endDate)}');
    } catch (e) {
      if (!mounted) return;
      _showError('Erro ao liberar plano: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revogarPlano(String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revogar acesso?'),
        content: Text(
          'Deseja revogar o acesso de $email?\n\n'
          'O usuário perderá acesso imediatamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final revokedBy = FirebaseAuth.instance.currentUser?.email ?? 'masterpalm26@gmail.com';

      await _db.collection('usuarios').doc(email).set({
        'planoAtivo': false,
        'isLifetime': false,
        'manualOverride': false,
        'revogadoPor': revokedBy,
        'revogadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ✅ Espelhar na collection 'users/{uid}'
      try {
        final usersQuery = await _db.collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (usersQuery.docs.isNotEmpty) {
          await usersQuery.docs.first.reference.set({
            'status': 'revoked',
            'manualOverride': {'enabled': false},
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}

      if (!mounted) return;
      _showSuccess('Acesso revogado para $email');
    } catch (e) {
      if (!mounted) return;
      _showError('Erro ao revogar plano: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Impede excluir root ou a própria conta
  bool _isRootOrCurrent(String email) {
    final e = email.toLowerCase().trim();
    if (e == 'masterpalm26@gmail.com' || e == 'masterpalm@gmail.com' || e == 'admin@masterpalm.com') return true;
    if (e == _currentUserEmail.toLowerCase().trim()) return true;
    return false;
  }

  Future<void> _confirmarExclusaoUsuario({
    required String email,
    String? authUid,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir conta'),
        content: Text(
          'Tem certeza que deseja EXCLUIR permanentemente a conta de $email?\n\n'
          'Serão removidos o perfil (usuarios e users). '
          'Vendas, produtos e clientes da loja NÃO serão apagados.\n\n'
          'O usuário não conseguirá mais acessar o app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      await _db.collection('usuarios').doc(email).delete();

      if (authUid != null && authUid.isNotEmpty) {
        await _db.collection('users').doc(authUid).delete();
      } else {
        final q = await _db.collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        for (final d in q.docs) {
          await d.reference.delete();
        }
      }

      if (!mounted) return;
      _showSuccess('Conta excluída: $email');
    } catch (e) {
      if (!mounted) return;
      _showError('Erro ao excluir: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _alterarTipoUsuario(String email, String novoTipo) async {
    setState(() => _loading = true);
    try {
      await _db.collection('usuarios').doc(email).set({
        'tipo': novoTipo,
        'alteradoPor': _currentUserEmail,
        'alteradoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _showSuccess('Tipo alterado para $novoTipo: $email');
    } catch (e) {
      if (!mounted) return;
      _showError('Erro ao alterar tipo: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mostrarDialogNovoUsuario(BuildContext context) async {
    final emailCtrl = TextEditingController();
    final tipoSelecionado = ValueNotifier<String>('vendedor');
    try {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar Novo Usuário'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                hintText: 'usuario@exemplo.com',
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<String>(
              valueListenable: tipoSelecionado,
              builder: (context, tipo, _) {
                return DropdownButtonFormField<String>(
                  initialValue: tipo,
                  decoration: const InputDecoration(labelText: 'Tipo de usuário'),
                  items: const [
                    DropdownMenuItem(value: 'programador', child: Text('Programador')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'vendedor', child: Text('Vendedor')),
                  ],
                  onChanged: (v) => tipoSelecionado.value = v ?? 'vendedor',
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final email = emailCtrl.text.trim().toLowerCase();
              if (email.isEmpty) {
                _showError('Digite o e-mail');
                return;
              }
              if (!RegExp(_emailRegex).hasMatch(email)) {
                _showError('E-mail inválido');
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Criar'),
          ),
        ],
      ),
    );

    if (resultado != true) {
      return;
    }

    final email = emailCtrl.text.trim().toLowerCase();

    if (email.isEmpty || !RegExp(_emailRegex).hasMatch(email)) {
      _showError('E-mail inválido');
      return;
    }

    setState(() => _loading = true);
    try {
      await _db.collection('usuarios').doc(email).set({
        'email': email,
        'tipo': tipoSelecionado.value,
        'planoAtivo': false,
        'planoId': 'free',
        'criadoPor': _currentUserEmail,
        'criadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _showSuccess('Usuário criado: $email');
    } catch (e) {
      if (!mounted) return;
      _showError('Erro ao criar usuário: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    } finally {
      emailCtrl.dispose();
      tipoSelecionado.dispose();
    }
  }
}

