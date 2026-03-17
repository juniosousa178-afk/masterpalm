/**
 * Gera um arquivo firestore_tree.txt com a árvore completa
 * Inclui coleções, documentos e subcoleções
 */

const admin = require('firebase-admin');
const fs = require('fs');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const db = admin.firestore();
const output = [];

async function walkCollection(ref, indent = '') {
  const docs = await ref.listDocuments();

  for (const doc of docs) {
    output.push(`${indent}📄 ${doc.id}`);

    const subcollections = await doc.listCollections();
    for (const sub of subcollections) {
      output.push(`${indent}  📁 ${sub.id}`);
      await walkCollection(sub, indent + '    ');
    }
  }
}

async function run() {
  const collections = await db.listCollections();

  for (const col of collections) {
    output.push(`📁 ${col.id}`);
    await walkCollection(col, '  ');
  }

  fs.writeFileSync('firestore_tree.txt', output.join('\n'));
  console.log('✅ Arquivo firestore_tree.txt gerado com sucesso');
}

run();
