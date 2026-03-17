// Script para publicar catálogo da Naty (copiar draft → config)
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

const LOJAS_TO_PUBLISH = [
  'loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2',
  'nathy-pratas-e-folheados',
  'loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2',
  'masterpalm'
];

async function publishCatalog() {
  console.log('📢 ════════════════════════════════════════════════════');
  console.log('📢 PUBLICANDO CATÁLOGOS');
  console.log('📢 ════════════════════════════════════════════════════\n');

  for (const lojaId of LOJAS_TO_PUBLISH) {
    console.log(`\n🏪 Loja: ${lojaId}`);
    console.log('─'.repeat(60));

    // Copiar draft_config → config
    const draftConfigDoc = await db.collection('lojas').doc(lojaId).collection('draft_config').doc('config').get();

    if (!draftConfigDoc.exists) {
      console.log(`   ⚠️  draft_config/config NÃO existe, pulando...`);
      continue;
    }

    const draftConfigData = draftConfigDoc.data();

    // Salvar em config (publicado)
    await db.collection('lojas').doc(lojaId).collection('config').doc('config').set(draftConfigData);

    console.log(`   ✅ draft_config → config copiado`);
    console.log(`   - logoDesktop: ${draftConfigData.logoDesktop ? '✅' : '❌'}`);
    console.log(`   - logoMobile: ${draftConfigData.logoMobile ? '✅' : '❌'}`);
    console.log(`   - bannersMobile: ${draftConfigData.bannersMobile?.length || 0}`);
    console.log(`   - bannersDesktop: ${draftConfigData.bannersDesktop?.length || 0}`);

    // Copiar draft_produtos → produtos
    const draftProdutos = await db.collection('lojas').doc(lojaId).collection('draft_produtos').get();

    console.log(`\n   📦 Publicando ${draftProdutos.size} produtos...`);

    for (const prodDoc of draftProdutos.docs) {
      const prodId = prodDoc.id;
      const prodData = prodDoc.data();

      // Copiar para produtos (publicado)
      await db.collection('lojas').doc(lojaId).collection('produtos').doc(prodId).set(prodData);
    }

    console.log(`   ✅ ${draftProdutos.size} produtos publicados`);
  }

  console.log('\n\n✅ ════════════════════════════════════════════════════');
  console.log('✅ CATÁLOGOS PUBLICADOS COM SUCESSO!');
  console.log('✅ ════════════════════════════════════════════════════\n');

  console.log('🌐 Agora teste as URLs:');
  console.log('   - https://mastepalm.com.br/loja/nathy-pratas-e-folheados');
  console.log('   - https://mastepalm.com.br/loja/masterpalm\n');

  process.exit(0);
}

publishCatalog();
