/**
 * Gate de segurança multi-loja sob as Rules do repo: autoescalada (users/usuarios), admin global
 * forjável, matriz cross-tenant (estoque, vendas, pedidos, …), operação normal na própria loja,
 * plataforma (root) e contrato de criação de venda por faixa de versão do app.
 * Exige FIRESTORE_EMULATOR_HOST (firebase emulators:exec).
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  console.error("FIRESTORE_EMULATOR_HOST não definido — abortando.");
  process.exit(1);
}
const [host, portStr] = emulatorHost.split(":");
const port = Number(portStr || "8080");
const rules = readFileSync(
  process.env.SECURITY_RULES_FILE || join(dirname(fileURLToPath(import.meta.url)), "../../firestore.rules"),
  "utf8",
);

const ts = () => firebase.firestore.FieldValue.serverTimestamp();
const A = "loja_a";
const B = "loja_b";
const O = "loja_sem_dono";
const U = {
  ownerA: "owner_a", ownerB: "owner_b", sellerA: "seller_a", sellerB: "seller_b", memberAdminA: "member_admin_a",
  evil: "evil_user", evilProg: "evil_programador", fakeRoot: "fake_root", root: "real_root", legacyO: "legacy_o",
  unverifiedRoot: "unverified_root", formerRootGmail: "former_root_gmail",
  formerRootGmailUnverified: "former_root_gmail_unverified", fakeRootVerified: "fake_root_verified",
  newUser: "new_user", newSeller: "new_seller_a",
};
const EMAIL = {
  [U.fakeRoot]: "admin@masterpalm.com",
  [U.fakeRootVerified]: "admin@masterpalm.com",
  [U.root]: "masterpalm26@gmail.com",
  [U.unverifiedRoot]: "masterpalm26@gmail.com",
  [U.formerRootGmail]: "masterpalm@gmail.com",
  [U.formerRootGmailUnverified]: "masterpalm@gmail.com",
};
// Pior caso para ex-root: mesmo com e-mail verificado não há autoridade de plataforma.
const VERIFIED = new Set([U.root, U.formerRootGmail, U.fakeRootVerified]);
const emailOf = (uid) => EMAIL[uid] ?? `${uid}@example.test`;

const results = [];
let failed = 0;
function record(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failed += 1;
  results.push({ name, ok });
  console.log(`${ok ? "  OK " : " FAIL"} ${name} actual=${JSON.stringify(actual)} expected=${JSON.stringify(expected)}`);
}

async function attempt(fn) {
  try {
    await fn();
    return "ALLOWED";
  } catch (e) {
    return String(e?.code || e?.message || e).includes("permission") ? "DENIED" : `ERROR:${e?.code || e?.message}`;
  }
}

async function matrix(name, cases, expected) {
  const actual = {};
  for (const [k, fn] of Object.entries(cases)) actual[k] = await attempt(fn);
  const exp = typeof expected === "string" ? Object.fromEntries(Object.keys(cases).map((k) => [k, expected])) : expected;
  record(name, actual, exp);
}

let env;
const dbAs = (uid) =>
  env.authenticatedContext(uid, { email: emailOf(uid), email_verified: VERIFIED.has(uid) }).firestore();
const loja = (db, id) => db.collection("lojas").doc(id);

async function seed() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [id, owner, seller] of [[A, U.ownerA, U.sellerA], [B, U.ownerB, U.sellerB]]) {
      const l = db.collection("lojas").doc(id);
      await l.set({ ownerUid: owner, ownerEmail: emailOf(owner), nome: `Loja ${id}`, published: true });
      await l.collection("members").doc(owner).set({ role: "owner", email: emailOf(owner) });
      await l.collection("vendedores").doc(seller).set({ uid: seller, ativo: true, storeId: id, permissoes: { vendas: true, estoque: true } });
      await l.collection("members").doc(seller).set({ role: "seller", email: emailOf(seller) });
      await l.collection("estoque_vendas").doc(`venda_${id}`).set({ id: `venda_${id}`, total: 10, stockOperationId: `venda_${id}` });
      await l.collection("estoque_produtos").doc(`prod_${id}`).set({ nome: "Anel", quantidade: 5, variacoes: {}, stockRevision: 1, stockOperationId: "seed" });
      await l.collection("produtos").doc(`prod_${id}`).set({ nome: "Anel", quantidade: 5, preco: 10 });
      await l.collection("pre_pedidos").doc(`pp_${id}`).set({ lojaId: id, status: "pendente", total: 10, cliente: { email: "c@example.test" }, itens: [{ id: `prod_${id}`, quantidade: 1 }] });
      await l.collection("pedidos").doc(`ped_${id}`).set({ lojaId: id, status: "novo", total: 10 });
      await l.collection("clientes").doc(`cli_${id}`).set({ nome: "Cliente", email: "c@example.test" });
      await l.collection("categorias").doc(`cat_${id}`).set({ nome: "Anéis" });
      await l.collection("config").doc("payments").set({ provider: "mp" });
      await l.collection("comissoes").doc(`com_${id}`).set({ vendedorUid: seller, valor: 1 });
      await l.collection("contas_receber").doc(`cr_${id}`).set({ lojaId: id, valor: 10 });
      await l.collection("sale_intents").doc(`pre_pedido:pp_${id}`).set({ status: "completed" });
      await db.collection("users").doc(owner).set({ uid: owner, email: emailOf(owner), role: "admin", store_id: id, storeId: id, lojaId: id, ownerOf: id });
      await db.collection("users").doc(seller).set({ uid: seller, email: emailOf(seller), role: "vendedor", tipo: "vendedor", store_id: id, storeId: id, lojaId: id });
      await db.collection("usuarios").doc(emailOf(seller)).set({ authUid: seller, email: emailOf(seller), tipo: "vendedor", store_id: id, ownerStoreId: id, senha: "legacy-secret" });
      await db.collection("usuarios").doc(emailOf(owner)).set({ authUid: owner, email: emailOf(owner), tipo: "admin", store_id: id, ownerStoreId: id });
    }
    await db.collection("lojas").doc(A).collection("members").doc(U.memberAdminA).set({ role: "admin", email: emailOf(U.memberAdminA) });
    await db.collection("lojas").doc(A).collection("vendedores").doc("seller_a2").set({ uid: "seller_a2", ativo: true, storeId: A, permissoes: { vendas: true } });
    // Contas que hoje se autopromovem: role/tipo admin e programador gravados pelo próprio cliente.
    await db.collection("users").doc(U.evil).set({ uid: U.evil, role: "admin" });
    await db.collection("usuarios").doc(emailOf(U.evil)).set({ authUid: U.evil, tipo: "admin" });
    await db.collection("users").doc(U.evilProg).set({ uid: U.evilProg, role: "programador" });
    await db.collection("usuarios").doc(emailOf(U.evilProg)).set({ authUid: U.evilProg, tipo: "programador" });
    await db.collection("users").doc(U.fakeRoot).set({ uid: U.fakeRoot, role: "admin" });
    // Loja legada sem ownerUid, resolvida por users.store_id.
    await db.collection("lojas").doc(O).set({ nome: "Loja sem dono" });
    await db.collection("users").doc(U.legacyO).set({ uid: U.legacyO, role: "admin", store_id: O });
    await db.collection("lojas").doc(O).collection("estoque_vendas").doc("venda_o").set({ total: 1, stockOperationId: "venda_o" });
    await db.collection("app_config").doc("master_config").set({ x: 1 });
    // Evidências de baixa canónica por faixa de versão.
    await db.collection("lojas").doc(A).collection("stock_catalog_operations").doc("venda_op_server").set({ state: "APPLIED" });
    await db.collection("lojas").doc(A).collection("estoque_baixa_pagamento").doc("venda_marker_tx").set({ baixaAplicada: true });
  });
}

/** Leituras/escritas de um ator sobre a loja `id` (não deve ter acesso). */
function crossTenantCases(actor, id) {
  const db = dbAs(actor);
  const l = loja(db, id);
  return {
    readSales: () => l.collection("estoque_vendas").get(),
    createSale: () => l.collection("estoque_vendas").doc("x_sale").set({ total: 1, stockOperationId: "x_sale" }),
    updateSale: () => l.collection("estoque_vendas").doc(`venda_${id}`).update({ total: 0 }),
    deleteSale: () => l.collection("estoque_vendas").doc(`venda_${id}`).delete(),
    readStock: () => l.collection("estoque_produtos").get(),
    writeStock: () => l.collection("estoque_produtos").doc(`prod_${id}`).update({ quantidade: 0, stockRevision: 2, stockOperationId: "x_op" }),
    readPrePedidos: () => l.collection("pre_pedidos").get(),
    updatePrePedido: () => l.collection("pre_pedidos").doc(`pp_${id}`).update({ status: "cancelado" }),
    readPedidos: () => l.collection("pedidos").get(),
    updatePedido: () => l.collection("pedidos").doc(`ped_${id}`).update({ status: "cancelado" }),
    listClientes: () => l.collection("clientes").get(),
    writeCategoria: () => l.collection("categorias").doc("x_cat").set({ nome: "x" }),
    writeProduto: () => l.collection("produtos").doc(`prod_${id}`).update({ preco: 0 }),
    readSaleIntents: () => l.collection("sale_intents").get(),
    readPayments: () => l.collection("config").doc("payments").get(),
    writePayments: () => l.collection("config").doc("payments").set({ provider: "evil" }),
    readMembers: () => l.collection("members").get(),
    addSelfMemberOwner: () => l.collection("members").doc(actor).set({ role: "owner", email: emailOf(actor) }),
    addSelfSellerActive: () => l.collection("vendedores").doc(actor).set({ uid: actor, ativo: true, permissoes: { vendas: true } }),
    addSeller: () => l.collection("vendedores").doc("x_seller").set({ ativo: true, permissoes: { vendas: true } }),
    readComissoes: () => l.collection("comissoes").get(),
    readContasReceber: () => l.collection("contas_receber").where("lojaId", "==", id).get(),
    updateLojaNome: () => l.update({ nome: "pwned" }),
    takeOwnership: () => l.update({ ownerUid: "attacker" }),
  };
}

async function main() {
  env = await initializeTestEnvironment({ projectId: "demo-security-tenant", firestore: { rules, host, port } });
  try {
    await env.clearFirestore();
    await seed();

    // §1/§3 — autoescalada de papel e auto-reatribuição de loja.
    {
      const evil = dbAs(U.evil);
      const users = evil.collection("users");
      await matrix("ESCALATION.self_role_and_store", {
        setRoleProgramador: () => users.doc(U.evil).set({ role: "programador" }, { merge: true }),
        setTipoUsuarioProgramador: () => users.doc(U.evil).set({ tipo_usuario: "programador" }, { merge: true }),
        setIsRoot: () => users.doc(U.evil).set({ is_root: true }, { merge: true }),
        changeExistingRole: () => users.doc(U.evil).set({ role: "vendedor" }, { merge: true }),
        pointStoreIdToB: () => users.doc(U.evil).set({ store_id: B }, { merge: true }),
        pointStoreIdCamelToB: () => users.doc(U.evil).set({ storeId: B }, { merge: true }),
        pointLojaIdToB: () => users.doc(U.evil).set({ lojaId: B }, { merge: true }),
        pointOwnerOfToB: () => users.doc(U.evil).set({ ownerOf: B }, { merge: true }),
        claimOwnerlessStore: () => users.doc(U.evil).set({ store_id: O }, { merge: true }),
        paidPlan: () => users.doc(U.evil).set({ currentPlanId: "lifetime" }, { merge: true }),
        manualOverride: () => users.doc(U.evil).set({ manualOverride: true }, { merge: true }),
        usuariosTipoProgramador: () => evil.collection("usuarios").doc(emailOf(U.evil)).set({ tipo: "programador" }, { merge: true }),
        usuariosUnlimited: () => evil.collection("usuarios").doc(emailOf(U.evil)).set({ unlimitedAccess: true }, { merge: true }),
        usuariosPointToB: () => evil.collection("usuarios").doc(emailOf(U.evil)).set({ store_id: B }, { merge: true }),
        writeOtherUserDoc: () => users.doc(U.ownerB).set({ store_id: A }, { merge: true }),
        createUserDocForB: () => users.doc("victim").set({ role: "vendedor", store_id: B }),
      }, "DENIED");

      const fresh = dbAs("fresh_account");
      await matrix("ESCALATION.fresh_account_create", {
        createProgramador: () => fresh.collection("users").doc("fresh_account").set({ role: "programador" }),
        createAdminPointingToB: () => fresh.collection("users").doc("fresh_account").set({ role: "admin", store_id: B }),
        createUsuariosProgramador: () => fresh.collection("usuarios").doc(emailOf("fresh_account")).set({ tipo: "programador" }),
      }, "DENIED");
      // role 'admin' é o rótulo de dono no registo; já não confere autoridade (ver cross-tenant abaixo).
      record("ESCALATION.fresh_account_admin_label_is_inert",
        [await attempt(() => fresh.collection("users").doc("fresh_account").set({ role: "admin" })),
          await attempt(() => loja(fresh, B).collection("estoque_vendas").get())],
        ["ALLOWED", "DENIED"]);

      const seller = dbAs(U.sellerA);
      await matrix("ESCALATION.seller_self", {
        roleVendedorToAdmin: () => seller.collection("users").doc(U.sellerA).set({ role: "admin" }, { merge: true }),
        tipoVendedorToAdmin: () => seller.collection("usuarios").doc(emailOf(U.sellerA)).set({ tipo: "admin" }, { merge: true }),
        selfMemberAdmin: () => loja(seller, A).collection("members").doc(U.sellerA).set({ role: "admin" }),
        selfPermissions: () => loja(seller, A).collection("vendedores").doc(U.sellerA).update({ "permissoes.financeiro": true }),
      }, "DENIED");
    }

    // §5/§7 — matriz cross-tenant: nenhum destes atores acede à loja B.
    for (const actor of [
      U.ownerA, U.sellerA, U.memberAdminA, U.evil, U.evilProg, U.fakeRoot, U.legacyO,
      U.unverifiedRoot, U.formerRootGmail, U.formerRootGmailUnverified, U.fakeRootVerified,
    ]) {
      await matrix(`CROSS_TENANT.${actor}->B`, crossTenantCases(actor, B), "DENIED");
    }
    {
      const ownerA = dbAs(U.ownerA);
      await matrix("CROSS_TENANT.identity_docs", {
        ownerAReadsOwnerBUser: () => ownerA.collection("users").doc(U.ownerB).get(),
        ownerAReadsSellerBUser: () => ownerA.collection("users").doc(U.sellerB).get(),
        ownerAReadsSellerBUsuarios: () => ownerA.collection("usuarios").doc(emailOf(U.sellerB)).get(),
        ownerADeletesSellerBUser: () => ownerA.collection("users").doc(U.sellerB).delete(),
        ownerAUpdatesSellerBUsuarios: () => ownerA.collection("usuarios").doc(emailOf(U.sellerB)).set({ tipo: "vendedor", store_id: A }, { merge: true }),
        ownerACreatesSellerForB: () => ownerA.collection("users").doc("nova_conta").set({ role: "vendedor", store_id: B }),
        evilListsUsuarios: () => dbAs(U.evil).collection("usuarios").get(),
        evilReadsSellerAUsuarios: () => dbAs(U.evil).collection("usuarios").doc(emailOf(U.sellerA)).get(),
        evilProgReadsMasterConfig: () => dbAs(U.evilProg).collection("app_config").doc("master_config").get(),
        fakeRootReadsMasterConfig: () => dbAs(U.fakeRoot).collection("app_config").doc("master_config").get(),
        fakeRootReadsAnyUser: () => dbAs(U.fakeRoot).collection("users").doc(U.ownerB).get(),
      }, "DENIED");
    }

    // §6 — operação normal na própria loja.
    {
      const ownerA = dbAs(U.ownerA);
      const l = loja(ownerA, A);
      await matrix("SAME_STORE.owner", {
        readSales: () => l.collection("estoque_vendas").get(),
        createSaleV103: () => l.collection("estoque_vendas").doc("venda_nova").set({ total: 10, stockOperationId: "venda_nova" }),
        editSale: () => l.collection("estoque_vendas").doc(`venda_${A}`).update({ total: 11 }),
        deleteSale: () => l.collection("estoque_vendas").doc("venda_nova").delete(),
        readStock: () => l.collection("estoque_produtos").get(),
        writeStock: () => l.collection("estoque_produtos").doc(`prod_${A}`).update({ quantidade: 4, stockRevision: 2, stockOperationId: "op_owner" }),
        readPrePedidos: () => l.collection("pre_pedidos").get(),
        updatePrePedidoStatus: () => l.collection("pre_pedidos").doc(`pp_${A}`).update({ status: "embalando" }),
        readPedidos: () => l.collection("pedidos").get(),
        updatePedido: () => l.collection("pedidos").doc(`ped_${A}`).update({ status: "enviado" }),
        listClientes: () => l.collection("clientes").get(),
        writeCategoria: () => l.collection("categorias").doc("cat_nova").set({ nome: "Colares" }),
        writeProduto: () => l.collection("produtos").doc(`prod_${A}`).update({ preco: 12 }),
        createSaleIntent: () => l.collection("sale_intents").doc("pdv_manual:x1").set({
          protocolVersion: 1, saleIntentId: "pdv_manual:x1", lojaId: A, origin: "pdv_manual", operationId: "x1",
          status: "reserved", stockEffectHash: "h", createdAt: ts(), updatedAt: ts(),
        }),
        readSaleIntents: () => l.collection("sale_intents").get(),
        readPayments: () => l.collection("config").doc("payments").get(),
        writePayments: () => l.collection("config").doc("payments").set({ provider: "mp", ok: true }),
        readMembers: () => l.collection("members").get(),
        addSeller: () => l.collection("vendedores").doc(U.newSeller).set({ uid: U.newSeller, ativo: true, storeId: A, permissoes: { vendas: true } }),
        toggleSeller: () => l.collection("vendedores").doc(U.sellerA).update({ ativo: true }),
        addMemberSeller: () => l.collection("members").doc(U.newSeller).set({ role: "seller", email: emailOf(U.newSeller) }),
        createSellerUserDoc: () => ownerA.collection("users").doc(U.newSeller).set({
          uid: U.newSeller, email: emailOf(U.newSeller), role: "vendedor", tipo: "vendedor", ownerId: U.ownerA,
          lojaId: A, storeId: A, store_id: A, createdAt: ts(), ativo: true,
        }),
        updateSellerUserDoc: () => ownerA.collection("users").doc(U.sellerA).update({ ativo: true, updatedAt: ts() }),
        createSellerUsuarios: () => ownerA.collection("usuarios").doc(emailOf(U.newSeller)).set({
          authUid: U.newSeller, email: emailOf(U.newSeller), tipo: "vendedor", role: "vendedor",
          store_id: A, ownerStoreId: A, ownerAdminEmail: emailOf(U.ownerA), ativo: true, createdAt: ts(), updatedAt: ts(),
        }),
        readSellerUsuarios: () => ownerA.collection("usuarios").doc(emailOf(U.sellerA)).get(),
        readSellerUser: () => ownerA.collection("users").doc(U.sellerA).get(),
        readComissoes: () => l.collection("comissoes").get(),
        readContasReceber: () => l.collection("contas_receber").where("lojaId", "==", A).get(),
        updateLojaNome: () => l.update({ nome: "Loja A renomeada" }),
        ensureOwnerUidSameOwner: () => l.set({ ownerUid: U.ownerA, updatedAt: ts() }, { merge: true }),
        selfFcmToken: () => ownerA.collection("users").doc(U.ownerA).set({ fcmToken: "t", fcmTokenUpdatedAt: ts() }, { merge: true }),
        readOwnUser: () => ownerA.collection("users").doc(U.ownerA).get(),
      }, "ALLOWED");
      await matrix("SAME_STORE.owner_limits", {
        transferOwnership: () => l.update({ ownerUid: U.sellerA }),
        sellerDocPointsToB: () => ownerA.collection("users").doc(U.sellerA).set({ store_id: B }, { merge: true }),
        sellerDocToProgramador: () => ownerA.collection("users").doc(U.sellerA).set({ role: "programador" }, { merge: true }),
      }, "DENIED");
    }
    {
      const mA = dbAs(U.memberAdminA);
      const l = loja(mA, A);
      await matrix("SAME_STORE.member_admin", {
        readSales: () => l.collection("estoque_vendas").get(),
        createSale: () => l.collection("estoque_vendas").doc("venda_member").set({ total: 1, stockOperationId: "venda_member" }),
        writeStock: () => l.collection("estoque_produtos").doc(`prod_${A}`).update({ quantidade: 3, stockRevision: 3, stockOperationId: "op_member" }),
        updatePrePedido: () => l.collection("pre_pedidos").doc(`pp_${A}`).update({ status: "enviado" }),
        writeCategoria: () => l.collection("categorias").doc("cat_member").set({ nome: "x" }),
        writePayments: () => l.collection("config").doc("payments").set({ provider: "mp" }),
        updateLojaNome: () => l.update({ nome: "Loja A (member)" }),
      }, "ALLOWED");
      record("SAME_STORE.member_admin_cannot_take_ownership",
        await attempt(() => l.set({ ownerUid: U.memberAdminA, updatedAt: ts() }, { merge: true })), "DENIED");
    }
    {
      const sA = dbAs(U.sellerA);
      const l = loja(sA, A);
      await matrix("SAME_STORE.seller", {
        readSales: () => l.collection("estoque_vendas").get(),
        createSale: () => l.collection("estoque_vendas").doc("venda_seller").set({ total: 1, stockOperationId: "venda_seller" }),
        writeStock: () => l.collection("estoque_produtos").doc(`prod_${A}`).update({ quantidade: 2, stockRevision: 4, stockOperationId: "op_seller" }),
        readPrePedidos: () => l.collection("pre_pedidos").get(),
        readPedidos: () => l.collection("pedidos").get(),
        listClientes: () => l.collection("clientes").get(),
        createSaleIntent: () => l.collection("sale_intents").doc("pdv_manual:s1").set({
          protocolVersion: 1, saleIntentId: "pdv_manual:s1", lojaId: A, origin: "pdv_manual", operationId: "s1",
          status: "reserved", stockEffectHash: "h", createdAt: ts(), updatedAt: ts(),
        }),
        readComissoes: () => l.collection("comissoes").get(),
        readOwnUser: () => sA.collection("users").doc(U.sellerA).get(),
        readOwnUsuarios: () => sA.collection("usuarios").doc(emailOf(U.sellerA)).get(),
        queryOwnUsuariosByAuthUid: () => sA.collection("usuarios").where("authUid", "==", U.sellerA).limit(1).get(),
        selfFcmToken: () => sA.collection("users").doc(U.sellerA).set({ fcmToken: "t" }, { merge: true }),
        // Reparo de login legado: recria usuarios/{email} copiando o perfil achado por authUid.
        legacyLoginRepairUsuarios: () => dbAs("seller_a2").collection("usuarios").doc(emailOf("seller_a2")).set({
          authUid: "seller_a2", tipo: "vendedor", store_id: A, ownerStoreId: A, email: emailOf("seller_a2"),
        }, { merge: true }),
      }, "ALLOWED");
      await matrix("SAME_STORE.seller_limits", {
        writeCategoria: () => l.collection("categorias").doc("cat_seller").set({ nome: "x" }),
        writePayments: () => l.collection("config").doc("payments").set({ provider: "x" }),
        updateLojaNome: () => l.update({ nome: "x" }),
        readOwnerUser: () => sA.collection("users").doc(U.ownerA).get(),
        pointOwnProfileToOtherStore: () => sA.collection("users").doc(U.sellerA).set({ store_id: B }, { merge: true }),
      }, "DENIED");
    }
    {
      const lo = dbAs(U.legacyO);
      await matrix("SAME_STORE.legacy_ownerless_store", {
        readSales: () => loja(lo, O).collection("estoque_vendas").get(),
        fcmTokenKeepsPointer: () => lo.collection("users").doc(U.legacyO).set({ fcmToken: "t" }, { merge: true }),
        backfillOwnerUidToSelf: () => loja(lo, O).set({ ownerUid: U.legacyO, updatedAt: ts() }, { merge: true }),
      }, "ALLOWED");
    }

    // Registo de conta nova (ordem do app: loja → config/members → users → usuarios).
    {
      const nu = dbAs(U.newUser);
      const slug = "loja_nova";
      await matrix("REGISTRATION.new_merchant", {
        createStore: () => loja(nu, slug).set({ ownerUid: U.newUser, ownerEmail: emailOf(U.newUser), nome: "Nova", slug, createdAt: ts() }),
        createConfig: () => loja(nu, slug).collection("config").doc("geral").set({ nome: "Nova" }),
        createMemberOwner: () => loja(nu, slug).collection("members").doc(U.newUser).set({ role: "owner", email: emailOf(U.newUser), joinedAt: ts() }),
        createUsersDoc: () => nu.collection("users").doc(U.newUser).set({
          uid: U.newUser, email: emailOf(U.newUser), nome: "Nova", role: "admin", ownerId: U.newUser,
          lojaId: slug, store_id: slug, ownerOf: slug, currentPlanId: "free_trial_90d", status: "trialing", createdAt: ts(),
        }),
        createUsuariosDoc: () => nu.collection("usuarios").doc(emailOf(U.newUser)).set({
          authUid: U.newUser, email: emailOf(U.newUser), tipo: "admin", store_id: slug, ownerStoreId: slug, createdAt: ts(),
        }),
        createFirstSale: () => loja(nu, slug).collection("estoque_vendas").doc("v1").set({ total: 1, stockOperationId: "v1" }),
      }, "ALLOWED");
    }

    // Plataforma legítima (root real).
    {
      const root = dbAs(U.root);
      await matrix("PLATFORM.root", {
        readSalesB: () => loja(root, B).collection("estoque_vendas").get(),
        updateLojaB: () => loja(root, B).update({ suporte: true }),
        readUserB: () => root.collection("users").doc(U.ownerB).get(),
        listUsuarios: () => root.collection("usuarios").get(),
        readMasterConfig: () => root.collection("app_config").doc("master_config").get(),
        writeMasterConfig: () => root.collection("app_config").doc("master_config").set({ x: 2 }),
        selfRoleProgramador: () => root.collection("users").doc(U.root).set({ role: "programador", is_root: true }, { merge: true }),
      }, "ALLOWED");
    }

    // E-mail root sem email_verified (registo não confirmado do endereço) não é plataforma.
    {
      const ur = dbAs(U.unverifiedRoot);
      await matrix("PLATFORM.root_unverified", {
        readSalesB: () => loja(ur, B).collection("estoque_vendas").get(),
        updateLojaB: () => loja(ur, B).update({ suporte: true }),
        readUserB: () => ur.collection("users").doc(U.ownerB).get(),
        listUsuarios: () => ur.collection("usuarios").get(),
        writeMasterConfig: () => ur.collection("app_config").doc("master_config").set({ x: 3 }),
      }, "DENIED");
    }

    // Ex-root (masterpalm@gmail.com, admin@masterpalm.com) não têm autoridade de plataforma.
    for (const actor of [U.formerRootGmail, U.formerRootGmailUnverified, U.fakeRoot, U.fakeRootVerified]) {
      const fr = dbAs(actor);
      await matrix(`PLATFORM.former_root.${actor}`, {
        readSalesB: () => loja(fr, B).collection("estoque_vendas").get(),
        updateLojaB: () => loja(fr, B).update({ suporte: true }),
        readUserB: () => fr.collection("users").doc(U.ownerB).get(),
        listUsuarios: () => fr.collection("usuarios").get(),
        readMasterConfig: () => fr.collection("app_config").doc("master_config").get(),
        writeMasterConfig: () => fr.collection("app_config").doc("master_config").set({ x: 4 }),
        selfRoleProgramador: () => fr.collection("users").doc(actor).set({ role: "programador", is_root: true }, { merge: true }),
      }, "DENIED");
    }

    // §10–§13 — contrato de criação de venda por faixa de versão (loja A, dono).
    {
      const l = loja(dbAs(U.ownerA), A);
      await matrix("SALE_CONTRACT.by_version", {
        v1_0_79_noLinkage: () => l.collection("estoque_vendas").doc("legacy-uuid-1").set({ total: 50, status: "concluida", formasPagamento: "PIX" }),
        v1_0_80_clientTxMarker: () => l.collection("estoque_vendas").doc("venda_marker_tx").set({ total: 50 }),
        v1_0_84_serverOperation: () => l.collection("estoque_vendas").doc("venda_op_server").set({ total: 50 }),
        v1_0_84_noOperationDoc: () => l.collection("estoque_vendas").doc("venda_sem_op").set({ total: 50 }),
        v1_0_103_stockOperationId: () => l.collection("estoque_vendas").doc("venda_v103").set({ total: 50, stockOperationId: "venda_v103" }),
        emptyStockOperationId: () => l.collection("estoque_vendas").doc("venda_vazia").set({ total: 50, stockOperationId: "" }),
        legacyEditExistingSale: () => l.collection("estoque_vendas").doc(`venda_${A}`).set({ total: 9 }, { merge: true }),
      }, {
        v1_0_79_noLinkage: "DENIED",
        v1_0_80_clientTxMarker: "ALLOWED",
        v1_0_84_serverOperation: "ALLOWED",
        v1_0_84_noOperationDoc: "DENIED",
        v1_0_103_stockOperationId: "ALLOWED",
        emptyStockOperationId: "DENIED",
        legacyEditExistingSale: "ALLOWED",
      });
    }
  } finally {
    await env.cleanup();
  }
  console.log(JSON.stringify({ failed, total: results.length }));
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
