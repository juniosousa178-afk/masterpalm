/**
 * Alinha `draft_produtos` e `produtos` (catálogo) com `estoque_produtos`
 * usando o MESMO id de documento do estoque (pós-correção no app).
 *
 * Credenciais (escolha UMA — no Windows o JSON costuma ser o mais simples):
 *
 * 1) Ficheiro JSON da conta de serviço (recomendado):
 *    node ... --credentials "C:\caminho\serviceAccount.json" --lojaId <id>
 *
 * 2) Variável de ambiente (PowerShell):
 *    $env:GOOGLE_APPLICATION_CREDENTIALS="C:\caminho\serviceAccount.json"
 *
 * 3) Google Cloud SDK:
 *    gcloud auth application-default login
 *
 * Obter JSON: Firebase Console → Definições do projeto → Contas de serviço →
 *   "Gerar nova chave privada" (ou IAM no GCP). A conta precisa de permissão
 *   para ler/escrever Firestore no projeto.
 *
 * Troque SUA_LOJA_ID pelo id real da loja (mesmo valor usado em `lojas/{id}`).
 *
 * Modo seguro custo/peso (não apaga nem sobrescreve outros campos):
 *   --only-custo-peso --all-lojas
 *   Faz merge só em peso, custoReal, tipoEmbalagem e updatedAt no DRAFT.
 *   No LIVE (`produtos`) só peso/tipoEmbalagem/updatedAt; custoReal é sempre removido (FieldValue.delete).
 */
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import process from "node:process";

import { applicationDefault, cert, initializeApp } from "firebase-admin/app";
import {
  FieldPath,
  FieldValue,
  getFirestore,
} from "firebase-admin/firestore";

const BATCH_MAX = 400;

function parseArgs(argv) {
  const args = {
    lojaId: "",
    dryRun: false,
    draft: true,
    live: true,
    removeLegacySlug: false,
    limit: 0,
    credentialsPath: "",
    projectId: "",
    allowAdc: false,
    allLojas: false,
    onlyCustoPeso: false,
    _help: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const c = argv[i];
    const n = argv[i + 1];
    if (c === "--lojaId" && n) {
      args.lojaId = String(n).trim();
      i += 1;
      continue;
    }
    if (c === "--credentials" && n) {
      args.credentialsPath = path.resolve(String(n).trim());
      i += 1;
      continue;
    }
    if (c === "--projectId" && n) {
      args.projectId = String(n).trim();
      i += 1;
      continue;
    }
    if (c === "--allow-adc") {
      args.allowAdc = true;
      continue;
    }
    if (c === "--all-lojas") {
      args.allLojas = true;
      continue;
    }
    if (c === "--only-custo-peso") {
      args.onlyCustoPeso = true;
      continue;
    }
    if (c === "--help" || c === "-h") {
      args._help = true;
      continue;
    }
    if (c === "--dry-run" || c === "--dry") {
      args.dryRun = true;
      continue;
    }
    if (c === "--no-draft") {
      args.draft = false;
      continue;
    }
    if (c === "--no-live") {
      args.live = false;
      continue;
    }
    if (c === "--remove-legacy-slug") {
      args.removeLegacySlug = true;
      continue;
    }
    if (c === "--limit" && n) {
      const p = Number.parseInt(n, 10);
      if (Number.isFinite(p) && p > 0) args.limit = p;
      i += 1;
    }
  }

  // npm ≥10 trata --credentials como opção do próprio npm e pode não repassar ao Node.
  // Aceitar um caminho posicional para o JSON da conta de serviço (ex.: npm run ... -- .\\serviceAccount.json).
  if (!args.credentialsPath) {
    for (const token of argv) {
      if (String(token).startsWith("-")) continue;
      const p = path.resolve(String(token).trim());
      if (!existsSync(p) || !p.toLowerCase().endsWith(".json")) continue;
      try {
        const j = JSON.parse(readFileSync(p, "utf8"));
        if (j && (j.private_key || j.client_email || j.type === "service_account")) {
          args.credentialsPath = p;
          break;
        }
      } catch {
        /* ignora */
      }
    }
  }

  return args;
}

function usage() {
  console.log(`
Uso:
  node ./scripts/backfill_catalogo_from_estoque.js --lojaId <id> [opções]
  node ./scripts/backfill_catalogo_from_estoque.js --all-lojas --only-custo-peso --credentials ... --dry-run

  --all-lojas            Processa todas as lojas (documentos em "lojas")
  --only-custo-peso      Merge mínimo: draft (peso+custo+embalagem); live (só peso+embalagem, apaga custo)

Credenciais (obrigatório configurar um):
  --credentials <ficheiro.json>   Chave da conta de serviço
  <ficheiro.json> (posicional)      Mesmo efeito se npm não repassar --credentials (recom. com npm run)
  --projectId <id>                Projeto Firebase/GCP (opcional; senão usa env ou masterpalm-58c46)

  Com npm run: use o JSON no fim após -- (npm engole --credentials em algumas versões):
    npm run backfill:custo-peso-all:dry -- .\\serviceAccount.json

  Ou defina GOOGLE_APPLICATION_CREDENTIALS com o caminho do JSON.
  Ou: gcloud auth application-default login (cria ficheiro em %APPDATA%\\gcloud\\... no Windows)

  --allow-adc            Tentar credenciais padrão mesmo sem JSON (só se souber que ADC está OK)

Opções:
  --dry-run / --dry      Só mostra o que faria (sem escrever)
  --no-draft             Não atualiza draft_produtos
  --no-live              Não atualiza produtos (catálogo publicado)
  --remove-legacy-slug   Remove doc duplicado por slug legado (ignorado com --only-custo-peso)
  --limit N              Processa no máximo N produtos de estoque (por loja)

Exemplos (PowerShell):
  node .\\scripts\\backfill_catalogo_from_estoque.js --all-lojas --only-custo-peso --credentials ".\\serviceAccount.json" --dry-run
  node .\\scripts\\backfill_catalogo_from_estoque.js --lojaId nathy-pratas --credentials "C:\\chaves\\adm.json" --dry-run
  $env:GOOGLE_APPLICATION_CREDENTIALS="C:\\chaves\\adm.json"
  node .\\scripts\\backfill_catalogo_from_estoque.js --lojaId nathy-pratas --dry-run
`);
}

function printCredentialHelp() {
  console.error(`
[erro] Não foi possível carregar credenciais do Google Cloud.

No Windows, o mais simples é usar um JSON de conta de serviço:

  1) Firebase Console → Definições do projeto → Contas de serviço
     → "Gerar nova chave privada" (guardar o .json)

  2) Executar:
     node .\\scripts\\backfill_catalogo_from_estoque.js --lojaId SEU_ID_REAL --credentials "C:\\caminho\\chave.json" --dry-run

Ou no PowerShell:
     $env:GOOGLE_APPLICATION_CREDENTIALS="C:\\caminho\\chave.json"

Ou instale o Google Cloud SDK e rode:
     gcloud auth application-default login

Confirme também que --lojaId é o id REAL da loja (não o texto "SUA_LOJA_ID").
`);
}

function gcloudApplicationDefaultCredentialsPath() {
  if (process.platform === "win32") {
    const appData = process.env.APPDATA;
    if (!appData) return "";
    return path.join(appData, "gcloud", "application_default_credentials.json");
  }
  return path.join(homedir(), ".config", "gcloud", "application_default_credentials.json");
}

function loadCredentialFromJsonFile(filePath) {
  if (!filePath || !existsSync(filePath)) {
    throw new Error(`Ficheiro de credenciais não encontrado: ${filePath || "(vazio)"}`);
  }
  const raw = readFileSync(filePath, "utf8");
  const json = JSON.parse(raw);
  return cert(json);
}

/** @returns {{ credential: any, source: string } | null} */
function resolveFirebaseCredential(args) {
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    return { credential: undefined, source: "emulator (sem ADC)" };
  }

  if (args.credentialsPath) {
    return {
      credential: loadCredentialFromJsonFile(args.credentialsPath),
      source: `--credentials ${args.credentialsPath}`,
    };
  }

  const envPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const envResolved = envPath ? path.resolve(envPath) : "";
  if (envResolved && existsSync(envResolved)) {
    return {
      credential: loadCredentialFromJsonFile(envResolved),
      source: "GOOGLE_APPLICATION_CREDENTIALS",
    };
  }

  const gcloudAdc = gcloudApplicationDefaultCredentialsPath();
  if (gcloudAdc && existsSync(gcloudAdc)) {
    return {
      credential: applicationDefault(),
      source: `gcloud application-default (${gcloudAdc})`,
    };
  }

  if (args.allowAdc) {
    return {
      credential: applicationDefault(),
      source: "Application Default Credentials (--allow-adc)",
    };
  }

  return null;
}

function num(v, fallback = 0) {
  if (v == null) return fallback;
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function buildPatch(estoqueId, est) {
  const preco = num(est.preco ?? est.precoFinal, 0);
  const qtd = num(est.quantidade, 0);
  const publicado = est.publicadoNoCatalogo === true;

  const patch = {
    id: estoqueId,
    nome: est.nome ?? "",
    slug: est.slug ?? "",
    descricao: est.descricao ?? "",
    preco,
    preco_venda: preco,
    precoFinal: preco,
    priceMin: preco,
    priceMax: preco,
    quantidade: qtd,
    estoque_atual: qtd,
    estoque: qtd,
    qtdEstoque: qtd,
    peso: num(est.peso, 0),
    tipoEmbalagem: est.tipoEmbalagem ? String(est.tipoEmbalagem) : "padrao",
    publicadoNoCatalogo: publicado,
    publicar: publicado,
    ativo: true,
    emPromocao: est.emPromocao === true,
    percentualPromo: est.percentualPromo ?? null,
    valorPromo: est.valorPromo ?? null,
    variacoes: est.variacoes ?? null,
    estoquePorTamanho: est.estoquePorTamanho ?? {},
    cores: Array.isArray(est.cores) ? est.cores : [],
    precoPorTamanho: est.precoPorTamanho ?? null,
    imagens: Array.isArray(est.imagens) ? est.imagens : [],
    images: Array.isArray(est.imagens) ? est.imagens : [],
    divideSemJuros: est.divideSemJuros === true,
    maxParcelasSemJuros: num(est.maxParcelasSemJuros, 12),
    percentualDescontoPix: num(est.percentualDescontoPix, 0),
    codigoBarras: est.codigoBarras || null,
    estoqueMinimo: num(est.estoqueMinimo, 0),
    tipoProduto: est.tipoProduto ? String(est.tipoProduto) : "simples",
    itensCombo: est.itensCombo ?? null,
    tamanhos: Array.isArray(est.tamanhos) ? est.tamanhos : [],
    updatedAt: FieldValue.serverTimestamp(),
  };

  Object.keys(patch).forEach((k) => {
    if (patch[k] === undefined) delete patch[k];
  });
  return patch;
}

function shouldWriteLive(est) {
  const publicado = est.publicadoNoCatalogo === true;
  const qtd = num(est.quantidade, 0);
  const tipo = String(est.tipoProduto || "simples");
  const comboOk = tipo === "combo" && publicado;
  return publicado && (qtd > 0 || comboOk);
}

/** Merge mínimo a partir de estoque_produtos — não altera outros campos do catálogo. */
function buildCustoPesoPatchDraft(est) {
  return {
    peso: num(est.peso, 0),
    custoReal: num(est.custoReal, 0),
    tipoEmbalagem: est.tipoEmbalagem ? String(est.tipoEmbalagem) : "padrao",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Catálogo live: nunca custo; apaga chaves de custo se existirem no doc. */
function buildCustoPesoPatchLive(est) {
  return {
    peso: num(est.peso, 0),
    tipoEmbalagem: est.tipoEmbalagem ? String(est.tipoEmbalagem) : "padrao",
    updatedAt: FieldValue.serverTimestamp(),
    custoReal: FieldValue.delete(),
    custo: FieldValue.delete(),
    precoCusto: FieldValue.delete(),
  };
}

async function commitBatches(db, ops, dryRun) {
  if (dryRun || ops.length === 0) return;
  for (let i = 0; i < ops.length; i += BATCH_MAX) {
    const batch = db.batch();
    const slice = ops.slice(i, i + BATCH_MAX);
    for (const { ref, data, merge } of slice) {
      batch.set(ref, data, { merge: merge !== false });
    }
    await batch.commit();
    console.log(`[batch] commit ${slice.length} escritas (${i + slice.length}/${ops.length})`);
  }
}

/**
 * @returns {Promise<{ processed: number, writes: number, skippedLive: number, skippedNoDraft: number, skippedNoLive: number, legacyMarked: number, deletes: number }>}
 */
async function processLoja(db, lojaId, args) {
  const lojaRef = db.collection("lojas").doc(lojaId);
  const estoqueRef = lojaRef.collection("estoque_produtos");
  const draftRef = lojaRef.collection("draft_produtos");
  const liveRef = lojaRef.collection("produtos");

  const stats = {
    processed: 0,
    skippedLive: 0,
    skippedNoDraft: 0,
    skippedNoLive: 0,
    legacyMarked: 0,
  };

  let snap;
  try {
    snap = await estoqueRef.orderBy(FieldPath.documentId()).get();
  } catch (e) {
    const msg = String(e?.message || e);
    if (
      msg.includes("default credentials") ||
      msg.includes("Could not load") ||
      msg.includes("authentication")
    ) {
      printCredentialHelp();
    }
    throw e;
  }

  if (snap.empty) {
    console.log(`[backfill] [${lojaId}] Nenhum documento em estoque_produtos.`);
    return { ...stats, writes: 0, deletes: 0 };
  }

  const writes = [];
  const deletes = [];

  for (const doc of snap.docs) {
    if (args.limit > 0 && stats.processed >= args.limit) break;
    stats.processed += 1;

    const estoqueId = doc.id;
    const est = doc.data() || {};
    const nomeEst = String(est.nome || "").trim();
    const slug = String(est.slug || "").trim();

    if (args.onlyCustoPeso) {
      const miniD = buildCustoPesoPatchDraft(est);
      const miniL = buildCustoPesoPatchLive(est);

      if (args.draft) {
        const dSnap = await draftRef.doc(estoqueId).get();
        if (dSnap.exists) {
          writes.push({
            ref: draftRef.doc(estoqueId),
            data: miniD,
            merge: true,
          });
          console.log(
            `[draft] [${lojaId}] ${estoqueId} peso=${miniD.peso} custo=${miniD.custoReal}`,
          );
        } else {
          stats.skippedNoDraft += 1;
        }
      }

      if (args.live) {
        const lSnap = await liveRef.doc(estoqueId).get();
        if (lSnap.exists) {
          writes.push({
            ref: liveRef.doc(estoqueId),
            data: miniL,
            merge: true,
          });
          console.log(`[live] [${lojaId}] ${estoqueId} peso=${miniL.peso} (custo apagado no live)`);
        } else {
          stats.skippedNoLive += 1;
        }
      }
    } else {
      const patch = buildPatch(estoqueId, est);

      if (args.draft) {
        writes.push({
          ref: draftRef.doc(estoqueId),
          data: { ...patch },
          merge: true,
        });
        console.log(
          `[draft] [${lojaId}] ${estoqueId} peso=${patch.peso} preco=${patch.preco}`,
        );
      }

      if (args.live) {
        if (shouldWriteLive(est)) {
          const livePatch = { ...patch };
          delete livePatch.priceMin;
          delete livePatch.priceMax;
          livePatch.custoReal = FieldValue.delete();
          livePatch.custo = FieldValue.delete();
          livePatch.precoCusto = FieldValue.delete();
          writes.push({
            ref: liveRef.doc(estoqueId),
            data: livePatch,
            merge: true,
          });
          console.log(
            `[live] [${lojaId}] ${estoqueId} peso=${patch.peso} preco=${patch.preco}`,
          );
        } else {
          stats.skippedLive += 1;
        }
      }

      if (
        args.removeLegacySlug &&
        slug &&
        slug !== estoqueId &&
        nomeEst.length > 0
      ) {
        for (const col of [draftRef, liveRef]) {
          const legRef = col.doc(slug);
          const legSnap = await legRef.get();
          if (!legSnap.exists) continue;
          const d = legSnap.data() || {};
          const nomeLeg = String(d.nome || "").trim();
          const innerId = String(d.id || "").trim();
          const sameProduto =
            nomeLeg.toLowerCase() === nomeEst.toLowerCase() &&
            (innerId === slug || innerId === "" || innerId === estoqueId);
          if (sameProduto) {
            stats.legacyMarked += 1;
            console.log(
              `[legacy] [${lojaId}] remover ${col.id}/${slug} (canônico=${estoqueId})`,
            );
            deletes.push(legRef);
          }
        }
      }
    }
  }

  await commitBatches(db, writes, args.dryRun);

  if (deletes.length > 0 && !args.dryRun) {
    for (let i = 0; i < deletes.length; i += BATCH_MAX) {
      const batch = db.batch();
      const slice = deletes.slice(i, i + BATCH_MAX);
      for (const ref of slice) {
        batch.delete(ref);
      }
      await batch.commit();
      console.log(`[legacy] [${lojaId}] delete batch ${slice.length}`);
    }
  } else if (deletes.length > 0 && args.dryRun) {
    console.log(
      `[legacy] [${lojaId}] dry-run: ${deletes.length} exclusões NÃO executadas`,
    );
  }

  return {
    ...stats,
    writes: writes.length,
    deletes: deletes.length,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args._help) {
    usage();
    return;
  }
  if (!args.allLojas && !args.lojaId) {
    usage();
    process.exitCode = 1;
    return;
  }

  if (!args.allLojas) {
    const lojaPlaceholders = new Set([
      "SUA_LOJA_ID",
      "SUA_LOJA",
      "SEU_ID_REAL",
      "SEU_ID_REAL_DA_LOJA",
      "ID_DA_LOJA",
      "ID_REAL_DA_LOJA",
      "EXEMPLO",
      "<id>",
    ]);
    if (lojaPlaceholders.has(args.lojaId.trim().toUpperCase())) {
      console.error(
        `[erro] --lojaId parece placeholder da documentação. No Firebase Console abra a coleção "lojas" e copie o ID do documento da sua loja (ex.: nathy-pratas-e-folheados).`,
      );
      process.exitCode = 1;
      return;
    }
  }

  const projectId =
    args.projectId ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.PROJECT_ID ||
    (() => {
      try {
        if (args.credentialsPath && existsSync(args.credentialsPath)) {
          const j = JSON.parse(readFileSync(args.credentialsPath, "utf8"));
          if (j.project_id) return j.project_id;
        }
        const envP = process.env.GOOGLE_APPLICATION_CREDENTIALS;
        if (envP && existsSync(envP)) {
          const j = JSON.parse(readFileSync(path.resolve(envP), "utf8"));
          if (j.project_id) return j.project_id;
        }
      } catch {
        /* ignore */
      }
      return "masterpalm-58c46";
    })();

  try {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      initializeApp({ projectId });
      console.log("[backfill] Emulator:", process.env.FIRESTORE_EMULATOR_HOST);
    } else {
      const resolved = resolveFirebaseCredential(args);
      if (resolved == null) {
        printCredentialHelp();
        console.error(
          "[acao] Sem credenciais detectadas. Use por exemplo:\n" +
            '  node .\\scripts\\backfill_catalogo_from_estoque.js --lojaId ID_DA_LOJA --credentials "C:\\chaves\\adm.json" --dry-run\n',
        );
        process.exitCode = 1;
        return;
      }
      initializeApp({ credential: resolved.credential, projectId });
      console.log(`[backfill] Credenciais: ${resolved.source}`);
    }
  } catch (e) {
    printCredentialHelp();
    console.error("[detalhe]", e?.message || e);
    process.exitCode = 1;
    return;
  }

  const db = getFirestore();

  let lojaIds = [];
  if (args.allLojas) {
    const lojasSnap = await db.collection("lojas").get();
    lojaIds = lojasSnap.docs.map((d) => d.id).filter((id) => id && String(id).trim());
    console.log(`[backfill] --all-lojas: ${lojaIds.length} documento(s) em "lojas".`);
    if (lojaIds.length === 0) {
      console.log("[backfill] Nenhuma loja encontrada.");
      return;
    }
  } else {
    lojaIds = [args.lojaId];
  }

  console.log(`[backfill] Projeto: ${projectId}`);
  console.log(
    `[backfill] modo=${args.onlyCustoPeso ? "only-custo-peso (merge mínimo)" : "full-merge"} draft=${args.draft} live=${args.live} removeLegacy=${args.removeLegacySlug && !args.onlyCustoPeso}`,
  );
  if (args.onlyCustoPeso) {
    console.log("[backfill] live: custo nunca gravado; custoReal/custo removidos com delete se existirem");
  }
  if (args.dryRun) console.log("[backfill] MODO DRY-RUN (sem escrita)");

  const totals = {
    lojas: 0,
    processed: 0,
    writes: 0,
    skippedLive: 0,
    skippedNoDraft: 0,
    skippedNoLive: 0,
    legacyDeletes: 0,
  };

  for (const lid of lojaIds) {
    totals.lojas += 1;
    console.log(`\n======== Loja: ${lid} ========`);
    const s = await processLoja(db, lid, args);
    totals.processed += s.processed;
    totals.writes += s.writes;
    totals.skippedLive += s.skippedLive;
    totals.skippedNoDraft += s.skippedNoDraft;
    totals.skippedNoLive += s.skippedNoLive;
    totals.legacyDeletes += s.deletes;
  }

  console.log("");
  console.log("[backfill] Resumo (todas as lojas processadas)");
  console.log(`  lojas: ${totals.lojas}`);
  console.log(`  estoque_docs_processados: ${totals.processed}`);
  console.log(`  escritas_agendadas: ${totals.writes}`);
  console.log(`  live_ignorados (modo full): ${totals.skippedLive}`);
  console.log(`  sem_doc_draft (modo custo/peso): ${totals.skippedNoDraft}`);
  console.log(`  sem_doc_live (modo custo/peso): ${totals.skippedNoLive}`);
  console.log(`  legacy_delete_refs: ${totals.legacyDeletes}`);
}

main().catch((e) => {
  console.error("[backfill] Falha:", e);
  process.exitCode = 1;
});
