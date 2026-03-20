// lib/screens/subcategorias_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/hive_box_names.dart';
import '../models/subcategoria.dart';
import '../services/store_resolver_facade.dart';
import 'package:hive/hive.dart';

/// Tela para gerenciar sub-categorias
class SubcategoriasScreen extends StatefulWidget {
  const SubcategoriasScreen({super.key});

  @override
  State<SubcategoriasScreen> createState() => _SubcategoriasScreenState();
}

class _SubcategoriasScreenState extends State<SubcategoriasScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String• _lojaId;
  List<Subcategoria> _subcategorias = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSubcategorias();
  }

  Future<void> _loadSubcategorias() async {
    setState(() => _loading = true);

    try {
      _lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (_lojaId == null || _lojaId!.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      // Carrega do Hive (box por loja)
      final boxName = HiveBoxNames.subcategorias(_lojaId!);
      final box = await Hive.openBox<Subcategoria>(boxName);
      setState(() {
        _subcategorias = box.values.toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Erro ao carregar sub-categorias (type=${e.runtimeType})');
      setState(() => _loading = false);
    }
  }

  Future<void> _addSubcategoria() async {
    final nomeController = TextEditingController();
    final categoriaController = TextEditingController();
    final iconeController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova Sub-categoria'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  hintText: 'Ex: Anéis de Prata',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoriaController,
                decoration: const InputDecoration(
                  labelText: 'Categoria Pai',
                  hintText: 'Ex: Anéis',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: iconeController,
                decoration: const InputDecoration(
                  labelText: 'Ícone (opcional)',
                  hintText: 'Ex: 💍',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );

    if (result == true && nomeController.text.trim().isNotEmpty) {
      await _saveSubcategoria(
        nome: nomeController.text.trim(),
        categoriaId: categoriaController.text.trim(),
        icone: iconeController.text.trim(),
      );
    }
  }

  Future<void> _saveSubcategoria({
    required String nome,
    required String categoriaId,
    String• icone,
  }) async {
    try {
      final novaSubcategoria = Subcategoria(
        nome: nome,
        categoriaId: categoriaId,
        icone: icone,
        ativa: true,
        dataCriacao: DateTime.now(),
      );

      // Salva no Hive (box por loja)
      final box = await Hive.openBox<Subcategoria>(HiveBoxNames.subcategorias(_lojaId!));
      await box.add(novaSubcategoria);

      // Salva no Firestore
      if (_lojaId != null && _lojaId!.isNotEmpty) {
        await _db
            .collection('lojas')
            .doc(_lojaId)
            .collection('subcategorias')
            .add({
          'nome': nome,
          'categoriaId': categoriaId,
          'icone': icone ?• '',
          'ativa': true,
          'dataCriacao': FieldValue.serverTimestamp(),
        });
      }

      await _loadSubcategorias();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sub-categoria adicionada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao salvar sub-categoria (type=${e.runtimeType})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    }
  }

  Future<void> _editSubcategoria(Subcategoria sub, int index) async {
    final nomeController = TextEditingController(text: sub.nome);
    final categoriaController = TextEditingController(text: sub.categoriaId);
    final iconeController = TextEditingController(text: sub.icone);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Sub-categoria'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoriaController,
                decoration: const InputDecoration(labelText: 'Categoria Pai'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: iconeController,
                decoration: const InputDecoration(labelText: 'Ícone (opcional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        sub.nome = nomeController.text.trim();
        sub.categoriaId = categoriaController.text.trim();
        sub.icone = iconeController.text.trim();
        await sub.save();

        await _loadSubcategorias();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Sub-categoria atualizada!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Erro ao editar (type=${e.runtimeType})');
      }
    }
  }

  Future<void> _deleteSubcategoria(Subcategoria sub) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: Text('Deseja realmente excluir a sub-categoria "${sub.nome}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await sub.delete();
        await _loadSubcategorias();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🗑️ Sub-categoria excluída'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Erro ao excluir (type=${e.runtimeType})');
      }
    }
  }

  Future<void> _toggleAtiva(Subcategoria sub) async {
    try {
      sub.ativa = !sub.ativa;
      await sub.save();
      setState(() {});
    } catch (e) {
      debugPrint('❌ Erro ao alternar status (type=${e.runtimeType})');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sub-categorias'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSubcategorias,
            tooltip: 'Recarregar',
          ),
        ],
      ),
      body: _loading
          • const Center(child: CircularProgressIndicator())
          : _subcategorias.isEmpty
              • Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.category, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'Nenhuma sub-categoria cadastrada',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _addSubcategoria,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar primeira sub-categoria'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _subcategorias.length,
                  itemBuilder: (context, index) {
                    final sub = _subcategorias[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: sub.ativa
                              • Colors.deepPurple.shade100
                              : Colors.grey.shade300,
                          child: Text(
                            sub.icone ?• '📁',
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                        title: Text(
                          sub.nome,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: sub.ativa • null : TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: Text('Categoria: ${sub.categoriaId}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: sub.ativa,
                              onChanged: (_) => _toggleAtiva(sub),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _editSubcategoria(sub, index);
                                } else if (value == 'delete') {
                                  _deleteSubcategoria(sub);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 20),
                                      SizedBox(width: 8),
                                      Text('Editar'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, size: 20, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Excluir', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSubcategoria,
        icon: const Icon(Icons.add),
        label: const Text('Nova Sub-categoria'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
    );
  }
}
