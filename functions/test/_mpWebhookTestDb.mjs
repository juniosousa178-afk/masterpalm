/**
 * Firestore em memória transacional (consignment-test-db) + API de documento fora de transação
 * (get/set/update/create), cada uma executada como transação de um único documento.
 * Sem emulador, sem rede, sem produção.
 */
import {createConsignmentTestDb} from './consignment-test-db.mjs';

export function createMpWebhookTestDb() {
  const inner = createConsignmentTestDb();

  function wrapRef(ref) {
    const self = {
      path: ref.path,
      id: ref.id,
      collection(name) { return wrapColl(ref.collection(name)); },
      get: () => inner.runTransaction(tx => tx.get(self)),
      set: (data, opts) => inner.runTransaction(async tx => { tx.set(self, data, opts); }),
      update: data => inner.runTransaction(async tx => { tx.update(self, data); }),
      create: data => inner.runTransaction(async tx => { tx.create(self, data); }),
    };
    return self;
  }

  function wrapColl(coll) {
    return {
      _query: coll._query,
      doc(id) { return wrapRef(coll.doc(id)); },
      where(...args) { return coll.where(...args); },
      get: () => coll.get(),
    };
  }

  return {
    inner,
    collection(name) { return wrapColl(inner.collection(name)); },
    runTransaction: fn => inner.runTransaction(fn),
    seed: (ref, data, opts) => inner.seed(ref, data, opts),
    getData: ref => inner.getData(ref),
    exists: ref => inner.exists(ref),
    get commits() { return inner.commits; },
    paths(prefix) {
      return [...inner._store.keys()].filter(p => p.startsWith(prefix)).sort();
    },
  };
}
