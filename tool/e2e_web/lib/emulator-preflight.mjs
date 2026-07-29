/** Preflight fail-closed — emulator + seed (R8.4.38) */

import {
  AUTH_HOST,
  FIRESTORE_HOST,
  LOJA_ID,
  PROJECT_ID,
  PRODUCTION_PROJECT_ID,
} from './constants.mjs';
import { getDoc } from './firestore-rest.mjs';

export async function assertEmulatorPreflight() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('WEB_UI_E2E_QA_FAILS_CLOSED: FIRESTORE_EMULATOR_HOST ausente');
  }
  if (!process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_HOST;
  }

  try {
    await fetch(`http://${FIRESTORE_HOST}`, { signal: AbortSignal.timeout(3000) });
  } catch {
    throw new Error(`WEB_UI_E2E_QA_FAILS_CLOSED: Firestore emulator indisponível em ${FIRESTORE_HOST}`);
  }

  try {
    await fetch(`http://${AUTH_HOST}`, { signal: AbortSignal.timeout(3000) });
  } catch {
    throw new Error(`WEB_UI_E2E_QA_FAILS_CLOSED: Auth emulator indisponível em ${AUTH_HOST}`);
  }

  if (PROJECT_ID === PRODUCTION_PROJECT_ID) {
    throw new Error('WEB_UI_E2E_QA_FAILS_CLOSED: projectId produção bloqueado');
  }

  const loja = await getDoc(`lojas/${LOJA_ID}`);
  if (!loja.fields?.nome?.stringValue) {
    throw new Error('WEB_UI_E2E_QA_FAILS_CLOSED: seed não aplicado — execute npm run seed');
  }
}
