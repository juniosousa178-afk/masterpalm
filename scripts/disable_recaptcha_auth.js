// Script para desabilitar reCAPTCHA no login com e-mail/senha (Firebase Auth)
// Resolve erro 400 em signInWithPassword causado por reCAPTCHA Enterprise
//
// CAUSA: Firebase Auth com reCAPTCHA Enterprise ativo exige token no Android.
// O app mobile não envia esse token automaticamente como o Web.
//
// Execute: node scripts/disable_recaptcha_auth.js
// Requer: scripts/serviceAccountKey.json (chave de serviço do Firebase)

const admin = require('firebase-admin');
const path = require('path');

let serviceAccount;
try {
  serviceAccount = require('./serviceAccountKey.json');
} catch (e) {
  console.error('❌ Arquivo serviceAccountKey.json não encontrado em scripts/');
  console.error('   Baixe em: Firebase Console → Configurações do projeto → Contas de serviço');
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

async function main() {
  try {
    await admin.auth().projectConfigManager().updateProjectConfig({
      recaptchaConfig: {
        emailPasswordEnforcementState: 'OFF',
      },
    });
    console.log('✅ reCAPTCHA desabilitado para login com e-mail/senha.');
    console.log('   O login deve funcionar agora. Teste em https://app.mastepalm.com.br');
  } catch (e) {
    console.error('❌ Erro:', e.message);
    if (e.code === 'auth/insufficient-permission') {
      console.error('   A conta de serviço precisa da permissão "Firebase Authentication Admin".');
    }
    process.exit(1);
  }
  process.exit(0);
}

main();
