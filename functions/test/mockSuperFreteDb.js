/**
 * Mock Firestore in-memory para testes SuperFrete.
 */

import { FieldValue } from "firebase-admin/firestore";

const DELETE_FIELD = FieldValue.delete();

function isDeleteField(value) {
  return value === DELETE_FIELD;
}

export function makeSuperFreteMockDb({
  lojas = {},
  fretes = {},
  fretesSecrets = {},
  draftConfig = {},
} = {}) {
  const writes = [];
  const state = {
    lojas: structuredClone(lojas),
    fretes: structuredClone(fretes),
    fretesSecrets: structuredClone(fretesSecrets),
    draftConfig: structuredClone(draftConfig),
  };

  function fretesPath(lojaId) {
    return `lojas/${lojaId}/config/fretes`;
  }

  function secretsPath(lojaId) {
    return `lojas/${lojaId}/config/fretes_secrets`;
  }

  function draftPath(lojaId) {
    return `lojas/${lojaId}/draft_config/config`;
  }

  function lojaPath(lojaId) {
    return `lojas/${lojaId}`;
  }

  function getAt(path) {
    if (path.startsWith("lojas/") && path.endsWith("/config/fretes")) {
      const lojaId = path.split("/")[1];
      const data = state.fretes[lojaId];
      return { exists: !!data, data: () => data, id: "fretes" };
    }
    if (path.startsWith("lojas/") && path.endsWith("/config/fretes_secrets")) {
      const lojaId = path.split("/")[1];
      const data = state.fretesSecrets[lojaId];
      return { exists: !!data, data: () => data, id: "fretes_secrets" };
    }
    if (path.startsWith("lojas/") && path.endsWith("/draft_config/config")) {
      const lojaId = path.split("/")[1];
      const data = state.draftConfig[lojaId];
      return { exists: !!data, data: () => data, id: "config" };
    }
    if (path.startsWith("lojas/") && path.split("/").length === 2) {
      const lojaId = path.split("/")[1];
      const data = state.lojas[lojaId];
      return { exists: !!data, data: () => data, id: lojaId };
    }
    return { exists: false, data: () => undefined, id: path.split("/").at(-1) };
  }

  function setAt(path, data, opts = {}) {
    writes.push({ op: "set", path, data, opts });
    if (path.startsWith("lojas/") && path.endsWith("/config/fretes")) {
      const lojaId = path.split("/")[1];
      if (opts.merge && state.fretes[lojaId]) {
        state.fretes[lojaId] = deepMerge(state.fretes[lojaId], data);
      } else {
        state.fretes[lojaId] = structuredClone(data);
      }
      return;
    }
    if (path.startsWith("lojas/") && path.endsWith("/config/fretes_secrets")) {
      const lojaId = path.split("/")[1];
      if (opts.merge && state.fretesSecrets[lojaId]) {
        state.fretesSecrets[lojaId] = deepMerge(state.fretesSecrets[lojaId], data);
      } else {
        state.fretesSecrets[lojaId] = structuredClone(data);
      }
      return;
    }
    if (path.startsWith("lojas/") && path.endsWith("/draft_config/config")) {
      const lojaId = path.split("/")[1];
      if (opts.merge && state.draftConfig[lojaId]) {
        state.draftConfig[lojaId] = deepMerge(state.draftConfig[lojaId], data);
      } else {
        state.draftConfig[lojaId] = structuredClone(data);
      }
    }
  }

  function deepMerge(base, patch) {
    const out = { ...base };
    for (const [k, v] of Object.entries(patch)) {
      if (isDeleteField(v)) {
        delete out[k];
        continue;
      }
      if (v && typeof v === "object" && !Array.isArray(v) && out[k] && typeof out[k] === "object") {
        out[k] = deepMerge(out[k], v);
      } else {
        out[k] = v;
      }
    }
    return out;
  }

  function docRef(path) {
    return {
      path,
      id: path.split("/").at(-1),
      async get() {
        return getAt(path);
      },
      async set(data, opts) {
        setAt(path, data, opts);
      },
      collection(name) {
        const parent = path;
        return {
          doc(id) {
            const full = `${parent}/${name}/${id}`;
            return docRef(full);
          },
        };
      },
    };
  }

  const db = {
    writes,
    state,
    fretesPath,
    secretsPath,
    draftPath,
    lojaPath,
    collection(name) {
      return {
        doc(id) {
          return docRef(`${name}/${id}`);
        },
      };
    },
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
  };

  return db;
}
