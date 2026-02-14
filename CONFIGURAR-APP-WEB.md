# Configurar app.mastepalm.com.br (AppWeb)

O AppWeb agora usa o subdomínio **app.mastepalm.com.br** para não conflitar com a landing page em **mastepalm.com.br**.

## O que foi alterado

| Antes | Depois |
|-------|--------|
| mastepalm.com.br → AppWeb | mastepalm.com.br → Landing page |
| — | app.mastepalm.com.br → AppWeb |

## Configurar DNS no Cloudflare

Para o AppWeb funcionar em **app.mastepalm.com.br**, adicione um registro no Cloudflare:

1. Acesse o painel do Cloudflare para **mastepalm.com.br**
2. Vá em **DNS** → **Records** → **Add record**
3. Configure:
   - **Type:** CNAME
   - **Name:** app
   - **Target:** `masterpalm-58c46.web.app` (ou o host onde o AppWeb está hospedado no Firebase)
   - **Proxy status:** DNS only (nuvem cinza)

**Se o AppWeb estiver no Firebase Hosting**, use o domínio do Firebase (ex: `masterpalm-58c46.web.app` ou `mastepalm.web.app`).

**Se o AppWeb estiver em outro provedor**, use o endereço que ele fornecer (ex: um CNAME ou IP).

## Verificar

Após a propagação (alguns minutos), acesse **https://app.mastepalm.com.br** e confira se o AppWeb carrega corretamente.
