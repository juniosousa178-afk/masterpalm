const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function testWebCatalogFlow() {
  console.log('🌐 SIMULANDO ACESSO WEB: https://mastepalm.com.br/loja/nathy-pratas-e-folheados\n');
  console.log('════════════════════════════════════════════════════\n');

  const slug = 'nathy-pratas-e-folheados';

  // PASSO 1: Resolver lojaId da URL
  console.log(`📋 PASSO 1: URL slug = "${slug}"`);
  let lojaId = slug;

  // PASSO 2: Verificar se existe no Firestore
  console.log(`\n📋 PASSO 2: Verificar se loja "${lojaId}" existe`);
  const lojaDoc = await db.collection('lojas').doc(lojaId).get();

  if (!lojaDoc.exists) {
    console.log(`   ❌ Loja "${lojaId}" NÃO EXISTE!`);
    console.log('   🔴 ERRO: Catálogo vai falhar!\n');
    process.exit(1);
  }

  console.log(`   ✅ Loja "${lojaId}" EXISTE`);

  // PASSO 3: Verificar redirect
  const lojaData = lojaDoc.data();
  const redirectTo = (lojaData.redirectTo || '').trim();

  if (redirectTo) {
    console.log(`\n📋 PASSO 3: Loja tem redirect → "${redirectTo}"`);
    lojaId = redirectTo;
  } else {
    console.log(`\n📋 PASSO 3: Loja NÃO tem redirect`);
  }

  // PASSO 4: Carregar config PUBLICADO (não draft!)
  console.log(`\n📋 PASSO 4: Carregar config PUBLICADO`);
  console.log(`   Caminho: /lojas/${lojaId}/config/config`);

  const configDoc = await db.collection('lojas').doc(lojaId).collection('config').doc('config').get();

  if (!configDoc.exists) {
    console.log(`   ❌ Config NÃO EXISTE!`);
    console.log('   🔴 ERRO: Catálogo vai aparecer VAZIO!\n');
    process.exit(1);
  }

  const configData = configDoc.data();
  console.log(`   ✅ Config EXISTE`);
  console.log(`   - Nome: ${configData.nome || 'VAZIO'}`);
  console.log(`   - Logo Desktop: ${configData.logoDesktopUrl ? 'SIM ✅' : 'NÃO ❌'}`);
  console.log(`   - Logo Mobile: ${configData.logoMobileUrl ? 'SIM ✅' : 'NÃO ❌'}`);
  console.log(`   - Banners Mobile: ${configData.bannersMobile?.length || 0}`);
  console.log(`   - Banners Desktop: ${configData.bannersDesktop?.length || 0}`);
  console.log(`   - Tema primária: ${configData.theme?.primaria || 'VAZIO'}`);
  console.log(`   - WhatsApp: ${configData.whatsapp || 'VAZIO'}`);

  // PASSO 5: Carregar produtos PUBLICADOS
  console.log(`\n📋 PASSO 5: Carregar produtos PUBLICADOS`);
  console.log(`   Caminho: /lojas/${lojaId}/produtos`);

  const produtosSnap = await db.collection('lojas').doc(lojaId).collection('produtos').get();
  console.log(`   Total: ${produtosSnap.size} produtos`);

  if (produtosSnap.size > 0) {
    console.log(`\n   📦 Produtos:`);
    produtosSnap.forEach(doc => {
      const data = doc.data();
      console.log(`   - ${data.nome || 'sem nome'} (ativo: ${data.ativo !== false ? 'SIM' : 'NÃO'})`);
    });
  }

  console.log('\n════════════════════════════════════════════════════');
  console.log('✅ FLUXO DE CARREGAMENTO DO CATÁLOGO WEB:');
  console.log(`   1. URL: https://mastepalm.com.br/loja/nathy-pratas-e-folheados`);
  console.log(`   2. Slug extraído: "${slug}"`);
  console.log(`   3. Loja final: "${lojaId}"`);
  console.log(`   4. Config: lojas/${lojaId}/config/config`);
  console.log(`   5. Produtos: lojas/${lojaId}/produtos`);
  console.log('');
  console.log('🎯 DEVE APARECER NO NAVEGADOR:');
  console.log(`   - Nome: ${configData.nome || 'N/A'}`);
  console.log(`   - Logo: ${configData.logoDesktopUrl ? 'SIM' : 'NÃO'}`);
  console.log(`   - Banners: ${configData.bannersDesktop?.length || 0}`);
  console.log(`   - Produtos: ${produtosSnap.size}`);
  console.log(`   - Tema: ${configData.theme?.primaria ? 'Rosa/Pink' : 'Padrão'}`);
  console.log('');
  console.log('⚠️  SE NÃO APARECER, FAÇA:');
  console.log('   1. Ctrl+Shift+R (Windows) ou Cmd+Shift+R (Mac) para limpar cache');
  console.log('   2. Ou abra em modo anônimo/privado');
  console.log('   3. Ou limpe cache do navegador em Configurações');
  console.log('════════════════════════════════════════════════════\n');

  process.exit(0);
}

testWebCatalogFlow();
