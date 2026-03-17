# CORREÇÕES LOGIN/AUTH — ENTREGA

## BLOCO 1 — ARQUIVOS ALTERADOS

| Arquivo | Alterações |
|---------|------------|
| `lib/screens/app_start_router.dart` | Erro crítico: signOut + redirecionar para /login em vez de /home |
| `lib/utils/last_route_observer.dart` | Novo método `clearLastRoute()` |
| `lib/services/session_sanity.dart` | Chamar `LojaIdService.clear()` e `LastRouteObserver.clearLastRoute()` em `fixIfNoFirebaseUser` e `clearAllStoreCache` |
| `lib/services/loja_id_service.dart` | `clear()` limpa `_instance._lojaId`; `get()` valida `currentUser == usuario_logado` antes de usar Hive |
| `lib/services/store_resolver_unified.dart` | `clearAllCaches()` chama `LojaIdService.clear()` e `LastRouteObserver.clearLastRoute()` |
| `lib/services/store_resolver_service.dart` | Removido fallback Hive quando auth é null (evita contaminação) |
| `lib/screens/login_screen.dart` | `_verificarLoginSalvo` usa authStateChanges com timeout; `onCurrentUserChanged` trata restore vs novo login; `LastRouteObserver.clearLastRoute()` no login; tratamento explícito de falha StoreResolver; validação lojaId antes de navegar |
| `lib/main.dart` | Fast path Web: aguarda authStateChanges até 3s antes de decidir hasUser |

---

## BLOCO 2 — PROBLEMA CORRIGIDO EM CADA ARQUIVO

| Arquivo | Problema | Correção |
|---------|----------|----------|
| `app_start_router.dart` | Erro crítico levava para /home sem validação | Em erro: signOut + `_go('/login')` |
| `last_route_observer.dart` | Não havia forma de limpar last_route | Método `clearLastRoute()` |
| `session_sanity.dart` | Logout não limpava LojaIdService nem last_route | Chamadas a `LojaIdService.clear()` e `LastRouteObserver.clearLastRoute()` |
| `loja_id_service.dart` | `_lojaId` em memória persistia após logout; Hive usado sem validar usuário | `clear()` limpa instância; `get()` valida `currentEmail == cachedUsuario` antes de usar Hive |
| `store_resolver_unified.dart` | `clearAllCaches` não limpava LojaIdService nem last_route | Chamadas adicionadas |
| `store_resolver_service.dart` | Fallback Hive com auth null podia usar loja de outra conta | Removido fallback; retorna null quando auth é null |
| `login_screen.dart` | Race entre _verificarLoginSalvo e onCurrentUserChanged; last_route não limpo; falha StoreResolver silenciosa | Unificação com authStateChanges; clearLastRoute no login; tratamento explícito e validação lojaId |
| `main.dart` | Fast path Web decidia com currentUser null cedo demais | Aguarda authStateChanges até 3s no Web antes de decidir |

---

## BLOCO 3 — SEGURANÇA CONTRA RISCOS

### Login indevido
- Erro no router → signOut + /login (não /home)
- Falha StoreResolver no login → snackbar + retorno (não navega)
- Validação lojaId antes de navegar

### Bloqueio indevido
- Fast path Web aguarda auth até 3s
- _verificarLoginSalvo usa authStateChanges com timeout 3s
- Fallback Hive em LojaIdService só quando currentUser == usuario_logado

### Contaminação entre contas
- Logout limpa LojaIdService, last_route, sessao, config
- last_route limpo no login e no logout
- StoreResolver não usa Hive quando auth é null
- LojaIdService.get() valida usuário antes de usar Hive
- AppStartRouter._bindActiveStore já validava currentEmail == cachedUsuario

---

## BLOCO 4 — DIFERENÇAS APK vs WEB APÓS CORREÇÃO

| Aspecto | APK | Web |
|---------|-----|-----|
| Fast path | currentUser direto | Aguarda authStateChanges até 3s se null |
| Restauração sessão | authStateChanges em _verificarLoginSalvo | Mesmo fluxo unificado |
| onCurrentUserChanged | Não usado (login manual) | Restore vs novo login: se manter_logado + email match → navega; senão → _handleGoogleUser |
| Fallback Hive | Só com currentUser e match usuario_logado | Idem |
| Logout | SessionSanity.clearAllStoreCache + LojaIdService + last_route | Idem |

---

## BLOCO 5 — TESTES MANUAIS SUGERIDOS

### Login manual
1. Email/senha válidos → deve ir para /router → /home
2. Email/senha inválidos → snackbar de erro
3. StoreResolver falha (ex.: offline) → snackbar "Erro ao carregar dados da loja"
4. Vendedor sem loja → snackbar "Vendedor sem loja vinculada"

### Login Google
1. APK: clicar no botão → fluxo Google → /router → /home
2. Web: clicar no botão → popup Google → /router → /home
3. Restore: manter_logado + sessão em cache → deve restaurar e ir para /router

### Login cliente
1. Catálogo → login cliente (email/senha ou Google) → pop e volta ao catálogo
2. Não deve alterar sessão do app admin

### Sessão restaurada
1. Fechar app com usuário logado
2. Reabrir → deve ir para /router → /home (sem tela de login)
3. Web: aguardar até 3s se auth demorar

### Logout
1. Home → logout → /login
2. Verificar: sessao vazia, config vazia, last_route limpo
3. Login com outra conta → não deve herdar rota da conta anterior

### Troca de conta
1. Usuário A logado → logout
2. Usuário B loga
3. Verificar: loja/contexto de B, não de A
4. last_route não deve restaurar tela de A

### Web multi-conta
1. Aba 1: usuário A logado
2. Aba 2: logout e login com B
3. Verificar: B não vê dados de A
4. IndexedDB/Hive não deve contaminar

### Offline com sessão anterior
1. Usuário logado → desligar rede
2. Fechar e reabrir app
3. Deve restaurar sessão (currentUser em cache)
4. StoreResolver com auth null não usa Hive (retorna null) → fluxo vai para login se auth não restaurar
