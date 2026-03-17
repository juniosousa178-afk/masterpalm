// firestore_tree.js
const admin = require('firebase-admin');
const path = require('path');

// 👉 Ajuste o nome do arquivo se for diferente
const serviceAccount = require('../../serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

/**
 * Imprime uma coleção e seus documentos
 */
async function printCollection(colRef, indent = '') {
  console.log(`${indent}/` + colRef.id);

  const snap = await colRef.limit(50).get(); // limita pra não explodir
  for (const doc of snap.docs) {
    await printDocument(doc.ref, indent + '  ');
  }
}

/**
 * Imprime um documento e suas subcoleções
 */
async function printDocument(docRef, indent = '') {
  console.log(`${indent}[doc] ${docRef.id}`);

  const subcols = await docRef.listCollections();
  for (const sub of subcols) {
    console.log(`${indent}  (subcol) ${sub.id}`);
    // Se quiser descer mais um nível na árvore:
    await printCollection(sub, indent + '    ');
  }
}

/**
 * Ponto de entrada:
 * lista coleções de topo e desce um pouco em cada uma.
 */
async function main() {
  console.log('=== Firestore Tree ===');

  const rootCollections = await db.listCollections();
  for (const col of rootCollections) {
    await printCollection(col, '');
    console.log('');
  }

  console.log('=== FIM ===');
  process.exit(0);
}

main().catch((err) => {
  console.error('Erro ao listar estrutura:', err);
  process.exit(1);
});
