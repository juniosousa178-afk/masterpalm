/** Firestore em memória para testes de billing (sem emulator / sem rede). */

export function createMemoryFirestore(seed = {}) {
  const docs = new Map(Object.entries(seed));

  function docRef(path) {
    const self = {
      path,
      id: path.split("/").pop(),
      collection(name) {
        return coll(`${path}/${name}`);
      },
      async get() {
        const d = docs.get(path);
        return {
          exists: d != null,
          data: () => (d != null ? { ...d } : undefined),
          id: path.split("/").pop(),
          ref: self,
        };
      },
      async set(data, opts) {
        const prev = docs.get(path) || {};
        const merged = opts?.merge ? { ...prev, ...data } : { ...data };
        docs.set(path, merged);
      },
    };
    return self;
  }

  function coll(prefix) {
    return {
      doc(id) {
        return docRef(`${prefix}/${id}`);
      },
      async get() {
        const p = `${prefix}/`;
        const found = [];
        for (const [k, v] of docs) {
          if (!k.startsWith(p)) continue;
          const rest = k.slice(p.length);
          if (!rest || rest.includes("/")) continue;
          found.push({
            id: rest,
            data: () => ({ ...v }),
            ref: docRef(k),
          });
        }
        return { empty: found.length === 0, docs: found };
      },
    };
  }

  return {
    _docs: docs,
    collection: coll,
    async runTransaction(fn) {
      const tx = {
        async get(ref) {
          return ref.get();
        },
        set(ref, data, opts) {
          return ref.set(data, opts);
        },
      };
      return fn(tx);
    },
    batch() {
      const ops = [];
      return {
        set(ref, data, opts) {
          ops.push(() => ref.set(data, opts));
        },
        async commit() {
          for (const o of ops) await o();
        },
      };
    },
  };
}
