// tools/scripts/wipe_firestore_dev.js
// ⚠️ CUIDADO: script destrutivo. Use só em ambiente de desenvolvimento.

const path = require('path');
const { Firestore } = require('@google-cloud/firestore');

const projectId = 'masterpalm-58c46'; // mesmo do bucket masterpalm-58c46.firebasestorage.app
const serviceAccountPath = path.resolve(__dirname, '../serviceAccountKey.json');

const db = new Firestore({
  projectId,
  keyFilename: serviceAccountPath,
});

// ---------------------------------------------------------------------
// CONFIGURAÇÕES – EDITE AQUI
// ---------------------------------------------------------------------

// Lojas que você QUER manter (o resto será apagado por completo)
const KEEP_LOJAS = ['minha-loja']; // altere para o(s) lojaId(s) que você realmente usa

// Subcoleções que fazem parte da estrutura oficial do projeto
const ALLOWED_SUBCOLS = [
  'config',
  'draft_config',
  'draft_produtos',
  'produtos',
  'cupons',
  'settings',
  'members',
  'payments',
  'pedidos',
];

// Destas acima, quais você quer LIMPAR (apagar todos os docs, mas manter a coleção vazia)
const SUBCOLS_TO_CLEAR = [
  'pedidos',
  'payments',
  'draft_produtos',
  'produtos',
];

// ---------------------------------------------------------------------
// HELPERS
// ---------------------------------------------------------------------

async function deleteDocumentRecursive(docRef) {
  // Apaga subcoleções primeiro
  const subcols = await docRef.listCollections();
  for (const col of subcols) {
    await deleteCollectionRecursive(col);
  }
  // Depois apaga o próprio documento
  await docRef.delete();
}

async function deleteCollectionRecursive(colRef, batchSize = 200) {
  while (true) {
    const snap = await colRef.limit(batchSize).get();
    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) {
      // Para cada doc, apaga recursivamente
      await deleteDocumentRecursive(doc.ref);
    }
    await batch.commit();
  }
}

async function clearCollectionDocs(colRef, batchSize = 200) {
  while (true) {
    const snap = await colRef.limit(batchSize).get();
    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) {
      await deleteDocumentRecursive(doc.ref);
    }
    await batch.commit();
  }
}

// ---------------------------------------------------------------------
// MAIN
// ---------------------------------------------------------------------

async function run() {
  console.log('🧨 INICIANDO LIMPEZA DO FIRESTORE (DEV)...');

  const lojasSnap = await db.collection('lojas').get();
  if (lojasSnap.empty) {
    console.log('ℹ️ Nenhuma loja encontrada em lojas/. Nada a fazer.');
    return;
  }

  for (const lojaDoc of lojasSnap.docs) {
    const lojaId = lojaDoc.id;
    const lojaRef = lojaDoc.ref;

    // 1) Apagar LOJAS que não estão na lista de "KEEP_LOJAS"
    if (!KEEP_LOJAS.includes(lojaId)) {
      console.log(`🗑️ Apagando loja inteira: ${lojaId}`);
      await deleteDocumentRecursive(lojaRef);
      continue;
    }

    // 2) Para as lojas que ficam: limpa coleções supérfluas e dados de teste
    console.log(`🧹 Limpando loja preservada: ${lojaId}`);

    const subcols = await lojaRef.listCollections();
    for (const col of subcols) {
      const colId = col.id;

      // Se for uma subcoleção que nem faz parte da estrutura → apaga inteira
      if (!ALLOWED_SUBCOLS.includes(colId)) {
        console.log(`  🗑️ Removendo subcoleção não utilizada: ${colId}`);
        await deleteCollectionRecursive(col);
        continue;
      }

      // Se for uma subcoleção que queremos apenas LIMPAR
      if (SUBCOLS_TO_CLEAR.includes(colId)) {
        console.log(`  🧽 Limpando documentos em: ${colId}`);
        await clearCollectionDocs(col);
        continue;
      }

      // Caso contrário, mantemos como está (ex.: config, settings, cupons, members)
      console.log(`  ✅ Mantendo estrutura em: ${colId}`);
    }
  }

  console.log('✅ Limpeza concluída com sucesso!');
}

// ---------------------------------------------------------------------

run()
  .then(() => {
    console.log('🏁 Fim.');
    process.exit(0);
  })
  .catch((err) => {
    console.error('❌ Erro geral:', err);
    process.exit(1);
  });
