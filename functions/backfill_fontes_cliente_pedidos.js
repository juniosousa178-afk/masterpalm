import process from "node:process";
import crypto from "node:crypto";

import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldPath, getFirestore, Timestamp } from "firebase-admin/firestore";

const MODE_CLIENTES_TOKEN = "clientes-sem-portal-token";
const MODE_CLIENTES_PORTAL_PERFIL = "clientes-portal-perfil";
const MODE_CLIENTES_PORTAL_PEDIDOS = "clientes-portal-pedidos";
const MODE_PEDIDO_STATUS_PUBLICO = "pedido-status-publico";

const VALID_MODES = new Set([
  MODE_CLIENTES_TOKEN,
  MODE_CLIENTES_PORTAL_PERFIL,
  MODE_CLIENTES_PORTAL_PEDIDOS,
  MODE_PEDIDO_STATUS_PUBLICO,
]);

function parseArgs(argv) {
  const args = {
    lojaId: "",
    limit: 100,
    startAfter: "",
    dryRun: false,
    mode: "",
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
    if (current === "--mode" && next) {
      args.mode = String(next).trim();
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
  node ./backfill_fontes_cliente_pedidos.js --mode <modo> --lojaId <lojaId> [--limit 100] [--startAfter <cursor>] [--dry-run]

Modos:
  ${MODE_CLIENTES_TOKEN}
  ${MODE_CLIENTES_PORTAL_PERFIL}
  ${MODE_CLIENTES_PORTAL_PEDIDOS}
  ${MODE_PEDIDO_STATUS_PUBLICO}

Exemplos:
  node ./backfill_fontes_cliente_pedidos.js --mode ${MODE_CLIENTES_TOKEN} --lojaId nathy --limit 50 --dry-run
  node ./backfill_fontes_cliente_pedidos.js --mode ${MODE_CLIENTES_PORTAL_PERFIL} --lojaId nathy --limit 50
  node ./backfill_fontes_cliente_pedidos.js --mode ${MODE_CLIENTES_PORTAL_PEDIDOS} --lojaId nathy --limit 50 --startAfter abc123
  node ./backfill_fontes_cliente_pedidos.js --mode ${MODE_PEDIDO_STATUS_PUBLICO} --lojaId nathy --limit 50
`);
}

function normalizeOptionalString(value) {
  const resolved = value == null ? "" : String(value).trim();
  return resolved.length > 0 ? resolved : null;
}

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function createPortalToken() {
  return crypto.randomBytes(24).toString("base64url");
}

function sanitizeEndereco(endereco) {
  if (!endereco || typeof endereco !== "object") return null;
  const allowedKeys = [
    "cep",
    "rua",
    "numero",
    "bairro",
    "cidade",
    "estado",
    "complemento",
    "logradouro",
    "street",
    "postalCode",
  ];
  const result = {};
  for (const key of allowedKeys) {
    const value = endereco[key];
    if (value == null) continue;
    const resolved = typeof value === "string" ? value.trim() : value;
    if (resolved === "" || resolved == null) continue;
    result[key] = resolved;
  }
  return Object.keys(result).length > 0 ? result : null;
}

function normalizeTimestamp(value) {
  if (value instanceof Timestamp) {
    return { seconds: value.seconds, nanoseconds: value.nanoseconds };
  }
  if (value instanceof Date) {
    return { iso: value.toISOString() };
  }
  return value;
}

function canonicalize(value) {
  if (Array.isArray(value)) {
    return value.map((item) => canonicalize(item));
  }
  if (value && typeof value === "object") {
    const normalized = normalizeTimestamp(value);
    if (normalized !== value) {
      return normalized;
    }
    const result = {};
    for (const key of Object.keys(value).sort()) {
      const current = canonicalize(value[key]);
      if (current === undefined) continue;
      result[key] = current;
    }
    return result;
  }
  return value;
}

function deepEqual(a, b) {
  return JSON.stringify(canonicalize(a)) === JSON.stringify(canonicalize(b));
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

function buildClientePortalProfile(lojaId, clienteId, clienteData = {}) {
  const endereco = sanitizeEndereco(clienteData.endereco);
  const enderecoFormatado = normalizeOptionalString(clienteData.enderecoFormatado);
  const payload = {
    lojaId: String(lojaId || ""),
    clienteId: String(clienteId || ""),
    dataAtualizacao:
      clienteData.updatedAt ??
      clienteData.updatedEm ??
      clienteData.dataAtualizacao ??
      clienteData.dataCadastro ??
      null,
  };

  if (endereco) payload.ultimoEndereco = endereco;
  if (enderecoFormatado) payload.ultimoEnderecoFormatado = enderecoFormatado;

  return payload;
}

function buildClientePortalPedido(lojaId, pedidoId, pedidoData = {}) {
  return buildPedidoStatusPublico(lojaId, pedidoId, pedidoData);
}

async function resolveClienteTarget(db, lojaId, pedidoData = {}) {
  const cliente = pedidoData.cliente && typeof pedidoData.cliente === "object"
    ? pedidoData.cliente
    : {};

  let clienteDoc = null;
  const clienteId = normalizeOptionalString(cliente.id);
  const clienteEmail = normalizeEmail(cliente.email);

  if (clienteId) {
    const snap = await db
      .collection("lojas")
      .doc(lojaId)
      .collection("clientes")
      .doc(clienteId)
      .get();
    if (snap.exists) {
      clienteDoc = { id: snap.id, ref: snap.ref, data: snap.data() || {} };
    }
  }

  if (!clienteDoc && clienteEmail) {
    const snapshot = await db
      .collection("lojas")
      .doc(lojaId)
      .collection("clientes")
      .where("email", "==", clienteEmail)
      .limit(1)
      .get();
    if (!snapshot.empty) {
      const snap = snapshot.docs[0];
      clienteDoc = { id: snap.id, ref: snap.ref, data: snap.data() || {} };
    }
  }

  return clienteDoc;
}

async function ensurePortalToken({ db, lojaId, clienteDoc, dryRun, stats }) {
  let portalToken = normalizeOptionalString(clienteDoc.data.portalToken);
  if (portalToken) {
    return { portalToken, generated: false };
  }

  portalToken = createPortalToken();
  stats.updated += 1;
  stats.portalTokensGerados += 1;
  if (!dryRun) {
    await clienteDoc.ref.set({ portalToken }, { merge: true });
  }
  clienteDoc.data.portalToken = portalToken;
  return { portalToken, generated: true };
}

function createStats(mode, startAfter) {
  return {
    mode,
    cursorInicial: startAfter || "",
    analisados: 0,
    created: 0,
    updated: 0,
    skipped: 0,
    failed: 0,
    portalTokensGerados: 0,
    invalidos: 0,
    proximoCursor: "",
  };
}

function logSummary(stats) {
  console.log("");
  console.log("[backfill] Resumo do lote");
  console.log(`  modo: ${stats.mode}`);
  console.log(`  analisados: ${stats.analisados}`);
  console.log(`  criados: ${stats.created}`);
  console.log(`  atualizados: ${stats.updated}`);
  console.log(`  pulados: ${stats.skipped}`);
  console.log(`  falharam: ${stats.failed}`);
  console.log(`  invalidos: ${stats.invalidos}`);
  console.log(`  portalTokensGerados: ${stats.portalTokensGerados}`);
  console.log(`  proximoCursor: ${stats.proximoCursor}`);
}

async function runClientesSemPortalToken({ db, lojaId, limit, startAfter, dryRun }) {
  const stats = createStats(MODE_CLIENTES_TOKEN, startAfter);
  let query = db
    .collection("lojas")
    .doc(lojaId)
    .collection("clientes")
    .orderBy(FieldPath.documentId())
    .limit(limit);

  if (startAfter) {
    query = query.startAfter(startAfter);
  }

  const snapshot = await query.get();
  if (snapshot.empty) return stats;

  for (const doc of snapshot.docs) {
    stats.analisados += 1;
    stats.proximoCursor = doc.id;
    try {
      const data = doc.data() || {};
      const portalToken = normalizeOptionalString(data.portalToken);
      if (portalToken) {
        stats.skipped += 1;
        continue;
      }
      stats.updated += 1;
      stats.portalTokensGerados += 1;
      if (!dryRun) {
        await doc.ref.set({ portalToken: createPortalToken() }, { merge: true });
      }
    } catch (error) {
      stats.failed += 1;
      console.error(`[error][${MODE_CLIENTES_TOKEN}] ${doc.id}:`, error);
    }
  }

  return stats;
}

async function runClientesPortalPerfil({ db, lojaId, limit, startAfter, dryRun }) {
  const stats = createStats(MODE_CLIENTES_PORTAL_PERFIL, startAfter);
  let query = db
    .collection("lojas")
    .doc(lojaId)
    .collection("clientes")
    .orderBy(FieldPath.documentId())
    .limit(limit);

  if (startAfter) {
    query = query.startAfter(startAfter);
  }

  const snapshot = await query.get();
  if (snapshot.empty) return stats;

  for (const doc of snapshot.docs) {
    stats.analisados += 1;
    stats.proximoCursor = doc.id;
    try {
      const clienteDoc = { id: doc.id, ref: doc.ref, data: doc.data() || {} };
      const { portalToken } = await ensurePortalToken({
        db,
        lojaId,
        clienteDoc,
        dryRun,
        stats,
      });

      const desired = buildClientePortalProfile(lojaId, doc.id, clienteDoc.data);
      const portalRef = db
        .collection("lojas")
        .doc(lojaId)
        .collection("clientes_portal")
        .doc(portalToken);
      const currentSnap = await portalRef.get();

      if (!currentSnap.exists) {
        stats.created += 1;
        if (!dryRun) {
          await portalRef.set(desired, { merge: false });
        }
        continue;
      }

      const current = currentSnap.data() || {};
      if (deepEqual(current, desired)) {
        stats.skipped += 1;
        continue;
      }

      stats.updated += 1;
      if (!dryRun) {
        await portalRef.set(desired, { merge: false });
      }
    } catch (error) {
      stats.failed += 1;
      console.error(`[error][${MODE_CLIENTES_PORTAL_PERFIL}] ${doc.id}:`, error);
    }
  }

  return stats;
}

async function runClientesPortalPedidos({ db, lojaId, limit, startAfter, dryRun }) {
  const stats = createStats(MODE_CLIENTES_PORTAL_PEDIDOS, startAfter);
  let query = db
    .collection("lojas")
    .doc(lojaId)
    .collection("pre_pedidos")
    .orderBy(FieldPath.documentId())
    .limit(limit);

  if (startAfter) {
    query = query.startAfter(startAfter);
  }

  const snapshot = await query.get();
  if (snapshot.empty) return stats;

  for (const doc of snapshot.docs) {
    stats.analisados += 1;
    stats.proximoCursor = doc.id;
    try {
      const pedidoData = doc.data() || {};
      const clienteDoc = await resolveClienteTarget(db, lojaId, pedidoData);
      if (!clienteDoc) {
        stats.invalidos += 1;
        stats.skipped += 1;
        continue;
      }

      const { portalToken } = await ensurePortalToken({
        db,
        lojaId,
        clienteDoc,
        dryRun,
        stats,
      });

      const desired = buildClientePortalPedido(lojaId, doc.id, pedidoData);
      const pedidoRef = db
        .collection("lojas")
        .doc(lojaId)
        .collection("clientes_portal")
        .doc(portalToken)
        .collection("pedidos")
        .doc(doc.id);
      const currentSnap = await pedidoRef.get();

      if (!currentSnap.exists) {
        stats.created += 1;
        if (!dryRun) {
          await pedidoRef.set(desired, { merge: false });
        }
        continue;
      }

      const current = currentSnap.data() || {};
      if (deepEqual(current, desired)) {
        stats.skipped += 1;
        continue;
      }

      stats.updated += 1;
      if (!dryRun) {
        await pedidoRef.set(desired, { merge: false });
      }
    } catch (error) {
      stats.failed += 1;
      console.error(`[error][${MODE_CLIENTES_PORTAL_PEDIDOS}] ${doc.id}:`, error);
    }
  }

  return stats;
}

async function runPedidoStatusPublico({ db, lojaId, limit, startAfter, dryRun }) {
  const stats = createStats(MODE_PEDIDO_STATUS_PUBLICO, startAfter);
  let query = db
    .collection("lojas")
    .doc(lojaId)
    .collection("pre_pedidos")
    .orderBy(FieldPath.documentId())
    .limit(limit);

  if (startAfter) {
    query = query.startAfter(startAfter);
  }

  const snapshot = await query.get();
  if (snapshot.empty) return stats;

  for (const doc of snapshot.docs) {
    stats.analisados += 1;
    stats.proximoCursor = doc.id;
    try {
      const desired = buildPedidoStatusPublico(lojaId, doc.id, doc.data() || {});
      if (!desired.pedidoId || !desired.lojaId) {
        stats.invalidos += 1;
        stats.skipped += 1;
        continue;
      }

      const publicRef = db
        .collection("lojas")
        .doc(lojaId)
        .collection("pedido_status_publico")
        .doc(doc.id);
      const currentSnap = await publicRef.get();

      if (!currentSnap.exists) {
        stats.created += 1;
        if (!dryRun) {
          await publicRef.set(desired, { merge: false });
        }
        continue;
      }

      const current = currentSnap.data() || {};
      if (deepEqual(current, desired)) {
        stats.skipped += 1;
        continue;
      }

      stats.updated += 1;
      if (!dryRun) {
        await publicRef.set(desired, { merge: false });
      }
    } catch (error) {
      stats.failed += 1;
      console.error(`[error][${MODE_PEDIDO_STATUS_PUBLICO}] ${doc.id}:`, error);
    }
  }

  return stats;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.lojaId || !VALID_MODES.has(args.mode)) {
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
  console.log(`[backfill] Loja: ${args.lojaId}`);
  console.log(`[backfill] Modo: ${args.mode}`);
  console.log(`[backfill] Limite: ${args.limit}`);
  if (args.startAfter) {
    console.log(`[backfill] StartAfter: ${args.startAfter}`);
  }
  if (args.dryRun) {
    console.log("[backfill] Modo dry-run ativo: nenhuma escrita será feita.");
  }

  let stats;
  switch (args.mode) {
    case MODE_CLIENTES_TOKEN:
      stats = await runClientesSemPortalToken({
        db,
        lojaId: args.lojaId,
        limit: args.limit,
        startAfter: args.startAfter,
        dryRun: args.dryRun,
      });
      break;
    case MODE_CLIENTES_PORTAL_PERFIL:
      stats = await runClientesPortalPerfil({
        db,
        lojaId: args.lojaId,
        limit: args.limit,
        startAfter: args.startAfter,
        dryRun: args.dryRun,
      });
      break;
    case MODE_CLIENTES_PORTAL_PEDIDOS:
      stats = await runClientesPortalPedidos({
        db,
        lojaId: args.lojaId,
        limit: args.limit,
        startAfter: args.startAfter,
        dryRun: args.dryRun,
      });
      break;
    case MODE_PEDIDO_STATUS_PUBLICO:
      stats = await runPedidoStatusPublico({
        db,
        lojaId: args.lojaId,
        limit: args.limit,
        startAfter: args.startAfter,
        dryRun: args.dryRun,
      });
      break;
    default:
      usage();
      process.exitCode = 1;
      return;
  }

  logSummary(stats);
}

main().catch((error) => {
  console.error("[backfill] Falha fatal:", error);
  process.exitCode = 1;
});
