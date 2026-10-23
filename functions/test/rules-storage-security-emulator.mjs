/**
 * Gate de segurança do Storage sob as Rules do repo: leitura pública do catálogo, escrita na própria loja,
 * contrato root (masterpalm26@gmail.com + email_verified) e escrita cross-tenant.
 * Exige FIREBASE_STORAGE_EMULATOR_HOST e FIRESTORE_EMULATOR_HOST (storage.rules usa firestore.get).
 * STORAGE_RULES_FILE permite correr a mesma matriz contra outro ruleset (ex.: o ativo em produção).
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";

const fsHost = process.env.FIRESTORE_EMULATOR_HOST;
const stHost = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
if (!fsHost || !stHost) {
  console.error("FIRESTORE_EMULATOR_HOST / FIREBASE_STORAGE_EMULATOR_HOST não definidos — abortando.");
  process.exit(1);
}
const hostPort = (h) => {
  const [host, port] = h.replace(/^https?:\/\//, "").split(":");
  return { host, port: Number(port) };
};
const here = dirname(fileURLToPath(import.meta.url));
const storageRules = readFileSync(process.env.STORAGE_RULES_FILE || join(here, "../../storage.rules"), "utf8");
const firestoreRules = readFileSync(join(here, "../../firestore.rules"), "utf8");

const A = "loja_a";
const B = "loja_b";
const U = {
  ownerA: "owner_a", ownerB: "owner_b", sellerA: "seller_a", memberAdminA: "member_admin_a", evil: "evil_user",
  root: "real_root", unverifiedRoot: "unverified_root", formerRootGmail: "former_root_gmail",
  fakeRootVerified: "fake_root_verified",
};
const EMAIL = {
  [U.root]: "masterpalm26@gmail.com",
  [U.unverifiedRoot]: "masterpalm26@gmail.com",
  [U.formerRootGmail]: "masterpalm@gmail.com",
  [U.fakeRootVerified]: "admin@masterpalm.com",
};
const VERIFIED = new Set([U.root, U.formerRootGmail, U.fakeRootVerified]);
const emailOf = (uid) => EMAIL[uid] ?? `${uid}@example.test`;

const results = [];
let failed = 0;
function record(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failed += 1;
  results.push({ name, ok, actual, expected });
  console.log(`${ok ? "  OK " : " FAIL"} ${name} actual=${JSON.stringify(actual)} expected=${JSON.stringify(expected)}`);
}
async function attempt(fn) {
  try {
    await fn();
    return "ALLOWED";
  } catch (e) {
    const s = String(e?.code || e?.message || e);
    return s.includes("unauthorized") || s.includes("permission") ? "DENIED" : `ERROR:${s}`;
  }
}
async function matrix(name, cases, expected) {
  const actual = {};
  for (const [k, fn] of Object.entries(cases)) actual[k] = await attempt(fn);
  const exp = typeof expected === "string" ? Object.fromEntries(Object.keys(cases).map((k) => [k, expected])) : expected;
  record(name, actual, exp);
}

let env;
const IMG = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
const META = { contentType: "image/jpeg" };
const st = (uid) =>
  uid ? env.authenticatedContext(uid, { email: emailOf(uid), email_verified: VERIFIED.has(uid) }).storage()
    : env.unauthenticatedContext().storage();
const put = (s, path) => s.ref(path).put(IMG, META);

async function seed() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [id, owner] of [[A, U.ownerA], [B, U.ownerB]]) {
      await db.collection("lojas").doc(id).set({ ownerUid: owner, nome: `Loja ${id}` });
      await db.collection("lojas").doc(id).collection("members").doc(owner).set({ role: "owner" });
      await db.collection("users").doc(owner).set({ uid: owner, role: "admin", store_id: id });
    }
    await db.collection("lojas").doc(A).collection("members").doc(U.memberAdminA).set({ role: "admin" });
    await db.collection("lojas").doc(A).collection("vendedores").doc(U.sellerA).set({ uid: U.sellerA, ativo: true });
    await db.collection("users").doc(U.sellerA).set({ uid: U.sellerA, role: "vendedor", store_id: A });
    const s = ctx.storage();
    for (const id of [A, B]) {
      for (const p of ["logos/logo.jpg", "banners/b1.jpg", "produtos/p1/img.jpg", "midias/m1.jpg", "logo.jpg"]) {
        await put(s, `lojas/${id}/${p}`);
      }
    }
  });
}

async function main() {
  env = await initializeTestEnvironment({
    projectId: "demo-storage-security",
    storage: { rules: storageRules, ...hostPort(stHost) },
    firestore: { rules: firestoreRules, ...hostPort(fsHost) },
  });
  try {
    await env.clearFirestore();
    await env.clearStorage();
    await seed();

    const anon = st(null);
    await matrix("PUBLIC.catalog_reads_anonymous", {
      logo: () => anon.ref(`lojas/${A}/logos/logo.jpg`).getMetadata(),
      banner: () => anon.ref(`lojas/${A}/banners/b1.jpg`).getMetadata(),
      produto: () => anon.ref(`lojas/${A}/produtos/p1/img.jpg`).getMetadata(),
      midia: () => anon.ref(`lojas/${A}/midias/m1.jpg`).getMetadata(),
    }, "ALLOWED");
    await matrix("PUBLIC.anonymous_writes", {
      produto: () => put(anon, `lojas/${A}/produtos/anon.jpg`),
      banner: () => put(anon, `lojas/${A}/banners/anon.jpg`),
      deleteLogo: () => anon.ref(`lojas/${A}/logos/logo.jpg`).delete(),
    }, "DENIED");

    for (const actor of [U.ownerA, U.sellerA, U.memberAdminA]) {
      const s = st(actor);
      await matrix(`SAME_STORE.${actor}`, {
        uploadProduto: () => put(s, `lojas/${A}/produtos/${actor}/n.jpg`),
        updateProduto: () => put(s, `lojas/${A}/produtos/${actor}/n.jpg`),
        deleteProduto: () => s.ref(`lojas/${A}/produtos/${actor}/n.jpg`).delete(),
        uploadBanner: () => put(s, `lojas/${A}/banners/${actor}.jpg`),
        uploadLogo: () => put(s, `lojas/${A}/logos/${actor}.jpg`),
      }, "ALLOWED");
    }

    const root = st(U.root);
    await matrix("PLATFORM.root_verified", {
      uploadProdutoB: () => put(root, `lojas/${B}/produtos/root/n.jpg`),
      deleteProdutoB: () => root.ref(`lojas/${B}/produtos/root/n.jpg`).delete(),
    }, "ALLOWED");

    for (const actor of [U.ownerA, U.sellerA, U.evil, U.unverifiedRoot, U.formerRootGmail, U.fakeRootVerified]) {
      const s = st(actor);
      await matrix(`CROSS_TENANT.${actor}->B`, {
        uploadProduto: () => put(s, `lojas/${B}/produtos/x/evil.jpg`),
        overwriteProduto: () => put(s, `lojas/${B}/produtos/p1/img.jpg`),
        deleteProduto: () => s.ref(`lojas/${B}/produtos/p1/img.jpg`).delete(),
        overwriteBanner: () => put(s, `lojas/${B}/banners/b1.jpg`),
        overwriteLogoDir: () => put(s, `lojas/${B}/logos/logo.jpg`),
        overwriteMidia: () => put(s, `lojas/${B}/midias/m1.jpg`),
        overwriteRootLogo: () => put(s, `lojas/${B}/logo.jpg`),
      }, "DENIED");
    }
  } finally {
    await env.cleanup();
  }
  console.log(JSON.stringify({ failed, total: results.length, failedNames: results.filter((r) => !r.ok).map((r) => r.name) }));
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
