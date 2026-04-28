# Baseline de segurança e anti-regressão — Web MasterPalm

## Baseline de build

- **BuildId:** `diag-20260427-APPSTARTFIX-f14fe79`
- **Documento canónico:** [BASELINE_STABLE.md](BASELINE_STABLE.md)

## O que estes mecanismos evitam

- Raiz do host do app (`app.mastepalm.com.br/`) a ser tratada como **domínio de loja** sem mapeamento (erro de “loja não configurada” / `CatalogDomainBootstrapErrorApp` no fluxo errado).
- Uso inseguro de **`Firebase.apps`** no **WebKit** antes de `Firebase.initializeApp` (null check / crash).
- `/loja` sem slug ou slug placeholder **`minha-loja`** a ser tratado como loja real.
- **Spinner infinito** “Preparando tudo…” na raiz (fluxo pós-bootstrap / rota errada) — corrigido na linha APPSTARTFIX; manter testes e checklists.

## Testes de rota (obrigatórios em CI / pré-deploy)

Ficheiro: `test/catalog_initial_web_route_test.dart`  
Função pura: `CatalogRouteDecision.fromUri` em `lib/catalog/catalog_initial_web_route.dart` (não acede a Firebase/HTTP).

| ID | Cenário | Garantia |
|----|---------|----------|
| B1 | `app.mastepalm.com.br/` | `appRoot` |
| B2 | `.../loja/nathy-pratas-e-folheados` | `publicCatalogByLojaPath` (slug de vitrine; nome legado “bySlug” = mesmo tipo) |
| B3 | `.../loja` | `lojaPathOrSlugInvalid`, **não** `appRoot` |
| B4 | `?loja=nathy-pratas-e-folheados` na raiz | `publicCatalogByLegacyQuery` (se suportado) |
| B5 | Raiz do app | **Nunca** `customDomainNotConfigured` (não abre o ramo de erro de domínio da decisão estática) |
| B6 | `minha-loja` em path ou query | inválido, nunca loja real |
| B7 | Domínio próprio com mapeamento (simulado) | `customDomainPublicCatalog` |
| B8 | Domínio desconhecido sem mapeamento (simulado) | `customDomainNotConfigured` |

## Diagnósticos temporários (não remover sem revisão)

| Chave / modo | Comportamento esperado (política) |
|----------------|-----------------------------------|
| `bootTrace` | Ativar com **`diag=1` e `bootTrace=1`** (raiz) — ver `WebRootBootTraceApp` em `main.dart`. |
| `appStartTrace` | Ativar com **`diag=1` e `appStartTrace=1`** — overlay de fases no `_BootApp`. |
| `netTest` | Ativar com **`diag=1` e `netTest=1`**. |
| `traceCatalog` | No **catálogo** (`public_catalog_screen.dart`), painel técnico com **`diag=1` ou `traceCatalog=1`** (zona de catálogo; não editar no âmbito de regras “banners” sem pedido explícito). |

**Nota:** Unificar tudo a “só com `diag=1`” pode exigir alteração em `public_catalog_screen.dart` — fazer noutro escopo se for obrigatório; até lá, tratar `traceCatalog` como diagnóstico consciente em ambiente de suporte.

## Rollback (Git)

Se o remoto tiver a tag de baseline:

```bash
git fetch origin
git checkout baseline-web-appstartfix-20260427
```

Para criar um branch a partir da tag (sem detached HEAD permanente):

```bash
git checkout -b hotfix/rollback-baseline baseline-web-appstartfix-20260427
```

**Build antigo no Firebase:** não é “revert” automático; é necessário fazer **deploy** de um artefacto `build/web` gerado a partir desse commit (ou do `buildId` documentado) e validar o [pós-deploy](DEPLOY_CHECKLIST.md#pós-deploy).

## Congelamento (repetido)

Não misturar com esta baseline, sem escopo e buildId novos:

- Configuração Firebase
- Regras Firestore / regras de hosting
- Rotas e catálogo público (ficheiros protegidos por regras de equipa)
