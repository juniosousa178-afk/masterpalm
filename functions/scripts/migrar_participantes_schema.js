// functions/scripts/migrar_participantes_schema.js
// Migra participantes legados para o schema canônico (dataParticipacao, numeroSorte)
//
// Uso:
//   node ./scripts/migrar_participantes_schema.js           # Executa migração
//   node ./scripts/migrar_participantes_schema.js --dry-run # Só mostra o que seria alterado
//   node ./scripts/migrar_participantes_schema.js --loja masterpalm  # Apenas uma loja
//
// Requer: GOOGLE_APPLICATION_CREDENTIALS apontando para serviceAccount.json

import 'dotenv/config';
import admin from 'firebase-admin';

function initAdmin() {
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function parseArgs() {
  const args = process.argv.slice(2);
  const out = { dryRun: false, loja: null };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--dry-run' || a === '-n') out.dryRun = true;
    else if ((a === '--loja' || a === '-l') && args[i + 1]) {
      out.loja = args[i + 1].trim().toLowerCase();
      i++;
    }
  }
  return out;
}

/**
 * Extrai Timestamp de dataParticipacao, criadoEm ou data (legado)
 */
function obterTimestamp(d) {
  if (!d) return null;
  if (d.toDate && typeof d.toDate === 'function') return d; // Firestore Timestamp
  if (d instanceof Date) return admin.firestore.Timestamp.fromDate(d);
  if (typeof d === 'object' && d._seconds != null)
    return new admin.firestore.Timestamp(d._seconds, d._nanoseconds || 0);
  return null;
}

/**
 * Migra participantes de uma campanha
 */
async function migrarParticipantesCampanha(db, lojaId, campanhaId, dryRun, log) {
  const participantesRef = db
    .collection('lojas')
    .doc(lojaId)
    .collection('campanhas_sorteio')
    .doc(campanhaId)
    .collection('participantes');

  const snapshot = await participantesRef.get();
  let alterados = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const updates = {};

    // dataParticipacao ausente -> preencher com criadoEm ou data
    if (!data.dataParticipacao) {
      const ts = obterTimestamp(data.criadoEm) || obterTimestamp(data.data);
      if (ts) {
        updates.dataParticipacao = ts;
      } else {
        log.push({ tipo: 'aviso', doc: doc.id, msg: 'Sem dataParticipacao, criadoEm nem data' });
        continue;
      }
    }

    // numeroSorte ausente -> preencher com numeros[0]
    if (!data.numeroSorte && Array.isArray(data.numeros) && data.numeros.length > 0) {
      const primeiro = data.numeros[0];
      if (typeof primeiro === 'string') {
        updates.numeroSorte = primeiro;
      } else {
        updates.numeroSorte = String(primeiro);
      }
    }

    if (Object.keys(updates).length === 0) continue;

    alterados++;
    log.push({
      tipo: 'alterar',
      path: `lojas/${lojaId}/campanhas_sorteio/${campanhaId}/participantes/${doc.id}`,
      updates,
    });

    if (!dryRun) {
      await doc.ref.update(updates);
    }
  }

  return alterados;
}

async function main() {
  const { dryRun, loja } = parseArgs();
  const db = initAdmin();

  console.log('🔧 Migração de participantes para schema canônico');
  if (dryRun) console.log('   [DRY-RUN] Nenhuma alteração será gravada\n');

  const lojasRef = db.collection('lojas');
  let lojasDocs;
  if (loja) {
    const d = await lojasRef.doc(loja).get();
    lojasDocs = d.exists ? [d] : [];
  } else {
    lojasDocs = (await lojasRef.get()).docs;
  }

  let totalAlterados = 0;
  const logGeral = [];

  for (const lojaDoc of lojasDocs) {
    const lojaId = lojaDoc.id;
    const campanhasSnap = await db
      .collection('lojas')
      .doc(lojaId)
      .collection('campanhas_sorteio')
      .get();

    for (const campanhaDoc of campanhasSnap.docs) {
      const campanhaId = campanhaDoc.id;
      const alterados = await migrarParticipantesCampanha(
        db,
        lojaId,
        campanhaId,
        dryRun,
        logGeral
      );
      totalAlterados += alterados;
    }
  }

  // Resumo
  console.log(`\n✅ Concluído. Participantes alterados: ${totalAlterados}`);

  if (logGeral.length > 0) {
    console.log('\n📋 Log de alterações:');
    for (const e of logGeral) {
      if (e.tipo === 'alterar') {
        console.log(`   [${dryRun ? 'DRY' : 'OK'}] ${e.path}`);
        console.log(`        updates: ${JSON.stringify(e.updates)}`);
      } else if (e.tipo === 'aviso') {
        console.log(`   [AVISO] ${e.doc}: ${e.msg}`);
      }
    }
  }
}

main().catch((err) => {
  console.error('❌ Erro:', err);
  process.exit(1);
});
