# Regressao Tecnica - WEB lojaId (Vendas/Clientes)

## Objetivo
Garantir que o erro no WEB:

`Nao foi possivel carregar a loja. Verifique sua conexao e tente novamente.`

nao volte a acontecer nas telas administrativas de `Vendas` e `Clientes`, sem abrir risco de carregar loja errada.

---

## 1) Causa raiz confirmada

- O problema ocorria no **WEB** quando `FirebaseAuth.currentUser` ainda nao estava restaurado no momento em que as telas iniciavam.
- `VendasScreen` e `ClientesScreen` dependiam de `LojaIdService.getWithTimeout(...)`.
- No fluxo antigo, quando `StoreResolverService.resolve()` retornava `null` por `auth` pendente, o caminho de fallback nao aproveitava de forma segura o `store_id` persistido no Hive para esse estado especifico.
- Resultado: `lojaId` ficava `null`, e as telas entravam no estado de erro de loja nao carregada.

Por que o APK nao era afetado:
- No mobile, a restauracao de auth geralmente ocorria dentro das janelas de tempo das telas, evitando o `null` no mesmo ponto do fluxo.

---

## 2) Fluxo antigo (antes da correcao)

1. Tela abre (`VendasScreen`/`ClientesScreen`).
2. Chama `LojaIdService.getWithTimeout(...)`.
3. `StoreResolverFacade.resolveForAdminApp()` -> `StoreResolverService.resolve()`.
4. Com `auth` pendente no WEB, `resolve()` podia retornar `null`.
5. `lojaId` seguia `null`.
6. Tela mostrava erro: "Nao foi possivel carregar a loja...".

---

## 3) Fluxo corrigido (atual)

### 3.1 Resolucao central (StoreResolverService)
Arquivo: `lib/services/store_resolver_service.dart`

- Se `currentUser` continuar `null` no WEB apos espera:
  - entra em `_safeHiveFallbackWhenAuthNull()`;
  - valida principal de sessao (`usuario_logado_email` ou `usuario_logado`);
  - valida `store_id` com `normalizeFromBox(...)`;
  - rejeita valor invalido/placeholder;
  - se seguro, retorna `store_id` e evita falha por corrida de auth.

### 3.2 Camada de loja (LojaIdService)
Arquivo: `lib/services/loja_id_service.dart`

- `getWithTimeout()` manteve tentativas normais e ganhou fallback final WEB centralizado:
  - `_resolveSafeWebHiveFallback(authEmail: ...)`.
- `get()` tambem utiliza fallback WEB seguro quando `currentUser` esta `null`.
- Validacoes de seguranca:
  - candidato obrigatoriamente valido (`isValidForPublicLink`);
  - principal de sessao obrigatorio;
  - se `authEmail` existir, precisa ser igual ao principal de sessao.

### 3.3 Persistencia no bootstrap WEB
Arquivo: `lib/main.dart`

- `_ensureStoreIdOnBootstrap(...)` persiste `store_id` em:
  - `sessao['store_id']`
  - `config['store_id']`
- Esse dado agora e reaproveitado pelos fallbacks centrais quando `auth` ainda nao restaurou.

---

## 4) Cenarios de validacao manual (regressao)

### Cenario A - WEB com auth atrasado e cache valido (Vendas)
**Pre-condicao**
- Usuario logado previamente.
- `sessao/config` com `store_id` valido.
- Simular restauracao lenta de auth (reload em aba com rede lenta ou primeira carga apos inatividade).

**Passos**
1. Abrir app WEB.
2. Navegar para `Vendas`.

**Resultado esperado**
- Tela abre normalmente sem erro de loja.
- Nao exibe "Nao foi possivel carregar a loja...".

---

### Cenario B - WEB com auth atrasado e cache valido (Clientes)
**Passos**
1. Abrir app WEB.
2. Navegar para `Clientes`.

**Resultado esperado**
- Tela abre normalmente sem erro de loja.

---

### Cenario C - WEB sem cache seguro
**Pre-condicao**
- Limpar dados locais (Storage/IndexedDB) ou remover `store_id` da sessao/config.
- Auth ainda pendente/indisponivel.

**Passos**
1. Abrir app WEB.
2. Navegar para `Vendas` ou `Clientes`.

**Resultado esperado**
- Falha legitima permanece.
- Tela mostra erro de loja nao carregada (sem falso positivo).

---

### Cenario D - Troca de conta no mesmo navegador (cache antigo)
**Pre-condicao**
- Conta A deixa `store_id` em cache.
- Trocar para Conta B no mesmo browser.

**Passos**
1. Abrir `Vendas`/`Clientes` com Conta B.

**Resultado esperado**
- Fallback deve rejeitar cache contaminado quando principal nao bater.
- Nao carregar loja de outra conta.

---

### Cenario E - APK/mobile
**Passos**
1. Abrir app mobile.
2. Navegar para `Vendas` e `Clientes`.

**Resultado esperado**
- Comportamento preservado (sem regressao).

---

## 5) Arquivos alterados na correcao

- `lib/services/store_resolver_service.dart`
  - fallback WEB seguro para auth pendente.
- `lib/services/loja_id_service.dart`
  - fallback WEB seguro centralizado em `get()`/`getWithTimeout()`.
- `lib/screens/vendas_screen.dart`
  - limpeza de logs temporarios de diagnostico.
- `lib/screens/clientes_screen.dart`
  - limpeza de logs temporarios de diagnostico.

---

## 6) Riscos evitados com a correcao

- Erro intermitente de loja nao carregada em WEB por corrida de restauracao de auth.
- Dependencia fragil de timing em `Vendas`/`Clientes`.
- Aceite inseguro de cache de outra conta (contaminacao multi-conta no mesmo navegador).
- Mascarar erro real quando nao houver dados seguros (fluxo atual continua retornando erro legitimo).

---

## 7) Checklist de regressao

- [ ] Vendas WEB abre com auth atrasado + cache valido
- [ ] Clientes WEB abre com auth atrasado + cache valido
- [ ] Erro legitimo mantido quando nao ha dados seguros
- [ ] Cache contaminado rejeitado em troca de conta
- [ ] APK preservado

