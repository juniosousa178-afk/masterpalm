// Script para verificar produtos no catálogo
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkProductsCatalog() {
  console.log('🔍 Verificando produtos no catálogo...\n');

  try {
    const lojasSnapshot = await db.collection('lojas').get();

    for (const lojaDoc of lojasSnapshot.docs) {
      const lojaId = lojaDoc.id;
      console.log(`\n${'='.repeat(80)}`);
      console.log(`🏪 Loja: ${lojaId}`);
      console.log(`${'='.repeat(80)}`);

      // Produtos LIVE (publicados no catálogo web)
      const produtosLive = await db.collection('lojas').doc(lojaId).collection('produtos').get();

      console.log(`\n📦 Total de produtos LIVE: ${produtosLive.size}`);

      if (!produtosLive.empty) {
        console.log('\nDetalhamento dos produtos:');
        produtosLive.forEach(doc => {
          const data = doc.data();
          const estoque = data.estoque || data.estoqueAtual || data.qtd_estoque || data.quantidade || data.estoque_disponivel || 0;
          const exibirCatalogo = !(
            data.exibir_no_catalogo === false ||
            data.ocultar_catalogo === true ||
            data.catalog_ativo === false
          );
          const ativo = data.ativo !== false;

          const mostrarNoCatalogo = ativo && exibirCatalogo && estoque > 0;

          console.log(`\n   📦 ${doc.id}`);
          console.log(`      Nome: ${data.nome || 'sem nome'}`);
          console.log(`      Ativo: ${ativo ? 'SIM' : 'NÃO'}`);
          console.log(`      Estoque: ${estoque}`);
          console.log(`      exibir_no_catalogo: ${data.exibir_no_catalogo !== undefined ? data.exibir_no_catalogo : 'não definido'}`);
          console.log(`      ocultar_catalogo: ${data.ocultar_catalogo || 'não definido'}`);
          console.log(`      catalog_ativo: ${data.catalog_ativo !== undefined ? data.catalog_ativo : 'não definido'}`);
          console.log(`      ➡️  DEVE APARECER NO CATÁLOGO: ${mostrarNoCatalogo ? '✅ SIM' : '❌ NÃO'}`);

          if (ativo && !mostrarNoCatalogo) {
            if (estoque <= 0) {
              console.log(`      ⚠️  PROBLEMA: Produto ativo mas sem estoque!`);
            }
            if (!exibirCatalogo) {
              console.log(`      ⚠️  PROBLEMA: Produto ativo mas oculto do catálogo!`);
            }
          }
        });
      }
    }

    console.log('\n\n✅ Verificação concluída!');

  } catch (error) {
    console.error('❌ Erro durante verificação:', error);
  }

  process.exit(0);
}

checkProductsCatalog();
