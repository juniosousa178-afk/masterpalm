// Script para verificar qual loja está ativa baseado na URL da screenshot
// URL mostrada: mastepalm.com.br/loja/mast...

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkAllStores() {
  console.log('🔍 Verificando TODAS as lojas e produtos com estoque...\n');

  try {
    const lojasSnapshot = await db.collection('lojas').get();

    for (const lojaDoc of lojasSnapshot.docs) {
      const lojaId = lojaDoc.id;
      const lojaData = lojaDoc.data();

      console.log(`\n${'='.repeat(80)}`);
      console.log(`🏪 Loja ID: ${lojaId}`);
      console.log(`   Nome: ${lojaData.nome || 'não definido'}`);
      console.log(`   Slug: ${lojaData.slug || 'não definido'}`);
      console.log(`${'='.repeat(80)}`);

      // Buscar TODOS os produtos (incluindo sem estoque e draft)
      const produtosLive = await db.collection('lojas').doc(lojaId).collection('produtos').get();
      const produtosDraft = await db.collection('lojas').doc(lojaId).collection('draft_produtos').get();

      console.log(`\n📦 Produtos LIVE: ${produtosLive.size}`);
      if (produtosLive.size > 0) {
        produtosLive.forEach(doc => {
          const data = doc.data();
          const estoque = data.estoque || data.estoqueAtual || data.qtd_estoque || data.quantidade || data.estoque_disponivel || 0;
          console.log(`   - ${data.nome || 'sem nome'} | Estoque: ${estoque} | Ativo: ${data.ativo !== false}`);
        });
      }

      console.log(`\n📝 Produtos DRAFT: ${produtosDraft.size}`);
      if (produtosDraft.size > 0) {
        produtosDraft.forEach(doc => {
          const data = doc.data();
          const estoque = data.estoque || data.estoqueAtual || data.qtd_estoque || data.quantidade || data.estoque_disponivel || 0;
          console.log(`   - ${data.nome || 'sem nome'} | Estoque: ${estoque} | Ativo: ${data.ativo !== false}`);
        });
      }

      // Verificar config
      const configLive = await db.collection('lojas').doc(lojaId).collection('config').doc('config').get();
      if (configLive.exists) {
        const cfg = configLive.data();
        const media = cfg.media || {};
        console.log(`\n⚙️ CONFIG LIVE:`);
        console.log(`   Logo Mobile: ${media.mobile?.logoUrl ? 'CONFIGURADO' : 'NÃO CONFIGURADO'}`);
        console.log(`   Banners Mobile: ${media.mobile?.banners?.length || 0} banner(s)`);
      }
    }

    console.log('\n\n✅ Verificação completa concluída!');

  } catch (error) {
    console.error('❌ Erro:', error);
  }

  process.exit(0);
}

checkAllStores();
