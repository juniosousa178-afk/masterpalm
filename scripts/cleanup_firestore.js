// Script para limpar Firestore mantendo apenas masterpalm@gmail.com
// Execute com: node scripts/cleanup_firestore.js

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();
const auth = admin.auth();

// Email do programador root que deve ser mantido
const ROOT_EMAIL = 'masterpalm@gmail.com';
const ROOT_EMAIL_SLUG = 'masterpalm_gmail_com';

// Função para deletar documentos em lote
async function deleteCollection(collectionPath, batchSize = 100) {
  const collectionRef = db.collection(collectionPath);
  const query = collectionRef.limit(batchSize);

  return new Promise((resolve, reject) => {
    deleteQueryBatch(query, resolve).catch(reject);
  });
}

async function deleteQueryBatch(query, resolve) {
  const snapshot = await query.get();

  const batchSize = snapshot.size;
  if (batchSize === 0) {
    resolve();
    return;
  }

  const batch = db.batch();
  snapshot.docs.forEach((doc) => {
    batch.delete(doc.ref);
  });
  await batch.commit();

  process.nextTick(() => {
    deleteQueryBatch(query, resolve);
  });
}

// Função para deletar subcoleções recursivamente
async function deleteDocumentWithSubcollections(docRef) {
  const subcollections = await docRef.listCollections();

  for (const subcollection of subcollections) {
    await deleteCollection(subcollection.path);
  }

  await docRef.delete();
}

async function cleanupFirestore() {
  console.log('🧹 Iniciando limpeza do Firestore...\n');

  try {
    // 1. Buscar UID do usuário root
    console.log('1️⃣ Buscando usuário root...');
    let rootUid = null;
    try {
      const rootUser = await auth.getUserByEmail(ROOT_EMAIL);
      rootUid = rootUser.uid;
      console.log(`✅ Usuário root encontrado: ${ROOT_EMAIL} (UID: ${rootUid})`);
    } catch (error) {
      console.log(`⚠️ Usuário root não encontrado no Firebase Auth`);
    }

    // 2. Limpar usuários do Firebase Authentication (exceto root)
    console.log('\n2️⃣ Limpando usuários do Firebase Authentication...');
    let deletedAuthUsers = 0;
    const listAllUsers = async (nextPageToken) => {
      const result = await auth.listUsers(1000, nextPageToken);

      for (const user of result.users) {
        if (user.email !== ROOT_EMAIL && user.uid !== rootUid) {
          try {
            await auth.deleteUser(user.uid);
            deletedAuthUsers++;
            console.log(`   ❌ Deletado: ${user.email || user.uid}`);
          } catch (error) {
            console.log(`   ⚠️ Erro ao deletar ${user.email}: ${error.message}`);
          }
        }
      }

      if (result.pageToken) {
        await listAllUsers(result.pageToken);
      }
    };
    await listAllUsers();
    console.log(`✅ ${deletedAuthUsers} usuários removidos do Authentication`);

    // 3. Limpar coleção usuarios (exceto root)
    console.log('\n3️⃣ Limpando coleção /usuarios...');
    const usuariosSnapshot = await db.collection('usuarios').get();
    let deletedUsuarios = 0;
    for (const doc of usuariosSnapshot.docs) {
      const data = doc.data();
      if (data.email !== ROOT_EMAIL && doc.id !== ROOT_EMAIL && doc.id !== rootUid) {
        await doc.ref.delete();
        deletedUsuarios++;
        console.log(`   ❌ Deletado: ${doc.id}`);
      } else {
        console.log(`   ✅ Mantido: ${doc.id} (root)`);
      }
    }
    console.log(`✅ ${deletedUsuarios} usuários removidos de /usuarios`);

    // 4. Limpar coleção lojas (exceto loja do root)
    console.log('\n4️⃣ Limpando coleção /lojas...');
    const lojasSnapshot = await db.collection('lojas').get();
    let deletedLojas = 0;
    for (const doc of lojasSnapshot.docs) {
      const data = doc.data();
      const isRootStore = doc.id === ROOT_EMAIL_SLUG ||
                         doc.id === `loja_uid_${rootUid}` ||
                         data.owner === ROOT_EMAIL ||
                         data.owner === rootUid;

      if (!isRootStore) {
        // Deletar com subcoleções
        await deleteDocumentWithSubcollections(doc.ref);
        deletedLojas++;
        console.log(`   ❌ Deletado: ${doc.id}`);
      } else {
        console.log(`   ✅ Mantido: ${doc.id} (loja do root)`);
      }
    }
    console.log(`✅ ${deletedLojas} lojas removidas`);

    // 5. Limpar coleções relacionadas a vendas e pedidos
    console.log('\n5️⃣ Limpando coleção /pre_pedidos...');
    await deleteCollection('pre_pedidos');
    console.log('✅ Todos os pré-pedidos removidos');

    console.log('\n6️⃣ Limpando coleção /checkout_planos...');
    await deleteCollection('checkout_planos');
    console.log('✅ Todos os checkouts removidos');

    console.log('\n7️⃣ Limpando coleção /campanhas_sorteio...');
    await deleteCollection('campanhas_sorteio');
    console.log('✅ Todas as campanhas removidas');

    console.log('\n8️⃣ Limpando coleção /assinaturas...');
    const assinaturasSnapshot = await db.collection('assinaturas').get();
    let deletedAssinaturas = 0;
    for (const doc of assinaturasSnapshot.docs) {
      const data = doc.data();
      if (data.userId !== rootUid && data.userEmail !== ROOT_EMAIL) {
        await doc.ref.delete();
        deletedAssinaturas++;
      }
    }
    console.log(`✅ ${deletedAssinaturas} assinaturas removidas`);

    // 9. Limpar coleção /clientes_globais
    console.log('\n9️⃣ Limpando coleção /clientes_globais...');
    await deleteCollection('clientes_globais');
    console.log('✅ Todos os clientes globais removidos');

    // 10. Manter configurações essenciais
    console.log('\n🔟 Mantendo coleções essenciais:');
    console.log('   ✅ /app_config (configurações master)');
    console.log('   ✅ /planos (planos de assinatura)');
    console.log('   ✅ Loja do root em /lojas');
    console.log('   ✅ Usuário root em /usuarios');

    console.log('\n✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('✅ LIMPEZA CONCLUÍDA COM SUCESSO!');
    console.log('✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('\n📊 Resumo:');
    console.log(`   - Usuários Auth removidos: ${deletedAuthUsers}`);
    console.log(`   - Documentos /usuarios removidos: ${deletedUsuarios}`);
    console.log(`   - Lojas removidas: ${deletedLojas}`);
    console.log(`   - Assinaturas removidas: ${deletedAssinaturas}`);
    console.log(`   - Usuário mantido: ${ROOT_EMAIL}`);
    console.log(`\n✨ Firestore pronto para novos cadastros!`);

  } catch (error) {
    console.error('❌ Erro durante a limpeza:', error);
    process.exit(1);
  }

  process.exit(0);
}

// Confirmação antes de executar
console.log('⚠️  ATENÇÃO! Este script irá:');
console.log('   - Deletar TODOS os usuários exceto masterpalm@gmail.com');
console.log('   - Deletar TODAS as lojas exceto a do root');
console.log('   - Deletar TODOS os pedidos, checkouts, campanhas');
console.log('   - Esta ação NÃO PODE SER DESFEITA!\n');

const readline = require('readline').createInterface({
  input: process.stdin,
  output: process.stdout
});

readline.question('Digite "CONFIRMAR" para continuar: ', (answer) => {
  if (answer === 'CONFIRMAR') {
    readline.close();
    cleanupFirestore();
  } else {
    console.log('❌ Operação cancelada.');
    readline.close();
    process.exit(0);
  }
});
