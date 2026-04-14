/**
 * Admin: cria/atualiza catalog_domains/{hostNormalizado} para piloto de domínio customizado do catálogo web.
 *
 * IMPORTANTE (npm run): o npm v10+ pode comer QUALQUER flag --algo=... (trata como "cli config") e não repassa ao Node.
 * Formas que funcionam com npm run:
 *   npm run setup:catalog-domain -- catalogo.loja.com.br id-doc-lojas
 *   $env:CATALOG_DOMAIN_HOST="..."; $env:CATALOG_DOMAIN_LOJA_ID="..."; npm run setup:catalog-domain
 *   node scripts/setup_catalog_domain.js --host=... --lojaId=...   (sem npm)
 *
 * Credenciais: se scripts/serviceAccountKey.json estiver expirado/errado, use --no-local-sa e
 * GOOGLE_APPLICATION_CREDENTIALS ou gcloud auth application-default login + GCLOUD_PROJECT.
 *
 * Não configura DNS, Hosting, Auth nem regras Firestore.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const COLLECTION = "catalog_domains";
const LOJAS = "lojas";

const INVALID_LITERALS = new Set(["null", "undefined", "", "minha-loja", "minha_loja"]);

function parseArgs(argv) {
  const out = {
    host: (process.env.CATALOG_DOMAIN_HOST || "").trim(),
    lojaId: (process.env.CATALOG_DOMAIN_LOJA_ID || "").trim(),
    status: (process.env.CATALOG_DOMAIN_STATUS || "active").trim() || "active",
    verified: !/^(0|false|no)$/i.test(
      String(process.env.CATALOG_DOMAIN_VERIFIED ?? "true").trim()
    ),
    dryRun: false,
    serviceAccount: (process.env.CATALOG_DOMAIN_SERVICE_ACCOUNT || "").trim(),
    skipLocalServiceAccount: false,
  };
  const dr = (process.env.DRY_RUN || "").toString().toLowerCase();
  if (dr === "1" || dr === "true" || dr === "yes") out.dryRun = true;

  const positionals = [];

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") {
      out.dryRun = true;
      continue;
    }
    if (a === "--no-local-sa") {
      out.skipLocalServiceAccount = true;
      continue;
    }
    const m = /^--([^=]+)=(.*)$/.exec(a);
    if (m) {
      const key = m[1];
      const val = m[2];
      switch (key) {
        case "catalog-host":
          out.host = val;
          break;
        case "catalog-loja-id":
          out.lojaId = val;
          break;
        case "host":
          out.host = val;
          break;
        case "lojaId":
          out.lojaId = val;
          break;
        case "status":
          out.status = val;
          break;
        case "verified":
          out.verified = /^(1|true|yes)$/i.test(val.trim());
          break;
        case "service-account":
          out.serviceAccount = val;
          break;
        default:
          break;
      }
      continue;
    }
    if (a.startsWith("-")) continue;
    positionals.push(a);
  }

  if (!out.host && positionals[0]) out.host = positionals[0];
  if (!out.lojaId && positionals[1]) out.lojaId = positionals[1];

  return out;
}

function printHelp() {
  console.log(`
Uso (RECOMENDADO com npm run — 2 argumentos posicionais; o npm não os rouba):
  npm run setup:catalog-domain -- catalogo.loja.com.br id-doc-em-lojas

Com Node direto (flags --host= funcionam):
  node scripts/setup_catalog_domain.js --host=catalogo.loja.com.br --lojaId=id-doc-em-lojas

Variáveis de ambiente (PowerShell + npm):
  $env:CATALOG_DOMAIN_HOST="catalogo.loja.com.br"
  $env:CATALOG_DOMAIN_LOJA_ID="meu-loja-doc-id"
  npm run setup:catalog-domain

Opções (argv; com "npm run" as flags --x= podem ser ignoradas pelo npm):
  --host= / --lojaId= / --catalog-host= / --catalog-loja-id=
  --status=         Default: active
  --verified=       Default: true
  --service-account= Caminho ao JSON da service account (opcional)
  --no-local-sa     Não usar scripts/serviceAccountKey.json (útil se estiver inválido; use ADC ou GOOGLE_APPLICATION_CREDENTIALS)
  --dry-run         Só imprime o payload; não escreve no Firestore

Env: CATALOG_DOMAIN_HOST, CATALOG_DOMAIN_LOJA_ID, CATALOG_DOMAIN_STATUS, CATALOG_DOMAIN_VERIFIED

Credenciais (ordem): --service-account= → GOOGLE_APPLICATION_CREDENTIALS → scripts/serviceAccountKey.json (se existir e não for --no-local-sa) → ADC (gcloud).

Projeto: use JSON com project_id correto, ou GCLOUD_PROJECT / GCP_PROJECT.

Erro UNAUTHENTICATED: regenere a chave JSON no Firebase Console ou aponte para um JSON válido do mesmo projeto do Firestore.
`);
}

function normalizeCatalogDomainHost(raw) {
  let s = String(raw || "").trim();
  if (!s) return "";

  s = s.replace(/^\s+|\s+$/g, "");
  const lower = s.toLowerCase();

  if (lower.includes("://") || lower.startsWith("//")) {
    try {
      const url = new URL(lower.startsWith("//") ? `https:${lower}` : lower);
      s = url.hostname || "";
    } catch (_) {
      s = lower.replace(/^https?:\/\//, "").split("/")[0] || "";
    }
  } else {
    s = lower.split("/")[0] || lower;
  }

  s = s.trim().toLowerCase();
  if (!s) return "";

  if (s.startsWith("[")) {
    const end = s.indexOf("]");
    if (end > 0) s = s.slice(0, end + 1);
    return s;
  }

  const colon = s.lastIndexOf(":");
  if (colon > 0) {
    const after = s.slice(colon + 1);
    if (/^\d+$/.test(after)) s = s.slice(0, colon);
  }

  while (s.endsWith(".")) s = s.slice(0, -1);
  while (s.endsWith("/")) s = s.slice(0, -1);

  return s;
}

function validateLojaId(lojaId) {
  const t = String(lojaId || "").trim();
  if (!t) return "lojaId vazio";
  if (INVALID_LITERALS.has(t.toLowerCase())) return `lojaId inválido: "${t}"`;
  return null;
}

function validateHost(hostNorm) {
  if (!hostNorm) return "host vazio após normalização";
  if (INVALID_LITERALS.has(hostNorm)) return `host inválido: "${hostNorm}"`;
  if (!/^[a-z0-9.\-]+$/.test(hostNorm)) {
    return "host contém caracteres não permitidos (use apenas a-z 0-9 . -)";
  }
  return null;
}

function initAdmin(serviceAccountArg, skipLocalServiceAccount) {
  if (admin.apps.length) return;

  let credPath =
    serviceAccountArg ||
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    "";
  const localSa = path.join(__dirname, "serviceAccountKey.json");
  if (!credPath && !skipLocalServiceAccount && fs.existsSync(localSa)) {
    credPath = localSa;
  }

  const envProjectId =
    process.env.GCLOUD_PROJECT ||
    process.env.GCP_PROJECT ||
    process.env.FIREBASE_PROJECT ||
    "";

  if (credPath) {
    const resolved = path.isAbsolute(credPath)
      ? credPath
      : path.resolve(process.cwd(), credPath);
    if (!fs.existsSync(resolved)) {

      console.error(

        "[ERRO] Arquivo de credenciais não encontrado:\n   " + resolved + "\n"

      );

      const looksLikePlaceholder =

        /caminho|chave-correta|exemplo|placeholder/i.test(resolved);

      if (looksLikePlaceholder) {

        console.error(

          "   → Parece o caminho de EXEMPLO da documentação. Use o caminho real do .json descarregado do Firebase Console.\n"

        );

      }

      if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {

        console.error(

          "   PowerShell: $env:GOOGLE_APPLICATION_CREDENTIALS = $null  (volta ao JSON em scripts/ se existir)\n"

        );

      }

      process.exit(1);

    }

    const sa = require(resolved);
    const jsonProjectId =
      (sa && typeof sa.project_id === "string" && sa.project_id.trim()) || "";
    const projectId = envProjectId || jsonProjectId;
    admin.initializeApp({
      credential: admin.credential.cert(sa),
      ...(projectId ? { projectId } : {}),
    });
    console.log(
      `🔐 Admin SDK: credential file → ${resolved} (projectId=${projectId || "(não definido)"})`
    );
  } else {
    if (!envProjectId) {
      console.warn(
        "⚠️ Sem JSON de service account e sem GCLOUD_PROJECT/GCP_PROJECT: o Firestore pode falhar com ADC."
      );
    }
    admin.initializeApp(envProjectId ? { projectId: envProjectId } : {});
    console.log(
      "🔐 Admin SDK: application default credentials (sem arquivo JSON explícito)"
    );
  }
}

function payloadEqual(existing, next) {
  if (!existing) return false;
  return (
    (existing.host || "") === next.host &&
    (existing.lojaId || "") === next.lojaId &&
    (existing.status || "") === next.status &&
    existing.verified === next.verified
  );
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.includes("--help") || argv.includes("-h")) {
    printHelp();
    process.exit(0);
  }

  const args = parseArgs(argv);
  const hostOriginal = args.host;
  const hostNorm = normalizeCatalogDomainHost(args.host);
  const lojaId = String(args.lojaId || "").trim();

  console.log("══════════════════════════════════════════════════════════");
  console.log(" setup_catalog_domain — catalog_domains (Admin SDK)");
  console.log("══════════════════════════════════════════════════════════");
  console.log(`   host (entrada):  ${hostOriginal || "(vazio)"}`);
  console.log(`   host (normalizado): ${hostNorm || "(vazio)"}`);
  console.log(`   lojaId:           ${lojaId || "(vazio)"}`);
  console.log(`   status:           ${args.status}`);
  console.log(`   verified:         ${args.verified}`);
  console.log(`   dry-run:          ${args.dryRun}`);
  console.log("══════════════════════════════════════════════════════════\n");

  const eh = validateHost(hostNorm);
  if (eh) {
    console.error(`❌ ${eh}`);
    process.exit(1);
  }
  const el = validateLojaId(lojaId);
  if (el) {
    console.error(`❌ ${el}`);
    process.exit(1);
  }

  if (!args.status || String(args.status).trim() === "") {
    console.error('❌ status inválido (use por exemplo --status=active)');
    process.exit(1);
  }
  if (String(args.status).trim() !== "active") {
    console.error(
      '❌ O app só aceita catálogo com status "active". Ajuste --status=active.'
    );
    process.exit(1);
  }
  if (args.verified !== true) {
    console.error(
      '❌ O app só aceita catálogo com verified true. Ajuste --verified=true.'
    );
    process.exit(1);
  }

  initAdmin(args.serviceAccount, args.skipLocalServiceAccount);
  const db = admin.firestore();

  const lojaRef = db.collection(LOJAS).doc(lojaId);
  const lojaSnap = await lojaRef.get();
  console.log(`📂 Validação: ${LOJAS}/${lojaId} exists=${lojaSnap.exists}`);
  if (!lojaSnap.exists) {
    console.error(
      `❌ Loja não encontrada em /${LOJAS}/${lojaId}. Abortando — nada foi escrito em ${COLLECTION}.`
    );
    process.exit(1);
  }

  const docRef = db.collection(COLLECTION).doc(hostNorm);
  const existingSnap = await docRef.get();
  const existingData = existingSnap.exists ? existingSnap.data() : null;

  const nextPayload = {
    host: hostNorm,
    lojaId,
    status: String(args.status).trim(),
    verified: args.verified === true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (payloadEqual(existingData, nextPayload)) {
    console.log(
      "✅ Documento já está alinhado (host, lojaId, status, verified). Nenhuma escrita necessária."
    );
    process.exit(0);
  }

  console.log("📄 Payload a gravar (merge):");
  console.log(
    JSON.stringify(
      { ...nextPayload, updatedAt: "<ServerTimestamp>" },
      null,
      2
    )
  );

  if (args.dryRun) {
    console.log("\n🔸 DRY-RUN: nenhuma escrita no Firestore.");
    process.exit(0);
  }

  await docRef.set(nextPayload, { merge: true });
  const verb = existingSnap.exists ? "atualizado" : "criado";
  console.log(`\n✅ catalog_domains/${hostNorm} ${verb} com sucesso.`);
  process.exit(0);
}

main().catch((err) => {
  const msg = err && err.message ? err.message : String(err);
  console.error("❌ Erro:", msg);
  if (/UNAUTHENTICATED|invalid authentication credentials/i.test(msg)) {
    console.error(`
💡 Credenciais inválidas ou expiradas (o JSON não autentica neste projeto).

   • Gere uma chave nova: Firebase Console → Definições do projeto → Contas de serviço → Gerar nova chave privada
   • Defina: $env:GOOGLE_APPLICATION_CREDENTIALS="C:\\caminho\\para\\chave.json"
   • Ou ignore o ficheiro local (se estiver antigo): adicione --no-local-sa e use ADC:
       gcloud auth application-default login
       $env:GCLOUD_PROJECT="masterpalm-58c46"   (ajuste ao teu project id)
   • Confirme que project_id dentro do JSON é o mesmo projeto onde está o Firestore.
`);
  }
  if (err && err.stack) console.error(err.stack);
  process.exit(1);
});
