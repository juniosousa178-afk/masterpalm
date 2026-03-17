// Script para verificar configuração de catálogo no Firestore
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkCatalogConfig() {
  console.log('🔍 Verificando configuração de catálogo no Firestore...\n');

  try {
    // Listar todas as lojas
    const lojasSnapshot = await db.collection('lojas').get();

    console.log(`📊 Total de lojas: ${lojasSnapshot.size}\n`);

    for (const lojaDoc of lojasSnapshot.docs) {
      const lojaId = lojaDoc.id;
      console.log(`\n${'='.repeat(80)}`);
      console.log(`🏪 Loja: ${lojaId}`);
      console.log(`${'='.repeat(80)}`);

      // Verificar config LIVE
      const configLiveRef = db.collection('lojas').doc(lojaId).collection('config').doc('config');
      const configLiveSnap = await configLiveRef.get();

      if (configLiveSnap.exists) {
        const data = configLiveSnap.data();
        console.log('\n✅ CONFIG (LIVE - publicado):');
        console.log(`   Caminho: lojas/${lojaId}/config/config`);

        // Verificar banner/logo
        const media = data.media || {};
        const desktop = media.desktop || {};
        const mobile = media.mobile || {};

        console.log('\n   📱 MEDIA:');
        console.log(`      Desktop Logo: ${desktop.logoUrl || 'NÃO CONFIGURADO'}`);
        console.log(`      Desktop Banners: ${JSON.stringify(desktop.banners || [])}`);
        console.log(`      Mobile Logo: ${mobile.logoUrl || 'NÃO CONFIGURADO'}`);
        console.log(`      Mobile Banners: ${JSON.stringify(mobile.banners || [])}`);

        // Verificar campos legados
        console.log('\n   📄 CAMPOS LEGADOS:');
        console.log(`      logoDesktopUrl: ${data.logoDesktopUrl || 'vazio'}`);
        console.log(`      logoMobileUrl: ${data.logoMobileUrl || 'vazio'}`);
        console.log(`      bannersDesktop: ${JSON.stringify(data.bannersDesktop || [])}`);
        console.log(`      bannersMobile: ${JSON.stringify(data.bannersMobile || [])}`);

        // Verificar tema
        const theme = data.theme || {};
        console.log('\n   🎨 TEMA:');
        console.log(`      Fundo: ${theme.fundo || 'não configurado'}`);
        console.log(`      Card: ${theme.card || 'não configurado'}`);
        console.log(`      Texto: ${theme.texto || 'não configurado'}`);
        console.log(`      Primária: ${theme.primaria || 'não configurado'}`);

      } else {
        console.log('\n❌ CONFIG (LIVE) não existe');
      }

      // Verificar draft_config
      const configDraftRef = db.collection('lojas').doc(lojaId).collection('draft_config').doc('config');
      const configDraftSnap = await configDraftRef.get();

      if (configDraftSnap.exists) {
        const data = configDraftSnap.data();
        console.log('\n📝 DRAFT_CONFIG (rascunho):');
        console.log(`   Caminho: lojas/${lojaId}/draft_config/config`);

        const media = data.media || {};
        const desktop = media.desktop || {};
        const mobile = media.mobile || {};

        console.log('\n   📱 MEDIA:');
        console.log(`      Desktop Logo: ${desktop.logoUrl || 'NÃO CONFIGURADO'}`);
        console.log(`      Desktop Banners: ${JSON.stringify(desktop.banners || [])}`);
        console.log(`      Mobile Logo: ${mobile.logoUrl || 'NÃO CONFIGURADO'}`);
        console.log(`      Mobile Banners: ${JSON.stringify(mobile.banners || [])}`);
      } else {
        console.log('\n⚠️ DRAFT_CONFIG não existe');
      }

      // Verificar produtos
      const produtosLive = await db.collection('lojas').doc(lojaId).collection('produtos').limit(5).get();
      console.log(`\n📦 Produtos (LIVE): ${produtosLive.size} produtos (amostra de 5)`);

      if (!produtosLive.empty) {
        produtosLive.forEach(doc => {
          const data = doc.data();
          console.log(`   - ${data.nome || 'sem nome'} | Estoque: ${data.estoque || data.quantidade || 0} | Catálogo: ${data.exibir_no_catalogo !== false && data.ocultar_catalogo !== true && data.catalog_ativo !== false ? 'SIM' : 'NÃO'}`);
        });
      }
    }

    console.log('\n\n✅ Verificação concluída!');

  } catch (error) {
    console.error('❌ Erro durante verificação:', error);
  }

  process.exit(0);
}

checkCatalogConfig();
