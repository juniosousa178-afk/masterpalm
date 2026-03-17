/**
 * Script: Corrigir lojas e usuários no Firestore
 *
 * Correções:
 * 1. masterpalm@gmail.com → loja "masterpalm", role "programador"
 * 2. juniosousa178@gmail.com → loja "master", role "admin"
 */

const admin = require('firebase-admin');

// Inicializar Firebase Admin
if (!admin.apps.length) {
  const serviceAccount = require('../masterpalm-service-account.json');
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const db = admin.firestore();
const auth = admin.auth();

// Configuração das correções
const CORRECOES = [
  {
    email: 'masterpalm@gmail.com',
    targetStore: 'masterpalm',
    role: 'programador',
    isRoot: true,
    descricao: 'Usuário MASTER do sistema',
  },
  {
    email: 'juniosousa178@gmail.com',
    targetStore: 'master',
    role: 'admin',
    isRoot: false,
    descricao: 'Admin da loja master (Junio)',
  },
];

async function getUidByEmail(email) {
  try {
    const user = await auth.getUserByEmail(email);
    return user.uid;
  } catch (e) {
    console.log(`   ⚠️ Usuário ${email} não encontrado no Auth: ${e.message}`);
    return null;
  }
}

async function corrigirUsuario(config) {
  console.log('');
  console.log('━'.repeat(60));
  console.log(`🔧 CORRIGINDO: ${config.email}`);
  console.log(`   → Loja: ${config.targetStore}`);
  console.log(`   → Role: ${config.role}`);
  console.log('━'.repeat(60));

  const uid = await getUidByEmail(config.email);
  if (!uid) {
    console.log(`   ❌ Não foi possível obter UID para ${config.email}`);
    return false;
  }

  console.log(`   UID: ${uid}`);

  try {
    // 1. Atualizar/criar loja
    console.log(`\n1️⃣ Verificando loja "${config.targetStore}"...`);
    const lojaRef = db.collection('lojas').doc(config.targetStore);
    const lojaDoc = await lojaRef.get();

    if (lojaDoc.exists) {
      // Atualizar ownerUid
      await lojaRef.update({
        ownerUid: uid,
        ownerEmail: config.email,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`   ✅ Loja atualizada - ownerUid: ${uid}`);
    } else {
      // Criar loja
      await lojaRef.set({
        id: config.targetStore,
        lojaId: config.targetStore,
        slug: config.targetStore,
        nome: config.targetStore.charAt(0).toUpperCase() + config.targetStore.slice(1),
        ownerUid: uid,
        ownerEmail: config.email,
        ativa: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`   ✅ Loja criada - ${config.targetStore}`);
    }

    // 2. Atualizar collection 'usuarios' (por email)
    console.log(`\n2️⃣ Atualizando usuarios/${config.email}...`);
    await db.collection('usuarios').doc(config.email).set({
      email: config.email,
      tipo: config.role,
      role: config.role,
      store_id: config.targetStore,
      ownerStoreId: config.targetStore,
      authUid: uid,
      is_root: config.isRoot,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    console.log(`   ✅ usuarios/${config.email} atualizado`);

    // 3. Atualizar collection 'users' (por uid)
    console.log(`\n3️⃣ Atualizando users/${uid}...`);
    await db.collection('users').doc(uid).set({
      email: config.email,
      tipo: config.role,
      role: config.role,
      tipo_usuario: config.role,
      store_id: config.targetStore,
      storeId: config.targetStore,
      ownerOf: config.targetStore,
      is_root: config.isRoot,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    console.log(`   ✅ users/${uid} atualizado`);

    // 4. Verificar resultado
    console.log(`\n4️⃣ Verificação final...`);

    const usuarioDoc = await db.collection('usuarios').doc(config.email).get();
    const userData = usuarioDoc.data() || {};
    console.log(`   usuarios/${config.email}:`);
    console.log(`     - tipo: ${userData.tipo}`);
    console.log(`     - store_id: ${userData.store_id}`);
    console.log(`     - is_root: ${userData.is_root}`);

    const userDoc = await db.collection('users').doc(uid).get();
    const userDocData = userDoc.data() || {};
    console.log(`   users/${uid}:`);
    console.log(`     - role: ${userDocData.role}`);
    console.log(`     - store_id: ${userDocData.store_id}`);
    console.log(`     - is_root: ${userDocData.is_root}`);

    const lojaFinalDoc = await lojaRef.get();
    const lojaData = lojaFinalDoc.data() || {};
    console.log(`   lojas/${config.targetStore}:`);
    console.log(`     - ownerUid: ${lojaData.ownerUid}`);
    console.log(`     - ownerEmail: ${lojaData.ownerEmail}`);

    console.log(`\n✅ ${config.email} corrigido com sucesso!`);
    return true;
  } catch (e) {
    console.error(`\n❌ Erro ao corrigir ${config.email}:`, e);
    return false;
  }
}

async function main() {
  console.log('');
  console.log('═'.repeat(60));
  console.log('🔧 SCRIPT DE CORREÇÃO DE LOJAS E USUÁRIOS');
  console.log('═'.repeat(60));
  console.log('');

  let sucessos = 0;
  let falhas = 0;

  for (const config of CORRECOES) {
    const ok = await corrigirUsuario(config);
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
  console.log('💡 Os usuários devem fazer LOGOUT e LOGIN novamente.');
  console.log('═'.repeat(60));

  process.exit(falhas > 0 ? 1 : 0);
}

main().catch(e => {
  console.error('❌ Erro fatal:', e);
  process.exit(1);
});
