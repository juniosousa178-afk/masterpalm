/** In-memory transactional Firestore for consignment tests. No production network. */
import {FieldValue, Timestamp} from 'firebase-admin/firestore';

function cloneData(value) {
  if (value instanceof Timestamp) return value;
  if (Array.isArray(value)) return value.map(cloneData);
  if (value && typeof value === 'object' && value.constructor === Object) {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = cloneData(v);
    return out;
  }
  return value && typeof value === 'object' ? structuredClone(value) : value;
}

function isSentinel(value, method) {
  if (value == null || typeof value !== 'object') return false;
  if (value._methodName === method) return true;
  try {
    if (method === 'serverTimestamp' && typeof FieldValue.serverTimestamp === 'function') {
      const s = FieldValue.serverTimestamp();
      if (typeof value.isEqual === 'function' && value.isEqual(s)) return true;
    }
    if (method === 'delete' && typeof FieldValue.delete === 'function') {
      const s = FieldValue.delete();
      if (typeof value.isEqual === 'function' && value.isEqual(s)) return true;
    }
  } catch { /* ignore */ }
  return false;
}

function isFieldValue(value) {
  if (value == null || typeof value !== 'object') return false;
  if (value instanceof FieldValue) return true;
  return typeof value._methodName === 'string' && value._methodName.length > 0;
}

/** Mirrors Admin SDK write validation: no transforms inside arrays, no undefined values. */
export function assertValidFirestoreData(value, path = '', inArray = false) {
  if (value === undefined) {
    throw new Error(`Cannot use "undefined" as a Firestore value (found in field "${path}").`);
  }
  if (isFieldValue(value)) {
    if (inArray) {
      const method = value.methodName || value._methodName || 'FieldValue';
      throw new Error(`${method}() cannot be used inside of an array (found in field "${path}").`);
    }
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((v, i) => assertValidFirestoreData(v, `${path}.\`${i}\``, true));
    return;
  }
  if (value && typeof value === 'object' && value.constructor === Object) {
    for (const [k, v] of Object.entries(value)) assertValidFirestoreData(v, path ? `${path}.${k}` : k, inArray);
  }
}

function materialize(value) {
  if (isSentinel(value, 'serverTimestamp')) return new Date('2026-09-20T12:00:00.000Z');
  if (Array.isArray(value)) return value.map(materialize);
  if (value && typeof value === 'object' && value.constructor === Object) {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (isSentinel(v, 'delete')) continue;
      out[k] = materialize(v);
    }
    return out;
  }
  return value;
}

export function createConsignmentTestDb() {
  const store = new Map();

  function makeRef(segments) {
    const path = segments.join('/');
    return {
      path,
      id: segments[segments.length - 1],
      collection(name) { return makeColl([...segments, name]); },
    };
  }
  function makeColl(segments) {
    return {
      doc(id) { return makeRef([...segments, id]); },
      async get() {
        const prefix = `${segments.join('/')}/`;
        const docs = [];
        for (const [path, data] of store) {
          if (!path.startsWith(prefix)) continue;
          const rest = path.slice(prefix.length);
          if (!rest || rest.includes('/')) continue;
          docs.push({
            id: rest,
            exists: true,
            data: () => cloneData(data),
          });
        }
        return {docs, empty: docs.length === 0, size: docs.length};
      },
    };
  }

  function snapFrom(working, ref) {
    const d = working.get(ref.path);
    return {
      exists: d !== undefined,
      id: ref.id,
      ref,
      data: () => (d === undefined ? undefined : cloneData(d)),
    };
  }

  const db = {
    _store: store,
    collection(name) { return makeColl([name]); },
    seed(ref, data) { store.set(ref.path, cloneData(data)); },
    getData(ref) { return store.has(ref.path) ? cloneData(store.get(ref.path)) : undefined; },
    exists(ref) { return store.has(ref.path); },
    snapshot() {
      return new Map([...store.entries()].map(([k, v]) => [k, cloneData(v)]));
    },
    async runTransaction(fn) {
      const working = new Map([...store.entries()].map(([k, v]) => [k, cloneData(v)]));
      const tx = {
        async get(ref) { return snapFrom(working, ref); },
        async getAll(...refs) { return refs.map(ref => snapFrom(working, ref)); },
        set(ref, data, opts) {
          assertValidFirestoreData(data);
          const prev = working.get(ref.path) || {};
          const next = opts?.merge ? {...prev, ...materialize(data)} : materialize(data);
          working.set(ref.path, next);
        },
        create(ref, data) {
          assertValidFirestoreData(data);
          if (working.has(ref.path)) {
            const err = new Error('ALREADY_EXISTS');
            err.code = 6;
            throw err;
          }
          working.set(ref.path, materialize(data));
        },
        update(ref, data) {
          assertValidFirestoreData(data);
          if (!working.has(ref.path)) {
            const err = new Error('NOT_FOUND');
            err.code = 5;
            throw err;
          }
          const prev = working.get(ref.path);
          const patch = materialize(data);
          working.set(ref.path, {...prev, ...patch});
        },
        delete(ref) { working.delete(ref.path); },
      };
      const result = await fn(tx);
      store.clear();
      for (const [k, v] of working) store.set(k, cloneData(v));
      return result;
    },
  };
  return db;
}
