# Entrega: Segurança clientes + Fallback loja (MasterPalm)

**Data:** 2025-03-06  
**Escopo:** Prioridade 1 (clientes.update), Prioridade 2 (clientes.list), Prioridade 3 (fallback 'default').  
**Restrições respeitadas:** Sem refatorar sistema inteiro; sem quebrar login, cadastro, perfil, Meus Pedidos ou carrinho; sem alterar PedidoCollectionResolver, triggers de sync, mpWebhookHandler ou HiveBoxNames.

---

## 1. Diagnóstico por prioridade

### Prioridade 1 — clientes.update
- **Problema:** A rule permitia update por qualquer um que mantivesse o mesmo `email`, sem checar loja nem identidade (portalToken).
- **Solução:** Regra de update exige **belongsToStore(lojaId)** (admin/vendedor) **OU** mesmo **portalToken** no payload e no documento, com `size <= 30`. O app envia `portalToken` em todos os updates feitos pelo catálogo (perfil, favoritos, carrinho, senha, etc.). Token é obtido/criado via CF getDadosCompletos; o app não faz mais update “só com portalToken” para criar o token (evita abuso).

### Prioridade 2 — clientes.list
- **Problema:** List sem auth era permitido com `limit <= 10`, permitindo vazamento de até 10 clientes.
- **Solução:** Exceção alterada para **limit <= 1**. Login/cadastro já usam `.limit(1)` com filtro por email; comportamento mantido com vazamento máximo de 1 documento por query.

### Prioridade 3 — fallback 'default'
- **Problema:** Uso de `'default'` (ou equivalente) como loja/store_id podia fazer operações na loja errada (desfazer venda, backup, catálogo, campanhas).
- **Solução:** Removido fallback para `'default'` nos pontos críticos; quando não há loja definida, não se opera (return/skip ou mensagem “Selecione a loja”).

---

## 2. Lista exata dos arquivos alterados

| Arquivo | Alteração |
|--------|-----------|
| `firestore.rules` | Regras de `clientes`: list `limit <= 1`; update com belongsToStore OU portalToken + size <= 30. |
| `lib/services/cliente_auth_service.dart` | portalToken em todos os updates em `clientes`; _ensurePortalToken via getDadosCompletos (sem update direto); garantir token em solicitarRedefinicaoSenha e redefinirSenhaComCodigo. |
| `lib/services/vendas_service.dart` | desfazerVenda: lojaId da venda ou do nome da box; sem 'default'; return se loja vazia. |
| `lib/services/backup_auto_service_io.dart` | store_id da sessão sem 'default'; return se vazio. |
| `lib/screens/backup_screen_web.dart` | _storeId sem 'default'; guard em _exportarBackupWeb se _storeId vazio. |
| `lib/screens/catalago_screen.dart` | Sem 'default'; abrir catálogo só com lojaId definido; mensagem “Loja não definida” quando vazio. |
| `lib/screens/campanhas_sorteio_screen.dart` | store_id sem defaultValue 'mastepalm'; tela “Selecione uma loja” quando vazio. |
| `docs/ENTREGA_SEGURANCA_CLIENTES_E_FALLBACK.md` | Este documento. |

---

## 3. Código das alterações (resumo)

### firestore.rules — clientes
- **list:** `request.query.limit <= 10` → `request.query.limit <= 1`.
- **update:** de `isAdminOrSystem() || (email igual e size <= 25)` para:
  - `belongsToStore(lojaId) || (request.resource.data.portalToken is string && request.resource.data.portalToken == resource.data.portalToken && request.resource.data.size() <= 30)`.

### cliente_auth_service.dart
- **_ensurePortalToken:** Não faz mais `ref.update({'portalToken': ...})`. Obtém token dos dados ou via `getDadosCompletos` (CF cria token se faltar).
- **atualizarDados:** Obtém portalToken de `getClienteLogado()`; se vazio retorna erro “Sessão inválida”; inclui `portalToken` em `updates`.
- **toggleFavorito:** Inclui `portalToken` no update (de `dados`); retorna erro se token vazio.
- **saveCarrinho:** Obtém portalToken de `getClienteLogado()`; inclui no update; se vazio retorna sem escrever.
- **loginComGoogle (update existente):** Inclui `portalToken` do doc no update.
- **solicitarRedefinicaoSenha (mobile):** Se doc sem portalToken, chama `getDadosCompletos` para obter/criar; envia `portalToken` nos dois updates.
- **redefinirSenhaComCodigo:** Se token vazio, obtém via `getDadosCompletos`; envia `portalToken` em todos os updates.
- **redefinirSenhaPelaLoja:** Inclui `portalToken` do doc no update (admin já passa por belongsToStore).
- **alterarSenha:** Exige token em sessão; inclui `portalToken` no update; retorna “Sessão inválida” se vazio.

### vendas_service.dart — desfazerVenda
- `lojaId = venda.lojaId ?? 'default'` substituído por: lojaId da venda ou, se vazio, extraído do nome da box (`vendas_lojaId`); se ainda vazio, `return` sem desfazer.

### backup_auto_service_io.dart
- `store_id` da sessão com fallback `''`; se `storeId.isEmpty`, `return` (não executa backup).

### backup_screen_web.dart
- `_storeId` inicial e em _loadStoreId sem 'default'; em _exportarBackupWeb, se `_storeId.isEmpty` mostra SnackBar e return.

### catalago_screen.dart
- `lojaId = _lojaId ?? 'default'` removido; se `lojaId.isEmpty` não abre box de catálogo; carrega config; em build mostra “Loja não definida…” quando sem loja.

### campanhas_sorteio_screen.dart
- store_id sem defaultValue 'mastepalm'; se `lojaId.isEmpty` mostra tela “Selecione uma loja para acessar as campanhas”.

---

## 4. Compatibilidade preservada

- **Login / Cadastro:** Continuam com `.where('email', ...).limit(1)`; a rule list `limit <= 1` permite.
- **Perfil (atualizarDados):** Envia portalToken da sessão; usuário logado no catálogo já tem token (getDadosCompletos/cadastro).
- **portalToken:** Criado/obtido pela CF getClienteCatalog/getDadosCompletos; o app só lê ou envia o mesmo valor nos updates.
- **Carrinho / Favoritos:** Passam a enviar portalToken; sessão já tem token após login/getDadosCompletos.
- **Esqueci senha / Redefinir com código:** Obtêm token via getDadosCompletos quando o doc não tem; fluxo de email e código inalterado.
- **Redefinir senha pela loja:** Admin/vendedor continua passando por belongsToStore; portalToken no payload mantém consistência.
- **getClienteCatalog (CF):** Não alterado; segue criando/retornando portalToken.
- **Desfazer venda:** Quando venda tem lojaId ou a box é da loja (nome `vendas_lojaId`), comportamento igual; sem loja definida não desfaz (evita loja errada).
- **Backup (auto e web):** Com loja definida na sessão, igual; sem loja não faz backup / pede seleção.
- **Catálogo:** Com loja na sessão, igual; sem loja mostra mensagem em vez de usar 'default'.
- **Campanhas sorteio:** Com loja selecionada, igual; sem loja mostra “Selecione uma loja”.

---

## 5. Checklist de testes manuais

- [ ] **Login catálogo:** Email/senha e login com Google; verificar que perfil e token são carregados.
- [ ] **Cadastro catálogo:** Novo cliente; verificar que pode acessar perfil e favoritos/carrinho.
- [ ] **Perfil:** Alterar nome/telefone/endereço; salvar e recarregar; verificar que não dá “Sessão inválida”.
- [ ] **Favoritos:** Adicionar/remover favorito; verificar que persiste.
- [ ] **Carrinho:** Adicionar itens e sair; voltar e verificar carrinho; salvar e recarregar.
- [ ] **Esqueci senha (app):** Solicitar código; receber email; redefinir com código; login com nova senha.
- [ ] **Alterar senha (perfil):** Trocar senha estando logado; login com nova senha.
- [ ] **Redefinir senha pela loja (admin):** Na tela de cliente, redefinir senha; cliente faz login com nova senha.
- [ ] **Desfazer venda:** Em vendas da loja A, desfazer uma venda com lojaId; verificar estoque e que não afeta outra loja.
- [ ] **Backup automático (mobile):** Com sessão de uma loja, aguardar/trigger backup; sem loja não deve gravar com 'default'.
- [ ] **Backup web:** Com loja selecionada, exportar; sem loja deve mostrar “Selecione uma loja”.
- [ ] **Catálogo:** Acessar com loja definida; sem loja deve mostrar “Loja não definida…”.
- [ ] **Campanhas sorteio:** Com loja definida, listar campanhas; sem loja deve mostrar “Selecione uma loja”.

---

## 6. Riscos residuais

- **clientes.list:** Ainda existe list sem auth com `limit <= 1`; um atacante pode fazer muitas queries e enumerar emails (1 doc por query). Fechar totalmente exigiria CF para “find by email” e remover list público (próxima etapa).
- **clientes.update:** Quem conhece o portalToken do documento pode atualizar esse documento (por design). Manter portalToken só no servidor (CF) e no app do cliente; não expor em URLs ou logs.
- **Vendas antigas sem lojaId:** Se uma venda não tiver lojaId e a box não seguir o padrão `vendas_lojaId`, desfazerVenda não desfaz (return). Pode ser desejável preencher lojaId em dados antigos ou tratar em migração.

---

## 7. O que fica para a próxima etapa

- Substituir **clientes.list** público por Cloud Function “find by email” e remover exceção de limit na rule (fechar list só para admin/vendedor).
- Revisar outros usos de `defaultValue`/fallback para loja em telas e scripts (ex.: relatorio_financeiro_screen com lojaId vazio → box `vendas_`).
- Auditoria de onde **portalToken** é exposto (URLs, logs, analytics) e garantir que não vaze.
- Opcional: migração de vendas antigas sem `lojaId` para preencher a partir do contexto (box/nome) quando possível.
