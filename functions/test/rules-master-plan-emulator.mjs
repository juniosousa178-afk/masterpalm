/**
 * Prova Firestore Rules no Emulator — cortesia e auditoria de planos.
 * Exige FIRESTORE_EMULATOR_HOST (firebase emulators:exec define automaticamente).
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  console.error(
    "FIRESTORE_EMULATOR_HOST não definido — abortando para evitar conexão com produção.",
  );
  process.exit(1);
}

const [host, portStr] = emulatorHost.split(":");
const port = Number(portStr || "8080");
const projectId = "masterpalm-rules-p1-local";

const rulesPath = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../firestore.rules",
);
const rules = readFileSync(rulesPath, "utf8");

const OWNER_UID = "owner_uid_p1";
const COMMON_UID = "common_uid_p1";
const MASTER_UID = "master_uid_p1";
const ACTION_ID = "master_plan_test_action_001";

let passed = 0;
let failed = 0;

async function check(name, promise) {
  try {
    await promise;
    console.log(`  OK  ${name}`);
    passed += 1;
  } catch (err) {
    console.error(` FAIL ${name}`, err?.message || err);
    failed += 1;
  }
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules, host, port },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("users").doc(OWNER_UID).set({
        email: "owner@test.com",
        role: "vendedor",
      });
      await db.collection("users").doc(COMMON_UID).set({
        email: "common@test.com",
        role: "vendedor",
      });
      await db.collection("users").doc(MASTER_UID).set({
        email: "masterpalm26@gmail.com",
        role: "admin",
      });
      await db
        .collection("users")
        .doc(OWNER_UID)
        .collection("manualCourtesyGrant")
        .doc("current")
        .set({ active: true, planId: "pro_monthly" });
      await db.collection("admin_plan_actions").doc(ACTION_ID).set({
        actionType: "grant_courtesy",
        targetUid: OWNER_UID,
      });
    });

    const owner = testEnv.authenticatedContext(OWNER_UID, {
      email: "owner@test.com",
    });
    const common = testEnv.authenticatedContext(COMMON_UID, {
      email: "common@test.com",
    });
    const master = testEnv.authenticatedContext(MASTER_UID, {
      email: "masterpalm26@gmail.com",
    });
    const anon = testEnv.unauthenticatedContext();

    const courtesyPath = (ctx) =>
      ctx
        .firestore()
        .collection("users")
        .doc(OWNER_UID)
        .collection("manualCourtesyGrant")
        .doc("current");

    const auditPath = (ctx) =>
      ctx.firestore().collection("admin_plan_actions").doc(ACTION_ID);

    console.log("manualCourtesyGrant — proprietário");
    await check("1. owner read current", assertFails(courtesyPath(owner).get()));
    await check(
      "2. owner create current",
      assertFails(
        courtesyPath(owner).set({ active: true, planId: "basic_monthly" }),
      ),
    );
    await check(
      "3. owner update current",
      assertFails(courtesyPath(owner).update({ active: false })),
    );
    await check("4. owner delete current", assertFails(courtesyPath(owner).delete()));

    console.log("manualCourtesyGrant — Mestre como cliente Firestore");
    await check("5. master read current", assertFails(courtesyPath(master).get()));
    await check(
      "6. master write current",
      assertFails(courtesyPath(master).set({ active: true })),
    );

    console.log("admin_plan_actions — usuário comum");
    await check("7. common read audit", assertFails(auditPath(common).get()));
    await check(
      "8. common create audit",
      assertFails(auditPath(common).set({ actionType: "x" })),
    );
    await check(
      "9. common update audit",
      assertFails(auditPath(common).update({ reason: "x" })),
    );
    await check("10. common delete audit", assertFails(auditPath(common).delete()));

    console.log("admin_plan_actions — Mestre como cliente Firestore");
    await check("11. master read audit", assertFails(auditPath(master).get()));
    await check(
      "12. master write audit",
      assertFails(auditPath(master).set({ actionType: "x" })),
    );

    console.log("Não autenticado e subcaminho");
    await check("12b. anon read courtesy", assertFails(courtesyPath(anon).get()));
    await check("12c. anon read audit", assertFails(auditPath(anon).get()));
    await check(
      "13. subcaminho extra negado (wildcard não libera)",
      assertFails(
        courtesyPath(owner)
          .collection("probe_sub")
          .doc("extra")
          .get(),
      ),
    );

    // Controle: owner pode ler próprio doc users/{uid}
    await check(
      "owner pode ler users/{uid} (fora do escopo sensível)",
      assertSucceeds(
        owner.firestore().collection("users").doc(OWNER_UID).get(),
      ),
    );
  } finally {
    await testEnv.cleanup();
  }

  console.log(`\nRules emulator: ${passed} passou, ${failed} falhou`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
