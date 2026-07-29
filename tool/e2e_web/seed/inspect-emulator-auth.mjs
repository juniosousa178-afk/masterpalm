/**
 * Inspeção read-only do Auth Emulator seed (R8.4.41).
 */
import { LOJA_ID, USER_EMAIL, USER_PASSWORD } from '../lib/constants.mjs';

const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9199';
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180';
const PROJECT = process.env.FIREBASE_PROJECT_ID || 'masterpalm-r8433-web-e2e-local';

async function fetchFirestoreDoc(collection, id) {
  const url = `http://${FS_HOST}/v1/projects/${PROJECT}/databases/(default)/documents/${collection}/${id}`;
  const res = await fetch(url);
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Firestore ${res.status}`);
  return res.json();
}

async function verifyAuthUser() {
  const res = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: USER_EMAIL,
        password: USER_PASSWORD,
        returnSecureToken: true,
      }),
    },
  );
  if (!res.ok) return null;
  return res.json();
}

async function main() {
  const authData = await verifyAuthUser();
  const authUid = authData?.localId || '';
  const userDoc = authUid ? await fetchFirestoreDoc('users', authUid) : null;
  const usuarioDoc = await fetchFirestoreDoc('usuarios', USER_EMAIL);
  const lojaDoc = await fetchFirestoreDoc('lojas', LOJA_ID);

  const lojaFields = lojaDoc?.fields || {};
  const ativa =
    lojaFields.ativo?.booleanValue === true ||
    lojaFields.ativa?.booleanValue === true;

  const userLojaId =
    userDoc?.fields?.lojaId?.stringValue ||
    userDoc?.fields?.store_id?.stringValue ||
    usuarioDoc?.fields?.loja_id?.stringValue ||
    usuarioDoc?.fields?.store_id?.stringValue ||
    '';

  const lines = {
    AUTH_USER_EXISTS: Boolean(authUid),
    AUTH_UID_MATCH: Boolean(authUid && userDoc),
    USER_DOCUMENT_EXISTS: Boolean(userDoc || usuarioDoc),
    EMPRESA_LINK_VALID: userLojaId === LOJA_ID,
    EMPRESA_ACTIVE: Boolean(ativa),
  };

  for (const [k, v] of Object.entries(lines)) {
    console.log(`${k}=${v}`);
  }

  const allGreen = Object.values(lines).every(Boolean);
  process.exit(allGreen ? 0 : 1);
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
