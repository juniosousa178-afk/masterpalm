/**
 * Script: Associar juniosousa178@gmail.com à loja masterpalm
 */

const admin = require('firebase-admin');
if (!admin.apps.length) {
  const serviceAccount = require('../masterpalm-service-account.json');
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const JUNHO_EMAIL = 'juniosousa178@gmail.com';
const JUNHO_UID = 'H3be6ett8NZBjzh0nJa35tligDZ2';
const TARGET_STORE = 'masterpalm';

async function fix() {
  console.log('━'.repeat(60));
  console.log('🔧 ASSOCIANDO juniosousa178@gmail.com → masterpalm');
  console.log('━'.repeat(60));

  // 1. Atualizar ownerUid da loja masterpalm
  console.log('\n1️⃣ Atualizando ownerUid da loja masterpalm...');
  await db.collection('lojas').doc(TARGET_STORE).update({
    ownerUid: JUNHO_UID,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log('   ✅ ownerUid atualizado para', JUNHO_UID);

  // 2. Atualizar store_id no usuarios/{email}
  console.log('\n2️⃣ Atualizando usuarios/{email}...');
  await db.collection('usuarios').doc(JUNHO_EMAIL).update({
    store_id: TARGET_STORE,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log('   ✅ store_id atualizado para', TARGET_STORE);

  // 3. Atualizar store_id no users/{uid}
  console.log('\n3️⃣ Atualizando users/{uid}...');
  await db.collection('users').doc(JUNHO_UID).set({
    store_id: TARGET_STORE,
    ownerOf: TARGET_STORE,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log('   ✅ store_id atualizado para', TARGET_STORE);

  // 4. Verificar resultado
  console.log('\n━'.repeat(60));
  console.log('✅ CORREÇÃO APLICADA!');
  console.log('━'.repeat(60));
  console.log('\nVerificação:');

  const usuarioDoc = await db.collection('usuarios').doc(JUNHO_EMAIL).get();
  console.log('   usuarios/{email}.store_id:', usuarioDoc.data().store_id);

  const userDoc = await db.collection('users').doc(JUNHO_UID).get();
  console.log('   users/{uid}.store_id:', userDoc.data().store_id);

  const lojaDoc = await db.collection('lojas').doc(TARGET_STORE).get();
  console.log('   lojas/masterpalm.ownerUid:', lojaDoc.data().ownerUid);

  console.log('\n💡 O usuário junho deve fazer LOGOUT e LOGIN novamente.');
  console.log('   URL pública: https://mastepalm.com.br/loja/masterpalm');
  console.log('━'.repeat(60));

  process.exit(0);
}

fix().catch(e => {
  console.error('❌ Erro:', e);
  process.exit(1);
});
