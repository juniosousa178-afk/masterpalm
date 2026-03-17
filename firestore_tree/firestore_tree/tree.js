import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import fs from "fs";

// ======== CONFIGURAR SERVICE ACCOUNT =========
const serviceAccount = JSON.parse(
  fs.readFileSync("./serviceAccountKey.json", "utf8")
);

// =============================================
initializeApp({
  credential: cert(serviceAccount),
});

const db = getFirestore();

async function listCollections(path = "", ref = db) {
  const colls = await ref.listCollections();
  let out = "";

  for (const col of colls) {
    const colPath = path ? `${path}/${col.id}` : col.id;
    out += `${colPath}/\n`;

    const docs = await col.listDocuments();
    for (const doc of docs) {
      const docPath = `${colPath}/${doc.id}`;
      out += `${docPath}\n`;

      // listar subcoleções
      const subs = await doc.listCollections();
      for (const s of subs) {
        out += await listCollections(`${docPath}`, doc);
      }
    }
  }

  return out;
}

listCollections().then(tree => {
  fs.writeFileSync("firestore_tree.txt", tree);
  console.log("🔥 Árvore gerada → firestore_tree.txt");
});
