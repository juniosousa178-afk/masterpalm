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

/** Field transforms count toward Firestore's per-commit write limit; FieldValue.delete() does not. */
function countTransforms(value) {
  if (isFieldValue(value)) return isSentinel(value, 'delete') ? 0 : 1;
  if (Array.isArray(value)) return value.reduce((n, v) => n + countTransforms(v), 0);
  if (value && typeof value === 'object' && value.constructor === Object) {
    return Object.values(value).reduce((n, v) => n + countTransforms(v), 0);
  }
  return 0;
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

/** Top-level FieldValue.delete() in an update / set(merge) removes the stored field. */
function withoutDeleted(merged, patch) {
  for (const [k, v] of Object.entries(patch ?? {})) if (isSentinel(v, 'delete')) delete merged[k];
  return merged;
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

const MAX_TRANSACTION_ATTEMPTS = 5;

export function createConsignmentTestDb() {
  const store = new Map();
  const versions = new Map();
  const bump = path => versions.set(path, (versions.get(path) ?? 0) + 1);

  function makeRef(segments) {
    const path = segments.join('/');
    return {
      path,
      id: segments[segments.length - 1],
      collection(name) { return makeColl([...segments, name]); },
    };
  }
  function makeQuery(segments, filters, max) {
    return {
      _query: {segments, filters, max},
      where(field, op, value) {
        if (op !== '==') throw new Error(`Unsupported test query op ${op}`);
        return makeQuery(segments, [...filters, {field, value}], max);
      },
      limit(n) { return makeQuery(segments, filters, n); },
      async get() { return runQuery(store, this._query); },
    };
  }
  function runQuery(source, {segments, filters, max}, onMatch) {
    const prefix = `${segments.join('/')}/`;
    const docs = [];
    for (const [path, data] of [...source.entries()].sort(([a], [b]) => a.localeCompare(b))) {
      if (!path.startsWith(prefix)) continue;
      const rest = path.slice(prefix.length);
      if (!rest || rest.includes('/')) continue;
      if (!filters.every(f => data?.[f.field] === f.value)) continue;
      if (max !== undefined && docs.length >= max) break;
      const ref = makeRef([...segments, rest]);
      onMatch?.(ref);
      docs.push({id: rest, ref, exists: true, data: () => cloneData(data)});
    }
    return {docs, empty: docs.length === 0, size: docs.length};
  }
  function makeColl(segments) {
    return {
      _query: {segments, filters: [], max: undefined},
      doc(id) { return makeRef([...segments, id]); },
      where(field, op, value) { return makeQuery(segments, [], undefined).where(field, op, value); },
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
    seed(ref, data) { store.set(ref.path, cloneData(data)); bump(ref.path); },
    /** Non-transactional write from another client; aborts transactions that already read this doc. */
    concurrentWrite(ref, data) { store.set(ref.path, cloneData(data)); bump(ref.path); },
    getData(ref) { return store.has(ref.path) ? cloneData(store.get(ref.path)) : undefined; },
    exists(ref) { return store.has(ref.path); },
    snapshot() {
      return new Map([...store.entries()].map(([k, v]) => [k, cloneData(v)]));
    },
    lastCommit: null,
    /** Every committed transaction: {writes, transforms, ops: [{type, path}]}. */
    commits: [],
    /** Collection paths queried inside transactions. */
    queryReads: [],
    attempts: 0,
    /** (path, attempt) => void, called on every transactional read. */
    onRead: null,
    /** ({type, path, index}) => void, called on every queued write; throwing aborts before commit. */
    faultInjector: null,
    async runTransaction(fn) {
      for (let attempt = 1; ; attempt++) {
        db.attempts++;
        const working = new Map([...store.entries()].map(([k, v]) => [k, cloneData(v)]));
        const readVersions = new Map();
        const stats = {writes: 0, transforms: 0};
        const ops = [];
        const read = ref => {
          if (!readVersions.has(ref.path)) readVersions.set(ref.path, versions.get(ref.path) ?? 0);
          db.onRead?.(ref.path, attempt);
          return snapFrom(working, ref);
        };
        const record = (type, ref, data) => {
          db.faultInjector?.({type, path: ref.path, index: ops.length});
          ops.push({type, path: ref.path});
          stats.writes++;
          if (data !== undefined) stats.transforms += countTransforms(data);
        };
        const tx = {
          async get(ref) {
            if (ref?._query) {
              db.queryReads.push(ref._query.segments.join('/'));
              return runQuery(working, ref._query, read);
            }
            return read(ref);
          },
          async getAll(...refs) { return refs.map(read); },
          set(ref, data, opts) {
            record('set', ref, data);
            assertValidFirestoreData(data);
            const prev = working.get(ref.path) || {};
            const next = opts?.merge ? withoutDeleted({...prev, ...materialize(data)}, data) : materialize(data);
            working.set(ref.path, next);
          },
          create(ref, data) {
            record('create', ref, data);
            assertValidFirestoreData(data);
            if (working.has(ref.path)) {
              const err = new Error('ALREADY_EXISTS');
              err.code = 6;
              throw err;
            }
            working.set(ref.path, materialize(data));
          },
          update(ref, data) {
            record('update', ref, data);
            assertValidFirestoreData(data);
            if (!working.has(ref.path)) {
              const err = new Error('NOT_FOUND');
              err.code = 5;
              throw err;
            }
            const prev = working.get(ref.path);
            const patch = materialize(data);
            working.set(ref.path, withoutDeleted({...prev, ...patch}, data));
          },
          delete(ref) { record('delete', ref); working.delete(ref.path); },
        };
        const result = await fn(tx);
        const conflict = [...readVersions].some(([path, v]) => (versions.get(path) ?? 0) !== v);
        if (conflict) {
          if (attempt >= MAX_TRANSACTION_ATTEMPTS) {
            const err = new Error('ABORTED: too much contention');
            err.code = 10;
            throw err;
          }
          continue;
        }
        const touched = new Set(ops.map(o => o.path));
        for (const path of touched) {
          if (working.has(path)) store.set(path, cloneData(working.get(path)));
          else store.delete(path);
          bump(path);
        }
        db.lastCommit = stats;
        db.commits.push({...stats, ops});
        return result;
      }
    },
  };
  return db;
}

/** The commit that created consignment_operations/{operationId} (the stock command itself, not projections). */
export function commandCommit(db, operationId) {
  return db.commits.find(c => c.ops.some(o => o.type === 'create' && o.path.endsWith(`/consignment_operations/${operationId}`)));
}

export const commitUnits = commit => commit.writes + commit.transforms;

/** Commits after `fromIndex` that wrote canonical stock (estoque_produtos). */
export function stockCommitsSince(db, fromIndex) {
  return db.commits.slice(fromIndex).filter(c => c.ops.some(o => o.path.includes('/estoque_produtos/')));
}
