// Script de verificação final - Testa todas as correções
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function verifyFinalState() {
  console.log('✅ ════════════════════════════════════════════════════');
  console.log('✅ VERIFICAÇÃO FINAL DO ESTADO DO FIRESTORE');
  console.log('✅ ════════════════════════════════════════════════════\n');

  let allTestsPassed = true;

  // ═══════════════════════════════════════════════════════
  // TESTE 1: Loja da Naty (slug)
  // ═══════════════════════════════════════════════════════
  console.log('\n🧪 TESTE 1: Loja da Naty (slug: nathy-pratas-e-folheados)');
  console.log('─────────────────────────────────────────────────────');

  const natyLojaSlug = await db.collection('lojas').doc('nathy-pratas-e-folheados').get();

  if (!natyLojaSlug.exists) {
    console.log('❌ Loja nathy-pratas-e-folheados NÃO existe');
    allTestsPassed = false;
  } else {
    const data = natyLojaSlug.data();

    console.log(`✅ Loja existe`);
    console.log(`   - Nome: ${data.nome}`);
    console.log(`   - Owner: ${data.owner}`);
    console.log(`   - OwnerUid: ${data.ownerUid}`);
    console.log(`   - Slug: ${data.slug}`);
    console.log(`   - RedirectTo: ${data.redirectTo || 'N/A (loja principal)'}`);

    if (data.ownerUid !== 'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2') {
      console.log(`❌ OwnerUid incorreto! Esperado: tcnbZdmFXsMPJ2bU29dDt3z5ZHr2`);
      allTestsPassed = false;
    }

    if (data.redirectTo) {
      console.log(`❌ Loja PRINCIPAL não deveria ter redirectTo!`);
      allTestsPassed = false;
    }

    // Verificar config
    const config = await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('config').doc('config').get();
    if (!config.exists) {
      console.log(`❌ Config NÃO existe`);
      allTestsPassed = false;
    } else {
      const configData = config.data();
      console.log(`✅ Config existe`);
      console.log(`   - Banners mobile: ${configData.bannersMobile?.length || 0}`);
      console.log(`   - Banners desktop: ${configData.bannersDesktop?.length || 0}`);
    }

    // Verificar produtos
    const produtos = await db.collection('lojas').doc('nathy-pratas-e-folheados').collection('produtos').get();
    console.log(`✅ ${produtos.size} produtos`);
  }

  // ═══════════════════════════════════════════════════════
  // TESTE 2: Loja da Naty (UID - deve ter redirect)
  // ═══════════════════════════════════════════════════════
  console.log('\n🧪 TESTE 2: Loja da Naty (UID: loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2)');
  console.log('─────────────────────────────────────────────────────');

  const natyLojaUid = await db.collection('lojas').doc('loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2').get();

  if (!natyLojaUid.exists) {
    console.log('❌ Loja loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2 NÃO existe');
    allTestsPassed = false;
  } else {
    const data = natyLojaUid.data();

    console.log(`✅ Loja existe`);
    console.log(`   - RedirectTo: ${data.redirectTo || 'N/A'}`);

    if (data.redirectTo !== 'nathy-pratas-e-folheados') {
      console.log(`❌ RedirectTo incorreto! Esperado: nathy-pratas-e-folheados`);
      allTestsPassed = false;
    } else {
      console.log(`✅ Redirect correto → nathy-pratas-e-folheados`);
    }
  }

  // ═══════════════════════════════════════════════════════
  // TESTE 3: Usuário da Naty
  // ═══════════════════════════════════════════════════════
  console.log('\n🧪 TESTE 3: Usuário da Naty (/users/tcnbZdmFXsMPJ2bU29dDt3z5ZHr2)');
  console.log('─────────────────────────────────────────────────────');

  const natyUser = await db.collection('users').doc('tcnbZdmFXsMPJ2bU29dDt3z5ZHr2').get();

  if (!natyUser.exists) {
    console.log('❌ Usuário NÃO existe');
    allTestsPassed = false;
  } else {
    const data = natyUser.data();

    console.log(`✅ Usuário existe`);
    console.log(`   - Email: ${data.email}`);
    console.log(`   - store_id: ${data.store_id}`);
    console.log(`   - lojaId: ${data.lojaId}`);

    if (data.store_id !== 'nathy-pratas-e-folheados') {
      console.log(`❌ store_id incorreto! Esperado: nathy-pratas-e-folheados`);
      allTestsPassed = false;
    } else {
      console.log(`✅ store_id correto (slug)`);
    }

    // Verificar se a loja existe
    const lojaRef = await db.collection('lojas').doc(data.store_id).get();
    if (!lojaRef.exists) {
      console.log(`❌ Loja ${data.store_id} NÃO existe!`);
      allTestsPassed = false;
    } else {
      const lojaData = lojaRef.data();
      if (lojaData.ownerUid === 'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2') {
        console.log(`✅ Loja ${data.store_id} pertence ao usuário`);
      } else {
        console.log(`❌ Loja ${data.store_id} NÃO pertence ao usuário (owner: ${lojaData.ownerUid})`);
        allTestsPassed = false;
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // TESTE 4: Loja do Root (slug)
  // ═══════════════════════════════════════════════════════
  console.log('\n🧪 TESTE 4: Loja do Root (slug: masterpalm)');
  console.log('─────────────────────────────────────────────────────');

  const rootLojaSlug = await db.collection('lojas').doc('masterpalm').get();

  if (!rootLojaSlug.exists) {
    console.log('❌ Loja masterpalm NÃO existe');
    allTestsPassed = false;
  } else {
    const data = rootLojaSlug.data();

    console.log(`✅ Loja existe`);
    console.log(`   - Owner: ${data.owner}`);
    console.log(`   - OwnerUid: ${data.ownerUid}`);
    console.log(`   - RedirectTo: ${data.redirectTo || 'N/A (loja principal)'}`);

    if (data.redirectTo) {
      console.log(`❌ Loja PRINCIPAL não deveria ter redirectTo!`);
      allTestsPassed = false;
    }

    // Verificar config
    const config = await db.collection('lojas').doc('masterpalm').collection('config').doc('config').get();
    if (!config.exists) {
      console.log(`❌ Config NÃO existe`);
      allTestsPassed = false;
    } else {
      const configData = config.data();
      console.log(`✅ Config existe`);
      console.log(`   - Banners mobile: ${configData.bannersMobile?.length || 0}`);
    }
  }

  // ═══════════════════════════════════════════════════════
  // TESTE 5: Usuário do Root
  // ═══════════════════════════════════════════════════════
  console.log('\n🧪 TESTE 5: Usuário do Root (/users/vd0X6xXlq4be0cKhmIOiDtXTvKb2)');
  console.log('─────────────────────────────────────────────────────');

  const rootUser = await db.collection('users').doc('vd0X6xXlq4be0cKhmIOiDtXTvKb2').get();

  if (!rootUser.exists) {
    console.log('❌ Usuário NÃO existe');
    allTestsPassed = false;
  } else {
    const data = rootUser.data();

    console.log(`✅ Usuário existe`);
    console.log(`   - Email: ${data.email}`);
    console.log(`   - store_id: ${data.store_id}`);

    if (data.store_id !== 'masterpalm') {
      console.log(`❌ store_id incorreto! Esperado: masterpalm`);
      allTestsPassed = false;
    } else {
      console.log(`✅ store_id correto (slug)`);
    }
  }

  // ═══════════════════════════════════════════════════════
  // TESTE 6: Não há UIDs duplicados
  // ═══════════════════════════════════════════════════════
  console.log('\n🧪 TESTE 6: Verificar UIDs duplicados');
  console.log('─────────────────────────────────────────────────────');

  const uidErrado = await db.collection('users').doc('c4NemqNa28YDmSrykCCXZdShztG3').get();

  if (uidErrado.exists) {
    console.log('❌ UID duplicado c4NemqNa28YDmSrykCCXZdShztG3 ainda existe!');
    allTestsPassed = false;
  } else {
    console.log('✅ UID duplicado c4NemqNa28YDmSrykCCXZdShztG3 foi removido');
  }

  // ═══════════════════════════════════════════════════════
  // TESTE 7: Usuários órfãos
  // ═══════════════════════════════════════════════════════
  console.log('\n🧪 TESTE 7: Verificar usuários órfãos');
  console.log('─────────────────────────────────────────────────────');

  const usersSnapshot = await db.collection('users').get();
  let orphans = 0;

  for (const userDoc of usersSnapshot.docs) {
    const userData = userDoc.data();
    const uid = userDoc.id;

    // Pular root e Naty
    if (uid === 'vd0X6xXlq4be0cKhmIOiDtXTvKb2' || uid === 'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2') continue;

    const storeId = userData.store_id;

    if (storeId) {
      const lojaExists = await db.collection('lojas').doc(storeId).get();
      if (!lojaExists.exists) {
        console.log(`❌ Usuário órfão: ${userData.email || uid} (loja ${storeId} não existe)`);
        orphans++;
      }
    }
  }

  if (orphans > 0) {
    console.log(`❌ ${orphans} usuários órfãos encontrados`);
    allTestsPassed = false;
  } else {
    console.log(`✅ Nenhum usuário órfão (${usersSnapshot.size} usuários no total)`);
  }

  // ═══════════════════════════════════════════════════════
  // RESULTADO FINAL
  // ═══════════════════════════════════════════════════════
  console.log('\n\n' + '═'.repeat(60));

  if (allTestsPassed) {
    console.log('✅ ✅ ✅ TODOS OS TESTES PASSARAM! ✅ ✅ ✅');
    console.log('\n🎉 FIRESTORE ESTÁ 100% CONFIGURADO CORRETAMENTE!');
    console.log('\n📋 Próximos passos:');
    console.log('   1. Fazer deploy do código atualizado');
    console.log('   2. Testar URLs no navegador:');
    console.log('      - https://mastepalm.com.br/loja/nathy-pratas-e-folheados');
    console.log('      - https://mastepalm.com.br/loja/masterpalm');
    console.log('   3. Configurar logo/banners nas lojas (se necessário)');
  } else {
    console.log('❌ ❌ ❌ ALGUNS TESTES FALHARAM ❌ ❌ ❌');
    console.log('\n⚠️  Verifique os erros acima e execute os scripts de correção novamente.');
  }

  console.log('═'.repeat(60) + '\n');

  process.exit(allTestsPassed ? 0 : 1);
}

verifyFinalState();
