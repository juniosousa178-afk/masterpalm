/**
 * Script: Migrar vendedores existentes para nova estrutura
 *
 * O que faz:
 * 1. Busca todos os usuários com role='vendedor' em users/
 * 2. Para cada vendedor, cria documento em lojas/{storeId}/vendedores/{uid}
 * 3. Atualiza campos storeId, store_id no documento users/{uid}
 *
 * Uso: node functions/scripts/migrar_vendedores.cjs
 */

const admin = require('firebase-admin');

// Inicializar Firebase Admin
if (!admin.apps.length) {
  const serviceAccount = require('../masterpalm-service-account.json');
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const db = admin.firestore();

// Permissões padrão de vendedor
const PERMISSOES_PADRAO = {
  catalogo: false,
  vendas: false,
  estoque: false,
  clientes: false,
  historico_cliente: false,
  meu_perfil: true,
  minhas_comissoes: true,
  meu_link: true,
};

async function migrarVendedor(userDoc) {
  const uid = userDoc.id;
  const data = userDoc.data();

  console.log(`\n📦 Migrando vendedor: ${data.email || uid}`);

  // Buscar storeId
  let storeId = data.storeId || data.store_id || data.lojaId || data.ownerStoreId || '';

  // Se não tem storeId no users, buscar em usuarios/{email}
  if (!storeId && data.email) {
    try {
      const usuarioDoc = await db.collection('usuarios').doc(data.email).get();
      if (usuarioDoc.exists) {
        const usuarioData = usuarioDoc.data();
        storeId = usuarioData.store_id || usuarioData.ownerStoreId || '';
      }
    } catch (e) {
      console.log(`   ⚠️ Erro ao buscar usuario: ${e.message}`);
    }
  }

  if (!storeId) {
    console.log(`   ❌ Sem storeId - pulando`);
    return false;
  }

  console.log(`   → storeId: ${storeId}`);

  try {
    // 1. Atualizar users/{uid} com storeId
    await db.collection('users').doc(uid).update({
      storeId: storeId,
      store_id: storeId,
      tipo: 'vendedor',
      role: 'vendedor',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`   ✅ users/${uid} atualizado`);

    // 2. Criar/atualizar lojas/{storeId}/vendedores/{uid}
    const vendedorRef = db
      .collection('lojas')
      .doc(storeId)
      .collection('vendedores')
      .doc(uid);

    const vendedorDoc = await vendedorRef.get();

    if (vendedorDoc.exists) {
      // Atualizar
      await vendedorRef.update({
        storeId: storeId,
        atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`   ✅ lojas/${storeId}/vendedores/${uid} atualizado`);
    } else {
      // Criar novo
      await vendedorRef.set({
        uid: uid,
        email: data.email || '',
        nome: data.nome || data.name || '',
        telefone: data.telefone || data.phone || '',
        storeId: storeId,
        adminUid: data.ownerId || '',
        adminEmail: data.ownerAdminEmail || '',
        ativo: true,
        permissoes: PERMISSOES_PADRAO,
        comissaoPercentual: null,
        role: 'vendedor',
        tipo: 'vendedor',
        criadoEm: admin.firestore.FieldValue.serverTimestamp(),
        atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`   ✅ lojas/${storeId}/vendedores/${uid} criado`);
    }

    return true;
  } catch (e) {
    console.error(`   ❌ Erro: ${e.message}`);
    return false;
  }
}

async function main() {
  console.log('');
  console.log('═'.repeat(60));
  console.log('🔄 MIGRAÇÃO DE VENDEDORES PARA NOVA ESTRUTURA');
  console.log('═'.repeat(60));

  // Buscar todos os vendedores
  const usersSnapshot = await db
    .collection('users')
    .where('role', '==', 'vendedor')
    .get();

  console.log(`\n📋 Encontrados ${usersSnapshot.size} vendedores com role='vendedor'`);

  // Também buscar por tipo='vendedor'
  const usersSnapshot2 = await db
    .collection('users')
    .where('tipo', '==', 'vendedor')
    .get();

  console.log(`📋 Encontrados ${usersSnapshot2.size} vendedores com tipo='vendedor'`);

  // Combinar (evitar duplicatas)
  const vendedoresMap = new Map();
  usersSnapshot.docs.forEach((doc) => vendedoresMap.set(doc.id, doc));
  usersSnapshot2.docs.forEach((doc) => vendedoresMap.set(doc.id, doc));

  const vendedores = Array.from(vendedoresMap.values());
  console.log(`📋 Total de vendedores únicos: ${vendedores.length}`);

  if (vendedores.length === 0) {
    console.log('\n✅ Nenhum vendedor para migrar.');
    process.exit(0);
  }

  let sucessos = 0;
  let falhas = 0;

  for (const vendedorDoc of vendedores) {
    const ok = await migrarVendedor(vendedorDoc);
    if (ok) {
      sucessos++;
    } else {
      falhas++;
    }
  }

  console.log('');
  console.log('═'.repeat(60));
  console.log('📊 RESUMO');
  console.log('═'.repeat(60));
  console.log(`   ✅ Sucessos: ${sucessos}`);
  console.log(`   ❌ Falhas: ${falhas}`);
  console.log('');
  console.log('💡 Vendedores devem fazer LOGOUT e LOGIN novamente.');
  console.log('═'.repeat(60));

  process.exit(falhas > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error('❌ Erro fatal:', e);
  process.exit(1);
});
