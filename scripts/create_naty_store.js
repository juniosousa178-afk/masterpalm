// Script para criar/configurar loja da Naty corretamente
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function createNatyStore() {
  console.log('🔧 Configurando loja da Naty...\n');

  const natyEmail = 'natypolylopes1997@gmail.com';
  const natyUid = 'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2';
  const natyLojaId = 'loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2';
  const natySlug = 'nathy-pratas-e-folheados';

  try {
    // 1. Criar/atualizar loja com UID correto
    console.log(`1️⃣ Criando loja: ${natyLojaId}`);

    await db.collection('lojas').doc(natyLojaId).set({
      slug: natySlug,
      owner: natyEmail,
      ownerUid: natyUid, // ✅ UID correto da Naty
      nome: 'Nathy Pratas e Folheados',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      publishedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    console.log(`✅ Loja ${natyLojaId} criada/atualizada`);

    // 2. Atualizar documento users
    console.log(`\n2️⃣ Atualizando /users/${natyUid}`);

    await db.collection('users').doc(natyUid).set({
      email: natyEmail,
      store_id: natyLojaId,
      lojaId: natySlug,
      tipo: 'admin',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    console.log(`✅ Usuário atualizado com store_id: ${natyLojaId}`);

    // 3. Atualizar documento usuarios
    console.log(`\n3️⃣ Atualizando /usuarios/${natyEmail}`);

    await db.collection('usuarios').doc(natyEmail).set({
      email: natyEmail,
      tipo: 'admin',
      lojaId: natySlug,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    console.log(`✅ Documento usuarios atualizado`);

    // 4. Copiar config da loja nathy-pratas-e-folheados para a nova loja
    console.log(`\n4️⃣ Copiando configurações de ${natySlug}...`);

    const oldLojaConfig = await db.collection('lojas').doc(natySlug).collection('config').doc('config').get();

    if (oldLojaConfig.exists) {
      await db.collection('lojas').doc(natyLojaId).collection('config').doc('config').set(
        oldLojaConfig.data(),
        { merge: true }
      );
      console.log(`✅ Config copiada`);
    } else {
      // Criar config padrão
      await db.collection('lojas').doc(natyLojaId).collection('config').doc('config').set({
        theme: {
          fundo: 4278519049,
          card: 4279308570,
          texto: 4294967295,
          primaria: 4278233343,
          botaoTexto: 4294967295
        },
        nome: 'Nathy Pratas e Folheados',
        whatsapp: '',
        slug: natySlug,
        lojaId: natyLojaId,
        media: {
          desktop: { logoUrl: null, banners: [], logoH: 105, logoW: 327, bannerH: 256, bannerW: 1280 },
          mobile: { logoUrl: null, banners: [], logoH: 105, logoW: 327, bannerH: 300, bannerW: 562 }
        }
      });
      console.log(`✅ Config padrão criada`);
    }

    // 5. Copiar produtos de nathy-pratas-e-folheados para a nova loja
    console.log(`\n5️⃣ Copiando produtos...`);

    const oldProdutos = await db.collection('lojas').doc(natySlug).collection('produtos').get();

    if (!oldProdutos.empty) {
      for (const prodDoc of oldProdutos.docs) {
        const prodData = prodDoc.data();
        await db.collection('lojas').doc(natyLojaId).collection('produtos').doc(prodDoc.id).set(
          prodData,
          { merge: true }
        );
      }
      console.log(`✅ ${oldProdutos.size} produto(s) copiado(s)`);
    } else {
      console.log(`ℹ️  Nenhum produto para copiar`);
    }

    // 6. Atualizar loja antiga nathy-pratas-e-folheados para redirecionar
    console.log(`\n6️⃣ Atualizando loja antiga...`);

    await db.collection('lojas').doc(natySlug).set({
      redirectTo: natyLojaId, // Para redirecionar se alguém acessar o slug antigo
      owner: natyEmail,
      ownerUid: natyUid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    console.log(`✅ Loja antiga atualizada com redirect`);

    // 7. Atualizar outras lojas erradas (nathy)
    console.log(`\n7️⃣ Removendo loja 'nathy' duplicada...`);

    await db.collection('lojas').doc('nathy').delete();
    console.log(`✅ Loja 'nathy' removida`);

    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('✅ LOJA DA NATY CONFIGURADA COM SUCESSO!');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    console.log(`\n📝 Informações da loja:`);
    console.log(`   Loja ID: ${natyLojaId}`);
    console.log(`   Slug: ${natySlug}`);
    console.log(`   Owner: ${natyEmail}`);
    console.log(`   OwnerUid: ${natyUid}`);

    console.log(`\n🌐 URLs:`);
    console.log(`   App: usar loja ${natyLojaId}`);
    console.log(`   Web: https://mastepalm.com.br/loja/${natySlug}`);
    console.log(`   Web (UID): https://mastepalm.com.br/loja/${natyLojaId}`);

  } catch (error) {
    console.error('❌ Erro:', error);
  }

  process.exit(0);
}

createNatyStore();
