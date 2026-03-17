// Script para corrigir store_id da Naty
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixNatyStoreId() {
  console.log('🔧 Corrigindo store_id da Naty...\n');

  const NATY_UID = 'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2';
  const NATY_EMAIL = 'natypolylopes1997@gmail.com';
  const NATY_SLUG = 'nathy-pratas-e-folheados';

  // Atualizar /users
  await db.collection('users').doc(NATY_UID).update({
    store_id: NATY_SLUG,
    lojaId: NATY_SLUG,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  });

  console.log(`✅ Atualizado /users/${NATY_UID}`);
  console.log(`   store_id: loja_uid_${NATY_UID} → ${NATY_SLUG}`);

  // Atualizar /usuarios
  await db.collection('usuarios').doc(NATY_EMAIL).update({
    lojaId: NATY_SLUG,
    store_id: NATY_SLUG,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  });

  console.log(`✅ Atualizado /usuarios/${NATY_EMAIL}`);
  console.log(`   lojaId: → ${NATY_SLUG}`);

  console.log('\n✅ Correção concluída!');

  process.exit(0);
}

fixNatyStoreId();
