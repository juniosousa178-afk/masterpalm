import process from "node:process";

import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldPath, getFirestore } from "firebase-admin/firestore";

function parseArgs(argv) {
  const args = {
    lojaId: "",
    limit: 100,
    startAfter: "",
    dryRun: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const current = argv[i];
    const next = argv[i + 1];

    if (current === "--lojaId" && next) {
      args.lojaId = String(next).trim();
      i += 1;
      continue;
    }
    if (current === "--limit" && next) {
      const parsed = Number.parseInt(next, 10);
      if (Number.isFinite(parsed) && parsed > 0) {
        args.limit = parsed;
      }
      i += 1;
      continue;
    }
    if (current === "--startAfter" && next) {
      args.startAfter = String(next).trim();
      i += 1;
      continue;
    }
    if (current === "--dry-run") {
      args.dryRun = true;
    }
  }

  return args;
}

function usage() {
  console.log(`
Uso:
  node ./backfill_pedido_status_publico.js --lojaId <lojaId> [--limit 100] [--startAfter <pedidoId>] [--dry-run]

Exemplos:
  node ./backfill_pedido_status_publico.js --lojaId nathy --limit 50 --dry-run
  node ./backfill_pedido_status_publico.js --lojaId nathy --limit 50 --startAfter abc123
`);
}

function normalizeOptionalString(value) {
  const resolved = value == null ? "" : String(value).trim();
  return resolved.length > 0 ? resolved : null;
}

function buildPedidoStatusPublico(lojaId, pedidoId, data = {}) {
  const itens = Array.isArray(data.itens) ? data.itens : [];
  const itensResumo = itens
    .map((item) => ({
      nome: normalizeOptionalString(item?.nome) || "",
      quantidade: Number(item?.quantidade) || 1,
    }))
    .filter((item) => item.nome.length > 0);

  const frete = data.frete && typeof data.frete === "object" ? data.frete : {};
  const payload = {
    pedidoId: String(pedidoId || ""),
    lojaId: String(lojaId || ""),
    status: normalizeOptionalString(data.status) || "pendente",
    dataCriacao: data.dataCriacao ?? null,
    dataAtualizacao: data.dataAtualizacao ?? data.dataCriacao ?? null,
    total: Number(data.total) || 0,
    itensResumo,
  };

  const codigoRastreio = normalizeOptionalString(
    data.codigoRastreio || data.codigo_rastreio || data.rastreio,
  );
  const freteNome = normalizeOptionalString(data.freteNome || frete.nome);

  if (codigoRastreio) payload.codigoRastreio = codigoRastreio;
  if (freteNome) payload.freteNome = freteNome;

  return payload;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.lojaId) {
    usage();
    process.exitCode = 1;
    return;
  }

  const projectId =
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.PROJECT_ID ||
    "masterpalm-58c46";

  if (process.env.FIRESTORE_EMULATOR_HOST) {
    initializeApp({ projectId });
  } else {
    initializeApp({
      credential: applicationDefault(),
      projectId,
    });
  }

  const db = getFirestore();
  const lojaRef = db.collection("lojas").doc(args.lojaId);
  const prePedidosRef = lojaRef.collection("pre_pedidos");
  const statusPublicoRef = lojaRef.collection("pedido_status_publico");

  let query = prePedidosRef
    .orderBy(FieldPath.documentId())
    .limit(args.limit);

  if (args.startAfter) {
    query = query.startAfter(args.startAfter);
  }

  console.log(`[backfill] Loja: ${args.lojaId}`);
  console.log(`[backfill] Limite: ${args.limit}`);
  if (args.startAfter) {
    console.log(`[backfill] StartAfter: ${args.startAfter}`);
  }
  if (args.dryRun) {
    console.log("[backfill] Modo dry-run ativo: nenhuma escrita será feita.");
  }

  const snapshot = await query.get();
  if (snapshot.empty) {
    console.log("[backfill] Nenhum pre_pedido encontrado para este lote.");
    return;
  }

  const batch = db.batch();
  let created = 0;
  let skippedExisting = 0;
  let skippedInvalid = 0;
  let errors = 0;

  for (const doc of snapshot.docs) {
    try {
      const pedidoId = doc.id;
      const publicRef = statusPublicoRef.doc(pedidoId);
      const publicSnap = await publicRef.get();

      if (publicSnap.exists) {
        skippedExisting += 1;
        console.log(`[skip] ${pedidoId} já possui espelho público.`);
        continue;
      }

      const data = doc.data() || {};
      const payload = buildPedidoStatusPublico(args.lojaId, pedidoId, data);

      if (!payload.pedidoId || !payload.lojaId) {
        skippedInvalid += 1;
        console.log(`[skip] ${pedidoId} inválido para espelhamento.`);
        continue;
      }

      created += 1;
      console.log(`[create] ${pedidoId} -> pedido_status_publico`);

      if (!args.dryRun) {
        batch.set(publicRef, payload, { merge: false });
      }
    } catch (error) {
      errors += 1;
      console.error(`[error] ${doc.id}:`, error);
    }
  }

  if (!args.dryRun && created > 0) {
    await batch.commit();
  }

  const lastDoc = snapshot.docs[snapshot.docs.length - 1];
  console.log("");
  console.log("[backfill] Resumo do lote");
  console.log(`  criados: ${created}`);
  console.log(`  ignorados_existentes: ${skippedExisting}`);
  console.log(`  ignorados_invalidos: ${skippedInvalid}`);
  console.log(`  erros: ${errors}`);
  console.log(`  proximo_startAfter: ${lastDoc.id}`);
}

main().catch((error) => {
  console.error("[backfill] Falha fatal:", error);
  process.exitCode = 1;
});
