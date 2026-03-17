// Script para verificar qual loja está vinculada ao usuário
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();
const auth = admin.auth();

async function checkUserStore() {
  console.log('🔍 Verificando usuários e suas lojas...\n');

  try {
    // Buscar usuário natypolylopes1997@gmail.com
    const targetEmail = 'natypolylopes1997@gmail.com';

    console.log(`📧 Buscando usuário: ${targetEmail}\n`);

    // Verificar Firebase Auth
    let userAuth = null;
    try {
      userAuth = await auth.getUserByEmail(targetEmail);
      console.log('✅ Firebase Authentication:');
      console.log(`   UID: ${userAuth.uid}`);
      console.log(`   Email: ${userAuth.email}`);
      console.log(`   Email Verified: ${userAuth.emailVerified}`);
    } catch (e) {
      console.log('❌ Usuário NÃO encontrado no Firebase Auth');
      console.log(`   Erro: ${e.message}\n`);
    }

    if (userAuth) {
      // Verificar documento users
      const userDoc = await db.collection('users').doc(userAuth.uid).get();

      console.log('\n📄 Firestore /users/{uid}:');
      if (userDoc.exists) {
        const userData = userDoc.data();
        console.log('   ✅ Documento existe');
        console.log(`   store_id: ${userData.store_id || 'NÃO DEFINIDO'}`);
        console.log(`   storeId: ${userData.storeId || 'NÃO DEFINIDO'}`);
        console.log(`   loja_id: ${userData.loja_id || 'NÃO DEFINIDO'}`);
        console.log(`   lojaId: ${userData.lojaId || 'NÃO DEFINIDO'}`);
        console.log(`   tipo: ${userData.tipo || 'NÃO DEFINIDO'}`);
      } else {
        console.log('   ❌ Documento NÃO existe');
      }

      // Verificar documento usuarios (coleção alternativa)
      const usuarioDoc = await db.collection('usuarios').doc(targetEmail).get();

      console.log('\n📄 Firestore /usuarios/{email}:');
      if (usuarioDoc.exists) {
        const usuarioData = usuarioDoc.data();
        console.log('   ✅ Documento existe');
        console.log(`   email: ${usuarioData.email || 'NÃO DEFINIDO'}`);
        console.log(`   tipo: ${usuarioData.tipo || 'NÃO DEFINIDO'}`);
        console.log(`   lojaId: ${usuarioData.lojaId || 'NÃO DEFINIDO'}`);
      } else {
        console.log('   ❌ Documento NÃO existe');
      }

      // Buscar lojas onde ownerUid == uid
      console.log('\n🏪 Lojas do usuário (ownerUid == uid):');
      const lojasQuery = await db.collection('lojas')
        .where('ownerUid', '==', userAuth.uid)
        .get();

      if (lojasQuery.empty) {
        console.log('   ❌ Nenhuma loja encontrada');
      } else {
        lojasQuery.forEach(doc => {
          const data = doc.data();
          console.log(`\n   ✅ Loja: ${doc.id}`);
          console.log(`      Nome: ${data.nome || 'não definido'}`);
          console.log(`      Slug: ${data.slug || 'não definido'}`);
          console.log(`      Owner: ${data.owner || 'não definido'}`);
          console.log(`      OwnerUid: ${data.ownerUid || 'não definido'}`);
        });
      }
    }

    // Verificar TODAS as lojas para ver configurações
    console.log('\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('📊 RESUMO DE TODAS AS LOJAS:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    const allLojas = await db.collection('lojas').get();

    for (const lojaDoc of allLojas.docs) {
      const data = lojaDoc.data();
      const configSnap = await db.collection('lojas').doc(lojaDoc.id).collection('config').doc('config').get();

      let hasConfig = false;
      let hasLogo = false;
      let hasBanner = false;

      if (configSnap.exists) {
        hasConfig = true;
        const cfg = configSnap.data();
        const media = cfg.media || {};
        hasLogo = !!(media.mobile?.logoUrl || media.desktop?.logoUrl);
        hasBanner = (media.mobile?.banners?.length || 0) + (media.desktop?.banners?.length || 0) > 0;
      }

      console.log(`🏪 ${lojaDoc.id}`);
      console.log(`   Owner: ${data.owner || 'não definido'}`);
      console.log(`   OwnerUid: ${data.ownerUid || 'não definido'}`);
      console.log(`   Config: ${hasConfig ? '✅' : '❌'}`);
      console.log(`   Logo: ${hasLogo ? '✅' : '❌'}`);
      console.log(`   Banner: ${hasBanner ? '✅' : '❌'}`);
      console.log('');
    }

    console.log('✅ Verificação concluída!');

  } catch (error) {
    console.error('❌ Erro:', error);
  }

  process.exit(0);
}

checkUserStore();
