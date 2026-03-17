const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkCurrentState() {
  console.log('🔍 Verificando estado atual das lojas...\n');

  // 1. Verificar config da loja nathy-pratas-e-folheados
  console.log('📋 Loja: nathy-pratas-e-folheados');
  const natyConfigDoc = await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('config').doc('config').get();

  if (natyConfigDoc.exists) {
    const data = natyConfigDoc.data();
    console.log('   ✅ config/config EXISTE');
    console.log(`   - Nome: ${data.nome || 'N/A'}`);
    console.log(`   - Logo Desktop: ${data.logoDesktopUrl ? 'SIM' : 'NÃO'}`);
    console.log(`   - Logo Mobile: ${data.logoMobileUrl ? 'SIM' : 'NÃO'}`);
    console.log(`   - Banners Mobile: ${data.bannersMobile?.length || 0}`);
    console.log(`   - Banners Desktop: ${data.bannersDesktop?.length || 0}`);
    console.log(`   - Tema primária: ${data.theme?.primaria || 'N/A'}`);
    console.log(`   - WhatsApp: ${data.whatsapp || 'N/A'}`);
  } else {
    console.log('   ❌ config/config NÃO EXISTE');
  }

  // 2. Verificar produtos da loja nathy-pratas-e-folheados
  const natyProdutos = await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('produtos').get();
  console.log(`   - Produtos publicados: ${natyProdutos.size}`);

  console.log('\n════════════════════════════════════════════════════\n');

  // 3. Verificar loja UID da Naty
  console.log('📋 Loja: loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2');
  const uidConfigDoc = await db.collection('lojas').doc('loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2').collection('config').doc('config').get();

  if (uidConfigDoc.exists) {
    const data = uidConfigDoc.data();
    console.log('   ✅ config/config EXISTE');
    console.log(`   - Nome: ${data.nome || 'N/A'}`);
    console.log(`   - Logo Desktop: ${data.logoDesktopUrl ? 'SIM' : 'NÃO'}`);
    console.log(`   - Banners Mobile: ${data.bannersMobile?.length || 0}`);
    console.log(`   - Banners Desktop: ${data.bannersDesktop?.length || 0}`);
  } else {
    console.log('   ❌ config/config NÃO EXISTE');
  }

  const uidProdutos = await db.collection('lojas').doc('loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2').collection('produtos').get();
  console.log(`   - Produtos publicados: ${uidProdutos.size}`);

  console.log('\n════════════════════════════════════════════════════\n');

  // 4. Verificar documento base da loja nathy-pratas-e-folheados
  console.log('📄 Documento base da loja nathy-pratas-e-folheados:');
  const natyDoc = await db.collection('lojas').doc('nathy-pratas-e-folheados').get();
  if (natyDoc.exists) {
    const data = natyDoc.data();
    console.log(`   - redirectTo: ${data.redirectTo || 'NENHUM'}`);
    console.log(`   - ownerUid: ${data.ownerUid || 'N/A'}`);
    console.log(`   - nome: ${data.nome || 'N/A'}`);
  }

  process.exit(0);
}

checkCurrentState();
