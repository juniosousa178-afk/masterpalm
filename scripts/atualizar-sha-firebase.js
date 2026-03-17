#!/usr/bin/env node
/**
 * Atualiza SHA-1 e SHA-256 no Firebase para o app Android.
 * Roda gradlew signingReport, extrai os hashes e adiciona via Firebase Management API.
 *
 * Uso: node scripts/atualizar-sha-firebase.js
 *      GOOGLE_APPLICATION_CREDENTIALS=scripts/serviceAccountKey.json node scripts/atualizar-sha-firebase.js
 */

const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const PROJECT_ID = 'masterpalm-58c46';
const ANDROID_APP_ID = '1:950139833317:android:01d76e9d022ae1851ebd0c';
const SCRIPT_DIR = path.dirname(__filename);
const ROOT_DIR = path.join(SCRIPT_DIR, '..');

async function getAccessToken() {
  // Usa google-auth-library (vem com firebase-admin)
  const { GoogleAuth } = require('google-auth-library');
  const keyPath = path.join(SCRIPT_DIR, 'serviceAccountKey.json');
  if (!fs.existsSync(keyPath)) {
    throw new Error('serviceAccountKey.json não encontrado em scripts/');
  }
  const auth = new GoogleAuth({
    keyFilename: keyPath,
    scopes: ['https://www.googleapis.com/auth/firebase', 'https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  return token.token;
}

function runSigningReport() {
  const isWin = process.platform === 'win32';
  const gradlew = isWin ? 'gradlew.bat' : 'gradlew';
  const cmd = path.join(ROOT_DIR, 'android', gradlew);
  const cwd = path.join(ROOT_DIR, 'android');
  if (!fs.existsSync(cmd)) {
    throw new Error('gradlew não encontrado em android/');
  }
  const out = execSync(`"${cmd}" signingReport`, {
    cwd,
    encoding: 'utf-8',
    maxBuffer: 4 * 1024 * 1024,
  });
  return out;
}

function parseShas(output) {
  const shas = { debug: { sha1: null, sha256: null }, release: { sha1: null, sha256: null } };
  const lines = output.split('\n');
  let currentVariant = null;
  for (const line of lines) {
    if (line.includes('Variant: release')) {
      currentVariant = 'release';
    } else if (line.includes('Variant: debug') && !line.includes('debugAndroidTest')) {
      currentVariant = 'debug';
    } else if (line.includes('Variant: profile') || line.includes('Variant: debugAndroidTest')) {
      currentVariant = null; // não sobrescrever release com SHAs de profile (usa debug)
    } else if (currentVariant && line.trim().startsWith('SHA1:')) {
      const m = line.match(/SHA1:\s*([A-Fa-f0-9:]+)/);
      if (m) shas[currentVariant].sha1 = m[1].trim();
    } else if (currentVariant && line.trim().startsWith('SHA-256:')) {
      const m = line.match(/SHA-256:\s*([A-Fa-f0-9:]+)/);
      if (m) shas[currentVariant].sha256 = m[1].trim();
    }
  }
  return shas;
}

async function listExistingShas(token) {
  const appIdEnc = encodeURIComponent(ANDROID_APP_ID);
  const url = `https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/androidApps/${appIdEnc}/sha`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok && res.status !== 404) {
    const text = await res.text();
    throw new Error(`listSha failed: ${res.status} ${text}`);
  }
  if (res.status === 404) return [];
  const data = await res.json();
  return data.certificates || [];
}

async function addSha(token, shaHash, certType) {
  const appIdEnc = encodeURIComponent(ANDROID_APP_ID);
  const url = `https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/androidApps/${appIdEnc}/sha`;
  const body = JSON.stringify({
    shaHash,
    certType,
  });
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`addSha failed (${shaHash}): ${res.status} ${text}`);
  }
  return res.json();
}

function shaAlreadyExists(existing, shaHash) {
  const normalized = shaHash.replace(/:/g, '').toLowerCase();
  return existing.some((c) => {
    const h = (c.shaHash || '').replace(/:/g, '').toLowerCase();
    return h === normalized;
  });
}

async function main() {
  console.log('🔐 Atualizando SHA no Firebase...\n');

  console.log('1️⃣ Executando gradlew signingReport...');
  const output = runSigningReport();
  const shas = parseShas(output);

  const toAdd = [];
  if (shas.debug.sha1) toAdd.push({ sha: shas.debug.sha1, type: 'SHA_1', label: 'debug SHA-1' });
  if (shas.debug.sha256) toAdd.push({ sha: shas.debug.sha256, type: 'SHA_256', label: 'debug SHA-256' });
  if (shas.release.sha1) toAdd.push({ sha: shas.release.sha1, type: 'SHA_1', label: 'release SHA-1' });
  if (shas.release.sha256) toAdd.push({ sha: shas.release.sha256, type: 'SHA_256', label: 'release SHA-256' });

  if (toAdd.length === 0) {
    console.log('❌ Nenhum SHA encontrado no output do Gradle.');
    process.exit(1);
  }

  console.log('   Debug SHA-1:', shas.debug.sha1 || '-');
  console.log('   Debug SHA-256:', shas.debug.sha256 || '-');
  console.log('   Release SHA-1:', shas.release.sha1 || '-');
  console.log('   Release SHA-256:', shas.release.sha256 || '-');
  console.log('');

  console.log('2️⃣ Autenticando...');
  const token = await getAccessToken();

  console.log('3️⃣ Verificando SHAs existentes no Firebase...');
  let existing = [];
  try {
    const listRes = await listExistingShas(token);
    existing = Array.isArray(listRes) ? listRes : (listRes.certificates || listRes.certs || []);
  } catch (e) {
    console.log('   (não foi possível listar, tentando adicionar mesmo assim)');
  }

  console.log('4️⃣ Adicionando SHAs faltantes...');
  let added = 0;
  for (const { sha, type, label } of toAdd) {
    if (shaAlreadyExists(existing, sha)) {
      console.log(`   ✓ ${label} já existe`);
      continue;
    }
    try {
      await addSha(token, sha, type);
      console.log(`   ✅ ${label} adicionado`);
      added++;
    } catch (e) {
      if (e.message && e.message.includes('ALREADY_EXISTS')) {
        console.log(`   ✓ ${label} já existe`);
      } else {
        console.error(`   ❌ ${label}:`, e.message);
      }
    }
  }

  console.log('');
  if (added > 0) {
    console.log(`✅ ${added} SHA(s) adicionado(s). Baixe o novo google-services.json em:`);
    console.log('   Firebase Console → Configurações do projeto → Seus apps → Android');
  } else {
    console.log('✅ Todos os SHAs já estavam no Firebase.');
  }
}

main().catch((e) => {
  console.error('❌ Erro:', e.message);
  process.exit(1);
});
