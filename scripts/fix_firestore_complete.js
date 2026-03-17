// Script para corrigir TODOS os problemas do Firestore
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();
const auth = admin.auth();

const ROOT_UID = 'vd0X6xXlq4be0cKhmIOiDtXTvKb2';
const ROOT_EMAIL = 'masterpalm@gmail.com';
const NATY_UID_CORRETO = 'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2';
const NATY_UID_ERRADO = 'c4NemqNa28YDmSrykCCXZdShztG3';
const NATY_EMAIL = 'natypolylopes1997@gmail.com';

async function fixFirestoreComplete() {
  console.log('🔧 ════════════════════════════════════════════════════');
  console.log('🔧 CORREÇÃO COMPLETA DO FIRESTORE');
  console.log('🔧 ════════════════════════════════════════════════════\n');

  // ═══════════════════════════════════════════════════════
  // 1️⃣ REMOVER UID DUPLICADO DA NATY
  // ═══════════════════════════════════════════════════════
  console.log('\n1️⃣ ════════════════════════════════════════════════════');
  console.log('1️⃣ REMOVENDO UID DUPLICADO DA NATY');
  console.log('1️⃣ ════════════════════════════════════════════════════\n');

  try {
    // Deletar documento do UID errado em /users
    await db.collection('users').doc(NATY_UID_ERRADO).delete();
    console.log(`✅ Deletado /users/${NATY_UID_ERRADO}`);
  } catch (e) {
    console.log(`⚠️  Erro ao deletar UID errado: ${e.message}`);
  }

  try {
    // Deletar usuário do Firebase Authentication (UID errado)
    await auth.deleteUser(NATY_UID_ERRADO);
    console.log(`✅ Deletado usuário ${NATY_UID_ERRADO} do Firebase Auth`);
  } catch (e) {
    console.log(`⚠️  Erro ao deletar auth: ${e.message}`);
  }

  // ═══════════════════════════════════════════════════════
  // 2️⃣ CORRIGIR DOCUMENTO DA NATY (UID CORRETO)
  // ═══════════════════════════════════════════════════════
  console.log('\n2️⃣ ════════════════════════════════════════════════════');
  console.log('2️⃣ CORRIGINDO DOCUMENTO DA NATY (UID CORRETO)');
  console.log('2️⃣ ════════════════════════════════════════════════════\n');

  await db.collection('users').doc(NATY_UID_CORRETO).set({
    email: NATY_EMAIL,
    store_id: `loja_uid_${NATY_UID_CORRETO}`,
    lojaId: 'nathy-pratas-e-folheados', // slug amigável
    tipo: 'admin',
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Atualizado /users/${NATY_UID_CORRETO}`);

  // ═══════════════════════════════════════════════════════
  // 3️⃣ CORRIGIR /usuarios (email-based)
  // ═══════════════════════════════════════════════════════
  console.log('\n3️⃣ ════════════════════════════════════════════════════');
  console.log('3️⃣ CORRIGINDO /usuarios (email-based)');
  console.log('3️⃣ ════════════════════════════════════════════════════\n');

  await db.collection('usuarios').doc(NATY_EMAIL).set({
    uid: NATY_UID_CORRETO,
    lojaId: 'nathy-pratas-e-folheados', // slug amigável
    store_id: `loja_uid_${NATY_UID_CORRETO}`,
    tipo: 'admin',
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Atualizado /usuarios/${NATY_EMAIL}`);

  await db.collection('usuarios').doc(ROOT_EMAIL).set({
    uid: ROOT_UID,
    lojaId: `loja_uid_${ROOT_UID}`, // UID como slug
    store_id: `loja_uid_${ROOT_UID}`,
    tipo: 'admin',
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Atualizado /usuarios/${ROOT_EMAIL}`);

  // Deletar documento estranho com UID como email
  try {
    await db.collection('usuarios').doc(ROOT_UID).delete();
    console.log(`✅ Deletado documento estranho /usuarios/${ROOT_UID}`);
  } catch (e) {
    console.log(`⚠️  Erro ao deletar: ${e.message}`);
  }

  // ═══════════════════════════════════════════════════════
  // 4️⃣ CORRIGIR LOJAS
  // ═══════════════════════════════════════════════════════
  console.log('\n4️⃣ ════════════════════════════════════════════════════');
  console.log('4️⃣ CORRIGINDO LOJAS');
  console.log('4️⃣ ════════════════════════════════════════════════════\n');

  // Loja da Naty (UID)
  await db.collection('lojas').doc(`loja_uid_${NATY_UID_CORRETO}`).set({
    nome: 'Nathy Pratas e Folheados',
    slug: 'nathy-pratas-e-folheados',
    owner: NATY_EMAIL,
    ownerUid: NATY_UID_CORRETO,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Atualizada loja_uid_${NATY_UID_CORRETO}`);

  // Loja da Naty (slug) - REMOVER redirect, tornar loja principal
  await db.collection('lojas').doc('nathy-pratas-e-folheados').set({
    nome: 'Nathy Pratas e Folheados',
    slug: 'nathy-pratas-e-folheados',
    owner: NATY_EMAIL,
    ownerUid: NATY_UID_CORRETO,
    redirectTo: admin.firestore.FieldValue.delete(), // REMOVER redirect
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Atualizada nathy-pratas-e-folheados (removido redirect)`);

  // Loja do Root (UID)
  await db.collection('lojas').doc(`loja_uid_${ROOT_UID}`).set({
    nome: 'MasterPalm',
    slug: `loja_uid_${ROOT_UID}`, // UID como slug
    owner: ROOT_EMAIL,
    ownerUid: ROOT_UID,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Atualizada loja_uid_${ROOT_UID}`);

  // Loja masterpalm_gmail_com - REDIRECIONAR para loja UID
  await db.collection('lojas').doc('masterpalm_gmail_com').set({
    nome: 'MasterPalm',
    slug: 'masterpalm_gmail_com',
    owner: ROOT_EMAIL,
    ownerUid: ROOT_UID,
    redirectTo: `loja_uid_${ROOT_UID}`, // Redirecionar para loja principal
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Atualizada masterpalm_gmail_com (redirect → loja_uid_${ROOT_UID})`);

  // ═══════════════════════════════════════════════════════
  // 5️⃣ COPIAR CONFIGURAÇÕES ENTRE LOJAS DA NATY
  // ═══════════════════════════════════════════════════════
  console.log('\n5️⃣ ════════════════════════════════════════════════════');
  console.log('5️⃣ SINCRONIZANDO CONFIGURAÇÕES DAS LOJAS DA NATY');
  console.log('5️⃣ ════════════════════════════════════════════════════\n');

  const lojaUidConfig = await db.collection('lojas').doc(`loja_uid_${NATY_UID_CORRETO}`).collection('config').doc('config').get();
  const lojaSlugConfig = await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('config').doc('config').get();

  // Verificar qual tem mais dados e copiar para a outra
  if (lojaUidConfig.exists && lojaSlugConfig.exists) {
    // Ambas existem, mesclar dados
    const uidData = lojaUidConfig.data();
    const slugData = lojaSlugConfig.data();

    // Preferir dados da loja UID (mais recente)
    const mergedConfig = { ...slugData, ...uidData };

    // Atualizar ambas
    await db.collection('lojas').doc(`loja_uid_${NATY_UID_CORRETO}`).collection('config').doc('config').set(mergedConfig, { merge: true });
    await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('config').doc('config').set(mergedConfig, { merge: true });

    console.log(`✅ Configurações sincronizadas entre as duas lojas da Naty`);
  } else if (lojaUidConfig.exists) {
    // Copiar UID → slug
    await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('config').doc('config').set(lojaUidConfig.data(), { merge: true });
    console.log(`✅ Config copiada de loja_uid → nathy-pratas-e-folheados`);
  } else if (lojaSlugConfig.exists) {
    // Copiar slug → UID
    await db.collection('lojas').doc(`loja_uid_${NATY_UID_CORRETO}`).collection('config').doc('config').set(lojaSlugConfig.data(), { merge: true });
    console.log(`✅ Config copiada de nathy-pratas-e-folheados → loja_uid`);
  }

  // ═══════════════════════════════════════════════════════
  // 6️⃣ SINCRONIZAR PRODUTOS ENTRE LOJAS DA NATY
  // ═══════════════════════════════════════════════════════
  console.log('\n6️⃣ ════════════════════════════════════════════════════');
  console.log('6️⃣ SINCRONIZANDO PRODUTOS DAS LOJAS DA NATY');
  console.log('6️⃣ ════════════════════════════════════════════════════\n');

  const produtosUid = await db.collection('lojas').doc(`loja_uid_${NATY_UID_CORRETO}`).collection('produtos').get();
  const produtosSlug = await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('produtos').get();

  console.log(`📦 Produtos em loja_uid: ${produtosUid.size}`);
  console.log(`📦 Produtos em nathy-pratas-e-folheados: ${produtosSlug.size}`);

  // Copiar todos os produtos únicos para ambas as lojas
  const allProductIds = new Set();

  produtosUid.forEach(doc => allProductIds.add(doc.id));
  produtosSlug.forEach(doc => allProductIds.add(doc.id));

  for (const prodId of allProductIds) {
    const uidDoc = await db.collection('lojas').doc(`loja_uid_${NATY_UID_CORRETO}`).collection('produtos').doc(prodId).get();
    const slugDoc = await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('produtos').doc(prodId).get();

    let prodData = null;

    if (uidDoc.exists && slugDoc.exists) {
      // Mesclar dados (preferir UID)
      prodData = { ...slugDoc.data(), ...uidDoc.data() };
    } else if (uidDoc.exists) {
      prodData = uidDoc.data();
    } else if (slugDoc.exists) {
      prodData = slugDoc.data();
    }

    if (prodData) {
      // Copiar para ambas
      await db.collection('lojas').doc(`loja_uid_${NATY_UID_CORRETO}`).collection('produtos').doc(prodId).set(prodData, { merge: true });
      await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('produtos').doc(prodId).set(prodData, { merge: true });
    }
  }

  console.log(`✅ Produtos sincronizados: ${allProductIds.size} produtos`);

  // ═══════════════════════════════════════════════════════
  // 7️⃣ LIMPAR USUÁRIOS ÓRFÃOS (store_id inexistente)
  // ═══════════════════════════════════════════════════════
  console.log('\n7️⃣ ════════════════════════════════════════════════════');
  console.log('7️⃣ LIMPANDO USUÁRIOS ÓRFÃOS');
  console.log('7️⃣ ════════════════════════════════════════════════════\n');

  const usersSnapshot = await db.collection('users').get();
  let orphansDeleted = 0;

  for (const userDoc of usersSnapshot.docs) {
    const userData = userDoc.data();
    const uid = userDoc.id;

    // Pular root e Naty
    if (uid === ROOT_UID || uid === NATY_UID_CORRETO) continue;

    const storeId = userData.store_id;

    if (storeId) {
      // Verificar se loja existe
      const lojaExists = await db.collection('lojas').doc(storeId).get();

      if (!lojaExists.exists) {
        console.log(`🗑️  Deletando usuário órfão: ${userData.email || uid} (loja ${storeId} não existe)`);
        await db.collection('users').doc(uid).delete();

        // Deletar do Auth também
        try {
          await auth.deleteUser(uid);
        } catch (e) {
          // Ignorar erro se já foi deletado
        }

        orphansDeleted++;
      }
    } else if (!userData.email) {
      // Sem email e sem store_id - deletar
      console.log(`🗑️  Deletando usuário sem dados: ${uid}`);
      await db.collection('users').doc(uid).delete();

      try {
        await auth.deleteUser(uid);
      } catch (e) {
        // Ignorar erro
      }

      orphansDeleted++;
    }
  }

  console.log(`✅ ${orphansDeleted} usuários órfãos deletados`);

  // ═══════════════════════════════════════════════════════
  // ✅ RESUMO FINAL
  // ═══════════════════════════════════════════════════════
  console.log('\n\n✅ ════════════════════════════════════════════════════');
  console.log('✅ CORREÇÃO COMPLETA FINALIZADA');
  console.log('✅ ════════════════════════════════════════════════════\n');

  console.log('📋 RESUMO DAS CORREÇÕES:\n');
  console.log('✅ 1. UID duplicado da Naty removido');
  console.log('✅ 2. Documento /users da Naty corrigido');
  console.log('✅ 3. Documento /usuarios corrigido');
  console.log('✅ 4. Lojas atualizadas com slugs e ownerUid corretos');
  console.log('✅ 5. Configurações sincronizadas entre lojas da Naty');
  console.log('✅ 6. Produtos sincronizados entre lojas da Naty');
  console.log(`✅ 7. ${orphansDeleted} usuários órfãos removidos\n`);

  console.log('🌐 ESTRUTURA FINAL:\n');
  console.log('👤 Naty (natypolylopes1997@gmail.com):');
  console.log(`   - UID: ${NATY_UID_CORRETO}`);
  console.log(`   - Loja: loja_uid_${NATY_UID_CORRETO}`);
  console.log(`   - Slug: nathy-pratas-e-folheados`);
  console.log(`   - URL: https://mastepalm.com.br/loja/nathy-pratas-e-folheados\n`);

  console.log('👤 Root (masterpalm@gmail.com):');
  console.log(`   - UID: ${ROOT_UID}`);
  console.log(`   - Loja: loja_uid_${ROOT_UID}`);
  console.log(`   - URL: https://mastepalm.com.br/loja/loja_uid_${ROOT_UID}\n`);

  console.log('════════════════════════════════════════════════════\n');

  process.exit(0);
}

fixFirestoreComplete();
