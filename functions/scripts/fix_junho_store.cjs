/**
 * Script Específico: Correção da loja do usuário junho
 *
 * Diagnóstico e correção da loja:
 * - Email: juniosousa178@gmail.com
 * - Store IDs em questão:
 *   - loja_uid_H3be6ett8NZBjzh0nJa35tligDZ2 (mixed-case)
 *   - loja_uid_h3be6ett8nzbjzh0nja35tligdz2 (lowercase)
 *
 * Uso:
 *   node scripts/fix_junho_store.js [--fix]
 *
 * --fix: Aplica as correções (sem flag, apenas diagnóstico)
 */

const admin = require('firebase-admin');

// Inicializar Firebase Admin
if (!admin.apps.length) {
  const serviceAccount = require('../masterpalm-service-account.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

// Configuração
const FIX_MODE = process.argv.includes('--fix');
const JUNHO_EMAIL = 'juniosousa178@gmail.com';
const MIXED_CASE_ID = 'loja_uid_H3be6ett8NZBjzh0nJa35tligDZ2';
const LOWERCASE_ID = 'loja_uid_h3be6ett8nzbjzh0nja35tligdz2';

async function diagnose() {
  console.log('━'.repeat(70));
  console.log('🔍 DIAGNÓSTICO DA LOJA DO JUNHO');
  console.log(`   Email: ${JUNHO_EMAIL}`);
  console.log(`   Modo: ${FIX_MODE ? '🔧 CORREÇÃO' : '🔍 APENAS DIAGNÓSTICO'}`);
  console.log('━'.repeat(70));

  const results = {
    issues: [],
    recommendations: [],
  };

  // 1. Verificar doc do usuário em usuarios/{email}
  console.log('\n📧 1. Verificando usuarios/{email}...');
  const usuarioDoc = await db.collection('usuarios').doc(JUNHO_EMAIL).get();
  if (usuarioDoc.exists) {
    const data = usuarioDoc.data();
    console.log(`   ✅ Doc existe`);
    console.log(`      store_id: ${data.store_id || '(vazio)'}`);
    console.log(`      authUid: ${data.authUid || '(vazio)'}`);
    console.log(`      tipo: ${data.tipo || '(vazio)'}`);

    if (!data.store_id) {
      results.issues.push('usuarios/{email} sem store_id');
    }
  } else {
    console.log(`   ❌ Doc NÃO existe`);
    results.issues.push('usuarios/{email} não existe');
  }

  // 2. Verificar doc do usuário em users/{uid}
  console.log('\n👤 2. Verificando users/{uid}...');
  const usersQuery = await db.collection('users')
    .where('email', '==', JUNHO_EMAIL)
    .limit(1)
    .get();

  if (!usersQuery.empty) {
    const userDoc = usersQuery.docs[0];
    const data = userDoc.data();
    console.log(`   ✅ Doc existe (ID: ${userDoc.id})`);
    console.log(`      store_id: ${data.store_id || '(vazio)'}`);
    console.log(`      ownerOf: ${data.ownerOf || '(vazio)'}`);

    if (!data.store_id) {
      results.issues.push('users/{uid} sem store_id');
    }
  } else {
    console.log(`   ⚠️  Nenhum doc encontrado com email=${JUNHO_EMAIL}`);
    // Tentar buscar pelo authUid do usuarios
    if (usuarioDoc.exists && usuarioDoc.data().authUid) {
      const uid = usuarioDoc.data().authUid;
      const userByUid = await db.collection('users').doc(uid).get();
      if (userByUid.exists) {
        const data = userByUid.data();
        console.log(`   ✅ Doc encontrado por UID: ${uid}`);
        console.log(`      store_id: ${data.store_id || '(vazio)'}`);
      } else {
        console.log(`   ❌ Nenhum doc users/{uid} encontrado`);
        results.issues.push('users/{uid} não existe');
      }
    }
  }

  // 3. Verificar loja mixed-case
  console.log(`\n🏪 3. Verificando loja mixed-case: ${MIXED_CASE_ID}...`);
  const mixedCaseDoc = await db.collection('lojas').doc(MIXED_CASE_ID).get();
  if (mixedCaseDoc.exists) {
    const data = mixedCaseDoc.data();
    console.log(`   ✅ Doc existe`);
    console.log(`      ownerUid: ${data.ownerUid || '(vazio)'}`);
    console.log(`      slug: ${data.slug || '(vazio)'}`);
    console.log(`      redirectTo: ${data.redirectTo || '(não configurado)'}`);

    // Contar produtos
    const prodCount = await db.collection('lojas').doc(MIXED_CASE_ID)
      .collection('produtos').count().get();
    const draftCount = await db.collection('lojas').doc(MIXED_CASE_ID)
      .collection('draft_produtos').count().get();
    console.log(`      produtos: ${prodCount.data().count}`);
    console.log(`      draft_produtos: ${draftCount.data().count}`);

    if (!data.redirectTo) {
      results.recommendations.push(`Configurar redirectTo=${LOWERCASE_ID} em ${MIXED_CASE_ID}`);
    }
  } else {
    console.log(`   ❌ Doc NÃO existe`);
  }

  // 4. Verificar loja lowercase
  console.log(`\n🏪 4. Verificando loja lowercase: ${LOWERCASE_ID}...`);
  const lowercaseDoc = await db.collection('lojas').doc(LOWERCASE_ID).get();
  if (lowercaseDoc.exists) {
    const data = lowercaseDoc.data();
    console.log(`   ✅ Doc existe`);
    console.log(`      ownerUid: ${data.ownerUid || '(vazio)'}`);
    console.log(`      slug: ${data.slug || '(vazio)'}`);

    // Contar produtos
    const prodCount = await db.collection('lojas').doc(LOWERCASE_ID)
      .collection('produtos').count().get();
    const draftCount = await db.collection('lojas').doc(LOWERCASE_ID)
      .collection('draft_produtos').count().get();
    console.log(`      produtos: ${prodCount.data().count}`);
    console.log(`      draft_produtos: ${draftCount.data().count}`);
  } else {
    console.log(`   ⚠️  Doc NÃO existe (será criado se --fix)`);
    results.recommendations.push(`Criar doc ${LOWERCASE_ID} copiando dados de ${MIXED_CASE_ID}`);
  }

  // 5. Verificar config das lojas
  console.log('\n⚙️  5. Verificando configs...');

  for (const lojaId of [MIXED_CASE_ID, LOWERCASE_ID]) {
    const configDoc = await db.collection('lojas').doc(lojaId)
      .collection('config').doc('config').get();
    const draftConfigDoc = await db.collection('lojas').doc(lojaId)
      .collection('draft_config').doc('config').get();

    console.log(`   ${lojaId}:`);
    console.log(`      config: ${configDoc.exists ? '✅ existe' : '❌ não existe'}`);
    console.log(`      draft_config: ${draftConfigDoc.exists ? '✅ existe' : '❌ não existe'}`);
  }

  // Resumo
  console.log('\n' + '━'.repeat(70));
  console.log('📊 RESUMO DO DIAGNÓSTICO');
  console.log('━'.repeat(70));

  if (results.issues.length === 0) {
    console.log('   ✅ Nenhum problema crítico encontrado');
  } else {
    console.log('   ❌ Problemas encontrados:');
    results.issues.forEach(issue => console.log(`      - ${issue}`));
  }

  if (results.recommendations.length > 0) {
    console.log('\n   💡 Recomendações:');
    results.recommendations.forEach(rec => console.log(`      - ${rec}`));
  }

  console.log('━'.repeat(70));

  return results;
}

async function fix() {
  console.log('\n🔧 APLICANDO CORREÇÕES...\n');

  // 1. Verificar se a loja mixed-case existe
  const mixedCaseDoc = await db.collection('lojas').doc(MIXED_CASE_ID).get();
  if (!mixedCaseDoc.exists) {
    console.log('   ❌ Loja mixed-case não existe, nada a fazer');
    return;
  }

  const mixedCaseData = mixedCaseDoc.data();

  // 2. Verificar/criar loja lowercase
  const lowercaseDoc = await db.collection('lojas').doc(LOWERCASE_ID).get();

  if (!lowercaseDoc.exists) {
    console.log('   📝 Criando loja lowercase...');

    const newData = {
      ...mixedCaseData,
      lojaId: LOWERCASE_ID,
      id: LOWERCASE_ID,
      migratedFrom: MIXED_CASE_ID,
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    delete newData.redirectTo;

    await db.collection('lojas').doc(LOWERCASE_ID).set(newData);
    console.log('   ✅ Loja lowercase criada');

    // Copiar subcoleções
    const subcollections = ['produtos', 'draft_produtos', 'config', 'draft_config'];

    for (const subcol of subcollections) {
      const snapshot = await db.collection('lojas').doc(MIXED_CASE_ID)
        .collection(subcol).get();

      if (!snapshot.empty) {
        const batch = db.batch();
        let count = 0;

        for (const doc of snapshot.docs) {
          const data = doc.data();
          // Atualizar lojaId nos dados
          if (data.lojaId === MIXED_CASE_ID) {
            data.lojaId = LOWERCASE_ID;
          }

          batch.set(
            db.collection('lojas').doc(LOWERCASE_ID).collection(subcol).doc(doc.id),
            data
          );
          count++;
        }

        await batch.commit();
        console.log(`   📦 ${subcol}: ${count} docs copiados`);
      }
    }
  } else {
    console.log('   ✅ Loja lowercase já existe');
  }

  // 3. Configurar redirect na loja mixed-case
  if (!mixedCaseData.redirectTo) {
    console.log('   🔀 Configurando redirect...');
    await db.collection('lojas').doc(MIXED_CASE_ID).update({
      redirectTo: LOWERCASE_ID,
      redirectConfiguredAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('   ✅ Redirect configurado');
  }

  // 4. Atualizar store_id no perfil do usuário
  console.log('   👤 Atualizando perfil do usuário...');

  const usuarioDoc = await db.collection('usuarios').doc(JUNHO_EMAIL).get();
  if (usuarioDoc.exists) {
    await db.collection('usuarios').doc(JUNHO_EMAIL).update({
      store_id: LOWERCASE_ID,
      store_id_migrated_from: MIXED_CASE_ID,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('   ✅ usuarios/{email} atualizado');
  }

  // Atualizar users/{uid}
  const authUid = usuarioDoc.exists ? usuarioDoc.data().authUid : null;
  if (authUid) {
    await db.collection('users').doc(authUid).set({
      store_id: LOWERCASE_ID,
      store_id_migrated_from: MIXED_CASE_ID,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    console.log('   ✅ users/{uid} atualizado');
  }

  console.log('\n✅ CORREÇÕES APLICADAS COM SUCESSO!');
  console.log('\n💡 O usuário junho agora deve:');
  console.log('   1. Fazer LOGOUT no app');
  console.log('   2. Fazer LOGIN novamente');
  console.log('   3. A loja deve carregar corretamente');
  console.log(`\n   URL pública: https://mastepalm.com.br/loja/${LOWERCASE_ID}`);
}

async function main() {
  try {
    const results = await diagnose();

    if (FIX_MODE) {
      await fix();
    } else {
      console.log('\n💡 Para aplicar correções, execute com --fix:');
      console.log('   node scripts/fix_junho_store.js --fix\n');
    }

  } catch (error) {
    console.error('❌ Erro:', error);
    process.exit(1);
  }

  process.exit(0);
}

main();
