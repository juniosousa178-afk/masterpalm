// Script para verificar o estado do Firestore após a limpeza
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function verifyCleanup() {
  console.log('🔍 Verificando estado do Firestore após limpeza...\n');

  try {
    // Verificar usuários
    console.log('📋 Usuários em /usuarios:');
    const usuarios = await db.collection('usuarios').get();
    usuarios.forEach(doc => {
      const data = doc.data();
      console.log(`   ✅ ${doc.id} (${data.email || 'sem email'}) - Tipo: ${data.tipo || 'N/A'}`);
    });
    console.log(`   Total: ${usuarios.size} usuário(s)\n`);

    // Verificar lojas
    console.log('🏪 Lojas em /lojas:');
    const lojas = await db.collection('lojas').get();
    lojas.forEach(doc => {
      const data = doc.data();
      console.log(`   ✅ ${doc.id}`);
      console.log(`      Nome: ${data.nome || 'N/A'}`);
      console.log(`      Owner: ${data.owner || 'N/A'}`);
      console.log(`      Slug: ${data.slug || 'N/A'}`);
    });
    console.log(`   Total: ${lojas.size} loja(s)\n`);

    // Verificar configuração master
    console.log('⚙️ Configurações Master:');
    const masterConfig = await db.collection('app_config').doc('master_config').get();
    if (masterConfig.exists) {
      const data = masterConfig.data();
      console.log(`   ✅ Master config existe`);
      console.log(`      MP configurado: ${data.mercadoPagoAccessToken ? 'SIM' : 'NÃO'}`);
      console.log(`      Usuários ilimitados: ${data.usersWithUnlimitedAccess?.length || 0}`);
      if (data.usersWithUnlimitedAccess && data.usersWithUnlimitedAccess.length > 0) {
        data.usersWithUnlimitedAccess.forEach(user => {
          console.log(`         - ${user}`);
        });
      }
    } else {
      console.log('   ⚠️ Master config não encontrado');
    }
    console.log();

    // Verificar planos
    console.log('💳 Planos de Assinatura:');
    const planos = await db.collection('planos').get();
    planos.forEach(doc => {
      const data = doc.data();
      console.log(`   ✅ ${doc.id}: ${data.nome || 'N/A'} - R$ ${data.preco || 0}`);
    });
    console.log(`   Total: ${planos.size} plano(s)\n`);

    // Verificar coleções vazias
    console.log('📦 Coleções que devem estar vazias:');

    const prePedidos = await db.collection('pre_pedidos').limit(1).get();
    console.log(`   ${prePedidos.empty ? '✅' : '❌'} pre_pedidos: ${prePedidos.size} documento(s)`);

    const checkouts = await db.collection('checkout_planos').limit(1).get();
    console.log(`   ${checkouts.empty ? '✅' : '❌'} checkout_planos: ${checkouts.size} documento(s)`);

    const campanhas = await db.collection('campanhas_sorteio').limit(1).get();
    console.log(`   ${campanhas.empty ? '✅' : '❌'} campanhas_sorteio: ${campanhas.size} documento(s)`);

    const clientes = await db.collection('clientes_globais').limit(1).get();
    console.log(`   ${clientes.empty ? '✅' : '❌'} clientes_globais: ${clientes.size} documento(s)`);

    console.log('\n✅ Verificação concluída!');

  } catch (error) {
    console.error('❌ Erro durante verificação:', error);
  }

  process.exit(0);
}

verifyCleanup();
