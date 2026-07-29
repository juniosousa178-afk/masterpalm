/** Firestore REST helpers — somente emulator (R8.4.38) */

import { FIRESTORE_HOST, PROJECT_ID, PRODUCTION_PROJECT_ID } from './constants.mjs';

export function firestoreBase() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('WEB_UI_E2E_QA_FAILS_CLOSED: FIRESTORE_EMULATOR_HOST ausente');
  }
  return `http://${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
}

export function assertSeedSafe() {
  if (process.env.GCLOUD_PROJECT === PRODUCTION_PROJECT_ID) {
    console.error('WEB_E2E_SYNTHETIC_SEED_PRODUCTION_BLOCKED');
    process.exit(2);
  }
}

export async function putDoc(path, fields) {
  const url = `${firestoreBase()}/${path}`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`PUT ${path} failed: ${res.status} ${t}`);
  }
}

export async function getDoc(path) {
  const res = await fetch(`${firestoreBase()}/${path}`);
  if (!res.ok) throw new Error(`GET ${path} ${res.status}`);
  return res.json();
}

export function str(v) {
  return { stringValue: String(v) };
}

export function int(v) {
  return { integerValue: String(v) };
}

export function bool(v) {
  return { booleanValue: !!v };
}

export function dbl(v) {
  return { doubleValue: v };
}

export function mapFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    if (typeof v === 'string') fields[k] = str(v);
    else if (typeof v === 'number' && Number.isInteger(v)) fields[k] = int(v);
    else if (typeof v === 'number') fields[k] = dbl(v);
    else if (typeof v === 'boolean') fields[k] = bool(v);
  }
  return { mapValue: { fields } };
}

export function parseIntField(fields, key, fallback = 0) {
  return Number(fields?.[key]?.integerValue ?? fields?.[key]?.doubleValue ?? fallback);
}

export function parseStringField(fields, key) {
  return fields?.[key]?.stringValue ?? '';
}
