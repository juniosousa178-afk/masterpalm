# AUDITORIA COMPLETA — Fluxo de Login/Autenticação MasterPalm

**Data:** 15/03/2025  
**Escopo:** APK Android, App Web, Login Google, Login manual, Login cliente, Admin/Programador/Vendedor, Restauração de sessão, Logout, Troca de conta, Offline, Multi-loja, Permissões  
**Regra:** Nenhum código foi alterado — apenas diagnóstico técnico.

---

## BLOCO 1 — MAPA REAL DO LOGIN

### A. Login manual admin
1. `LoginScreen` → `_login()` (linha ~250)
2. `signInWithEmailAndPassword` → Firebase Auth
3. `_buscarUsuarioLocal` ou `usuarios/{email}` no Firestore
4. Se vendedor: `store_id` de `_dadosExtrasUsuario`; senão: `StoreResolverFacade.resolveForAdminApp()`
5. Fallback se null: `loja_uid_$uid` ou `loja_email_${_slugLoja(email)}`
6. `sessao.put('usuario_logado', store_id, tipo_usuario, manter_logado)`
7. `_safeReplaceNamed('/router')`
8. `AppStartRouter._run()` → `_bindActiveStore` → `_routeByRoleAndLoja` → `_goHomeOrRestore()`

### B. Login Google admin
1. **APK:** `_loginWithGoogle()` → `googleSignIn.signOut()` → `signIn()` → `_handleGoogleUser()`
2. **Web:** `onCurrentUserChanged` (ignora primeiros 1.5s) → `_handleGoogleUser()`
3. `signInWithCredential` → Firebase Auth
4. `_carregarUsuarioDoFirestore` ou `_criarUsuarioGoogle`
5. Mesmo fluxo de loja que login manual (StoreResolver ou fallback)
6. `_safeReplaceNamed('/router')`

### C. Login cliente
1. `LoginScreenCliente` → `ClienteAuthService.login()` ou `loginComGoogle()`
2. Usa `widget.lojaId` (contexto do catálogo)
3. Não usa sessão Hive do app admin; fluxo isolado
4. `Navigator.pop()` ao sucesso (retorna ao catálogo)

### D. Sessão já restaurada no app start
1. `main.dart` → `_bootstrapSafe()` → fast path se `currentUser == null`, senão fluxo completo
2. **Web:** Se `currentUser == null`, aguarda `authStateChanges().first` até 2s (linha 1596–1604)
3. `MyApp` → `initialRoute: '/'` → `AppStartRouter`
4. `AppStartRouter._run()` → `user != null` → carrega sessão Hive → continua
5. Root: `_goHomeOrRestore()` imediato; vendedor com cache: idem; admin: verifica plano → `_bindActiveStore` → `_goHomeOrRestore()`

### E. Sessão restaurada no Web
1. `currentUser` pode ser null no início (IndexedDB/Firebase Auth demora)
2. Fast path usa `currentUser` direto — se null, vai para login sem esperar
3. Se fluxo completo: `authStateChanges().first` até 2s no bootstrap
4. `LoginScreen._verificarLoginSalvo()`: 500ms delay → se `currentUser != null` e `manter_logado` → `_safeReplaceNamed('/router')`
5. `onCurrentUserChanged` ignora primeiros 1.5s para evitar auto-login de cache

### F. Logout e novo login com outra conta
1. **Home:** `fazerLogout()` → `FirebaseAuth.signOut()` → `SessionSanity.clearAllStoreCache()` → `sessao.clear()` → `config.clear()` → `pushNamedAndRemoveUntil('/login')`
2. **AuthSession:** `signOutAndGoToLogin()` → `signOut` → `SessionSanity.clearAllStoreCache()` → clear boxes → `pushNamedAndRemoveUntil('/login')`
3. **AuthService.logout()** existe mas **não é usado** no fluxo principal (home usa `SessionSanity`)
4. **LojaIdService:** `_lojaId` em memória **não é limpo** por SessionSanity nem StoreResolverUnified

### G. Login offline com sessão anterior
1. `StoreResolverService.resolve()`: se `currentUser == null`, aguarda auth até 15s (Web) ou 5s (APK)
2. Se auth null após timeout: fallback Hive sessao/config (linhas 66–77)
3. **Risco:** Hive pode ter loja de usuário anterior (troca de conta no mesmo dispositivo)
4. `AppStartRouter`: vendedor usa `sessao.get('store_id')` em offline; admin usa plano em cache

### H. Login com conta sem loja
1. Vendedor: `ownerStoreId.isEmpty` → snackbar "Vendedor sem loja vinculada" → bloqueia
2. Admin: `StoreResolverFacade.resolveForAdminApp()` null → fallback `loja_uid_$uid` ou `loja_email_$slug` → cria loja implícita
3. `AppStartRouter`: vendedor sem store → `_go('/login')` (linha 305)

### I–K. Conta sem role / role inválido / outra loja
- Role vem de Firestore `users/{uid}` ou `usuarios/{email}`; fallback `vendedor`
- `AppStartRouter` usa `RoleUtils.resolveRole` para consistência
- Não há validação explícita de "loja do usuário = loja da sessão" antes de abrir home

### L. Login parcial (auth OK, loja falha)
1. `login_screen.dart` linha 510–512: `catch (e)` → `debugPrint` → **continua** e navega para `/router`
2. `lojaId` pode ficar null/vazio; fallback `loja_uid_$uid` ou `loja_email_$slug` é aplicado
3. Usuário chega no router com loja possivelmente incorreta

### M. Login que autentica mas não navega
- `_safeReplaceNamed` usa `_navLocked` e `mounted`; risco baixo
- Se `Navigator.pushReplacementNamed` falhar, `_navLocked` é resetado no `finally`

### N. Login que navega sem contexto de loja
- Router faz `_bindActiveStore` antes de `_goHomeOrRestore`
- Se `resolveForRouter` retorna null e fallback sessão/config falha, `loja` fica vazio mas **não bloqueia** (linha 580–583: "Nenhuma loja encontrada, continuando...")
- Home pode abrir com `_lojaIdInterno` vazio

### O. Login indevido (sem permissão)
- Não há guard de rota por role antes de abrir telas
- `AppStartRouter` decide rota inicial por role, mas telas internas não revalidam

---

## BLOCO 2 — O QUE ESTÁ CORRETO

| Arquivo | Função/Contexto | Por que está correto |
|---------|-----------------|----------------------|
| `session_sanity.dart` | `fixIfNoFirebaseUser()` | Limpa sessão Hive quando `currentUser == null`; invalida StoreResolver e StoreContext |
| `session_sanity.dart` | `clearAllStoreCache()` | Limpa StoreResolver, StoreContext, sessao, config |
| `app_start_router.dart` | `_bindActiveStore` fallback | Verifica `currentEmail == cachedUsuario` antes de usar store_id da sessão (linhas 558–567) |
| `app_start_router.dart` | `_go()` | Checa `mounted` antes de navegar |
| `login_screen_cliente.dart` | Fluxo isolado | Usa `widget.lojaId`; não mistura com sessão admin |
| `auth_session.dart` | `signOutAndGoToLogin` | Limpa SessionSanity + boxes + navega para login |
| `store_resolver_service.dart` | Cache por UID | `_cachedUid` evita retornar loja de outro usuário quando UID muda |
| `loja_id_service.dart` | `getWithTimeout` Web | Evita Hive como fast path; última tentativa chama `get()` que usa Hive (comentário contradiz implementação) |
| `last_route_observer.dart` | `_restorableRoutes` | Lista explícita de rotas restauradas; não restaura /login |

---

## BLOCO 3 — BUGS / RISCOS ENCONTRADOS

### Críticos

| # | Arquivo | Função/Contexto | Problema | Impacto |
|---|---------|-----------------|----------|---------|
| 1 | `app_start_router.dart` | `catch (e, stack)` linha 436–442 | Qualquer exceção em `_run()` leva a `_goHomeOrRestore()` sem validar sessão | Usuário pode entrar na home com sessão inválida ou role/loja incorretos |
| 2 | `session_sanity.dart` / `store_resolver_unified.dart` | `clearAllStoreCache` / `clearAllCaches` | **Não chamam `LojaIdService.clear()`** | `LojaIdService._lojaId` em memória persiste após logout; próxima sessão pode usar loja antiga |
| 3 | `login_screen.dart` | `_verificarLoginSalvo` vs `onCurrentUserChanged` | Race: `_verificarLoginSalvo` espera 500ms; `onCurrentUserChanged` ignora 1.5s. Se auth restaura entre 500ms–1.5s, `_verificarLoginSalvo` pode navegar e `onCurrentUserChanged` também, ou ordem inversa | Dupla navegação ou comportamento imprevisível |
| 4 | `last_route_observer.dart` + `login_screen.dart` | Restauração de rota no login | Login **não limpa** `last_route_before_background`. Se usuário A navegou para /vendedores, fez logout (ou foi para login), usuário B loga: sessao tem dados de B mas `last_route` ainda é de A | Usuário B pode ser redirecionado para tela de usuário A (ex: /admin_sync, /vendedores) |
| 5 | `main.dart` | Fast path (linha 1316) | Usa `currentUser` direto. No Web, auth pode restaurar depois; `currentUser == null` leva ao fast path e login, mesmo com sessão válida em IndexedDB | Usuário logado pode ver login em vez de home |

### Médios

| # | Arquivo | Função/Contexto | Problema | Impacto |
|---|---------|-----------------|----------|---------|
| 6 | `login_screen.dart` | `_loginWithGoogle` APK (linha 568) | `googleSignIn.signOut()` antes de `signIn()` | No Web (outra aba), pode deslogar conta Google compartilhada |
| 7 | `store_resolver_service.dart` | `resolve()` quando `currentUser == null` | Fallback Hive sessao/config (linhas 66–77) sem validar se usuário atual é o dono da sessão | Troca de conta: loja do usuário anterior pode ser usada |
| 8 | `loja_id_service.dart` | `getWithTimeout` (linhas 147–158) | Em Web, última tentativa chama `get()` que usa Hive sessao/config como fallback | Comentário diz "NÃO usar Hive" mas `get()` usa; risco de loja de outro usuário |
| 9 | `app_start_router.dart` | Atalho vendedor (linhas 115–128) | Se `cachedTipo == 'vendedor'` e `cachedStore` preenchido, abre home e valida em background | Role/store em cache podem estar desatualizados; validação em background pode falhar tarde |
| 10 | `login_screen.dart` | `catch (e)` linha 510 | StoreResolver falha → apenas `debugPrint` → continua com fallback `loja_uid_$uid` ou `loja_email_$slug` | Loja pode ser criada/incorreta sem feedback ao usuário |
| 11 | `app_start_router.dart` | `signOut` (linhas 385, 414) | `await FirebaseAuth.instance.signOut()` seguido de `_go()` sem checar `mounted` em um branch | Risco de navegação após dispose (baixo, mas existe) |
| 12 | `store_resolver_service.dart` | `_ensureAuthListener` | Listener de `authStateChanges` nunca é cancelado | Possível leak e reações a mudanças de auth em momentos inesperados |

### Baixos

| # | Arquivo | Função/Contexto | Problema | Impacto |
|---|---------|-----------------|----------|---------|
| 13 | `session_sanity.dart` | `fixIfNoFirebaseUser` | `Firebase.app()` pode lançar se não inicializado | Catch existe; impacto baixo |
| 14 | `home_screen.dart` | `fazerLogout` | Usa `SessionSanity.clearAllStoreCache` mas não `AuthService.logout` | AuthService tem `StoreResolverUnified.clearAllCaches`; home usa SessionSanity; ambos não limpam LojaIdService |
| 15 | `splash_screen.dart` | Legado | Rota `/splash` existe mas fluxo principal usa `AppStartRouter` em `/` | Splash pode estar obsoleto ou usado em cenário específico |

---

## BLOCO 4 — APK vs WEB

| Aspecto | APK | Web | Observação |
|--------|-----|-----|------------|
| Auth restore | `currentUser` geralmente pronto no cold start | `currentUser` pode ser null; IndexedDB demora | Web precisa de `authStateChanges` no bootstrap (2s) |
| Fast path | `currentUser` confiável | Pode ser null temporariamente | Web pode ir para login indevidamente |
| Google Sign-In | `signIn()` explícito; `signOut()` antes | `renderButton` + `onCurrentUserChanged` | Web: `signOut()` em outra aba pode afetar conta compartilhada |
| Hive/IndexedDB | Isolado por origem | Compartilhado no mesmo domínio | Troca de conta no mesmo navegador: risco de sessão/loja antiga |
| StoreResolver timeout | 3s (router), 5s (auth wait) | 6s (router), 15s (auth wait) | Web mais tolerante a latência |
| LojaIdService.getWithTimeout | 10s base | 30s base, retry 20s, última tentativa +3s | Web tenta mais antes de desistir |
| Last route restore | `getAndClearLastRoute` → sempre home no APK | Restaura última rota se path vazio | Web: risco de rota de conta anterior |
| Bootstrap | Sem espera extra de auth | `authStateChanges().first` até 2s se `currentUser == null` | Web tenta restaurar auth antes de desistir |

**Divergências que viram bug:**
- Fast path Web com `currentUser` null → login prematuro
- `last_route` restaurado no Web pode ser de outra conta
- Hive/IndexedDB compartilhado → contaminação de store_id entre usuários

---

## BLOCO 5 — ACESSO INDEVIDO / BLOQUEIO INDEVIDO

1. **Existe risco de login indevido?**  
   Sim. Erro em `AppStartRouter` cai no `catch` e vai para home. Usuário sem role/loja validada pode entrar. Não há guard por role nas rotas internas.

2. **Existe risco de usuário válido ser bloqueado?**  
   Sim. Web: fast path com `currentUser` null → login. Timeout do StoreResolver ou plano → pode bloquear. `_verificarLoginSalvo` com 500ms pode ser cedo demais se auth demorar.

3. **Existe risco de conta antiga contaminar a nova?**  
   Sim. `LojaIdService._lojaId` não é limpo. `last_route_before_background` não é limpo no login. Hive sessao/config no fallback do StoreResolver pode ter dados antigos.

4. **Existe risco de entrar com loja errada?**  
   Sim. Fallback `loja_email_$slug` ou `loja_uid_$uid` pode criar/usar loja incorreta. Cache de vendedor no router pode estar desatualizado.

5. **Existe risco de role errada?**  
   Médio. Role vem de Firestore; fallback `vendedor`. Cache em sessão pode estar antigo. `RoleUtils` tenta unificar, mas não há revalidação em todas as telas.

6. **Risco maior no Web ou no APK?**  
   Web. Auth restore tardio, IndexedDB compartilhado, `last_route` de outra conta, `currentUser` null no fast path.

---

## BLOCO 6 — CONCLUSÃO FINAL

### O fluxo de login está confiável?
Não totalmente. Há falhas silenciosas, race conditions e limpeza incompleta no logout/troca de conta.

### Pontos mais perigosos (ordem sugerida de correção)

1. **LojaIdService não limpo no logout** — Incluir `LojaIdService.clear()` em `SessionSanity.clearAllStoreCache` e `StoreResolverUnified.clearAllCaches`.
2. **Erro crítico no router leva à home** — Remover ou restringir o `catch` que chama `_goHomeOrRestore()`; em erro, ir para login.
3. **last_route de outra conta** — Limpar `last_route_before_background` no login (ou validar que pertence ao usuário atual).
4. **Fast path Web com currentUser null** — Garantir que o fluxo completo espere auth no Web antes de decidir login.
5. **Race _verificarLoginSalvo vs onCurrentUserChanged** — Unificar lógica (ex.: um único ponto que espera auth e decide).
6. **Fallback Hive no StoreResolver com auth null** — Validar que sessão Hive pertence ao `currentUser` antes de usar.
7. **Login não limpa last_route** — Deletar `last_route_before_background` ao fazer login.
8. **Catch silencioso no login (StoreResolver)** — Tratar falha de resolução de loja com feedback e possível bloqueio.

### Sem correções ainda
Nenhuma alteração de código foi feita nesta auditoria.
