import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/platform_adaptive.dart';

/// Tela de Perfil do Cliente
class PerfilClienteScreen extends StatelessWidget {
  final String lojaId;

  const PerfilClienteScreen({
    super.key,
    required this.lojaId,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meu Perfil')),
        body: const Center(child: Text('Você não está logado')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Perfil'),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('lojas')
            .doc(lojaId)
            .collection('clientes')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Dados não encontrados'));
          }

          final dados = snapshot.data!.data() as Map<String, dynamic>;
          final nome = dados['nome'] ?? user.displayName ?? 'Sem nome';
          final email = dados['email'] ?? user.email ?? '';
          final telefone = dados['telefone'] ?? '';
          final cupons = List<Map<String, dynamic>>.from(dados['cupons'] ?? []);
          final pedidos = List<Map<String, dynamic>>.from(dados['pedidos'] ?? []);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabeçalho com foto e nome
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.blue,
                  child: Text(
                    nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 40, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  nome,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  email,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                if (telefone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    telefone,
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),

                // Seção de Cupons
                _buildSecao(
                  'Meus Cupons',
                  Icons.local_offer,
                  Colors.orange,
                  cupons.isEmpty
                      ? const Text('Você ainda não tem cupons de desconto')
                      : Column(
                          children: cupons.map((cupom) {
                            final codigo = cupom['codigo'] ?? '';
                            final desconto = cupom['desconto'] ?? 0;
                            final validade = cupom['validade'] ?? '';
                            final usado = cupom['usado'] ?? false;

                            return Card(
                              color: usado ? Colors.grey[300] : Colors.orange[50],
                              child: ListTile(
                                leading: Icon(
                                  usado ? Icons.check_circle : Icons.local_offer,
                                  color: usado ? Colors.grey : Colors.orange,
                                ),
                                title: Text(
                                  codigo,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    decoration: usado
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle: Text('$desconto% de desconto\n$validade'),
                                trailing: Text(usado ? 'USADO' : 'ATIVO'),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 24),

                // Seção de Números da Sorte
                _buildSecao(
                  'Números da Sorte',
                  Icons.casino,
                  Colors.green,
                  pedidos.isEmpty
                      ? const Text('Você ainda não tem números da sorte')
                      : Column(
                          children: pedidos.map((pedido) {
                            final numeroSorte = pedido['numeroSorte'] ?? '';
                            final data = pedido['data'] ?? '';
                            final valor = pedido['valor'] ?? 0;

                            return Card(
                              color: Colors.green[50],
                              child: ListTile(
                                leading: const Icon(Icons.casino, color: Colors.green),
                                title: Text(
                                  'Número: $numeroSorte',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('Pedido de $data\nR\$ ${valor.toStringAsFixed(2)}'),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 24),

                // Seção de Pedidos
                _buildSecao(
                  'Meus Pedidos',
                  Icons.shopping_bag,
                  Colors.blue,
                  pedidos.isEmpty
                      ? const Text('Você ainda não fez pedidos')
                      : Column(
                          children: pedidos.map((pedido) {
                            final id = pedido['id'] ?? '';
                            final data = pedido['data'] ?? '';
                            final valor = pedido['valor'] ?? 0;
                            final status = pedido['status'] ?? 'Pendente';

                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.shopping_bag, color: Colors.blue),
                                title: Text('Pedido #${id.substring(0, 8)}'),
                                subtitle: Text('$data\nR\$ ${valor.toStringAsFixed(2)}'),
                                trailing: Chip(label: Text(status)),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 32),

                // Botão Sair
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirma = await showDialog<bool>(
                      context: context,
                      builder: (context) {
                        final maxW = math.min(
                          kMaxContentWidth,
                          MediaQuery.sizeOf(context).width - 40,
                        );
                        return ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxW),
                          child: AlertDialog(
                            title: const Text('Sair'),
                            content: const Text(
                                'Deseja realmente sair da sua conta?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancelar'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Sair'),
                              ),
                            ],
                          ),
                        );
                      },
                    );

                    if (confirma == true) {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Você saiu da sua conta'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sair da Conta'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSecao(String titulo, IconData icone, Color cor, Widget conteudo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icone, color: cor),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: cor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        conteudo,
      ],
    );
  }
}
