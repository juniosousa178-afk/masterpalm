// listar.js  (CommonJS, compatível com seu package.json)

// 1) Imports
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccount.json');

// 2) Inicializa o Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// Set para não repetir coleção se aparecer mais de uma vez
const seen = new Set();

/**
 * parent = null  -> coleções de topo
 * parent = DocumentReference -> subcoleções desse documento
 */
async function walkCollections(parent) {
  let collections;

  if (!parent) {
    // coleções de nível raiz
    collections = await db.listCollections();
  } else {
    // subcoleções de um documento
    collections = await parent.listCollections();
  }

  for (const col of collections) {
    // col.path já vem completo: ex "lojas/master/config"
    if (!seen.has(col.path)) {
      seen.add(col.path);
      console.log(col.path);
    }

    // Para achar subcoleções, precisamos passar documento por documento
    const snapshot = await col.get();
    for (const doc of snapshot.docs) {
      await walkCollections(doc.ref);
    }
  }
}

(async () => {
  try {
    await walkCollections(null); // começa na raiz
    console.error('✔ Listagem de coleções concluída.');
    process.exit(0);
  } catch (e) {
    console.error('Erro ao listar coleções:', e);
    process.exit(1);
  }
})();