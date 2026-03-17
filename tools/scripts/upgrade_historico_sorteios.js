/**
 * Atualiza automaticamente a coleção historico_sorteios
 * de TODAS as lojas do Firestore,
 * com backup automático antes de qualquer alteração.
 */

const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.cert(require("./serviceAccountKey.json")),
});

const db = admin.firestore();

// ------------------------------------------------------------
// 🔥 Função principal
// ------------------------------------------------------------
async function atualizarHistorico() {
  console.log("🚀 Iniciando atualização de historico_sorteios...\n");

  const lojasSnap = await db.collection("lojas").get();

  for (const loja of lojasSnap.docs) {
    const lojaId = loja.id;
    console.log(`🏪 Loja encontrada: ${lojaId}`);

    const historicoSnap = await db
      .collection("lojas")
      .doc(lojaId)
      .collection("historico_sorteios")
      .get();

    if (historicoSnap.empty) {
      console.log("   ⚠ Nenhum histórico encontrado.");
      continue;
    }

    for (const hist of historicoSnap.docs) {
      const dados = hist.data();
      const histId = hist.id;

      console.log(`   ➡ Atualizando histórico ${histId}`);

      // ------------------------------------------------------------
      // 📦 BACKUP AUTOMÁTICO
      // ------------------------------------------------------------
      await db
        .collection("backups_historico_sorteios")
        .doc(`${lojaId}__${histId}`)
        .set({
          lojaId,
          histId,
          dadosOriginais: dados,
          backupCriadoEm: admin.firestore.Timestamp.now(),
        });

      // ------------------------------------------------------------
      // 🧠 Conversão de dados
      // ------------------------------------------------------------
      const novoDoc = {
        nome: dados.nomeCliente ?? dados.nome ?? "Sem nome",
        telefone: dados.telefone ?? "",
        numero: dados.numeroVencedor ?? dados.numero ?? null,
        campanhaId: dados.campanhaId ?? "",
        createdAt: dados.createdAt ?? dados.criadoEm ?? admin.firestore.Timestamp.now(),
        valorCompra: dados.valorCompra ?? 0.0,
        participanteId: dados.participanteId ?? "",
      };

      // ------------------------------------------------------------
      // 💾 Salvando novo formato
      // ------------------------------------------------------------
      await hist.ref.set(novoDoc, { merge: true });

      console.log("      ✔ Atualizado:", novoDoc);
    }
  }

  console.log("\n✨ FINALIZADO com sucesso! Todos os registros foram convertidos.");
}

atualizarHistorico();
