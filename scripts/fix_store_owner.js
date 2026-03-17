// Script para adicionar ownerUid nas lojas
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();
const ROOT_UID = 'vd0X6xXlq4be0cKhmIOiDtXTvKb2';
const ROOT_EMAIL = 'masterpalm@gmail.com';

async function fixStoreOwner() {
  console.log('🔧 Adicionando ownerUid nas lojas...\n');

  try {
    const lojasSnapshot = await db.collection('lojas').get();

    for (const lojaDoc of lojasSnapshot.docs) {
      const lojaId = lojaDoc.id;
      const lojaData = lojaDoc.data();

      console.log(`\n🏪 Loja: ${lojaId}`);

      // Determinar owner baseado no ID da loja
      let ownerUid = ROOT_UID;
      let ownerEmail = ROOT_EMAIL;

      // Se a loja tem loja_uid_ no nome, usar o UID extraído
      if (lojaId.startsWith('loja_uid_')) {
        ownerUid = lojaId.replace('loja_uid_', '');
        console.log(`   Extraindo UID do nome da loja: ${ownerUid}`);
      }

      // Atualizar documento da loja
      await lojaDoc.ref.update({
        ownerUid: ownerUid,
        owner: ownerEmail,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      console.log(`   ✅ Atualizado: ownerUid = ${ownerUid}`);
    }

    // Criar/atualizar documento do usuário
    console.log(`\n👤 Atualizando documento do usuário...`);

    await db.collection('users').doc(ROOT_UID).set({
      email: ROOT_EMAIL,
      store_id: `loja_uid_${ROOT_UID}`,
      tipo: 'admin',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    console.log(`✅ Usuário atualizado com store_id: loja_uid_${ROOT_UID}`);

    console.log('\n✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('✅ TODAS AS LOJAS FORAM CORRIGIDAS!');
    console.log('✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  } catch (error) {
    console.error('❌ Erro:', error);
  }

  process.exit(0);
}

fixStoreOwner();
