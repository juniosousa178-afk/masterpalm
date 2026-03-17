// Script para diagnóstico completo do Firestore
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function diagnoseComplete() {
  console.log('🔍 ════════════════════════════════════════════════════');
  console.log('🔍 DIAGNÓSTICO COMPLETO DO FIRESTORE');
  console.log('🔍 ════════════════════════════════════════════════════\n');

  // ═══════════════════════════════════════════════════════
  // 1️⃣ COLEÇÃO: lojas
  // ═══════════════════════════════════════════════════════
  console.log('\n📦 ════════════════════════════════════════════════════');
  console.log('📦 COLEÇÃO: /lojas');
  console.log('📦 ════════════════════════════════════════════════════');

  const lojasSnapshot = await db.collection('lojas').get();

  console.log(`\n🔢 Total de lojas: ${lojasSnapshot.size}\n`);

  for (const lojaDoc of lojasSnapshot.docs) {
    const lojaId = lojaDoc.id;
    const lojaData = lojaDoc.data();

    console.log(`\n┌─────────────────────────────────────────────────`);
    console.log(`│ 🏪 Loja: ${lojaId}`);
    console.log(`├─────────────────────────────────────────────────`);
    console.log(`│ nome: ${lojaData.nome || 'N/A'}`);
    console.log(`│ slug: ${lojaData.slug || 'N/A'}`);
    console.log(`│ owner: ${lojaData.owner || 'N/A'}`);
    console.log(`│ ownerUid: ${lojaData.ownerUid || 'N/A'}`);
    console.log(`│ redirectTo: ${lojaData.redirectTo || 'N/A'}`);

    // Verificar subcoleção config
    const configDoc = await db.collection('lojas').doc(lojaId).collection('config').doc('config').get();

    if (configDoc.exists) {
      const configData = configDoc.data();
      console.log(`├─────────────────────────────────────────────────`);
      console.log(`│ ✅ CONFIG EXISTE:`);
      console.log(`│   - logoDesktop: ${configData.logoDesktop ? '✅ SIM' : '❌ NÃO'}`);
      console.log(`│   - logoMobile: ${configData.logoMobile ? '✅ SIM' : '❌ NÃO'}`);
      console.log(`│   - bannersMobile: ${configData.bannersMobile ? `✅ ${configData.bannersMobile.length} banners` : '❌ NÃO'}`);
      console.log(`│   - bannersDesktop: ${configData.bannersDesktop ? `✅ ${configData.bannersDesktop.length} banners` : '❌ NÃO'}`);
      console.log(`│   - theme.primaryColor: ${configData.theme?.primaryColor || 'N/A'}`);
      console.log(`│   - publicado: ${configData.publicado !== undefined ? (configData.publicado ? '✅ SIM' : '❌ NÃO') : 'N/A'}`);
    } else {
      console.log(`├─────────────────────────────────────────────────`);
      console.log(`│ ❌ CONFIG NÃO EXISTE`);
    }

    // Verificar produtos
    const produtosSnapshot = await db.collection('lojas').doc(lojaId).collection('produtos').get();
    console.log(`│ 📦 Produtos: ${produtosSnapshot.size}`);
    console.log(`└─────────────────────────────────────────────────`);
  }

  // ═══════════════════════════════════════════════════════
  // 2️⃣ COLEÇÃO: users
  // ═══════════════════════════════════════════════════════
  console.log('\n\n👤 ════════════════════════════════════════════════════');
  console.log('👤 COLEÇÃO: /users');
  console.log('👤 ════════════════════════════════════════════════════');

  const usersSnapshot = await db.collection('users').get();

  console.log(`\n🔢 Total de usuários: ${usersSnapshot.size}\n`);

  for (const userDoc of usersSnapshot.docs) {
    const uid = userDoc.id;
    const userData = userDoc.data();

    console.log(`\n┌─────────────────────────────────────────────────`);
    console.log(`│ 👤 UID: ${uid}`);
    console.log(`├─────────────────────────────────────────────────`);
    console.log(`│ email: ${userData.email || 'N/A'}`);
    console.log(`│ store_id: ${userData.store_id || 'N/A'}`);
    console.log(`│ lojaId: ${userData.lojaId || 'N/A'}`);
    console.log(`│ tipo: ${userData.tipo || 'N/A'}`);

    // Verificar se a loja existe
    if (userData.store_id) {
      const lojaRef = await db.collection('lojas').doc(userData.store_id).get();
      console.log(`│ Loja ${userData.store_id} existe: ${lojaRef.exists ? '✅ SIM' : '❌ NÃO'}`);

      if (lojaRef.exists) {
        const lojaData = lojaRef.data();
        console.log(`│   - ownerUid da loja: ${lojaData.ownerUid || 'N/A'}`);
        console.log(`│   - Match com UID: ${lojaData.ownerUid === uid ? '✅ SIM' : '❌ NÃO'}`);
      }
    }
    console.log(`└─────────────────────────────────────────────────`);
  }

  // ═══════════════════════════════════════════════════════
  // 3️⃣ COLEÇÃO: usuarios (email-based)
  // ═══════════════════════════════════════════════════════
  console.log('\n\n📧 ════════════════════════════════════════════════════');
  console.log('📧 COLEÇÃO: /usuarios (email-based)');
  console.log('📧 ════════════════════════════════════════════════════');

  const usuariosSnapshot = await db.collection('usuarios').get();

  console.log(`\n🔢 Total de documentos: ${usuariosSnapshot.size}\n`);

  for (const usuarioDoc of usuariosSnapshot.docs) {
    const email = usuarioDoc.id;
    const usuarioData = usuarioDoc.data();

    console.log(`\n┌─────────────────────────────────────────────────`);
    console.log(`│ 📧 Email: ${email}`);
    console.log(`├─────────────────────────────────────────────────`);
    console.log(`│ uid: ${usuarioData.uid || 'N/A'}`);
    console.log(`│ lojaId: ${usuarioData.lojaId || 'N/A'}`);
    console.log(`│ store_id: ${usuarioData.store_id || 'N/A'}`);
    console.log(`│ tipo: ${usuarioData.tipo || 'N/A'}`);
    console.log(`└─────────────────────────────────────────────────`);
  }

  // ═══════════════════════════════════════════════════════
  // 4️⃣ ANÁLISE DE PROBLEMAS
  // ═══════════════════════════════════════════════════════
  console.log('\n\n⚠️  ════════════════════════════════════════════════════');
  console.log('⚠️  PROBLEMAS IDENTIFICADOS');
  console.log('⚠️  ════════════════════════════════════════════════════\n');

  const problems = [];

  // Verificar lojas sem config
  for (const lojaDoc of lojasSnapshot.docs) {
    const lojaId = lojaDoc.id;
    const configDoc = await db.collection('lojas').doc(lojaId).collection('config').doc('config').get();

    if (!configDoc.exists) {
      problems.push(`❌ Loja ${lojaId} NÃO tem documento config`);
    }
  }

  // Verificar users com store_id inexistente
  for (const userDoc of usersSnapshot.docs) {
    const userData = userDoc.data();
    if (userData.store_id) {
      const lojaRef = await db.collection('lojas').doc(userData.store_id).get();
      if (!lojaRef.exists) {
        problems.push(`❌ Usuário ${userData.email} tem store_id ${userData.store_id} que NÃO existe`);
      } else {
        const lojaData = lojaRef.data();
        if (lojaData.ownerUid !== userDoc.id) {
          problems.push(`❌ Usuário ${userData.email} (${userDoc.id}) tem store_id ${userData.store_id} mas ownerUid da loja é ${lojaData.ownerUid}`);
        }
      }
    }
  }

  // Verificar lojas sem slug
  for (const lojaDoc of lojasSnapshot.docs) {
    const lojaData = lojaDoc.data();
    if (!lojaData.slug || lojaData.slug.trim() === '') {
      problems.push(`❌ Loja ${lojaDoc.id} NÃO tem slug definido`);
    }
  }

  if (problems.length > 0) {
    problems.forEach(p => console.log(p));
  } else {
    console.log('✅ Nenhum problema identificado!');
  }

  console.log('\n════════════════════════════════════════════════════\n');

  process.exit(0);
}

diagnoseComplete();
