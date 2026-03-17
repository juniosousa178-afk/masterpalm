/**
 * Backfill catalog_redirect_index a partir das lojas existentes.
 * Uso: node ./backfill_catalog_redirect_index.js [--dry-run] [--limit N]
 * - dry-run: só imprime o que faria, não escreve
 * - limit: máximo de lojas a processar (default 500)
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
  let limit = 500;
  const dr = (process.env.DRY_RUN || "").toString().toLowerCase();
  if (dr === "1" || dr === "true" || dr === "yes") dryRun = true;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--dry-run") dryRun = true;
    if (argv[i] === "--limit" && argv[i + 1]) {
      limit = Math.max(1, parseInt(argv[i + 1], 10) || 500);
      i++;
    }
  }
  return { dryRun, limit };
}

async function main() {
  const { dryRun, limit } = parseArgs();
  const argv = process.argv.slice(2);
  if (argv.includes("--help") || argv.includes("-h")) {
    console.log(`
Uso: node ./backfill_catalog_redirect_index.js [--dry-run] [--limit N]
  --dry-run   Não escreve no Firestore, só lista
  --limit N   Máximo de lojas a processar (default 500)
`);
    process.exit(0);
  }

  initializeApp({ projectId: process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT });
  const db = getFirestore();

  const { syncCatalogRedirectIndex } = await import("./src/catalogRedirectIndex.js");

  const snap = await db.collection(COLLECTION_LOJAS).limit(limit).get();
  if (dryRun) {
    console.log(`[backfill_catalog_redirect] DRY-RUN: nenhuma escrita será feita. Lojas a processar: ${snap.size}`);
  } else {
    console.log(`[backfill_catalog_redirect] Lojas a processar: ${snap.size} (dryRun=false, escrevendo no Firestore)`);
  }

  let ok = 0;
  let err = 0;
  for (const doc of snap.docs) {
    const lojaId = doc.id;
    const data = doc.data() || {};
    try {
      if (dryRun) {
        // dry-run: nenhuma escrita
      } else {
        await syncCatalogRedirectIndex(db, lojaId, data);
      }
      const slug = (data.slug || lojaId).toString().trim();
      const linkCurto = (data.linkCurto || "").toString().trim();
      console.log(`  ${dryRun ? "[dry-run] " : ""}${lojaId} → slug=${slug} linkCurto=${linkCurto || "(vazio)"}`);
      ok++;
    } catch (e) {
      console.error(`  ERRO ${lojaId}:`, e.message);
      err++;
    }
  }

  console.log(`[backfill_catalog_redirect] Fim: ok=${ok} err=${err}`);
  process.exit(err > 0 ? 1 : 0);
}

main();
