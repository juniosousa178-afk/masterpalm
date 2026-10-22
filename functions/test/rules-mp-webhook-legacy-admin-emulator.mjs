/**
 * Cliente admin legado (≤ 1.0.79+95, antes de 79f6950) × venda canónica do mpWebhook, sob as Rules do repo.
 * Replica as escritas de `_confirmarPedido` @585c792: registrarVendaCatalogo(baixarEstoque:false) →
 * syncVenda (estoque_vendas/{uuid}) → confirmarPrePedido (pre_pedidos update) → PosPagamento._baixarEstoque
 * (transação estoque_produtos update+set merge + produtos set merge, sem stockRevision).
 * Exige FIRESTORE_EMULATOR_HOST (firebase emulators:exec).
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";
import { classifyOrderForAutoSale } from "../src/mpCatalogPaymentSale.js";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  console.error("FIRESTORE_EMULATOR_HOST não definido — abortando.");
  process.exit(1);
}
const [host, portStr] = emulatorHost.split(":");
const port = Number(portStr || "8080");
const rules = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../../firestore.rules"), "utf8");

const PAYMENT_ID = "900000000001";
const OP_ID = `mp_payment_sale_${PAYMENT_ID}`;
const PROD_ID = "prod_legacy_1";
const ADMIN_UID = "merchant_admin_uid";
const OWNER_UID = "merchant_owner_uid";
const ts = () => firebase.firestore.FieldValue.serverTimestamp();

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
    return String(e?.code || e?.message || e).includes("permission") ? "DENIED" : `ERROR:${e?.code || e?.message}`;
  }
}

function orderPending(lojaId, orderId) {
  return {
    lojaId,
    status: "pendente",
    statusPagamento: "pendente",
    pagamento: "PIX",
    total: 50,
    subtotal: 50,
    cliente: { nome: "Cliente Sintetico" },
    itens: [{ id: PROD_ID, produtosId: PROD_ID, nome: "Anel teste", quantidade: 1, precoUnitario: 50, tamanho: "", cor: "" }],
  };
}

async function seedStore(env, { lojaId, ownerUid, adminRole, webhookApplied }) {
  const orderId = `order_${lojaId}`;
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const loja = db.collection("lojas").doc(lojaId);
    await loja.set({ ownerUid, nome: `Loja ${lojaId}` });
    if (adminRole) await db.collection("users").doc(ownerUid).set({ role: "admin", store_id: lojaId });
    const order = orderPending(lojaId, orderId);
    await loja.collection("pre_pedidos").doc(orderId).set(order);
    await loja.collection("estoque_produtos").doc(PROD_ID).set({
      nome: "Anel teste", quantidade: 10, variacoes: {}, stockRevision: 0, stockOperationId: "seed",
    });
    await loja.collection("produtos").doc(PROD_ID).set({ nome: "Anel teste", quantidade: 10 });
    if (webhookApplied) await applyWebhookCanonicalSale(env, lojaId, orderId);
  });
  return orderId;
}

/** Mesmo write-set da transação canónica do mpWebhook (Admin SDK ignora Rules). */
async function applyWebhookCanonicalSale(env, lojaId, orderId) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const loja = db.collection("lojas").doc(lojaId);
    const batch = db.batch();
    batch.update(loja.collection("pre_pedidos").doc(orderId), {
      status: "paid", statusPagamento: "aprovado", mpPaymentStatus: "approved", paidAt: ts(),
      paymentId: PAYMENT_ID, vendaId: OP_ID, saleId: OP_ID, saleOperationId: OP_ID,
    });
    batch.update(loja.collection("estoque_produtos").doc(PROD_ID), {
      quantidade: 9, stockRevision: 1, stockOperationId: OP_ID,
    });
    batch.set(loja.collection("produtos").doc(PROD_ID), { quantidade: 9 }, { merge: true });
    batch.set(loja.collection("estoque_vendas").doc(OP_ID), { id: OP_ID, lojaId, total: 50, status: "concluida", prePedidoId: orderId, paymentId: PAYMENT_ID });
    batch.set(loja.collection("stock_catalog_operations").doc(OP_ID), { state: "APPLIED", kind: "sale" });
    batch.set(loja.collection("sale_intents").doc(`pre_pedido:${orderId}`), { origin: "mp_webhook", status: "completed", stockEffectHash: `mp_payment:${PAYMENT_ID}` });
    batch.set(loja.collection("_mp_webhook_processed").doc(PAYMENT_ID), { orderId, saleOperationId: OP_ID });
    await batch.commit();
  });
}

async function snapshotState(env, lojaId, orderId) {
  let out;
  await env.withSecurityRulesDisabled(async (ctx) => {
    const loja = ctx.firestore().collection("lojas").doc(lojaId);
    const vendas = await loja.collection("estoque_vendas").get();
    const est = (await loja.collection("estoque_produtos").doc(PROD_ID).get()).data();
    const cat = (await loja.collection("produtos").doc(PROD_ID).get()).data();
    const order = (await loja.collection("pre_pedidos").doc(orderId).get()).data();
    out = {
      sales: vendas.size,
      stockQty: est.quantidade,
      stockRevision: est.stockRevision,
      catalogQty: cat.quantidade,
      orderStatus: order.status,
      orderVendaId: order.vendaId ?? null,
      order,
    };
  });
  return out;
}

/** Escritas exatas do cliente @585c792 a partir de um mapa de pre_pedido possivelmente obsoleto. */
async function legacyConfirm(env, { lojaId, orderId, uid, staleOrder }) {
  const db = env.authenticatedContext(uid, { email: `${uid}@example.test` }).firestore();
  const loja = db.collection("lojas").doc(lojaId);
  const vendaId = `legacy-uuid-${lojaId}`;
  const out = {};

  out.estoqueVendasSet = await attempt(async () => {
    await loja.collection("estoque_vendas").doc(vendaId).get();
    await loja.collection("estoque_vendas").doc(vendaId).set({
      id: vendaId, lojaId, data: firebase.firestore.Timestamp.now(), total: staleOrder.total, desconto: 0,
      formasPagamento: staleOrder.pagamento, frete: 0, clienteNome: "Cliente Sintetico",
      produtosDescricao: "Anel teste", quantidade: 1, preco: staleOrder.subtotal, tamanho: "",
      vendedor: "Loja online", observacao: "", pagamentoDinheiro: 0, pagamentoPix: staleOrder.total,
      pagamentoCartao: 0, taxas: 0, custoProdutos: 0,
      itens: [{ produtoNome: "Anel teste", quantidade: 1, tamanho: "", cor: "", precoUnitario: 50, precoTotal: 50, productId: PROD_ID }],
      clienteId: null, cancelada: false, estornada: false, createdAt: ts(), updatedAt: ts(), status: "concluida",
    }, { merge: true });
  });

  out.prePedidoUpdate = await attempt(() =>
    loja.collection("pre_pedidos").doc(orderId).update({ status: "confirmado", vendaId, dataAtualizacao: ts() }),
  );

  out.stockTransaction = await attempt(() =>
    db.runTransaction(async (tx) => {
      const ref = loja.collection("estoque_produtos").doc(PROD_ID);
      const snap = await tx.get(ref);
      const quantidade = (snap.data()?.quantidade ?? 0) - 1;
      if (quantidade < 0) throw new Error("estoque insuficiente");
      const updateData = { quantidade, updatedAt: ts() };
      tx.update(ref, updateData);
      tx.set(ref, updateData, { merge: true });
      tx.set(loja.collection("produtos").doc(PROD_ID), updateData, { merge: true });
    }),
  );
  return out;
}

async function main() {
  const env = await initializeTestEnvironment({ projectId: "demo-mp-legacy", firestore: { rules, host, port } });
  try {
    await env.clearFirestore();

    // A — webhook primeiro, cliente legado com UI obsoleta (merchant com users.role=admin, como no registo).
    {
      const lojaId = "loja_A_admin";
      const orderId = await seedStore(env, { lojaId, ownerUid: ADMIN_UID, adminRole: true, webhookApplied: true });
      const before = await snapshotState(env, lojaId, orderId);
      const w = await legacyConfirm(env, { lojaId, orderId, uid: ADMIN_UID, staleOrder: orderPending(lojaId, orderId) });
      const after = await snapshotState(env, lojaId, orderId);
      record("A_admin.writes", w, { estoqueVendasSet: "ALLOWED", prePedidoUpdate: "DENIED", stockTransaction: "DENIED" });
      // Resíduo aceite: venda órfã sem relação com o pre_pedido e sem baixa (builds < 2026-07-06).
      record("A_admin.RESIDUAL_ORPHAN_SALE_RECORD", after.sales - before.sales, 1);
      record("A_admin.ADDITIONAL_STOCK_DEBIT", before.stockQty - after.stockQty, 0);
      record("A_admin.order_canonical_preserved", [after.orderStatus, after.orderVendaId], ["paid", OP_ID]);
    }

    // A' — dono sem users.role (só ownerUid): pre_pedidos negado, venda ainda permitida.
    {
      const lojaId = "loja_A_owner";
      const orderId = await seedStore(env, { lojaId, ownerUid: OWNER_UID, adminRole: false, webhookApplied: true });
      const before = await snapshotState(env, lojaId, orderId);
      const w = await legacyConfirm(env, { lojaId, orderId, uid: OWNER_UID, staleOrder: orderPending(lojaId, orderId) });
      const after = await snapshotState(env, lojaId, orderId);
      record("A_owner.writes", w, { estoqueVendasSet: "ALLOWED", prePedidoUpdate: "DENIED", stockTransaction: "DENIED" });
      record("A_owner.RESIDUAL_ORPHAN_SALE_RECORD", after.sales - before.sales, 1);
      record("A_owner.ADDITIONAL_STOCK_DEBIT", before.stockQty - after.stockQty, 0);
    }

    // B — concorrente: cliente leu pre_pedido pendente; webhook commita; cliente grava.
    {
      const lojaId = "loja_B_admin";
      const orderId = await seedStore(env, { lojaId, ownerUid: ADMIN_UID, adminRole: true, webhookApplied: false });
      const stale = orderPending(lojaId, orderId);
      await applyWebhookCanonicalSale(env, lojaId, orderId);
      const w = await legacyConfirm(env, { lojaId, orderId, uid: ADMIN_UID, staleOrder: stale });
      const after = await snapshotState(env, lojaId, orderId);
      record("B_concurrent.writes", w, { estoqueVendasSet: "ALLOWED", prePedidoUpdate: "DENIED", stockTransaction: "DENIED" });
      record("B_concurrent.TOTAL_SALE_RECORDS_incl_residual", after.sales, 2);
      record("B_concurrent.TOTAL_STOCK_DEBITS", 10 - after.stockQty, 1);
      record("B_concurrent.order_canonical_preserved", [after.orderStatus, after.orderVendaId], ["paid", OP_ID]);
    }

    // C — legado completa antes do webhook (admin): pedido fica confirmado → webhook não vende.
    {
      const lojaId = "loja_C_admin";
      const orderId = await seedStore(env, { lojaId, ownerUid: ADMIN_UID, adminRole: true, webhookApplied: false });
      const w = await legacyConfirm(env, { lojaId, orderId, uid: ADMIN_UID, staleOrder: orderPending(lojaId, orderId) });
      const mid = await snapshotState(env, lojaId, orderId);
      const decision = classifyOrderForAutoSale(mid.order, PAYMENT_ID);
      record("C_admin.writes", w, { estoqueVendasSet: "ALLOWED", prePedidoUpdate: "ALLOWED", stockTransaction: "DENIED" });
      record("C_admin.webhook_decision", decision.state, "already_business_confirmed");
      record("C_admin.TOTAL_SALES_and_DEBITS", [mid.sales, 10 - mid.stockQty], [1, 0]);
    }

    // C' — legado antes do webhook (dono sem role): pedido continua pendente → webhook vende também.
    {
      const lojaId = "loja_C_owner";
      const orderId = await seedStore(env, { lojaId, ownerUid: OWNER_UID, adminRole: false, webhookApplied: false });
      await legacyConfirm(env, { lojaId, orderId, uid: OWNER_UID, staleOrder: orderPending(lojaId, orderId) });
      const mid = await snapshotState(env, lojaId, orderId);
      record("C_owner.webhook_decision", classifyOrderForAutoSale(mid.order, PAYMENT_ID).state, "payable");
      await applyWebhookCanonicalSale(env, lojaId, orderId);
      const after = await snapshotState(env, lojaId, orderId);
      record("C_owner.TOTAL_SALES_and_DEBITS", [after.sales, 10 - after.stockQty], [2, 1]);
    }

    // R — regressão: escritas do app atual em pre_pedidos continuam válidas; vínculo pago imutável.
    {
      const lojaId = "loja_R_admin";
      const paidId = await seedStore(env, { lojaId, ownerUid: ADMIN_UID, adminRole: true, webhookApplied: true });
      const pendingId = "order_R_pending";
      const manualId = "order_R_manual";
      await env.withSecurityRulesDisabled(async (ctx) => {
        const col = ctx.firestore().collection("lojas").doc(lojaId).collection("pre_pedidos");
        await col.doc(pendingId).set(orderPending(lojaId, pendingId));
        await col.doc(manualId).set({ ...orderPending(lojaId, manualId), status: "confirmado", vendaId: "venda-manual-1" });
      });
      const col = env.authenticatedContext(ADMIN_UID, { email: `${ADMIN_UID}@example.test` })
        .firestore().collection("lojas").doc(lojaId).collection("pre_pedidos");
      const del = firebase.firestore.FieldValue.delete();
      const cases = {
        statusEmbalandoOnPaid: await attempt(() => col.doc(paidId).update({ status: "embalando", dataAtualizacao: ts() })),
        statusEnviadoRastreioOnPaid: await attempt(() => col.doc(paidId).update({ status: "enviado", tipoEntregaEnvio: "rastreio", codigoRastreio: "AA123456789BR", dataAtualizacao: ts() })),
        publicConfirmOnPaid: await attempt(() => col.doc(paidId).update({ status: "confirmado", dataConfirmacao: ts(), dataAtualizacao: ts() })),
        governancaSubstituicaoOnPaid: await attempt(() => col.doc(paidId).update({ governancaStatus: "substituido", substituidoPor: "order_substituto_1", substituidoEm: ts(), dataAtualizacao: ts() })),
        currentManualConfirmOnPending: await attempt(() => col.doc(pendingId).update({ status: "confirmado", vendaId: "venda-nova-1", dataAtualizacao: ts() })),
        reconfirmManualChangesVendaId: await attempt(() => col.doc(manualId).update({ status: "confirmado", vendaId: "venda-manual-2", dataAtualizacao: ts() })),
        deleteVendaIdOnPaid: await attempt(() => col.doc(paidId).update({ vendaId: del })),
        clearPaidAtOnPaid: await attempt(() => col.doc(paidId).update({ paidAt: null })),
        changePaymentIdOnPaid: await attempt(() => col.doc(paidId).update({ paymentId: "999" })),
        changeSaleOperationIdOnPaid: await attempt(() => col.doc(paidId).update({ saleOperationId: "x" })),
      };
      record("R.current_app_writes", cases, {
        statusEmbalandoOnPaid: "ALLOWED",
        statusEnviadoRastreioOnPaid: "ALLOWED",
        publicConfirmOnPaid: "ALLOWED",
        governancaSubstituicaoOnPaid: "ALLOWED",
        currentManualConfirmOnPending: "ALLOWED",
        reconfirmManualChangesVendaId: "DENIED",
        deleteVendaIdOnPaid: "DENIED",
        clearPaidAtOnPaid: "DENIED",
        changePaymentIdOnPaid: "DENIED",
        changeSaleOperationIdOnPaid: "DENIED",
      });
      const after = await snapshotState(env, lojaId, paidId);
      record("R.paid_order_link_intact", [after.orderVendaId, after.order.paymentId, after.order.saleOperationId], [OP_ID, PAYMENT_ID, OP_ID]);
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
