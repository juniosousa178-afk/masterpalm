/** In-memory transactional Firestore for consignment tests. No production network. */
import {FieldValue} from 'firebase-admin/firestore';

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
            data: () => structuredClone(data),
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
      data: () => (d === undefined ? undefined : structuredClone(d)),
    };
  }

  const db = {
    _store: store,
    collection(name) { return makeColl([name]); },
    seed(ref, data) { store.set(ref.path, structuredClone(data)); },
    getData(ref) { return store.has(ref.path) ? structuredClone(store.get(ref.path)) : undefined; },
    exists(ref) { return store.has(ref.path); },
    snapshot() {
      return new Map([...store.entries()].map(([k, v]) => [k, structuredClone(v)]));
    },
    async runTransaction(fn) {
      const working = new Map([...store.entries()].map(([k, v]) => [k, structuredClone(v)]));
      const tx = {
        async get(ref) { return snapFrom(working, ref); },
        async getAll(...refs) { return refs.map(ref => snapFrom(working, ref)); },
        set(ref, data, opts) {
          const prev = working.get(ref.path) || {};
          const next = opts?.merge ? {...prev, ...materialize(data)} : materialize(data);
          working.set(ref.path, next);
        },
        create(ref, data) {
          if (working.has(ref.path)) {
            const err = new Error('ALREADY_EXISTS');
            err.code = 6;
            throw err;
          }
          working.set(ref.path, materialize(data));
        },
        update(ref, data) {
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
      for (const [k, v] of working) store.set(k, structuredClone(v));
      return result;
    },
  };
  return db;
}
