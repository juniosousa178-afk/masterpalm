// Script para sincronizar configs entre lojas do root
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function syncRootConfigs() {
  console.log('🔄 Sincronizando configurações do Root...\n');

  const SOURCE = 'loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2';
  const TARGET = 'masterpalm';

  // Copiar config/config
  const configDoc = await db.collection('lojas').doc(SOURCE).collection('config').doc('config').get();

  if (configDoc.exists) {
    await db.collection('lojas').doc(TARGET).collection('config').doc('config').set(configDoc.data());
    console.log(`✅ config/config copiado: ${SOURCE} → ${TARGET}`);

    const data = configDoc.data();
    console.log(`   - Banners mobile: ${data.bannersMobile?.length || 0}`);
    console.log(`   - Banners desktop: ${data.bannersDesktop?.length || 0}`);
  }

  // Copiar draft_config/config
  const draftConfigDoc = await db.collection('lojas').doc(SOURCE).collection('draft_config').doc('config').get();

  if (draftConfigDoc.exists) {
    await db.collection('lojas').doc(TARGET).collection('draft_config').doc('config').set(draftConfigDoc.data());
    console.log(`✅ draft_config/config copiado: ${SOURCE} → ${TARGET}`);
  }

  // Copiar produtos
  const produtos = await db.collection('lojas').doc(SOURCE).collection('produtos').get();

  for (const prodDoc of produtos.docs) {
    await db.collection('lojas').doc(TARGET).collection('produtos').doc(prodDoc.id).set(prodDoc.data());
  }

  console.log(`✅ ${produtos.size} produtos copiados: ${SOURCE} → ${TARGET}`);

  // Copiar draft_produtos
  const draftProdutos = await db.collection('lojas').doc(SOURCE).collection('draft_produtos').get();

  for (const prodDoc of draftProdutos.docs) {
    await db.collection('lojas').doc(TARGET).collection('draft_produtos').doc(prodDoc.id).set(prodDoc.data());
  }

  console.log(`✅ ${draftProdutos.size} draft_produtos copiados: ${SOURCE} → ${TARGET}`);

  console.log('\n✅ Sincronização concluída!\n');

  process.exit(0);
}

syncRootConfigs();
