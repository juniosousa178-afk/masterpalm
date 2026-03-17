// Script para encontrar produtos com problemas
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function findDeletedProducts() {
  console.log('🔍 Procurando produtos deletados ou com estoque zerado...\n');

  const lojasSnapshot = await db.collection('lojas').get();

  for (const lojaDoc of lojasSnapshot.docs) {
    const lojaId = lojaDoc.id;
    console.log(`\n🏪 Loja: ${lojaId}`);

    // Verificar produtos LIVE
    const produtosLive = await db.collection('lojas').doc(lojaId).collection('produtos').get();

    console.log(`\n📦 Analisando ${produtosLive.size} produtos LIVE:`);

    const problemProducts = [];

    produtosLive.forEach(doc => {
      const data = doc.data();
      const estoque = data.estoque || data.estoqueAtual || data.qtd_estoque || data.quantidade || data.estoque_disponivel;
      const ativo = data.ativo;

      const problems = [];

      // Verificar se tem estoque zero
      if (estoque === 0 || estoque === '0') {
        problems.push('ESTOQUE ZERO');
      }

      // Verificar se está inativo
      if (ativo === false) {
        problems.push('INATIVO (ativo=false)');
      }

      // Verificar flags de catálogo
      if (data.exibir_no_catalogo === false) {
        problems.push('exibir_no_catalogo=false');
      }
      if (data.ocultar_catalogo === true) {
        problems.push('ocultar_catalogo=true');
      }
      if (data.catalog_ativo === false) {
        problems.push('catalog_ativo=false');
      }

      if (problems.length > 0) {
        problemProducts.push({
          id: doc.id,
          nome: data.nome,
          estoque,
          ativo,
          problems
        });
      }
    });

    if (problemProducts.length > 0) {
      console.log(`\n⚠️  Produtos com PROBLEMAS (${problemProducts.length}):`);
      problemProducts.forEach(p => {
        console.log(`\n   ❌ ${p.nome}`);
        console.log(`      ID: ${p.id}`);
        console.log(`      Estoque: ${p.estoque}`);
        console.log(`      Ativo: ${p.ativo}`);
        console.log(`      Problemas: ${p.problems.join(', ')}`);
        console.log(`      ⚠️  ESTE PRODUTO NÃO DEVERIA APARECER NO CATÁLOGO!`);
      });
    } else {
      console.log(`   ✅ Todos os produtos estão OK`);
    }
  }

  console.log('\n\n✅ Análise concluída!');
  process.exit(0);
}

findDeletedProducts();
