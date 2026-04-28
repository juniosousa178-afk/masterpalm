# Checklist de deploy — MasterPalm Web

Baseline de referência: [BASELINE_STABLE.md](BASELINE_STABLE.md) — `diag-20260427-APPSTARTFIX-f14fe79`  
Alvo de hosting Firebase: **masterpalm-58c46** (site `app.mastepalm.com.br`).

---

## Pré-deploy

Executar na raiz do repositório (PowerShell, a partir de `temp_naty`):

```bash
flutter analyze
```

```bash
flutter test test/catalog_initial_web_route_test.dart
```

(opcional, suite completa)

```bash
flutter test
```

Build de produção com **source maps** (ajustar `CATALOG_BUILD_ID` ao build que vais publicar):

```bash
flutter build web --release --source-maps --dart-define=CATALOG_BUILD_ID=diag-20260427-APPSTARTFIX-f14fe79
```

**Verificar artefactos em `build/web/`:**

| Verificação | O que confirma |
|-------------|----------------|
| `build/web/version.json` existe | Metadado de build copiado do `web/version.json` |
| `buildId` em `version.json` **=** `CATALOG_BUILD_ID` usado no `flutter build` | Rastreabilidade app ↔ ficheiro servido |
| `build/web/main.dart.js` existe | Bundle principal |
| `build/web/main.dart.js.map` existe | Source maps para minificados |
| Alvo de deploy = **masterpalm-58c46** | `firebase.json` / comando `firebase deploy --only hosting:masterpalm-58c46` |

**Script automatizado (Windows):** [../scripts/pre_deploy_web_check.ps1](../scripts/pre_deploy_web_check.ps1) — executa análise, testes de rota, build e checagens de ficheiros (ajusta `CATALOG_BUILD_ID` no script se o build mudar).

**Comando de deploy (não executar por engano fora de release):**

```bash
firebase deploy --only hosting:masterpalm-58c46
```

---

## Pós-deploy

Validar no browser (substituir `check` por um sufixo único para evitar cache agressivo, ex. `check-20260427-1`):

| # | URL | Critério |
|---|-----|----------|
| 1 | `https://app.mastepalm.com.br/version.json?v=check` | `buildId` no JSON = build desejado (ex. `diag-20260427-APPSTARTFIX-f14fe79` ou o novo) |
| 2 | `https://app.mastepalm.com.br/?v=check` | Abre o **app web** (não tela de “Loja não encontrada” na raiz; não ficar preso em “Preparando tudo…”) |
| 3 | `https://app.mastepalm.com.br/loja/nathy-pratas-e-folheados?v=check` | Abre a **vitrine** da loja de exemplo |

**Não-regressão manual (rápida):**

- Raiz: sem mensagem de domínio/loja inválida para o host `app.mastepalm.com.br/`.
- Catálogo: carrega a loja (não exige login admin na URL pública).

---

## Relação com testes

A checklist **B** de [SECURITY_BASELINE.md](SECURITY_BASELINE.md) está coberta em `test/catalog_initial_web_route_test.dart` (decisão pura `CatalogRouteDecision`).
