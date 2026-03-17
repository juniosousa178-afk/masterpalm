/**
 * Backfill order_loja_index a partir de pedidos e pre_pedidos existentes.
 * Processa por loja; não reprocessa orderId já presente no índice (opcional).
 * Uso: node ./backfill_order_loja_index.js [--dry-run] [--limit N] [--skip-existing]
 * - dry-run: não escreve
 * - limit: máximo de lojas a processar (default 100)
 * - skip-existing: não sobrescreve doc já existente em order_loja_index
 */

import process from "node:process";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";

/**
 * Parse apenas argumentos reais (argv[0]=node, argv[1]=script).
 * Aceita também DRY_RUN=1 no ambiente (npm run sem "--" não repassa --dry-run ao script).
 */
function parseArgs() {
  const argv = process.argv.slice(2);
  let dryRun = false;
  let limit = 100;
  let skipExisting = false;
  const dr = (process.env.DRY_RUN || "").toString().toLowerCase();
  if (dr === "1" || dr === "true" || dr === "yes") dryRun = true;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--dry-run") dryRun = true;
    if (argv[i] === "--skip-existing") skipExisting = true;
    if (argv[i] === "--limit" && argv[i + 1]) {
      limit = Math.max(1, parseInt(argv[i + 1], 10) || 100);
      i++;
    }
  }
  return { dryRun, limit, skipExisting };
}

async function main() {
  const { dryRun, limit, skipExisting } = parseArgs();
  const argv = process.argv.slice(2);
  if (argv.includes("--help") || argv.includes("-h")) {
    console.log(`
Uso: node ./backfill_order_loja_index.js [--dry-run] [--limit N] [--skip-existing]
  --dry-run        Não escreve no Firestore
  --limit N        Máximo de lojas a processar (default 100)
  --skip-existing  Não sobrescreve orderId já existente no índice
`);
    process.exit(0);
  }

  initializeApp({ projectId: process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT });
  const db = getFirestore();

  const { writeOrderLojaIndex, readOrderLojaIndex } = await import("./src/orderLojaIndex.js");

  const lojasSnap = await db.collection(COLLECTION_LOJAS).limit(limit).get();
  if (dryRun) {
    console.log(`[backfill_order_loja] DRY-RUN: nenhuma escrita será feita. Lojas: ${lojasSnap.size}`);
  } else {
    console.log(`[backfill_order_loja] Lojas: ${lojasSnap.size} (dryRun=false, skipExisting=${skipExisting})`);
  }

  let totalPedidos = 0;
  let totalPrePedidos = 0;
  let written = 0;
  let skipped = 0;

  for (const lojaDoc of lojasSnap.docs) {
    const lojaId = lojaDoc.id;
    const pedidosRef = db.collection(COLLECTION_LOJAS).doc(lojaId).collection("pedidos");
    const prePedidosRef = db.collection(COLLECTION_LOJAS).doc(lojaId).collection("pre_pedidos");

    const [pedidosSnap, preSnap] = await Promise.all([pedidosRef.get(), prePedidosRef.get()]);

    for (const doc of pedidosSnap.docs) {
      totalPedidos++;
      if (skipExisting && !dryRun) {
        const existing = await readOrderLojaIndex(db, doc.id);
        if (existing) {
          skipped++;
          continue;
        }
      }
      if (dryRun) {
        written++;
      } else {
        await writeOrderLojaIndex(db, doc.id, lojaId, "pedidos");
        written++;
      }
    }
    for (const doc of preSnap.docs) {
      totalPrePedidos++;
      if (skipExisting && !dryRun) {
        const existing = await readOrderLojaIndex(db, doc.id);
        if (existing) {
          skipped++;
          continue;
        }
      }
      if (dryRun) {
        written++;
      } else {
        await writeOrderLojaIndex(db, doc.id, lojaId, "pre_pedidos");
        written++;
      }
    }
  }

  if (dryRun) {
    console.log(`[backfill_order_loja] Fim (DRY-RUN): pedidos=${totalPedidos} pre_pedidos=${totalPrePedidos} would_write=${written} skipped=${skipped}`);
  } else {
    console.log(`[backfill_order_loja] Fim: pedidos=${totalPedidos} pre_pedidos=${totalPrePedidos} written=${written} skipped=${skipped}`);
  }
  process.exit(0);
}

main();
