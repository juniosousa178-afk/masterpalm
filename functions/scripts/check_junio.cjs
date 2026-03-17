const admin = require('firebase-admin');
if (!admin.apps.length) {
  const serviceAccount = require('../masterpalm-service-account.json');
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

async function check() {
  console.log('━'.repeat(60));
  console.log('🔍 VERIFICANDO USUÁRIO E LOJA MASTERPALM');
  console.log('━'.repeat(60));

  // 1. Verificar usuario juniosousa178@gmail.com
  console.log('\n📧 Usuario juniosousa178@gmail.com:');
  const usuarioDoc = await db.collection('usuarios').doc('juniosousa178@gmail.com').get();
  if (usuarioDoc.exists) {
    const d = usuarioDoc.data();
    console.log('   store_id:', d.store_id || '(vazio)');
    console.log('   authUid:', d.authUid || '(vazio)');
    console.log('   tipo:', d.tipo || '(vazio)');
  } else {
    console.log('   ❌ Não existe');
  }

  // 2. Verificar loja masterpalm
  console.log('\n🏪 Loja masterpalm:');
  const lojaDoc = await db.collection('lojas').doc('masterpalm').get();
  if (lojaDoc.exists) {
    const d = lojaDoc.data();
    console.log('   ownerUid:', d.ownerUid || '(vazio)');
    console.log('   slug:', d.slug || '(vazio)');

    const prodCount = await db.collection('lojas').doc('masterpalm').collection('produtos').count().get();
    const draftCount = await db.collection('lojas').doc('masterpalm').collection('draft_produtos').count().get();
    console.log('   produtos:', prodCount.data().count);
    console.log('   draft_produtos:', draftCount.data().count);

    const configDoc = await db.collection('lojas').doc('masterpalm').collection('config').doc('config').get();
    console.log('   config:', configDoc.exists ? '✅ existe' : '❌ não existe');
  } else {
    console.log('   ❌ Não existe');
  }

  // 3. Verificar loja masterpalm_gmail_com também
  console.log('\n🏪 Loja masterpalm_gmail_com:');
  const lojaDoc2 = await db.collection('lojas').doc('masterpalm_gmail_com').get();
  if (lojaDoc2.exists) {
    const d = lojaDoc2.data();
    console.log('   ownerUid:', d.ownerUid || '(vazio)');
    const prodCount = await db.collection('lojas').doc('masterpalm_gmail_com').collection('produtos').count().get();
    console.log('   produtos:', prodCount.data().count);
  }

  // 4. Verificar users/{uid} do junho
  console.log('\n👤 Users pelo UID do junho:');
  const junioUid = 'H3be6ett8NZBjzh0nJa35tligDZ2';
  const userDoc = await db.collection('users').doc(junioUid).get();
  if (userDoc.exists) {
    const d = userDoc.data();
    console.log('   store_id:', d.store_id || '(vazio)');
    console.log('   ownerOf:', d.ownerOf || '(vazio)');
  } else {
    console.log('   ❌ Não existe');
  }

  console.log('\n━'.repeat(60));
  console.log('💡 Para associar juniosousa178@gmail.com à loja masterpalm,');
  console.log('   preciso atualizar o store_id no perfil dele.');
  console.log('━'.repeat(60));

  process.exit(0);
}
check();
