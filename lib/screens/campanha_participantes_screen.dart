import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CampanhaParticipantesScreen extends StatelessWidget {
  final String lojaId;
  final String campanhaId;

  const CampanhaParticipantesScreen({
    super.key,
    required this.lojaId,
    required this.campanhaId,
  });

  @override
  Widget build(BuildContext context) {
    final participantesRef = FirebaseFirestore.instance
        .collection("lojas")
        .doc(lojaId)
        .collection("campanhas_sorteio")
        .doc(campanhaId)
        .collection("participantes");

    return Scaffold(
      backgroundColor: const Color(0xFF05060A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Participantes do Sorteio"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: participantesRef
            .orderBy("dataParticipacao", descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            );
          }

          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "Nenhum participante até agora.",
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;

              final nome = (data["clienteNome"] ?? data["nomeCliente"] ?? "Cliente não informado") as String;
              final valor = ((data["valorPedido"] ?? data["valorCompra"]) as num?)?.toDouble() ?? 0.0;
              var numeros = List<String>.from(data["numeros"] ?? []);
              if (numeros.isEmpty && data["numeroSorte"] != null) {
                numeros = [data["numeroSorte"] as String];
              }

              return Card(
                color: const Color(0xFF10121A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Valor gasto: R\$ ${valor.toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Números (${numeros.length}):",
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: numeros.map((n) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha:0.2),
                              border: Border.all(color: Colors.greenAccent),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              n,
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

