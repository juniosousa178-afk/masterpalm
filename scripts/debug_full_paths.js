const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function debugFullPaths() {
  console.log('🔍 VERIFICANDO TODOS OS CAMINHOS DO FIRESTORE\n');
  console.log('════════════════════════════════════════════════════\n');

  const NATY_UID = 'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2';
  const NATY_EMAIL = 'natypolylopes1997@gmail.com';

  // 1. VERIFICAR USUÁRIO EM /users
  console.log('📁 1. /users/' + NATY_UID);
  const userDoc = await db.collection('users').doc(NATY_UID).get();
  if (userDoc.exists) {
    const data = userDoc.data();
    console.log(`   store_id: ${data.store_id || 'VAZIO'}`);
    console.log(`   lojaId: ${data.lojaId || 'VAZIO'}`);
    console.log(`   email: ${data.email || 'VAZIO'}`);
  } else {
    console.log('   ❌ NÃO EXISTE');
  }

  // 2. VERIFICAR USUÁRIO EM /usuarios
  console.log('\n📁 2. /usuarios/' + NATY_UID);
  const usuarioDoc = await db.collection('usuarios').doc(NATY_UID).get();
  if (usuarioDoc.exists) {
    const data = usuarioDoc.data();
    console.log(`   store_id: ${data.store_id || 'VAZIO'}`);
    console.log(`   lojaId: ${data.lojaId || 'VAZIO'}`);
    console.log(`   email: ${data.email || 'VAZIO'}`);
  } else {
    console.log('   ❌ NÃO EXISTE');
  }

  // 3. VERIFICAR POR EMAIL EM /users
  console.log('\n📁 3. /users (busca por email)');
  const usersByEmail = await db.collection('users').where('email', '==', NATY_EMAIL).get();
  if (!usersByEmail.empty) {
    usersByEmail.forEach(doc => {
      const data = doc.data();
      console.log(`   UID: ${doc.id}`);
      console.log(`   store_id: ${data.store_id || 'VAZIO'}`);
      console.log(`   lojaId: ${data.lojaId || 'VAZIO'}`);
    });
  } else {
    console.log('   ❌ NENHUM ENCONTRADO');
  }

  console.log('\n════════════════════════════════════════════════════\n');

  // 4. VERIFICAR LOJA nathy-pratas-e-folheados
  console.log('📁 4. /lojas/nathy-pratas-e-folheados');
  const natyLojaDoc = await db.collection('lojas').doc('nathy-pratas-e-folheados').get();
  if (natyLojaDoc.exists) {
    const data = natyLojaDoc.data();
    console.log('   ✅ EXISTE');
    console.log(`   nome: ${data.nome || 'VAZIO'}`);
    console.log(`   slug: ${data.slug || 'VAZIO'}`);
    console.log(`   ownerUid: ${data.ownerUid || 'VAZIO'}`);
    console.log(`   redirectTo: ${data.redirectTo || 'NENHUM'}`);
  } else {
    console.log('   ❌ NÃO EXISTE');
  }

  // 5. VERIFICAR CONFIG PUBLICADO
  console.log('\n📁 5. /lojas/nathy-pratas-e-folheados/config/config');
  const natyConfigDoc = await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('config').doc('config').get();
  if (natyConfigDoc.exists) {
    const data = natyConfigDoc.data();
    console.log('   ✅ EXISTE');
    console.log(`   nome: ${data.nome || 'VAZIO'}`);
    console.log(`   logoDesktopUrl: ${data.logoDesktopUrl ? 'SIM' : 'NÃO'}`);
    console.log(`   logoMobileUrl: ${data.logoMobileUrl ? 'SIM' : 'NÃO'}`);
    console.log(`   bannersMobile: ${data.bannersMobile?.length || 0}`);
    console.log(`   bannersDesktop: ${data.bannersDesktop?.length || 0}`);
    console.log(`   theme.primaria: ${data.theme?.primaria || 'VAZIO'}`);
    console.log(`   whatsapp: ${data.whatsapp || 'VAZIO'}`);
  } else {
    console.log('   ❌ NÃO EXISTE');
  }

  // 6. VERIFICAR DRAFT CONFIG
  console.log('\n📁 6. /lojas/nathy-pratas-e-folheados/draft_config/config');
  const natyDraftConfigDoc = await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('draft_config').doc('config').get();
  if (natyDraftConfigDoc.exists) {
    const data = natyDraftConfigDoc.data();
    console.log('   ✅ EXISTE');
    console.log(`   nome: ${data.nome || 'VAZIO'}`);
    console.log(`   logoDesktopUrl: ${data.logoDesktopUrl ? 'SIM' : 'NÃO'}`);
    console.log(`   bannersMobile: ${data.bannersMobile?.length || 0}`);
  } else {
    console.log('   ❌ NÃO EXISTE');
  }

  // 7. VERIFICAR PRODUTOS PUBLICADOS
  console.log('\n📁 7. /lojas/nathy-pratas-e-folheados/produtos');
  const natyProdutos = await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('produtos').get();
  console.log(`   Total: ${natyProdutos.size} produtos`);
  if (natyProdutos.size > 0) {
    natyProdutos.forEach(doc => {
      const data = doc.data();
      console.log(`   - ${doc.id}: ${data.nome || 'sem nome'} (ativo: ${data.ativo !== false})`);
    });
  }

  console.log('\n════════════════════════════════════════════════════\n');

  // 8. VERIFICAR LOJA UID
  console.log('📁 8. /lojas/loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2');
  const uidLojaDoc = await db.collection('lojas').doc('loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2').get();
  if (uidLojaDoc.exists) {
    const data = uidLojaDoc.data();
    console.log('   ✅ EXISTE');
    console.log(`   redirectTo: ${data.redirectTo || 'NENHUM'}`);
  } else {
    console.log('   ❌ NÃO EXISTE');
  }

  // 9. VERIFICAR CONFIG DA LOJA UID
  console.log('\n📁 9. /lojas/loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2/config/config');
  const uidConfigDoc = await db.collection('lojas').doc('loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2').collection('config').doc('config').get();
  if (uidConfigDoc.exists) {
    const data = uidConfigDoc.data();
    console.log('   ✅ EXISTE');
    console.log(`   nome: ${data.nome || 'VAZIO'}`);
    console.log(`   logoDesktopUrl: ${data.logoDesktopUrl ? 'SIM' : 'NÃO'}`);
    console.log(`   bannersMobile: ${data.bannersMobile?.length || 0}`);
  } else {
    console.log('   ❌ NÃO EXISTE');
  }

  console.log('\n════════════════════════════════════════════════════\n');

  // 10. VERIFICAR LOJA masterpalm
  console.log('📁 10. /lojas/masterpalm');
  const masterLojaDoc = await db.collection('lojas').doc('masterpalm').get();
  if (masterLojaDoc.exists) {
    const data = masterLojaDoc.data();
    console.log('   ✅ EXISTE');
    console.log(`   nome: ${data.nome || 'VAZIO'}`);
    console.log(`   ownerUid: ${data.ownerUid || 'VAZIO'}`);
    console.log(`   redirectTo: ${data.redirectTo || 'NENHUM'}`);
  } else {
    console.log('   ❌ NÃO EXISTE');
  }

  // 11. VERIFICAR CONFIG DA LOJA masterpalm
  console.log('\n📁 11. /lojas/masterpalm/config/config');
  const masterConfigDoc = await db.collection('lojas').doc('masterpalm').collection('config').doc('config').get();
  if (masterConfigDoc.exists) {
    const data = masterConfigDoc.data();
    console.log('   ✅ EXISTE');
    console.log(`   nome: ${data.nome || 'VAZIO'}`);
    console.log(`   logoDesktopUrl: ${data.logoDesktopUrl ? 'SIM' : 'NÃO'}`);
  } else {
    console.log('   ❌ NÃO EXISTE');
  }

  console.log('\n════════════════════════════════════════════════════\n');

  // 12. LISTAR TODAS AS LOJAS
  console.log('📋 12. TODAS AS LOJAS NO FIRESTORE:');
  const allLojas = await db.collection('lojas').get();
  allLojas.forEach(doc => {
    const data = doc.data();
    console.log(`   - ${doc.id}`);
    console.log(`     ownerUid: ${data.ownerUid || 'N/A'}`);
    console.log(`     nome: ${data.nome || 'N/A'}`);
    if (data.redirectTo) {
      console.log(`     redirectTo: ${data.redirectTo}`);
    }
  });

  process.exit(0);
}

debugFullPaths();
