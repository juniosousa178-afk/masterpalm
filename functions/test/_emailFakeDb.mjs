/**
 * Firestore em memória + fixtures para os testes de sendEmail / sendWhatsAppOrderConfirmation.
 */
import { handleSendEmailRequest } from "../src/emailContracts.js";

export const agora = new Date("2026-10-09T12:00:00Z");
export const dia = 24 * 3600 * 1000;
export const LOJA = "loja-a";
export const OUTRA = "loja-b";
export const CAMP = "camp-1";
export const VENDA = "venda-123";
export const PART = "venda_venda-123";
export const NUM = "48213";
export const EMAIL = "cliente@example.test";
export const FONE = "(11) 98888-7777";
export const OWNER = "owner-1";
export const TOKENS = { "tok-owner": OWNER, "tok-intruso": "intruso-9", "tok-outra": "owner-b" };

export function createDb({ failCampaignLookup = false } = {}) {
  const docs = new Map();
  const doc = (path) => ({
    id: path.split("/").pop(),
    path,
    collection: (name) => coll(`${path}/${name}`),
    async get() {
      const data = docs.get(path);
      return { exists: data !== undefined, id: path.split("/").pop(), data: () => (data ? { ...data } : undefined) };
    },
    async create(data) {
      if (docs.has(path)) {
        const e = new Error("6 ALREADY_EXISTS: Document already exists");
        e.code = 6;
        throw e;
      }
      docs.set(path, data);
    },
    async set(data) {
      docs.set(path, { ...data });
    },
    async delete() {
      docs.delete(path);
    },
  });
  const coll = (path, filters = [], lim = Infinity) => ({
    doc: (id) => doc(`${path}/${id}`),
    where: (f, op, v) => coll(path, [...filters, [f, op, v]], lim),
    limit: (n) => coll(path, filters, n),
    async get() {
      if (failCampaignLookup && path.endsWith("/campanhas_sorteio")) throw new Error("unavailable");
      const prefix = `${path}/`;
      const out = [];
      for (const [p, data] of docs) {
        if (!p.startsWith(prefix) || p.slice(prefix.length).includes("/")) continue;
        const ok = filters.every(([f, op, v]) => (op === "in" ? v.includes(data[f]) : data[f] === v));
        if (ok) out.push({ id: p.slice(prefix.length), ref: doc(p), data: () => ({ ...data }) });
      }
      const sliced = out.slice(0, lim);
      return { docs: sliced, empty: sliced.length === 0, size: sliced.length };
    },
  });
  return {
    collection: (name) => coll(name),
    _set: (path, data) => docs.set(path, data),
    _get: (path) => docs.get(path),
    _has: (path) => docs.has(path),
    _count: (prefix) => [...docs.keys()].filter((k) => k.startsWith(prefix)).length,
  };
}

export const campanha = (over = {}) => ({
  ativa: true,
  status: "aberta",
  nome: "Campanha Teste",
  dataInicio: new Date(agora.getTime() - dia),
  dataFim: new Date(agora.getTime() + dia),
  ...over,
});

export const participante = (over = {}) => ({
  numeroSorte: NUM,
  campanhaId: CAMP,
  lojaId: LOJA,
  vendaId: VENDA,
  pedidoId: VENDA,
  status: "valido",
  clienteNome: "Maria Silva",
  clienteEmail: EMAIL,
  clienteTelefone: "11988887777",
  dataParticipacao: new Date(agora.getTime() - 3600 * 1000),
  ...over,
});

export function seedStore(db, { loja = LOJA, owner = OWNER, nome = "Loja A" } = {}) {
  if (!db._has(`lojas/${loja}`)) db._set(`lojas/${loja}`, { nome, ownerUid: owner });
}

export function seedValid(db, { loja = LOJA, camp = CAMP, part = PART, partData = {}, owner } = {}) {
  seedStore(db, { loja, owner: owner ?? (loja === LOJA ? OWNER : `owner-${loja.slice(-1)}`) });
  db._set(`lojas/${loja}/campanhas_sorteio/${camp}`, campanha());
  db._set(`lojas/${loja}/campanhas_sorteio/${camp}/participantes/${part}`, participante({ lojaId: loja, campanhaId: camp, ...partData }));
}

export function seedPedido(db, { loja = LOJA, id = "ped-9", venda = VENDA, over = {} } = {}) {
  seedStore(db, { loja });
  db._set(`lojas/${loja}/pedidos/${id}`, {
    lojaId: loja,
    vendaId: venda,
    cliente: { nome: "Maria Silva", email: EMAIL, telefone: "11988887777" },
    total: 129.9,
    subtotal: 129.9,
    cupomRoleta: null,
    ...over,
  });
}

export const raffleBody = (over = {}) => ({
  emailType: "raffle_participation",
  lojaId: LOJA,
  saleId: VENDA,
  campaignId: CAMP,
  participationId: PART,
  luckyNumber: NUM,
  ...over,
});

/** Chama o núcleo do sendEmail com token Bearer (default: dono da loja). */
export function emailHarness(db, { token = "tok-owner", failSend = () => false } = {}) {
  const sent = [];
  const call = (body, opts = {}) =>
    handleSendEmailRequest({
      db,
      body,
      idToken: opts.token === undefined ? token : opts.token,
      verifyIdToken: async (t) => {
        if (!TOKENS[t]) throw new Error("invalid token");
        return { uid: TOKENS[t] };
      },
      smtpUser: "smtp@example.test",
      sendMail: async (o) => {
        if (failSend()) throw new Error("smtp down");
        sent.push(o);
      },
      agora: opts.agora || agora,
    });
  return { sent, call };
}
