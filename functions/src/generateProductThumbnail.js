/**
 * Cloud Function: Gera thumbnails automáticos no upload de imagens de produtos
 * Estilo Offstore: WEBP 3:4, fundo branco, sem corte (contain + letterbox)
 *
 * Trigger: onObjectFinalized (Storage)
 * Paths suportados: lojas/{lojaId}/produtos/*, lojas/{lojaId}/draft_produtos/*,
 *                  produtos/*, uploads/produtos/*
 */

import { onObjectFinalized } from "firebase-functions/v2/storage";
import { getStorage } from "firebase-admin/storage";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import sharp from "sharp";

// Configuração
const THUMB_WIDTH = 900;
const THUMB_HEIGHT = 1200; // 3:4
const WEBP_QUALITY = 80;
const METADATA_GENERATED_BY = "thumb-3x4-v1";
const SIGNED_URL_EXPIRY_MS = 10 * 365 * 24 * 60 * 60 * 1000; // 10 anos

const IMAGE_EXT = /\.(jpe?g|png|webp)$/i;
const SKIP_PATHS = ["/thumbnails/", "thumbnails/"];
const PRODUCT_PATH_PATTERNS = [
  /^lojas\/[^/]+\/produtos\//,
  /^lojas\/[^/]+\/draft_produtos\//,
  /^produtos\//,
  /^uploads\/produtos\//,
];

function shouldProcess(object) {
  const name = (object?.name || "").toString();
  const metadata = object?.metadata || {};

  // Ignorar se já é thumbnail ou tem flag generatedBy
  if (SKIP_PATHS.some((p) => name.includes(p))) {
    return false;
  }
  const genBy = metadata?.generatedBy || metadata?.metadata?.generatedBy;
  if (genBy) {
    return false;
  }

  // Deve ser imagem
  if (!IMAGE_EXT.test(name)) {
    return false;
  }

  // Deve estar em pasta de produtos
  const inProductPath = PRODUCT_PATH_PATTERNS.some((re) => re.test(name));
  if (!inProductPath) {
    return false;
  }

  return true;
}

/**
 * Extrai lojaId e produtoId do path para atualização Firestore
 * Ex: lojas/ABC123/produtos/PROD456/imagem.jpg -> { lojaId: 'ABC123', produtoId: 'PROD456' }
 */
function parseProductPath(filePath) {
  const parts = filePath.split("/").filter(Boolean);
  const prodIdx = parts.indexOf("produtos");
  const draftIdx = parts.indexOf("draft_produtos");
  const idx = prodIdx >= 0 ? prodIdx : draftIdx >= 0 ? draftIdx : -1;
  if (idx < 0 || idx + 1 >= parts.length) return null;
  const lojaId = idx >= 1 ? parts[idx - 1] : null;
  const produtoId = parts[idx + 1];
  if (!lojaId || !produtoId) return null;
  return { lojaId, produtoId };
}

/**
 * Gera path do thumbnail mantendo estrutura
 * Ex: lojas/ABC/produtos/X/img.jpg -> thumbnails/lojas/ABC/produtos/X/img.webp
 */
function getThumbnailPath(originalPath) {
  const dir = path.dirname(originalPath);
  const base = path.basename(originalPath, path.extname(originalPath));
  return `${dir}/thumbnails/${base}.webp`;
}

export const generateProductThumbnail = onObjectFinalized(
  {
    region: "southamerica-east1",
    memory: "512MiB",
    timeoutSeconds: 60,
  },
  async (event) => {
    const object = event.data;
    if (!object) {
      console.warn("[generateProductThumbnail] event.data vazio");
      return;
    }

    const filePath = object.name;
    const bucket = object.bucket;

    if (!shouldProcess(object)) {
      console.log("[generateProductThumbnail] Ignorando:", filePath);
      return;
    }

    console.log("[generateProductThumbnail] Processando:", filePath);

    const storage = getStorage();
    const db = getFirestore();
    const bucketObj = storage.bucket(bucket);
    const file = bucketObj.file(filePath);

    let tmpInput = null;
    let tmpOutput = null;

    try {
      // 1) Baixar para /tmp
      tmpInput = path.join(os.tmpdir(), `thumb_in_${Date.now()}_${path.basename(filePath)}`);
      await file.download({ destination: tmpInput });

      // 2) Gerar thumbnail 3:4 com sharp
      const image = sharp(tmpInput);
      const meta = await image.metadata();
      const origW = meta.width || 1;
      const origH = meta.height || 1;

      // Calcular dimensões para caber no canvas 3:4 (contain)
      const targetRatio = THUMB_WIDTH / THUMB_HEIGHT;
      const origRatio = origW / origH;
      let fitW, fitH;
      if (origRatio > targetRatio) {
        fitW = THUMB_WIDTH;
        fitH = Math.round(THUMB_WIDTH / origRatio);
      } else {
        fitH = THUMB_HEIGHT;
        fitW = Math.round(THUMB_HEIGHT * origRatio);
      }

      tmpOutput = path.join(os.tmpdir(), `thumb_out_${Date.now()}.webp`);

      const resizedBuf = await image.resize(fitW, fitH).toBuffer();
      await sharp({
        create: {
          width: THUMB_WIDTH,
          height: THUMB_HEIGHT,
          channels: 3,
          background: { r: 255, g: 255, b: 255 },
        },
      })
        .composite([
          {
            input: resizedBuf,
            top: Math.round((THUMB_HEIGHT - fitH) / 2),
            left: Math.round((THUMB_WIDTH - fitW) / 2),
          },
        ])
        .webp({ quality: WEBP_QUALITY })
        .toFile(tmpOutput);

      // 3) Path do thumbnail (dentro da mesma pasta do original, subpasta thumbnails)
      const thumbPath = getThumbnailPath(filePath);
      const thumbFile = bucketObj.file(thumbPath);

      await thumbFile.save(fs.readFileSync(tmpOutput), {
        contentType: "image/webp",
        metadata: {
          cacheControl: "public, max-age=31536000, immutable",
          metadata: {
            generatedBy: METADATA_GENERATED_BY,
            originalPath: filePath,
          },
        },
      });

      console.log("[generateProductThumbnail] Thumbnail salvo:", thumbPath);

      // 4) Gerar Signed URL (v4)
      const [signedUrl] = await thumbFile.getSignedUrl({
        action: "read",
        expires: Date.now() + SIGNED_URL_EXPIRY_MS,
      });

      const [originalSignedUrl] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + SIGNED_URL_EXPIRY_MS,
      });

      // 5) Atualizar Firestore (opcional)
      const parsed = parseProductPath(filePath);
      if (parsed) {
        const prodRef = db
          .collection("lojas")
          .doc(parsed.lojaId)
          .collection("produtos")
          .doc(parsed.produtoId);

        const prodSnap = await prodRef.get();
        if (prodSnap.exists) {
          await prodRef.set(
            {
              fotoThumbUrl: signedUrl,
              fotoOriginalUrl: originalSignedUrl,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          console.log("[generateProductThumbnail] Firestore atualizado:", prodRef.path);
        } else {
          // Tentar draft_produtos
          const draftRef = db
            .collection("lojas")
            .doc(parsed.lojaId)
            .collection("draft_produtos")
            .doc(parsed.produtoId);
          const draftSnap = await draftRef.get();
          if (draftSnap.exists) {
            await draftRef.set(
              {
                fotoThumbUrl: signedUrl,
                fotoOriginalUrl: originalSignedUrl,
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
            console.log("[generateProductThumbnail] Firestore draft atualizado:", draftRef.path);
          }
        }
      }
    } catch (err) {
      console.error("[generateProductThumbnail] Erro:", err);
      throw err;
    } finally {
      if (tmpInput && fs.existsSync(tmpInput)) {
        try {
          fs.unlinkSync(tmpInput);
        } catch (_) {}
      }
      if (tmpOutput && fs.existsSync(tmpOutput)) {
        try {
          fs.unlinkSync(tmpOutput);
        } catch (_) {}
      }
    }
  }
);
