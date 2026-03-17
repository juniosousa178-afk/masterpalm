// scripts/criar_usuario_teste.js
// Cria um usuário de teste para os avaliadores da Play Store
// O app irá criar automaticamente a loja no primeiro login (store_resolver)
//
// RODAR:  cd functions && node scripts/criar_usuario_teste.js
//
// Requer: masterpalm-service-account.json na pasta functions/

import admin from "firebase-admin";
import { readFileSync, existsSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const EMAIL = "reviewer@mastepalm.com.br";
const SENHA = "MasterPalm@Review2026";
const NOME = "Avaliador Play Store";

const serviceAccountPath = join(__dirname, "..", "masterpalm-service-account.json");

if (!existsSync(serviceAccountPath)) {
  console.error("❌ masterpalm-service-account.json não encontrado em:", serviceAccountPath);
  console.error("   Baixe em: Firebase Console > Configurações do projeto > Contas de serviço > Gerar nova chave");
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

    console.log("✅ Usuário de teste criado com sucesso!\n");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("  Use estas credenciais na Play Console:");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("  E-mail:  " + EMAIL);
    console.log("  Senha:   " + SENHA);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    console.log("  UID:", userRecord.uid);
    console.log("  No primeiro login, o app criará automaticamente uma loja para esse usuário.\n");
  } catch (e) {
    if (e.code === "auth/email-already-exists") {
      console.log("ℹ️  O usuário já existe. Use estas credenciais:\n");
      console.log("  E-mail:  " + EMAIL);
      console.log("  Senha:   (a que você definiu ao criar, ou resete no Firebase Console)\n");
      console.log("  Para resetar a senha: Firebase Console > Authentication > Users >", EMAIL);
    } else {
      console.error("❌ Erro:", e.message);
      process.exit(1);
    }
  }
}

main();
