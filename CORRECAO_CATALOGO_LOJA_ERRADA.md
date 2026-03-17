# CORREÇÃO CATÁLOGO LOJA ERRADA — ENTREGA

## BLOCO 1 — CAUSA REAL ENCONTRADA

### Causa 1: Fallback "masterpalm" em rotas e catalog_web
- **Arquivos:** `lib/app_routes.dart`, `lib/catalog_web.dart`
- **Problema:** Quando a URL tinha `/loja/minha-loja` ou path vazio, o código usava `'masterpalm'` como fallback, exibindo o catálogo da MasterPalm em vez da loja do usuário.
- **Impacto:** Usuário logado na própria loja via home ou URL incompleta viava produtos da MasterPalm.

### Causa 2: home_store_context_helper — Hive sem validação de usuário
- **Arquivo:** `lib/utils/home_store_context_helper.dart`
- **Problema:** Quando `StoreResolverFacade.resolveForAdminApp()` retornava vazio, o fallback usava `Hive.box('sessao').get('store_id')` sem checar se `currentUser == usuario_logado`.
- **Impacto:** No Web (IndexedDB compartilhado) ou troca de conta, a loja de outro usuário era usada para o catálogo.

### Causa 3: ClienteAuthService.getLojaId() no Perfil
- **Arquivo:** `lib/screens/public_catalog_screen.dart`
- **Problema:** Ao abrir Perfil do cliente, usava `ClienteAuthService.getLojaId()` (SharedPreferences) como prioridade, podendo ser de outra loja em sessão anterior.
- **Impacto:** Perfil e fluxos relacionados podiam usar loja errada.

### Causa 4: cadastro_catalogo_screen — Hive sem validação
- **Arquivo:** `lib/screens/cadastro_catalogo_screen.dart`
- **Problema:** Fallback para `Hive.box('sessao').get('store_id')` quando `LojaIdService` falhava, sem validar `currentUser == usuario_logado`.
- **Impacto:** Cadastro de produto podia ir para loja errada.

---

## BLOCO 2 — ARQUIVOS ALTERADOS

| Arquivo | Correção |
|---------|----------|
| `lib/app_routes.dart` | Removido fallback `'masterpalm'`; usa `raw` ou `'minha-loja'` (catálogo mostra "Loja não encontrada" se inválido) |
| `lib/catalog_web.dart` | Removido fallback `'masterpalm'`; usa `'minha-loja'` quando URL não tem slug |
| `lib/utils/home_store_context_helper.dart` | Validação `currentUser == usuario_logado` antes de usar Hive; retorna vazio se sessão for de outra conta |
| `lib/screens/public_catalog_screen.dart` | Removido `ClienteAuthService.getLojaId()` do fluxo do Perfil; usa apenas `_resolvedLojaId ?? widget.lojaId` |
| `lib/screens/cadastro_catalogo_screen.dart` | Validação `currentUser == usuario_logado` antes de usar Hive como fallback |

---

## BLOCO 3 — CORREÇÕES APLICADAS

### Ordem de resolução da loja no catálogo

1. **Catálogo público por URL**  
   - `widget.lojaId` vem da URL (`/loja/{slug}`).  
   - `StoreResolverUnified.resolveForPublicCatalog(lojaIdFromUrl)` valida no Firestore.  
   - Sem fallback para `masterpalm` nem `minha-loja` como loja válida.

2. **Preview/admin (home, loja config, estoque)**  
   - Home: `resolveHomeStoreContext()` → StoreResolver primeiro, Hive só se `currentUser == usuario_logado`.  
   - Loja config: `_activeStoreId()` (StoreResolver).  
   - Estoque: `lojaId` do contexto.

3. **Hive/sessão**  
   - Usado só como fallback offline.  
   - Sempre com validação `currentUser == usuario_logado`.

4. **Nunca**  
   - Fallback para `masterpalm`.  
   - Box/config global quando existir versão por loja.  
   - `ClienteAuthService.getLojaId()` para definir loja do catálogo.

---

## BLOCO 4 — GARANTIA DE ISOLAMENTO

| Cenário | Garantia |
|---------|----------|
| **Catálogo público** | Loja vem da URL; StoreResolverUnified valida; sem fallback `masterpalm` |
| **Preview/admin** | Loja vem de StoreResolver ou Hive validado (usuário correto) |
| **Web** | `home_store_context_helper` valida usuário antes de Hive; sem `masterpalm` |
| **APK** | Mesma lógica; Hive validado |
| **Offline** | Hive usado só quando `currentUser == usuario_logado` |

---

## BLOCO 5 — LOGS DE VALIDAÇÃO

| Prefixo | Onde | O que validar |
|---------|------|----------------|
| `[CATALOGO-STORE]` | `public_catalog_screen.dart` `_resolveLojaId` | lojaId final e origem (público/admin) |
| `[CATALOGO-CONTEXT]` | `public_catalog_screen.dart` | `widget.lojaId`, `preview` |
| `[CATALOGO-CONFIG]` | `_cfgStream` | Path Firestore `lojas/{lojaId}/config` |
| `[CATALOGO-CONTEXT]` | `home_store_context_helper` | Origem (StoreResolver ou Hive com user match) |

---

## BLOCO 6 — TESTES MANUAIS

### APK
1. Login com conta que tem loja configurada.  
2. Home → "Visualizar Loja" → conferir se é a loja correta.  
3. Loja Config → Preview → conferir se é a mesma loja.  
4. Estoque → ícone catálogo → conferir se é a mesma loja.  
5. Logout → login com outra conta → repetir e conferir loja da nova conta.  
6. Salvar config → Publicar → abrir catálogo → conferir se produtos e config batem.

### Web
1. Login com conta que tem loja.  
2. Home → "Visualizar Loja" → conferir loja.  
3. Abrir `/loja/{slug-da-minha-loja}` → conferir loja.  
4. Refresh na página do catálogo → conferir se mantém a loja.  
5. Troca de conta no mesmo navegador → conferir se não mostra loja da conta anterior.  
6. Abrir `/loja/` ou `/loja/minha-loja` → deve mostrar "Loja não encontrada", não MasterPalm.

### Validação de logs
- Procurar por `[CATALOGO-STORE]` e `[CATALOGO-CONTEXT]` no console.  
- Confirmar que `lojaId` e origem estão corretos para cada cenário.
