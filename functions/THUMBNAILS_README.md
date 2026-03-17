# Thumbnails automáticos (Offstore style)

Cloud Function que gera thumbnails WEBP 3:4 no upload de imagens de produtos, com fundo branco (letterbox) e sem corte.

## Instalação

```bash
cd functions
npm install sharp
```

O `package.json` já inclui `sharp` e `engines: { "node": "20" }`. Se precisar ajustar:

```json
{
  "engines": { "node": "20" }
}
```

## Deploy

```bash
cd functions
npm install
firebase deploy --only functions:generateProductThumbnail
```

Ou deploy de todas as functions:

```bash
firebase deploy --only functions
```

## Paths monitorados

A função processa uploads em:

- `lojas/{lojaId}/produtos/{produtoId}/*.jpg|png|webp`
- `lojas/{lojaId}/draft_produtos/{produtoId}/*.jpg|png|webp`
- `produtos/*.jpg|png|webp`
- `uploads/produtos/*.jpg|png|webp`

**Ignora:**

- Arquivos em pastas `/thumbnails/`
- Arquivos com metadata `generatedBy` (evita loop)

## Saída

- **Thumbnail salvo em:** `{mesma_pasta}/thumbnails/{nome_original}.webp`  
  Ex.: `lojas/ABC/produtos/X/foto.jpg` → `lojas/ABC/produtos/X/thumbnails/foto.webp`

- **Dimensões:** 900×1200 px (proporção 3:4)
- **Formato:** WEBP qualidade 80
- **Fundo:** branco (imagens não 3:4 são centralizadas com letterbox)

## Firestore (opcional)

Se o path for `lojas/{lojaId}/produtos/{produtoId}/...` ou `lojas/{lojaId}/draft_produtos/{produtoId}/...`:

- Atualiza `lojas/{lojaId}/produtos/{produtoId}` ou `lojas/{lojaId}/draft_produtos/{produtoId}`
- Campos: `fotoThumbUrl`, `fotoOriginalUrl`, `updatedAt`

### Estrutura diferente

Para outra estrutura Firestore, edite `src/generateProductThumbnail.js` na função `parseProductPath()` e no bloco de atualização. Exemplo para `produtos/{produtoId}` (coleção raiz):

```js
const prodRef = db.collection("produtos").doc(produtoId);
```

Para outra pasta de Storage, ajuste `PRODUCT_PATH_PATTERNS` no início do arquivo:

```js
const PRODUCT_PATH_PATTERNS = [
  /^minha-pasta\/produtos\//,
  // ...
];
```

## URLs

- Usa **Signed URL (v4)** com expiração de 10 anos (bucket pode ser privado)
- Se o bucket for público, as URLs funcionam normalmente; Signed URL continua sendo gerada para garantir acesso
