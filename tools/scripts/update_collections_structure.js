// tools/scripts/update_collections_structure.js
// Uso: node update_collections_structure.js minha-loja

const { Firestore } = require('@google-cloud/firestore');
const path = require('path');

async function run() {
  const lojaId = process.argv[2];
  if (!lojaId) {
    console.error('Uso: node update_collections_structure.js <lojaId>');
    process.exit(1);
  }

  const saPath = path.join(__dirname, '..', 'serviceAccountKey.json');
  const db = new Firestore({
    keyFilename: saPath,
  });

  const base = db.collection('lojas').doc(lojaId);

  console.log(`🔧 Ajustando estrutura da loja: ${lojaId}`);

  // -------------------------
  // 1) Migrar coleções antigas
  // -------------------------

  // products  -> produtos
  await migrateCollection(base, 'products', 'produtos');

  // produtos_publicos -> produtos
  await migrateCollection(base, 'produtos_publicos', 'produtos');

  // produtos_draft -> draft_produtos
  await migrateCollection(base, 'produtos_draft', 'draft_produtos');

  // -------------------------
  // 2) Garantir campos básicos
  // -------------------------
  await normalizeFlags(base, 'draft_produtos', { draft: true });
  await normalizeFlags(base, 'produtos', { draft: false });

  // -------------------------
  // 3) Criar estrutura de cupons
  // -------------------------
  const cuponsCol = base.collection('cupons');
  const snapCupons = await cuponsCol.limit(1).get();
  if (snapCupons.empty) {
    console.log('🎟  Criando coleção de cupons com exemplo...');
    await cuponsCol.doc('CUPOM_EXEMPLO').set({
      codigo: 'BEMVINDO10',
      tipo: 'percent',          // 'percent' | 'valor' | 'frete'
      valor: 10,                // 10%
      ativo: true,
      usoMaximo: 100,
      usado: 0,
      createdAt: Firestore.Timestamp.now(),
    });
  } else {
    console.log('🎟  Coleção de cupons já existe, nada a fazer.');
  }

  console.log('✅ Estrutura atualizada com sucesso.');
}

/**
 * Copia documentos de uma coleção antiga para a nova e NÃO apaga a antiga.
 */
async function migrateCollection(base, fromName, toName) {
  const fromCol = base.collection(fromName);
  const toCol = base.collection(toName);

  const snap = await fromCol.get();
  if (snap.empty) {
    console.log(`ℹ️  Coleção antiga vazia: ${fromName} (nada a migrar).`);
    return;
  }

  console.log(`🔁 Migrando ${snap.size} docs de ${fromName} → ${toName} ...`);
  const batch = base.firestore.batch();
  let counter = 0;

  snap.forEach((doc) => {
    const data = doc.data();

    // Campos mínimos que o catálogo espera:
    if (!('ativo' in data)) {
      data.ativo = true;
    }
    if (!('publicar' in data)) {
      data.publicar = true;
    }
    if (!('id' in data)) {
      data.id = doc.id;
    }

    batch.set(toCol.doc(doc.id), data, { merge: true });
    counter++;

    if (counter === 400) {
      batch.commit();
      counter = 0;
    }
  });

  if (counter > 0) {
    await batch.commit();
  }

  console.log(`✅ Migração de ${fromName} concluída.`);
}

/**
 * Garante que alguns campos existam em todos os docs da coleção.
 */
async function normalizeFlags(base, colName, extraData) {
  const col = base.collection(colName);
  const snap = await col.get();
  if (snap.empty) {
    console.log(`ℹ️  Coleção vazia: ${colName}.`);
    return;
  }

  console.log(`🧹 Normalizando flags em ${colName} (${snap.size} docs)...`);
  const batch = base.firestore.batch();
  let counter = 0;

  snap.forEach((doc) => {
    const data = doc.data();

    const patch = {
      id: data.id || doc.id,
      ativo: data.ativo !== false,
      publicar: data.publicar !== false,
      ...extraData,
    };

    batch.set(col.doc(doc.id), patch, { merge: true });
    counter++;

    if (counter === 400) {
      batch.commit();
      counter = 0;
    }
  });

  if (counter > 0) {
    await batch.commit();
  }

  console.log(`✅ Normalização de ${colName} concluída.`);
}

run().catch((e) => {
  console.error('❌ Erro geral:', e);
  process.exit(1);
});
