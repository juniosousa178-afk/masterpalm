# Domínio do App Web MasterPalm (SPA admin)

## Canônico (produção)

- **Host:** `app.masterpalm.com.br`
- **Origem:** `https://app.masterpalm.com.br`

## Compatibilidade temporária

- **Host legado (grafia antiga):** `app.mastepalm.com.br` — ainda aceito em App Check, deep links e CORS de Callables de **planos** até migração completa de DNS, bookmarks e Firebase Authorized domains.
- Não misturar com o **site** principal: `mastepalm.com.br` / `www.mastepalm.com.br`.

## Onde está no código

- Constantes: `lib/config/app_urls.dart` (`AppUrls.appWebHostCanonical`, `AppUrls.appWebHostLegacyTypo`, `AppUrls.appWebBase`, `AppUrls.appWebHostsAll`).
- Metadados estáticos do build Web: `web/index.html` (canonical, Open Graph, Twitter Card, JSON-LD), `web/robots.txt` e `web/sitemap.xml` usam o host **canônico**.
- Firebase Console: Authentication → Authorized domains deve incluir o host canônico; incluir o legado só enquanto houver tráfego real.

## Firebase Hosting (repo)

- **`firebase.json`**: dois alvos (`target` → `mastepalm` e `masterpalm-58c46`), ambos com `public: build/web`, os mesmos `headers` e `rewrites`. Não há URL de domínio embutida no JSON: o host público (`app.masterpalm.com.br` / legado) é definido em **Firebase Console → Hosting → domínios personalizados** e no **DNS**.
- **`.firebaserc`**: mapeia site IDs do Hosting (`mastepalm`, `masterpalm-58c46`) para o projeto `masterpalm-58c46`. O ID de site **`mastepalm`** é legado de nomenclatura (typo); **não é** o mesmo conceito que o hostname `app.mastepalm.com.br`. Evite renomear site ID sem migração planejada no Console.
- **SPA**: rewrite final `"source": "**", "destination": "/index.html"` cobre rotas do Flutter; rotas específicas (`/privacidade`, `/modelos-importacao`, `/mp-oauth*`, `/c/**`, `/loja/**`) vêm antes. Não há array `redirects` no `firebase.json` para troca de host — redirecionamento **app.mastepalm → app.masterpalm** (se desejado) é **infra** (registrador, página no Hosting legado ou regra no CDN), fora deste arquivo.
- **Header relevante para login Web**: `Cross-Origin-Opener-Policy: same-origin-allow-popups` em `**` (popup Google); deve ser servido na origem canônica (e repassado se houver proxy).

## Checklist fora do repositório

1. **Firebase Auth** — Authorized domains: canônico + legado (enquanto existir tráfego) + `*.web.app` conforme uso.
2. **App Check** — allowlist de hosts (canônico + legado conforme `app_check_config.dart`).
3. **DNS** — `app.masterpalm.com.br` apontando para o Hosting correto; se o legado ainda existir, documentar até quando permanece ativo.
4. **Links e QR codes** — materiais com `https://app.mastepalm.com.br` continuam válidos apenas enquanto DNS/Hosting aceitarem esse host; preferir sempre o canônico em material novo.
