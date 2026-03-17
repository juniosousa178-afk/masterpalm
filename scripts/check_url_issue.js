// Script para verificar problema de URL cortada
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkUrlIssue() {
  console.log('🔍 Investigando problema de URL cortada...\n');

  // Verificar se existe loja "nath"
  const nathDoc = await db.collection('lojas').doc('nath').get();

  if (nathDoc.exists) {
    console.log('❌ PROBLEMA ENCONTRADO: Existe loja com ID "nath"!');
    const data = nathDoc.data();
    console.log(`   - Nome: ${data.nome || 'N/A'}`);
    console.log(`   - Owner: ${data.owner || 'N/A'}`);
    console.log(`   - OwnerUid: ${data.ownerUid || 'N/A'}`);
    console.log(`   - RedirectTo: ${data.redirectTo || 'N/A'}`);
    console.log('\n❌ Esta loja está interceptando a URL!\n');
  } else {
    console.log('✅ Não existe loja com ID "nath"\n');
  }

  // Verificar loja correta
  const natyDoc = await db.collection('lojas').doc('nathy-pratas-e-folheados').get();

  if (natyDoc.exists) {
    console.log('✅ Loja "nathy-pratas-e-folheados" existe');
    const data = natyDoc.data();
    console.log(`   - Nome: ${data.nome}`);
    console.log(`   - Slug: ${data.slug}`);
    console.log(`   - OwnerUid: ${data.ownerUid}`);
  }

  // Listar TODAS as lojas que começam com "nath"
  console.log('\n📋 Todas as lojas que começam com "nath":');
  const allLojas = await db.collection('lojas').get();

  for (const lojaDoc of allLojas.docs) {
    const lojaId = lojaDoc.id;
    if (lojaId.toLowerCase().startsWith('nath')) {
      const lojaData = lojaDoc.data();
      console.log(`\n   🏪 ${lojaId}`);
      console.log(`      - Nome: ${lojaData.nome || 'N/A'}`);
      console.log(`      - Owner: ${lojaData.owner || 'N/A'}`);
      console.log(`      - OwnerUid: ${lojaData.ownerUid || 'N/A'}`);
      console.log(`      - RedirectTo: ${lojaData.redirectTo || 'N/A'}`);
    }
  }

  // Verificar loja "masterpalm_gmail_com"
  console.log('\n\n🔍 Verificando loja "masterpalm_gmail_com":');
  const masterDoc = await db.collection('lojas').doc('masterpalm_gmail_com').get();

  if (masterDoc.exists) {
    const data = masterDoc.data();
    console.log(`   - Nome: ${data.nome || 'N/A'}`);
    console.log(`   - RedirectTo: ${data.redirectTo || 'NENHUM'}`);

    // Verificar config
    const configDoc = await db.collection('lojas').doc('masterpalm_gmail_com').collection('config').doc('config').get();

    if (configDoc.exists) {
      const configData = configDoc.data();
      console.log(`   - Config: EXISTE`);
      console.log(`   - Banners: ${configData.bannersMobile?.length || 0}`);
    } else {
      console.log(`   - Config: NÃO EXISTE`);
    }
  }

  console.log('\n════════════════════════════════════════════════════\n');

  process.exit(0);
}

checkUrlIssue();
