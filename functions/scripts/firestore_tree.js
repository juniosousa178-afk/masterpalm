// scripts/firestore_tree.js
// Lista a árvore do Firestore (coleções e documentos) e destaca store_id em users/usuarios/lojas.
//
// RODAR (com conta de serviço):
//   cd functions && node scripts/firestore_tree.js
//
// Ou com Firebase CLI (Application Default Credentials):
//   cd functions && firebase use masterpalm-58c46 && node scripts/firestore_tree.js
//
// Opcional: salvar em arquivo
//   node scripts/firestore_tree.js > firestore_tree.txt

import admin from "firebase-admin";
import { readFileSync, existsSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "masterpalm-58c46";

const serviceAccountPath = join(__dirname, "..", "masterpalm-service-account.json");
if (!admin.apps.length) {
  if (existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(readFileSync(serviceAccountPath, "utf8"));
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  } else {
    admin.initializeApp({ projectId });
  }
}

const db = admin.firestore();

function normalizeStoreId(data) {
  if (!data || typeof data !== "object") return null;
  const v = data.store_id ?? data.storeId ?? data.loja_id ?? data.lojaId;
  return v != null ? String(v).trim() : null;
}

async function listSubcollections(docRef) {
  const cols = await docRef.listCollections();
  return cols.map((c) => c.id);
}

async function docSnapshot(docRef) {
  try {
    return await docRef.get();
  } catch (e) {
    return null;
  }
}

async function treeCollection(collectionRef, depth = 0, prefix = "") {
  const name = collectionRef.id;
  const snap = await collectionRef.limit(500).get();
  const indent = prefix + "  ";
  const lines = [];

  if (snap.empty) {
    lines.push(prefix + "📁 " + name + "/ (vazia)");
    return lines;
  }

  lines.push(prefix + "📁 " + name + "/ (" + snap.size + " doc(s))");

  const highlightStore = ["users", "usuarios", "lojas"].includes(name);

  for (const doc of snap.docs) {
    const docId = doc.id;
    const data = doc.data();
    const storeId = highlightStore ? normalizeStoreId(data) : null;
    const storeLabel = storeId ? "  → store_id: " + storeId : "";
    lines.push(indent + "📄 " + docId + storeLabel);

    // Uma camada de subcoleções (ex: lojas/{id}/config)
    const subcols = await listSubcollections(doc.ref);
    for (const subName of subcols.slice(0, 15)) {
      const subSnap = await doc.ref.collection(subName).limit(20).get();
      lines.push(indent + "  📁 " + subName + "/ (" + subSnap.size + " doc(s))");
      if (subSnap.size <= 5) {
        for (const sub of subSnap.docs) {
          lines.push(indent + "    📄 " + sub.id);
        }
      } else {
        subSnap.docs.slice(0, 3).forEach((sub) => lines.push(indent + "    📄 " + sub.id));
        lines.push(indent + "    ... +" + (subSnap.size - 3) + " mais");
      }
    }
  }

  return lines;
}

async function main() {
  console.log("Firestore – árvore de coleções (project: " + projectId + ")\n");
  console.log("Caminhos usados pelo app para resolver loja:");
  console.log("  • users/{uid}.store_id");
  console.log("  • usuarios/{email}.store_id");
  console.log("  • lojas/{lojaId}\n");
  console.log("═══════════════════════════════════════════════════════════════\n");

  const rootCols = await db.listCollections();
  const names = rootCols.map((c) => c.id).sort();

  for (const name of names) {
    const colRef = db.collection(name);
    const lines = await treeCollection(colRef, 0, "");
    lines.forEach((l) => console.log(l));
    console.log("");
  }

  console.log("═══════════════════════════════════════════════════════════════");
  console.log("Fim. Verifique se users e usuarios têm store_id para Nathy e Junio.");
}

main().catch((e) => {
  console.error("Erro:", e.message);
  process.exit(1);
});
