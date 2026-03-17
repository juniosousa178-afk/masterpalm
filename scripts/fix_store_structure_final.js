// Script para corrigir estrutura final das lojas
// DECISÃO: Usar SLUG como loja principal, UID como redirect
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

const ROOT_UID = 'vd0X6xXlq4be0cKhmIOiDtXTvKb2';
const ROOT_EMAIL = 'masterpalm@gmail.com';
const NATY_UID = 'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2';
const NATY_EMAIL = 'natypolylopes1997@gmail.com';
const NATY_SLUG = 'nathy-pratas-e-folheados';
const ROOT_SLUG = 'masterpalm'; // Criar slug amigável para root

async function fixStoreStructure() {
  console.log('🔧 ════════════════════════════════════════════════════');
  console.log('🔧 CORREÇÃO FINAL - ESTRUTURA DE LOJAS');
  console.log('🔧 DECISÃO: SLUG como loja PRINCIPAL, UID como redirect');
  console.log('🔧 ════════════════════════════════════════════════════\n');

  // ═══════════════════════════════════════════════════════
  // 1️⃣ LOJA DA NATY
  // ═══════════════════════════════════════════════════════
  console.log('\n1️⃣ ════════════════════════════════════════════════════');
  console.log('1️⃣ CONFIGURANDO LOJA DA NATY');
  console.log('1️⃣ ════════════════════════════════════════════════════\n');

  // Loja PRINCIPAL (slug amigável)
  await db.collection('lojas').doc(NATY_SLUG).set({
    nome: 'Nathy Pratas e Folheados',
    slug: NATY_SLUG,
    owner: NATY_EMAIL,
    ownerUid: NATY_UID,
    principal: true, // Marcar como principal
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Loja PRINCIPAL criada/atualizada: ${NATY_SLUG}`);

  // Loja UID (redirect para slug)
  await db.collection('lojas').doc(`loja_uid_${NATY_UID}`).set({
    nome: 'Nathy Pratas e Folheados',
    slug: NATY_SLUG,
    owner: NATY_EMAIL,
    ownerUid: NATY_UID,
    redirectTo: NATY_SLUG, // Redirecionar para loja principal
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Loja UID configurada com redirect: loja_uid_${NATY_UID} → ${NATY_SLUG}`);

  // Atualizar usuário
  await db.collection('users').doc(NATY_UID).set({
    email: NATY_EMAIL,
    store_id: NATY_SLUG, // ✅ SLUG como store_id principal
    lojaId: NATY_SLUG,
    tipo: 'admin',
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Usuário atualizado: /users/${NATY_UID} → store_id: ${NATY_SLUG}`);

  await db.collection('usuarios').doc(NATY_EMAIL).set({
    uid: NATY_UID,
    lojaId: NATY_SLUG,
    store_id: NATY_SLUG,
    tipo: 'admin',
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Usuário atualizado: /usuarios/${NATY_EMAIL} → lojaId: ${NATY_SLUG}`);

  // ═══════════════════════════════════════════════════════
  // 2️⃣ LOJA DO ROOT
  // ═══════════════════════════════════════════════════════
  console.log('\n2️⃣ ════════════════════════════════════════════════════');
  console.log('2️⃣ CONFIGURANDO LOJA DO ROOT');
  console.log('2️⃣ ════════════════════════════════════════════════════\n');

  // Loja PRINCIPAL (slug amigável)
  await db.collection('lojas').doc(ROOT_SLUG).set({
    nome: 'MasterPalm',
    slug: ROOT_SLUG,
    owner: ROOT_EMAIL,
    ownerUid: ROOT_UID,
    principal: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Loja PRINCIPAL criada/atualizada: ${ROOT_SLUG}`);

  // Loja UID (redirect para slug)
  await db.collection('lojas').doc(`loja_uid_${ROOT_UID}`).set({
    nome: 'MasterPalm',
    slug: ROOT_SLUG,
    owner: ROOT_EMAIL,
    ownerUid: ROOT_UID,
    redirectTo: ROOT_SLUG,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Loja UID configurada com redirect: loja_uid_${ROOT_UID} → ${ROOT_SLUG}`);

  // masterpalm_gmail_com também redireciona
  await db.collection('lojas').doc('masterpalm_gmail_com').set({
    nome: 'MasterPalm',
    slug: ROOT_SLUG,
    owner: ROOT_EMAIL,
    ownerUid: ROOT_UID,
    redirectTo: ROOT_SLUG,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Loja masterpalm_gmail_com configurada com redirect → ${ROOT_SLUG}`);

  // Atualizar usuário
  await db.collection('users').doc(ROOT_UID).set({
    email: ROOT_EMAIL,
    store_id: ROOT_SLUG, // ✅ SLUG como store_id principal
    lojaId: ROOT_SLUG,
    tipo: 'admin',
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Usuário atualizado: /users/${ROOT_UID} → store_id: ${ROOT_SLUG}`);

  await db.collection('usuarios').doc(ROOT_EMAIL).set({
    uid: ROOT_UID,
    lojaId: ROOT_SLUG,
    store_id: ROOT_SLUG,
    tipo: 'admin',
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ Usuário atualizado: /usuarios/${ROOT_EMAIL} → lojaId: ${ROOT_SLUG}`);

  // ═══════════════════════════════════════════════════════
  // 3️⃣ COPIAR CONFIG E PRODUTOS PARA LOJAS PRINCIPAIS
  // ═══════════════════════════════════════════════════════
  console.log('\n3️⃣ ════════════════════════════════════════════════════');
  console.log('3️⃣ COPIANDO CONFIGURAÇÕES E PRODUTOS');
  console.log('3️⃣ ════════════════════════════════════════════════════\n');

  // NATY: Copiar de loja_uid para nathy-pratas-e-folheados
  await copyConfigAndProducts(`loja_uid_${NATY_UID}`, NATY_SLUG);

  // ROOT: Copiar de loja_uid para masterpalm
  await copyConfigAndProducts(`loja_uid_${ROOT_UID}`, ROOT_SLUG);

  // ═══════════════════════════════════════════════════════
  // ✅ RESUMO FINAL
  // ═══════════════════════════════════════════════════════
  console.log('\n\n✅ ════════════════════════════════════════════════════');
  console.log('✅ ESTRUTURA FINAL CONFIGURADA');
  console.log('✅ ════════════════════════════════════════════════════\n');

  console.log('🌐 ESTRUTURA FINAL:\n');
  console.log('👤 Naty (natypolylopes1997@gmail.com):');
  console.log(`   - UID: ${NATY_UID}`);
  console.log(`   - Loja PRINCIPAL: ${NATY_SLUG} ⭐`);
  console.log(`   - Loja UID: loja_uid_${NATY_UID} → redirect para ${NATY_SLUG}`);
  console.log(`   - URL: https://mastepalm.com.br/loja/${NATY_SLUG}`);
  console.log(`   - store_id no /users: ${NATY_SLUG}\n`);

  console.log('👤 Root (masterpalm@gmail.com):');
  console.log(`   - UID: ${ROOT_UID}`);
  console.log(`   - Loja PRINCIPAL: ${ROOT_SLUG} ⭐`);
  console.log(`   - Loja UID: loja_uid_${ROOT_UID} → redirect para ${ROOT_SLUG}`);
  console.log(`   - Loja antiga: masterpalm_gmail_com → redirect para ${ROOT_SLUG}`);
  console.log(`   - URL: https://mastepalm.com.br/loja/${ROOT_SLUG}`);
  console.log(`   - store_id no /users: ${ROOT_SLUG}\n`);

  console.log('════════════════════════════════════════════════════\n');

  process.exit(0);
}

async function copyConfigAndProducts(fromLojaId, toLojaId) {
  console.log(`\n📋 Copiando de ${fromLojaId} → ${toLojaId}...`);

  // Copiar CONFIG
  const configDocFrom = await db.collection('lojas').doc(fromLojaId).collection('config').doc('config').get();
  const configDocTo = await db.collection('lojas').doc(toLojaId).collection('config').doc('config').get();

  if (configDocFrom.exists && configDocTo.exists) {
    // Mesclar (preferir dados mais completos)
    const dataFrom = configDocFrom.data();
    const dataTo = configDocTo.data();
    const merged = { ...dataTo, ...dataFrom };

    await db.collection('lojas').doc(toLojaId).collection('config').doc('config').set(merged, { merge: true });
    await db.collection('lojas').doc(fromLojaId).collection('config').doc('config').set(merged, { merge: true });

    console.log(`   ✅ Config mesclada e sincronizada`);
  } else if (configDocFrom.exists) {
    await db.collection('lojas').doc(toLojaId).collection('config').doc('config').set(configDocFrom.data(), { merge: true });
    console.log(`   ✅ Config copiada: ${fromLojaId} → ${toLojaId}`);
  } else if (configDocTo.exists) {
    await db.collection('lojas').doc(fromLojaId).collection('config').doc('config').set(configDocTo.data(), { merge: true });
    console.log(`   ✅ Config copiada: ${toLojaId} → ${fromLojaId}`);
  } else {
    console.log(`   ⚠️  Nenhuma config encontrada em ambas as lojas`);
  }

  // Copiar PRODUTOS
  const produtosFrom = await db.collection('lojas').doc(fromLojaId).collection('produtos').get();
  const produtosTo = await db.collection('lojas').doc(toLojaId).collection('produtos').get();

  const allProductIds = new Set();
  produtosFrom.forEach(doc => allProductIds.add(doc.id));
  produtosTo.forEach(doc => allProductIds.add(doc.id));

  for (const prodId of allProductIds) {
    const docFrom = await db.collection('lojas').doc(fromLojaId).collection('produtos').doc(prodId).get();
    const docTo = await db.collection('lojas').doc(toLojaId).collection('produtos').doc(prodId).get();

    let prodData = null;

    if (docFrom.exists && docTo.exists) {
      prodData = { ...docTo.data(), ...docFrom.data() };
    } else if (docFrom.exists) {
      prodData = docFrom.data();
    } else if (docTo.exists) {
      prodData = docTo.data();
    }

    if (prodData) {
      await db.collection('lojas').doc(toLojaId).collection('produtos').doc(prodId).set(prodData, { merge: true });
      await db.collection('lojas').doc(fromLojaId).collection('produtos').doc(prodId).set(prodData, { merge: true });
    }
  }

  console.log(`   ✅ ${allProductIds.size} produtos sincronizados`);
}

fixStoreStructure();
