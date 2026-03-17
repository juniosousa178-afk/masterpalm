// scripts/setup_roleta_inicial.js
// Script para configurar a roleta inicial para uma loja

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function setupRoletaInicial() {
  console.log('🎰 CONFIGURANDO ROLETA INICIAL\n');
  console.log('════════════════════════════════════════════════════\n');

  const LOJA_ID = 'nathy-pratas-e-folheados';

  // Configuração da roleta
  const configRoleta = {
    ativo: true,
    valorMinimo: 50.0,
    frequenciaPremio: 10, 
    vendasDesdePremio: 0,
    totalVendas: 0,
    premios: [
      {
        label: '10% de Desconto',
        tipo: 'desconto',
        valor: 10.0,
        ativo: true,
      },
      {
        label: 'Frete Grátis',
        tipo: 'freteGratis',
        valor: 0,
        ativo: true,
      },
      {
        label: 'Brinde: Colar de Prata',
        tipo: 'brinde',
        valor: 0,
        ativo: true,
      },
      {
        label: 'R$ 15 de Desconto',
        tipo: 'descontoFixo',
        valor: 15.0,
        ativo: true,
      },
      {
        label: 'Prêmio Surpresa',
        tipo: 'premioSurpresa',
        valor: 0,
        ativo: true,
      },
      {
        label: 'Tente Novamente',
        tipo: 'nenhum',
        valor: 0,
        ativo: true,
      },
    ],
    atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
  };

  try {
    // 1. Criar configuração da roleta
    console.log(`📋 Criando configuração da roleta para loja: ${LOJA_ID}`);

    await db
      .collection('lojas')
      .doc(LOJA_ID)
      .collection('campanhas_sorteio_config')
      .doc('roleta')
      .set(configRoleta, { merge: true });

    console.log('   ✅ Configuração criada com sucesso!\n');

    // 2. Exibir resumo
    console.log('📊 RESUMO DA CONFIGURAÇÃO:');
    console.log(`   Valor mínimo: R$ ${configRoleta.valorMinimo.toFixed(2)}`);
    console.log(`   Frequência: ${configRoleta.frequenciaPremio} `);
    console.log(`   Total de prêmios: ${configRoleta.premios.length}\n`);

    console.log('🎁 PRÊMIOS CONFIGURADOS:');
    configRoleta.premios.forEach((premio, index) => {
      console.log(`   ${index + 1}. ${premio.label} (${premio.tipo})`);
      if (premio.valor > 0) {
        console.log(`      Valor: ${premio.valor}`);
      }
    });

    console.log('\n════════════════════════════════════════════════════');
    console.log('✅ SETUP CONCLUÍDO COM SUCESSO!\n');
    console.log('📝 PRÓXIMOS PASSOS:');
    console.log('   1. Abrir o app admin');
    console.log('   2. Ir em "Roleta da Sorte"');
    console.log('   3. Verificar configuração');
    console.log('   4. Ajustar prêmios se necessário\n');
    console.log('🌐 TESTAR NO CATÁLOGO:');
    console.log(`   https://mastepalm.com.br/loja/${LOJA_ID}`);
    console.log('   - Adicionar R$ 50+ ao carrinho');
    console.log('   - Informar WhatsApp/Email');
    console.log('   - Girar a roleta');
    console.log('════════════════════════════════════════════════════\n');

  } catch (error) {
    console.error('❌ Erro ao configurar roleta:', error);
  } finally {
    process.exit(0);
  }
}

setupRoletaInicial();
