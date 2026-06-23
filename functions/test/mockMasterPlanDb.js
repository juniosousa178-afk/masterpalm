/**
 * Mock Firestore in-memory para testes Mestre de planos.
 */

import assert from "node:assert/strict";

export function makeMasterPlanMockDb({
  users = {},
  subscriptions = {},
  courtesy = {},
  auditActions = {},
} = {}) {
  const writes = [];
  const state = {
    users: structuredClone(users),
    subscriptions: structuredClone(subscriptions),
    courtesy: structuredClone(courtesy),
    auditActions: structuredClone(auditActions),
  };

  function pathParts(path) {
    return path.split("/");
  }

  function getDoc(path) {
    const p = pathParts(path);
    if (p[0] === "users" && p.length === 2) {
      const u = state.users[p[1]];
      return { exists: !!u, data: () => u, id: p[1] };
    }
    if (p[0] === "users" && p[2] === "subscriptions" && p.length === 4) {
      const sub = state.subscriptions[p[1]]?.[p[3]];
      return { exists: !!sub, data: () => sub, id: p[3] };
    }
    if (p[0] === "users" && p[2] === "manualCourtesyGrant" && p.length === 4) {
      const cg = state.courtesy[p[1]];
      return { exists: !!cg, data: () => cg, id: p[3] };
    }
    if (p[0] === "admin_plan_actions" && p.length === 2) {
      const a = state.auditActions[p[1]];
      return { exists: !!a, data: () => a, id: p[1] };
    }
    return { exists: false, data: () => undefined, id: p[p.length - 1] };
  }

  function setDoc(path, data, opts = {}) {
    writes.push({ op: "set", path, data, opts });
    const p = pathParts(path);
    if (p[0] === "users" && p.length === 2) {
      if (opts.merge) state.users[p[1]] = { ...(state.users[p[1]] || {}), ...data };
      else state.users[p[1]] = structuredClone(data);
      return;
    }
    if (p[0] === "users" && p[2] === "manualCourtesyGrant" && p.length === 4) {
      if (opts.merge) state.courtesy[p[1]] = { ...(state.courtesy[p[1]] || {}), ...data };
      else state.courtesy[p[1]] = structuredClone(data);
      return;
    }
    if (p[0] === "admin_plan_actions" && p.length === 2) {
      state.auditActions[p[1]] = structuredClone(data);
    }
  }

  function docRef(path) {
    return {
      path,
      id: pathParts(path).at(-1),
      async get() {
        return getDoc(path);
      },
      async set(data, opts) {
        setDoc(path, data, opts);
      },
      collection(name) {
        const p = pathParts(path);
        const uid = p[1];
        if (name === "subscriptions") {
          const subMap = state.subscriptions[uid] || {};
          const docs = Object.entries(subMap).map(([id, data]) => ({
            id,
            data: () => data,
          }));
          return {
            orderBy() {
              return {
                limit(n) {
                  return { async get() { return { docs: docs.slice(0, n) }; } };
                },
              };
            },
            limit(n) {
              return { async get() { return { docs: docs.slice(0, n) }; } };
            },
          };
        }
        if (name === "manualCourtesyGrant") {
          return {
            doc(grantId) {
              return docRef(`${path}/manualCourtesyGrant/${grantId}`);
            },
          };
        }
        throw new Error(`unexpected collection ${name}`);
      },
    };
  }

  const db = {
    writes,
    state,
    collection(name) {
      if (name === "users") {
        const ids = Object.keys(state.users).sort();
        return {
          doc(id) {
            return docRef(`users/${id}`);
          },
          where(field, op, value) {
            let filtered = ids;
            if (field === "email" && op === "==") {
              filtered = ids.filter(
                (id) => String(state.users[id]?.email || "").toLowerCase() === value,
              );
            } else if (field === "cancelAtPeriodEnd") {
              filtered = ids.filter((id) => state.users[id]?.cancelAtPeriodEnd === value);
            } else if (field === "currentPlanId") {
              filtered = ids.filter((id) => state.users[id]?.currentPlanId === value);
            } else if (field === "manualOverride.enabled") {
              filtered = ids.filter(
                (id) => state.users[id]?.manualOverride?.enabled === value,
              );
            }
            return {
              limit(n) {
                return {
                  async get() {
                    const picked = filtered.slice(0, n);
                    return {
                      docs: picked.map((id) => ({
                        id,
                        data: () => state.users[id],
                      })),
                      empty: filtered.length === 0,
                      size: picked.length,
                    };
                  },
                };
              },
              count() {
                return {
                  async get() {
                    return { data: () => ({ count: filtered.length }) };
                  },
                };
              },
            };
          },
          count() {
            return {
              async get() {
                return { data: () => ({ count: ids.length }) };
              },
            };
          },
          orderBy(field) {
            assert.equal(field, "__name__");
            return {
              limit(n) {
                return {
                  startAfter(token) {
                    const startIdx = ids.indexOf(token);
                    const slice = startIdx >= 0 ? ids.slice(startIdx + 1) : ids;
                    return {
                      async get() {
                        const picked = slice.slice(0, n);
                        return {
                          docs: picked.map((id) => ({
                            id,
                            data: () => state.users[id],
                          })),
                        };
                      },
                    };
                  },
                  async get() {
                    const picked = ids.slice(0, n);
                    return {
                      docs: picked.map((id) => ({
                        id,
                        data: () => state.users[id],
                      })),
                    };
                  },
                };
              },
            };
          },
        };
      }
      if (name === "admin_plan_actions") {
        const ids = Object.keys(state.auditActions).sort().reverse();
        return {
          doc(id) {
            return docRef(`admin_plan_actions/${id}`);
          },
          where(field, op, value) {
            const filtered = ids.filter(
              (id) => state.auditActions[id]?.[field] === value,
            );
            return {
              orderBy(field2, dir) {
                assert.equal(field2, "createdAt");
                return {
                  limit(n) {
                    return {
                      startAfter(token) {
                        const startIdx = filtered.indexOf(token);
                        const slice = startIdx >= 0 ? filtered.slice(startIdx + 1) : filtered;
                        return {
                          async get() {
                            const picked = slice.slice(0, n);
                            return {
                              docs: picked.map((id) => ({
                                id,
                                data: () => state.auditActions[id],
                              })),
                            };
                          },
                        };
                      },
                      async get() {
                        const picked = filtered.slice(0, n);
                        return {
                          docs: picked.map((id) => ({
                            id,
                            data: () => state.auditActions[id],
                          })),
                        };
                      },
                    };
                  },
                };
              },
            };
          },
        };
      }
      throw new Error(`unexpected collection ${name}`);
    },
    collectionGroup(name) {
      if (name === "manualCourtesyGrant") {
        const active = Object.values(state.courtesy).filter((c) => c?.active === true).length;
        return {
          where(field, op, value) {
            assert.equal(field, "active");
            assert.equal(op, "==");
            assert.equal(value, true);
            return {
              count() {
                return {
                  async get() {
                    return { data: () => ({ count: active }) };
                  },
                };
              },
            };
          },
        };
      }
      throw new Error(`unexpected collectionGroup ${name}`);
    },
    async runTransaction(fn) {
      const txWrites = [];
      const tx = {
        async get(ref) {
          return ref.get();
        },
        set(ref, data, opts) {
          txWrites.push({ ref, data, opts });
        },
      };
      const result = await fn(tx);
      for (const w of txWrites) {
        await w.ref.set(w.data, w.opts);
      }
      return result;
    },
  };

  return db;
}
