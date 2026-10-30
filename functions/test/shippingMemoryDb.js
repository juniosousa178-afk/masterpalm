/**
 * Firestore em memória para os testes de envio.
 * Transações são serializadas (como o isolamento do Firestore real) para testar concorrência.
 */

const isPlain = (v) => v != null && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype;

function deepMerge(target, src) {
  const out = isPlain(target) ? { ...target } : {};
  for (const [k, v] of Object.entries(src)) {
    out[k] = isPlain(v) && isPlain(out[k]) ? deepMerge(out[k], v) : v;
  }
  return out;
}

export function makeDb(initial = {}, { createTimeMs = null } = {}) {
  const docs = new Map(Object.entries(structuredClone(initial)));
  const writes = [];
  const reads = [];
  const db = { docs, writes, reads, createTimeMs };
  const docRef = (path) => ({
    path,
    collection: (name) => collectionRef(`${path}/${name}`),
    async get() {
      reads.push(path);
      const data = docs.get(path);
      const ms = db.createTimeMs;
      return {
        exists: data !== undefined,
        data: () => data,
        createTime: data !== undefined && Number.isFinite(ms) ? { toMillis: () => ms } : undefined,
      };
    },
    async set(data, opts = {}) {
      writes.push(path);
      docs.set(path, opts.merge ? deepMerge(docs.get(path), data) : { ...data });
    },
  });
  const collectionRef = (path) => ({ doc: (id) => docRef(`${path}/${id}`) });
  let chain = Promise.resolve();
  db.collection = (name) => collectionRef(name);
  db.runTransaction = (fn) => {
    const tx = {
      get: (ref) => ref.get(),
      set: (ref, data, opts) => ref.set(data, opts),
      update: (ref, data) => ref.set(data, { merge: true }),
    };
    const run = chain.then(() => fn(tx));
    chain = run.catch(() => {});
    return run;
  };
  return db;
}
