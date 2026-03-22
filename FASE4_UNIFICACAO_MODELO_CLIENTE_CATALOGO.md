# FASE 4: Unificação do Modelo de Cliente do Catálogo

**Objetivo:** Reduzir fragmentação entre coleções de cliente e definir a fonte principal da verdade para o fluxo catálogo → pre_pedido → clientes_portal → webhook → status.

**Status:** Proposta técnica (diagnóstico). Etapas A e B implementadas (ver seção "Implementação").

---

## 1. Resumo executivo

O MasterPalm possui **5 coleções** relacionadas a clientes, com papéis e chaves distintas. O fluxo principal do catálogo (PublicCatalogScreen, pre_pedido, checkout, Meus Pedidos) já está funcional e usa `clientes` como identidade e `clientes_portal` como espelho de pedidos. A fragmentação gera:

- **Duplicação de dados** (mesmo cliente em `clientes`, `estoque_clientes`, possivelmente `clientes_web`)
- **Chaves diferentes** (clienteId, portalToken, email, telefone) sem mapa claro
- **Cupons da roleta** em `clientes_catalogo` separados da identidade em `clientes`
- **Escritas paralelas** em `estoque_clientes` e `clientes` para fluxos distintos

**Recomendação:** Manter `clientes` (lojas/{lojaId}/clientes) como **fonte principal da verdade** para identidade do cliente do catálogo. `clientes_portal` continua como espelho/vista para Meus Pedidos. `clientes_catalogo` deve migrar para subcoleção em `clientes` ou manter-se como cache de cupons por email, com regra explícita. `clientes_web` e `estoque_clientes` permanecem com funções distintas (catálogo admin legado vs admin/sync).

---

## 2. Papel atual de cada coleção

### 2.1. `clientes` (lojas/{lojaId}/clientes)

| Atributo | Valor |
|----------|-------|
| **Chave do doc** | `clienteId` — timestamp_rand (`gerarClienteId`) ou `ec_xxx` determinístico (`clienteIdPorEmail`) |
| **Tipo** | Identidade principal do catálogo público |
| **Quem escreve** | `ClienteAuthService` (cadastro, login, atualizarDados, alterarSenha, Google), `PrePedidoService` (_ensureClienteComPortalToken, atualização de endereço), CF `resolveClientePortalTarget` (portalToken) |
| **Quem lê** | `ClienteAuthService` (login, cupons, perfil), `PrePedidoService` (_resolvePortalTokenForPedido), CF `getClienteCatalog`, CF `resolveClientePortalTarget`, CF `solicitarRedefinicaoSenhaCatalogo` |
| **Fluxos** | Login/cadastro catálogo web, pré-pedido, carrinho, favoritos, cupons, Meus Pedidos (via portalToken) |
| **Campos principais** | id, nome, email, senhaHash, telefone, portalToken, cupons, favoritos, pedidos, carrinho, endereco, enderecoFormatado, dataCadastro |
| **Sync Hive** | Não |

**Arquivos:** `lib/services/cliente_auth_service.dart`, `lib/services/pre_pedido_service.dart`, `lib/services/cliente_auth_helpers.dart`, `functions/index.js` (COLLECTION_CLIENTES)

---

### 2.2. `clientes_web` (lojas/{lojaId}/clientes_web)

| Atributo | Valor |
|----------|-------|
| **Chave do doc** | ID gerado pelo Firestore (add) |
| **Tipo** | Fluxo paralelo sem senha (login/cadastro por email) |
| **Quem escreve** | `ClienteWebService` (loginOuCadastro, update, cupons) |
| **Quem lê** | `ClienteWebService` (getClienteAutenticado, pedidos) |
| **Fluxos** | Catálogo interno/admin (rota `/catalogo`) — `CatalogoScreen`, `ClienteLoginScreen`, `ClientePerfilScreen` |
| **Campos principais** | Modelo `ClienteWeb` — nome, email, etc. (sem senha) |
| **Sync Hive** | Não |

**Arquivos:** `lib/services/cliente_web_service.dart`, `lib/screens/catalago_screen.dart`, `lib/screens/cliente_login_screen.dart`, `lib/screens/cliente_perfil_screen.dart`

**Observação:** O catálogo público principal (Web `/loja`) usa `PublicCatalogScreen` + `ClienteAuthService` (clientes). O `CatalogoScreen` (rota `/catalogo`) é o catálogo interno do app admin e usa `clientes_web`.

---

### 2.3. `clientes_portal` (lojas/{lojaId}/clientes_portal/{portalToken})

| Atributo | Valor |
|----------|-------|
| **Chave do doc** | `portalToken` (24 bytes base64url, aleatório) |
| **Estrutura** | Doc principal + subcoleção `pedidos/{pedidoId}` |
| **Tipo** | Espelho/vista para "Meus Pedidos" e perfil |
| **Quem escreve** | `PrePedidoService` (via `ClientePortalRepository.savePedidoResumo`), CF `syncPedidoStatusPublico` → `upsertClientePortalFromPedido`, `backfill_fontes_cliente_pedidos.js` |
| **Quem lê** | `ClientePortalRepository`, `MeusPedidosRepository` |
| **Fluxos** | Meus Pedidos (portal), perfil portal |
| **Campos principais** | lojaId, clienteId, dataAtualizacao, ultimoEndereco, ultimoEnderecoFormatado; subcoleção: pedidoId, status, total, itensResumo |
| **Sync Hive** | Não |

**Arquivos:** `lib/repositories/cliente_portal_repository.dart`, `lib/repositories/meus_pedidos_repository.dart`, `lib/services/pre_pedido_service.dart`, `functions/index.js`, `functions/backfill_fontes_cliente_pedidos.js`

---

### 2.4. `clientes_catalogo` (lojas/{lojaId}/clientes_catalogo/{email}/cupons/{codigo})

| Atributo | Valor |
|----------|-------|
| **Chave do doc** | `email` normalizado (lowercase) |
| **Estrutura** | Doc por email + subcoleção `cupons/{codigo}` |
| **Tipo** | Cache de cupons da roleta por email |
| **Quem escreve** | `PosPagamentoService` (cupom roleta após pagamento webhook), `CatalogoVendaService` (cupom roleta após confirmação venda local), `ClienteAuthService.marcarCupomRoletaComoUsado` |
| **Quem lê** | `ClienteAuthService.getCuponsRoleta` |
| **Fluxos** | Roleta da sorte, "Meus Cupons" (mesclado com cupons do doc `clientes`) |
| **Campos principais** | cupons: codigo, descricao, tipo, valor, dataGanho, dataExpiracao, usado, ativo, origem |
| **Sync Hive** | Não |

**Arquivos:** `lib/services/cliente_auth_service.dart`, `lib/services/pos_pagamento_service.dart`, `lib/services/catalogo_venda_service.dart`, `lib/screens/auth/perfil_cliente_screen_novo.dart` (mescla cupons de clientes + clientes_catalogo)

---

### 2.5. `estoque_clientes` (lojas/{lojaId}/estoque_clientes)

| Atributo | Valor |
|----------|-------|
| **Chave do doc** | `telefone` (apenas dígitos) |
| **Tipo** | Admin + histórico + sync Hive |
| **Quem escreve** | `PrePedidoService` (_salvarOuAtualizarCliente, _adicionarPedidoAoHistoricoCliente), `PosPagamentoService` (cupom roleta por telefone), `ClientesFirestoreService` (admin CRUD) |
| **Quem lê** | `ClientesFirestoreService`, `FullSyncService`, `PrePedidoService` (LimitsGuard, busca) |
| **Fluxos** | Admin (tela Clientes, Nova Venda), sync Firestore → Hive, histórico de compras, cupom roleta (por telefone) |
| **Campos principais** | nome, telefone, email, cpf, endereco, historicoCompras, totalCompras, quantidadeCompras |
| **Sync Hive** | Sim — `clientes_{lojaId}` via `FullSyncService._syncClientes` |

**Arquivos:** `lib/services/clientes_firestore_service.dart`, `lib/services/full_sync_service.dart`, `lib/services/pre_pedido_service.dart`, `lib/services/pos_pagamento_service.dart`, `lib/screens/historico_clientes_screen.dart` (usa Hive)

---

## 3. Fonte principal recomendada

### 3.1. Para o fluxo catálogo (identidade do cliente que compra no catálogo público)

| Coleção | Papel | Chave | Recomendação |
|---------|-------|-------|--------------|
| **clientes** | Identidade principal | clienteId (ec_xxx ou timestamp) | **Fonte da verdade** |
| **clientes_portal** | Vista "Meus Pedidos" | portalToken | Espelho derivado — manter |
| **clientes_catalogo** | Cupons roleta por email | email | Migrar para clientes ou manter com regra clara |
| **clientes_web** | Catálogo admin legado | doc id | Legado — não escrever novas features |
| **estoque_clientes** | Admin + sync | telefone | Separado — não misturar com catálogo |

### 3.2. Chave real de identidade hoje

| Coleção | Chave do doc | Chave lógica |
|---------|--------------|--------------|
| clientes | clienteId | email (login), portalToken (Meus Pedidos) |
| clientes_web | auto | email |
| clientes_portal | portalToken | portalToken (único por cliente) |
| clientes_catalogo | email | email |
| estoque_clientes | telefone | telefone |

**Vínculo cliente ↔ portal:** O doc `clientes/{clienteId}` contém `portalToken`. O doc `clientes_portal/{portalToken}` contém `clienteId`. A resolução é feita em `PrePedidoService._resolvePortalTokenForPedido` e na CF `resolveClientePortalTarget` (por clienteId ou email em clientes).

---

## 4. Coleções derivadas / legadas

| Coleção | Status | Ação sugerida |
|---------|--------|---------------|
| **clientes** | Principal | Manter como fonte da verdade |
| **clientes_portal** | Derivado | Manter — espelho necessário para Meus Pedidos |
| **clientes_catalogo** | Uso específico (cupons) | Unificar cupons em clientes ou documentar dependência por email |
| **clientes_web** | Legado (catálogo admin) | Marcar legado — não novas escritas de features de catálogo público |
| **estoque_clientes** | Admin separado | Manter — domínio distinto (admin, sync, histórico por telefone) |

---

## 5. Problemas atuais de fragmentação

1. **Mesmo cliente em múltiplas coleções**
   - Cliente que compra no catálogo: pode existir em `clientes` (por email), `clientes_portal` (por portalToken), `estoque_clientes` (por telefone), `clientes_catalogo` (por email para cupons).
   - Sem vínculo explícito entre clienteId e telefone; `estoque_clientes` e `clientes` não se cruzam por design.

2. **Campos divergentes**
   - `clientes`: nome, email, senhaHash, portalToken, cupons, carrinho, favoritos, endereco.
   - `estoque_clientes`: nome, telefone, email, historicoCompras, totalCompras.
   - Cupons: em `clientes.cupons` e em `clientes_catalogo/{email}/cupons` — perfil mescla os dois (`perfil_cliente_screen_novo._mesclarCupons`).

3. **Caminhos diferentes para o mesmo objetivo**
   - Login catálogo: `ClienteAuthService` (clientes) vs `ClienteWebService` (clientes_web) — rotas diferentes (`/loja` vs `/catalogo`).
   - Cupom roleta: `pos_pagamento_service` e `catalogo_venda_service` escrevem em `clientes_catalogo` e `estoque_clientes`; perfil lê de `clientes` + `clientes_catalogo`.

4. **Escrita nova em coleção potencialmente errada**
   - Cupom roleta: `clientes_catalogo` (por email) é coerente com `clientes` (que também usa email). Porém `estoque_clientes` (por telefone) pode criar "cliente fantasma" se email e telefone forem de perfis diferentes.

5. **Histórico preso em coleção legada**
   - Histórico de compras do admin está em `estoque_clientes` (Hive). O catálogo não usa esse histórico diretamente; Meus Pedidos vem de `clientes_portal`.

---

## 6. Plano de unificação em etapas

### Etapa A: Documentação e marcação de coleções legadas

- [ ] Documentar em `docs/MAPA_CLIENTES_E_PATHS.md` o status de cada coleção (principal, derivada, legada).
- [ ] Adicionar comentários em `FSPaths` e nos serviços: qual coleção usar para cada fluxo.
- [ ] Marcar `clientes_web` como legado (catálogo admin) — não usar para novas features do catálogo público.

### Etapa B: Parar novas escritas onde não deve mais escrever

- [ ] Garantir que novas features de catálogo público usem apenas `clientes` (não `clientes_web`).
- [ ] Não criar novos fluxos que escrevam em `clientes_catalogo` sem alinhar com `clientes` (ex.: sempre que houver cliente logado, preferir `clientes` para cupons).

### Etapa C: Adaptar leitores

- [ ] Revisar `perfil_cliente_screen_novo`: a mescla de cupons (clientes + clientes_catalogo) deve continuar até migração de dados.
- [ ] Garantir que `ClienteAuthService.getCuponsRoleta` e `marcarCupomRoletaComoUsado` tenham fallback se migrarmos cupons para `clientes`.

### Etapa D: Migração de dados (se necessário)

- [ ] **Opção 1 (conservadora):** Manter `clientes_catalogo` como cache de cupons por email. Documentar que o cliente do catálogo deve ter doc em `clientes` com mesmo email; cupons em `clientes_catalogo` são lidos em conjunto.
- [ ] **Opção 2 (unificação):** Migrar cupons de `clientes_catalogo/{email}/cupons` para `clientes/{clienteId}.cupons` (array) ou subcoleção `clientes/{clienteId}/cupons_roleta`. Exige script de migração e ajuste de escritores (pos_pagamento_service, catalogo_venda_service) e leitores (ClienteAuthService, perfil).
- [ ] **Recomendação:** Começar com Opção 1; avaliar Opção 2 em fase posterior se a fragmentação de cupons causar bugs ou complexidade.

---

## 7. Riscos de migração

| Risco | Mitigação |
|-------|-----------|
| Quebrar Meus Pedidos | Não alterar `clientes_portal` nem a lógica de `_resolvePortalTokenForPedido` |
| Perda de cupons roleta | Manter leitura dual (clientes + clientes_catalogo) até migração completa e validada |
| Cliente sem portalToken | `_ensureClienteComPortalToken` já cria cliente mínimo com portalToken; CF `resolveClientePortalTarget` também gera token se ausente |
| Duplicidade clienteId | `clienteIdPorEmail` (determinístico) reduz race em criações concorrentes |
| Admin vs catálogo | Manter `estoque_clientes` e `clientes` separados; não unificar sem plano específico |

---

## 8. Arquivos que terão de mudar numa fase de implementação

### Se manter modelo atual (apenas documentação e regras)

- `docs/MAPA_CLIENTES_E_PATHS.md` — atualizar status das coleções
- `lib/services/firestore_paths.dart` — comentários de uso
- Comentários em `ClienteWebService`, `ClienteAuthService` indicando qual fluxo usar

### Se migrar cupons de clientes_catalogo para clientes (Opção 2)

| Arquivo | Alteração |
|---------|-----------|
| `lib/services/cliente_auth_service.dart` | `getCuponsRoleta` ler de clientes; `marcarCupomRoletaComoUsado` escrever em clientes |
| `lib/services/pos_pagamento_service.dart` | Escrever cupom roleta em `clientes` (por email→clienteId) em vez de `clientes_catalogo` |
| `lib/services/catalogo_venda_service.dart` | Idem |
| `lib/screens/auth/perfil_cliente_screen_novo.dart` | Remover leitura de `clientes_catalogo`; usar apenas `clientes` |
| `lib/screens/public_catalog/widgets/carrinho_sheet_web.dart` | Revisar fallback de cupom roleta |
| Script de migração (novo) | Copiar cupons de clientes_catalogo para clientes |
| `firestore.rules` | Ajustar regras de `clientes_catalogo` se deprecar |

### Se marcar clientes_web como legado

- `lib/services/cliente_web_service.dart` — comentário de legado
- `lib/screens/catalago_screen.dart` — comentário
- Documentação

---

## 9. Conclusão

- **Fonte principal da verdade para o catálogo:** `clientes` (lojas/{lojaId}/clientes).
- **Espelho necessário:** `clientes_portal` (Meus Pedidos).
- **Cupons roleta:** Manter em `clientes_catalogo` por ora, com documentação clara; migrar para `clientes` em fase posterior se desejado.
- **clientes_web:** Legado (catálogo admin); não usar para catálogo público.
- **estoque_clientes:** Domínio admin; manter separado.

O plano é conservador: documentar, marcar legados e evitar novas fragmentações, sem refatoração pesada. A migração de cupons é opcional e pode ser feita em etapa posterior com script e testes dedicados.

---

## Implementação Etapas A e B (FASE 4 conservadora)

- **docs/MAPA_CLIENTES_E_PATHS.md** — Reescrito com arquitetura FASE 4 (fonte principal, derivadas, legadas)
- **firestore_paths.dart** — Comentários em cada coleção (FONTE PRINCIPAL, LEGADO, etc.)
- **ClienteAuthService** — Comentário FONTE PRINCIPAL
- **ClienteWebService** — Comentário LEGADO
- **ClientePortalRepository** — Comentário ESPELHO DERIVADO
- **ClientesFirestoreService** — Comentário DOMÍNIO ADMIN
- **pos_pagamento_service** — Comentários em estoque_clientes e clientes_catalogo
- **catalogo_venda_service** — Comentário USO ESPECÍFICO (clientes_catalogo)
- **pre_pedido_service** — Comentários em _salvarOuAtualizarCliente, _adicionarPedidoAoHistoricoCliente, clientes_portal
- **catalago_screen** — Comentário LEGADO
- **cliente_web.dart** — Comentário LEGADO

### FASE 4C (revisão leitores)
- **perfil_cliente_screen_novo.dart** — Doc classe + comentários em cada seção de dados
- **_buscarPedidosCompletos**, **_mesclarCupons** — Comentários FASE 4
- **carrinho_sheet_web.dart** — Comentário cupom roleta
- **cliente_auth_service** (getDadosCompletos, getPedidosDoCliente) — Comentários FONTE
