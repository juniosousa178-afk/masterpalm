/**
 * Atualiza automaticamente TODAS as campanhas de sorteio
 * convertendo a estrutura da coleção "participantes"
 * para o formato solicitado.
 */

const admin = require("firebase-admin");

// 🔥 Caminho do seu serviceAccountKey.json
admin.initializeApp({
  credential: admin.credential.cert(require("./serviceAccountKey.json")),
});

const db = admin.firestore();

async function atualizarParticipantes() {
  console.log("Iniciando atualização das campanhas...");

  const lojasSnap = await db.collection("lojas").get();

  for (const lojaDoc of lojasSnap.docs) {
    const lojaId = lojaDoc.id;
    console.log(`📌 Loja encontrada: ${lojaId}`);

    const campanhasSnap = await db
      .collection("lojas")
      .doc(lojaId)
      .collection("campanhas_sorteio")
      .get();

    for (const campanhaDoc of campanhasSnap.docs) {
      const campanhaId = campanhaDoc.id;

      console.log(`➡ Atualizando campanha ${campanhaId}`);

      const participantesSnap = await db
        .collection("lojas")
        .doc(lojaId)
        .collection("campanhas_sorteio")
        .doc(campanhaId)
        .collection("participantes")
        .get();

      for (const p of participantesSnap.docs) {
        const dados = p.data();

        // Recupera valores antigos
        const nome = dados.nomeCliente ?? "Sem nome";
        const telefone = dados.telefone ?? "";
        const numeros = dados.numeros ?? [];
        const numero = Array.isArray(numeros) && numeros.length > 0 ? numeros[0] : null;

        const novoDoc = {
          nome: nome,
          telefone: telefone,
          numero: numero,
          createdAt: dados.criadoEm ?? admin.firestore.Timestamp.now(),
          campanhaId: campanhaId,
        };

        console.log(`   ✔ Atualizando participante ${p.id}`, novoDoc);

        await p.ref.set(novoDoc, { merge: true });
      }
    }
  }

  console.log("\n✨ Finalizado com sucesso!");
}

atualizarParticipantes();
