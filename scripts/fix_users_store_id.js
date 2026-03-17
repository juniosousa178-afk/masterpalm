const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixUsersStoreId() {
  console.log('🔧 CORRIGINDO store_id em /users...\n');

  const NATY_UID = 'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2';
  const NATY_SLUG = 'nathy-pratas-e-folheados';

  // 1. ANTES
  console.log('📋 ANTES:');
  const userDocBefore = await db.collection('users').doc(NATY_UID).get();
  if (userDocBefore.exists) {
    const data = userDocBefore.data();
    console.log(`   store_id: ${data.store_id || 'VAZIO'}`);
    console.log(`   lojaId: ${data.lojaId || 'VAZIO'}`);
  }

  // 2. ATUALIZAR
  console.log('\n🔧 ATUALIZANDO...');
  await db.collection('users').doc(NATY_UID).update({
    store_id: NATY_SLUG,
    lojaId: NATY_SLUG,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  });
  console.log('   ✅ Atualizado!');

  // 3. DEPOIS
  console.log('\n📋 DEPOIS:');
  const userDocAfter = await db.collection('users').doc(NATY_UID).get();
  if (userDocAfter.exists) {
    const data = userDocAfter.data();
    console.log(`   store_id: ${data.store_id || 'VAZIO'}`);
    console.log(`   lojaId: ${data.lojaId || 'VAZIO'}`);
  }

  console.log('\n════════════════════════════════════════════════════');
  console.log('✅ CONCLUÍDO!');
  console.log('');
  console.log('⚠️  PRÓXIMO PASSO:');
  console.log('   1. No celular: DESINSTALAR o app');
  console.log('   2. REINSTALAR o app');
  console.log('   3. Fazer LOGIN com natypolylopes1997@gmail.com');
  console.log('   4. Agora vai usar: nathy-pratas-e-folheados');
  console.log('════════════════════════════════════════════════════\n');

  process.exit(0);
}

fixUsersStoreId();
