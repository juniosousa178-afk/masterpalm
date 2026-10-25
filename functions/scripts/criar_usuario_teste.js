// scripts/criar_usuario_teste.js
// Cria um usuário de teste para os avaliadores da Play Store
// O app irá criar automaticamente a loja no primeiro login (store_resolver)
//
// RODAR (PowerShell):
//   cd functions
//   $env:REVIEW_ACCOUNT_EMAIL = "<e-mail da conta de revisão>"
//   $env:REVIEW_ACCOUNT_PASSWORD_FILE = "<caminho fora do repositório>"
//   node scripts/criar_usuario_teste.js
//
// A senha vem só de REVIEW_ACCOUNT_PASSWORD_FILE (arquivo fora do Git) ou REVIEW_ACCOUNT_PASSWORD.
// Nunca versionar a senha nem colá-la neste arquivo; o script nunca a imprime.
//
// Requer: masterpalm-service-account.json na pasta functions/

import admin from "firebase-admin";
import { readFileSync, existsSync } from "fs";
import { dirname, join, resolve } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..", "..");

const MIN_PASSWORD_LENGTH = 16;

function fail(message) {
  console.error(`❌ ${message}`);
  process.exit(1);
}

function readReviewPassword() {
  const file = (process.env.REVIEW_ACCOUNT_PASSWORD_FILE || "").trim();
  if (file) {
    const full = resolve(file);
    if (full.toLowerCase().startsWith(repoRoot.toLowerCase())) {
      fail("REVIEW_ACCOUNT_PASSWORD_FILE deve ficar fora do repositório.");
    }
    if (!existsSync(full)) fail("REVIEW_ACCOUNT_PASSWORD_FILE não encontrado.");
    return readFileSync(full, "utf8").trim();
  }
  return (process.env.REVIEW_ACCOUNT_PASSWORD || "").trim();
}

const EMAIL = (process.env.REVIEW_ACCOUNT_EMAIL || "").trim();
const SENHA = readReviewPassword();
const NOME = (process.env.REVIEW_ACCOUNT_DISPLAY_NAME || "Avaliador Play Store").trim();

if (!EMAIL) fail("Defina REVIEW_ACCOUNT_EMAIL.");
if (SENHA.length < MIN_PASSWORD_LENGTH) {
  fail(`Defina REVIEW_ACCOUNT_PASSWORD_FILE (ou REVIEW_ACCOUNT_PASSWORD) com pelo menos ${MIN_PASSWORD_LENGTH} caracteres.`);
}

const serviceAccountPath = join(__dirname, "..", "masterpalm-service-account.json");

if (!existsSync(serviceAccountPath)) {
  console.error("❌ Arquivo de service account não encontrado em:", serviceAccountPath);
  console.error("   Baixe em: Firebase Console > Configurações > Contas de serviço > Gerar nova chave privada");
  process.exit(1);
}

const serviceAccount = JSON.parse(readFileSync(serviceAccountPath, "utf8"));

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const auth = admin.auth();

async function main() {
  try {
    const userRecord = await auth.createUser({
      email: EMAIL,
      password: SENHA,
      displayName: NOME,
      emailVerified: true,
    });

    console.log("✅ Usuário de teste criado com sucesso.");
    console.log("   E-mail:", EMAIL);
    console.log("   UID:", userRecord.uid);
    console.log("   A senha não é exibida; use a mesma fonte segura ao cadastrá-la no Play Console.");
  } catch (e) {
    if (e.code === "auth/email-already-exists") {
      console.log("⚠️ O usuário já existe:", EMAIL);
      console.log("   Para trocar a senha, use o procedimento de rotação da conta de revisão (fora do Git).");
    } else {
      console.error("Erro:", e.message);
      process.exit(1);
    }
  }
}

main();
