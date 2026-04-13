# Domínio do App Web MasterPalm (SPA admin)

## Canônico (produção)

- **Host:** `app.mastepalm.com.br`
- **Origem:** `https://app.mastepalm.com.br`

## Compatibilidade temporária

- **Host alternativo:** `app.masterpalm.com.br` — ainda aceito em App Check, deep links e CORS de Callables de **planos** enquanto houver tráfego, DNS ou bookmarks apontando para essa grafia.
- Não misturar com o **site** principal de marketing: `mastepalm.com.br` / `www.mastepalm.com.br`.

## Onde está no código

- Constantes: `lib/config/app_urls.dart` (`AppUrls.appWebHostCanonical`, `AppUrls.appWebHostLegacyTypo`, `AppUrls.appWebBase`, `AppUrls.appWebHostsAll`).
- Metadados estáticos do build Web: `web/index.html` (canonical, Open Graph, Twitter Card, JSON-LD), `web/robots.txt` e `web/sitemap.xml` usam o host **canônico**.
- Firebase Console: Authentication → Authorized domains deve incluir o host canônico; incluir `app.masterpalm.com.br` só enquanto houver tráfego real.
- **Cloud Functions** (`functions/index.js`): sem secret/env `WEB_BASE_URL`, o fallback canônico do app Web é `https://app.mastepalm.com.br` (ex.: `redirectCatalogo`, `planCreatePreference`, preferências MP internas). O callable `createPlanSubscription` usa, por último, `https://${ROOT_DOMAIN}` (marketing); para URLs no app, defina `WEB_BASE_URL` no Secret Manager.

## Firebase Hosting (repo)

- **`firebase.json`**: dois alvos (`target` → `mastepalm` e `masterpalm-58c46`), ambos com `public: build/web`, os mesmos `headers` e `rewrites`. Não há URL de domínio embutida no JSON: o host público (`app.mastepalm.com.br` / compat) é definido em **Firebase Console → Hosting → domínios personalizados** e no **DNS**.
- **`.firebaserc`**: mapeia site IDs do Hosting (`mastepalm`, `masterpalm-58c46`) para o projeto `masterpalm-58c46`. O ID de site **`mastepalm`** é legado de nomenclatura (typo); **não é** o mesmo conceito que o hostname `app.mastepalm.com.br`. Evite renomear site ID sem migração planejada no Console.
- **SPA**: rewrite final `"source": "**", "destination": "/index.html"` cobre rotas do Flutter; rotas específicas (`/privacidade`, `/modelos-importacao`, `/mp-oauth*`, `/c/**`, `/loja/**`) vêm antes. Redirecionamento **app.masterpalm → app.mastepalm** (se desejado) é **infra** (registrador, CDN), fora deste arquivo.
- **Header relevante para login Web**: `Cross-Origin-Opener-Policy: same-origin-allow-popups` em `**` (popup Google); deve ser servido na origem canônica (e repassado se houver proxy).

## Checklist fora do repositório

1. **Firebase Auth** — Authorized domains: canônico `app.mastepalm.com.br` + compat `app.masterpalm.com.br` (enquanto existir tráfego) + `*.web.app` conforme uso.
2. **App Check** — allowlist de hosts (canônico + compat conforme `app_check_config.dart`); reCAPTCHA: registrar ambos os hosts se ainda houver acessos ao domínio compat.
3. **DNS** — `app.mastepalm.com.br` apontando para o Hosting correto; se `app.masterpalm.com.br` ainda existir, documentar até quando permanece ativo.
4. **Links e QR codes** — materiais com `https://app.masterpalm.com.br` continuam válidos apenas enquanto DNS/Hosting aceitarem esse host; **material novo** deve usar o canônico `https://app.mastepalm.com.br`.
