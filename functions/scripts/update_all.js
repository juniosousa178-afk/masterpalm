// functions/scripts/update_all.js
// Rodar localmente: `npm run seed` (na pasta functions)
// Requer: credenciais do Firebase Admin no ambiente
//   - Linux/Mac: export GOOGLE_APPLICATION_CREDENTIALS="./serviceAccount.json"
//   - Windows PowerShell: $env:GOOGLE_APPLICATION_CREDENTIALS="C:\\caminho\\serviceAccount.json"

import 'dotenv/config';
import admin from 'firebase-admin';

function initAdmin() {
  try {
    // Se GOOGLE_APPLICATION_CREDENTIALS estiver definida, o Admin usa automaticamente.
    if (admin.apps.length === 0) {
      admin.initializeApp();
    }
  } catch (err) {
    console.error('Falha ao inicializar firebase-admin:', err);
    process.exit(1);
  }
  return {
    db: admin.firestore(),
  };
}

function parseArgs() {
  const args = process.argv.slice(2);
  const out = { loja: null };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if ((a === '--loja' || a === '-l') && args[i + 1]) {
      out.loja = args[i + 1].trim().toLowerCase();
      i++;
    }
  }
  return out;
}

async function ensureSettings(db, lojaId, whatsE164 = '') {
  const ref = db.collection('lojas').doc(lojaId).collection('settings').doc('general');
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set({
      whatsappE164: whatsE164 || '',
      theme: {
        primary: '#00C853',
        bg: '#FFFFFF',
        text: '#111111',
      },
      catalog: { public: true },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`  [+] settings/general criado`);
  } else {
    // opcional: merge de mínimos
    await ref.set(
      {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    console.log(`  [=] settings/general ok`);
  }
}

async function ensureOwnerMember(db, lojaId, ownerUid) {
  if (!ownerUid) return;
  const ref = db.collection('lojas').doc(lojaId).collection('members').doc(ownerUid);
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set({
      role: 'owner',
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`  [+] members/${ownerUid} (owner) criado`);
  } else {
    console.log(`  [=] members/${ownerUid} ok`);
  }
}

function _slugify(s) {
  return (s || '')
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^[-]+|[-]+$/g, '')
    || 'minha-loja';
}

async function fixLojaDoc(db, doc) {
  const data = doc.data() || {};
  const lojaId = doc.id;

  const updates = {};
  let changed = false;

  // name e slug básicos
  const currentName = (data.name || '').toString().trim();
  const currentSlug = (data.slug || '').toString().trim();
  if (!currentName) {
    updates.name = 'Minha Loja';
    changed = true;
  }
  if (!currentSlug) {
    updates.slug = lojaId;
    changed = true;
  }

  // id espelhado
  if (data.id !== lojaId) {
    updates.id = lojaId;
    changed = true;
  }

  // hostingStatus mínimo
  if (!data.hostingStatus) {
    updates.hostingStatus = 'PENDING';
    changed = true;
  }

  // owner compatível com as rules (ownerUid + owner.uid/email)
  const ownerUid = (data.ownerUid || (data.owner && data.owner.uid) || '').toString();
  if (!ownerUid) {
    console.warn(`  [!] Loja ${lojaId} sem ownerUid — nada a fazer além de mínimos.`);
  } else {
    if (data.ownerUid !== ownerUid) {
      updates.ownerUid = ownerUid;
      changed = true;
    }
    const ownerMap = data.owner || {};
    if (!ownerMap.uid || ownerMap.uid !== ownerUid) {
      updates.owner = { ...(ownerMap || {}), uid: ownerUid };
      changed = true;
    }
  }

  if (changed) {
    await db.collection('lojas').doc(lojaId).set(
      {
        ...updates,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    console.log(`  [~] lojas/${lojaId} atualizado`, updates);
  } else {
    console.log(`  [=] lojas/${lojaId} ok`);
  }

  // settings e member do owner
  await ensureSettings(db, lojaId, data.whatsappE164 || '');
  if (ownerUid) {
    await ensureOwnerMember(db, lojaId, ownerUid);
  }
}

async function run() {
  const { db } = initAdmin();
  const args = parseArgs();

  if (args.loja) {
    console.log(`▶ Atualizando somente a loja: ${args.loja}`);
    const snap = await db.collection('lojas').doc(args.loja).get();
    if (!snap.exists) {
      console.error(`❌ Loja ${args.loja} não encontrada`);
      process.exit(2);
    }
    await fixLojaDoc(db, snap);
    console.log('✅ Concluído (1 loja).');
    process.exit(0);
  }

  console.log('▶ Atualizando TODAS as lojas...');
  const colRef = db.collection('lojas');
  let last = undefined;
  let total = 0;

  while (true) {
    let q = colRef.orderBy(admin.firestore.FieldPath.documentId()).limit(300);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    if (page.empty) break;

    for (const doc of page.docs) {
      console.log(`\n• lojas/${doc.id}`);
      await fixLojaDoc(db, doc);
      total++;
    }
    last = page.docs[page.docs.length - 1];
    if (page.size < 300) break;
  }

  console.log(`\n✅ Concluído (${total} loja(s)).`);
  process.exit(0);
}

run().catch((err) => {
  console.error('Erro no seed:', err);
  process.exit(1);
});
