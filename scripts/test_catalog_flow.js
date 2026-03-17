// Script para testar o fluxo completo do catálogo
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function testCatalogFlow() {
  console.log('🧪 ════════════════════════════════════════════════════');
  console.log('🧪 TESTE DE FLUXO DO CATÁLOGO');
  console.log('🧪 ════════════════════════════════════════════════════\n');

  // ═══════════════════════════════════════════════════════
  // TESTE 1: Simular acesso via URL da Naty
  // ═══════════════════════════════════════════════════════
  console.log('\n📱 TESTE 1: URL https://mastepalm.com.br/loja/nathy-pratas-e-folheados');
  console.log('─────────────────────────────────────────────────────');

  const slug1 = 'nathy-pratas-e-folheados';
  console.log(`\n1️⃣ catalog_web.dart extrai slug: "${slug1}"`);
  console.log(`2️⃣ PublicCatalogScreen recebe lojaId: "${slug1}"`);
  console.log(`3️⃣ _resolveLojaId() verifica se loja existe...`);

  const loja1 = await db.collection('lojas').doc(slug1).get();

  if (!loja1.exists) {
    console.log(`❌ ERRO: Loja "${slug1}" NÃO existe no Firestore!`);
    return;
  }

  const loja1Data = loja1.data();
  console.log(`✅ Loja existe:`);
  console.log(`   - Nome: ${loja1Data.nome}`);
  console.log(`   - Owner: ${loja1Data.owner}`);
  console.log(`   - OwnerUid: ${loja1Data.ownerUid}`);
  console.log(`   - RedirectTo: ${loja1Data.redirectTo || 'N/A (sem redirect)'}`);

  let finalLojaId = slug1;

  if (loja1Data.redirectTo) {
    console.log(`\n4️⃣ 🔀 REDIRECT detectado: "${slug1}" → "${loja1Data.redirectTo}"`);
    finalLojaId = loja1Data.redirectTo;

    const lojaRedirect = await db.collection('lojas').doc(finalLojaId).get();
    if (!lojaRedirect.exists) {
      console.log(`❌ ERRO: Loja de redirect "${finalLojaId}" NÃO existe!`);
      return;
    }

    const lojaRedirectData = lojaRedirect.data();
    console.log(`✅ Loja final (após redirect):`);
    console.log(`   - Nome: ${lojaRedirectData.nome}`);
    console.log(`   - Owner: ${lojaRedirectData.owner}`);
  } else {
    console.log(`\n4️⃣ ✅ Sem redirect, usa loja "${slug1}"`);
  }

  console.log(`\n5️⃣ Carregando configurações de: /lojas/${finalLojaId}/config/config`);

  const config1 = await db.collection('lojas').doc(finalLojaId).collection('config').doc('config').get();

  if (!config1.exists) {
    console.log(`❌ ERRO: Config NÃO existe em /lojas/${finalLojaId}/config/config`);
  } else {
    const configData = config1.data();
    console.log(`✅ Config carregada:`);
    console.log(`   - logoDesktop: ${configData.logoDesktop ? '✅ SIM' : '❌ NÃO'}`);
    console.log(`   - logoMobile: ${configData.logoMobile ? '✅ SIM' : '❌ NÃO'}`);
    console.log(`   - bannersMobile: ${configData.bannersMobile ? `✅ ${configData.bannersMobile.length} banners` : '❌ NÃO'}`);
    console.log(`   - bannersDesktop: ${configData.bannersDesktop ? `✅ ${configData.bannersDesktop.length} banners` : '❌ NÃO'}`);

    if (configData.logoDesktop) {
      console.log(`\n   📸 logoDesktop URL: ${configData.logoDesktop}`);
    }

    if (configData.bannersMobile && configData.bannersMobile.length > 0) {
      console.log(`\n   📸 bannersMobile:`);
      configData.bannersMobile.forEach((banner, i) => {
        console.log(`      [${i + 1}] ${banner}`);
      });
    }
  }

  // Verificar produtos
  const produtos1 = await db.collection('lojas').doc(finalLojaId).collection('produtos').get();
  console.log(`\n6️⃣ Produtos: ${produtos1.size}`);

  // ═══════════════════════════════════════════════════════
  // TESTE 2: Verificar login da Naty no app
  // ═══════════════════════════════════════════════════════
  console.log('\n\n📱 TESTE 2: Login da Naty no app (natypolylopes1997@gmail.com)');
  console.log('─────────────────────────────────────────────────────');

  const natyUid = 'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2';
  console.log(`\n1️⃣ Usuário faz login, UID: ${natyUid}`);
  console.log(`2️⃣ StoreResolverService.resolve() consulta /users/${natyUid}...`);

  const natyUser = await db.collection('users').doc(natyUid).get();

  if (!natyUser.exists) {
    console.log(`❌ ERRO: Usuário /users/${natyUid} NÃO existe!`);
    return;
  }

  const natyUserData = natyUser.data();
  console.log(`✅ Usuário encontrado:`);
  console.log(`   - Email: ${natyUserData.email}`);
  console.log(`   - store_id: ${natyUserData.store_id}`);
  console.log(`   - lojaId: ${natyUserData.lojaId}`);

  console.log(`\n3️⃣ StoreResolverService retorna: "${natyUserData.store_id}"`);
  console.log(`4️⃣ PublicCatalogScreen usa lojaId: "${natyUserData.store_id}"`);

  const loja2 = await db.collection('lojas').doc(natyUserData.store_id).get();

  if (!loja2.exists) {
    console.log(`❌ ERRO: Loja "${natyUserData.store_id}" NÃO existe!`);
    return;
  }

  const loja2Data = loja2.data();
  console.log(`✅ Loja carregada:`);
  console.log(`   - Nome: ${loja2Data.nome}`);
  console.log(`   - OwnerUid: ${loja2Data.ownerUid}`);

  // Verificar se pertence ao usuário
  if (loja2Data.ownerUid === natyUid) {
    console.log(`✅ Loja pertence ao usuário (match de UID)`);
  } else {
    console.log(`❌ ERRO: Loja NÃO pertence ao usuário!`);
    console.log(`   - OwnerUid da loja: ${loja2Data.ownerUid}`);
    console.log(`   - UID do usuário: ${natyUid}`);
  }

  // ═══════════════════════════════════════════════════════
  // TESTE 3: Verificar qual loja TEM logo/banners
  // ═══════════════════════════════════════════════════════
  console.log('\n\n📱 TESTE 3: Verificar TODAS as lojas com logo/banners');
  console.log('─────────────────────────────────────────────────────');

  const todasLojas = await db.collection('lojas').get();

  for (const lojaDoc of todasLojas.docs) {
    const lojaId = lojaDoc.id;
    const lojaData = lojaDoc.data();

    const config = await db.collection('lojas').doc(lojaId).collection('config').doc('config').get();

    if (config.exists) {
      const configData = config.data();

      const hasLogo = configData.logoDesktop || configData.logoMobile;
      const hasBanners = (configData.bannersMobile && configData.bannersMobile.length > 0) ||
                         (configData.bannersDesktop && configData.bannersDesktop.length > 0);

      if (hasLogo || hasBanners) {
        console.log(`\n📦 ${lojaId}:`);
        console.log(`   - Nome: ${lojaData.nome}`);
        console.log(`   - Owner: ${lojaData.owner}`);
        console.log(`   - RedirectTo: ${lojaData.redirectTo || 'N/A'}`);

        if (configData.logoDesktop) {
          console.log(`   - ✅ logoDesktop: ${configData.logoDesktop.substring(0, 60)}...`);
        }
        if (configData.logoMobile) {
          console.log(`   - ✅ logoMobile: ${configData.logoMobile.substring(0, 60)}...`);
        }
        if (configData.bannersMobile && configData.bannersMobile.length > 0) {
          console.log(`   - ✅ bannersMobile: ${configData.bannersMobile.length} banners`);
        }
        if (configData.bannersDesktop && configData.bannersDesktop.length > 0) {
          console.log(`   - ✅ bannersDesktop: ${configData.bannersDesktop.length} banners`);
        }
      }
    }
  }

  console.log('\n════════════════════════════════════════════════════\n');

  process.exit(0);
}

testCatalogFlow();
