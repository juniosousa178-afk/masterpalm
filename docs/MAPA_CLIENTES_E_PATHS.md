# Mapa de Clientes e Paths Firestore – MasterPalm

Documentação interna. Arquitetura FASE 4 (Unificação do Modelo de Cliente do Catálogo).

**Documentos relacionados:**
- **Status final (fechamento):** [STATUS_FINAL_ARQUITETURA_CLIENTE_CATALOGO.md](STATUS_FINAL_ARQUITETURA_CLIENTE_CATALOGO.md) — Regras, riscos, o que não alterar
- **Diagnóstico FASE 4:** `FASE4_UNIFICACAO_MODELO_CLIENTE_CATALOGO.md`

---

## Arquitetura FASE 4 — Papéis das coleções

| Coleção | Papel | Uso |
|---------|-------|-----|
| **clientes** | **FONTE PRINCIPAL** | Identidade do cliente do catálogo público (login, perfil, portalToken) |
| **clientes_portal** | Espelho derivado | Vista "Meus Pedidos" por portalToken — não é fonte de identidade |
| **clientes_catalogo** | Uso específico | Cupons da roleta por email — cache complementar |
| **clientes_web** | Legado | Catálogo admin (rota /catalogo) — não usar para novas features do catálogo público |
| **estoque_clientes** | Domínio admin | Sync Hive, histórico admin — não é perfil do catálogo |

**Regra:** Novas features do catálogo público devem usar `clientes` como fonte principal. Não escrever identidade em `clientes_web`. Não tratar `estoque_clientes` como perfil do catálogo.

---

## 1. Coleções/estruturas de clientes

### clientes — FONTE PRINCIPAL (catálogo público)

- **Path:** `lojas/{lojaId}/clientes`
- **Finalidade:** **Autenticação e perfil do catálogo público** (login/cadastro por email+senha), carrinho, pré-pedido (portalToken, endereço). Documento por clienteId.
- **Escrevem:** ClienteAuthService (cadastro, login, atualização, Google), PrePedidoService (_ensureClienteComPortalToken, endereço), CF resolveClientePortalTarget (portalToken).
- **Leem:** ClienteAuthService (login, cupons, perfil), PrePedidoService (_resolvePortalTokenForPedido), CF getClienteCatalog, CF solicitarRedefinicaoSenhaCatalogo.
- **Fluxos:** PublicCatalogScreen (/loja), pré-pedido, checkout, Meus Pedidos (via portalToken).
- **Chave:** clienteId (timestamp ou ec_xxx determinístico por loja+email).
- **Sincroniza com Hive:** Não.

---

### clientes_portal — ESPELHO DERIVADO

- **Path:** `lojas/{lojaId}/clientes_portal/{portalToken}` e subcoleção `pedidos`
- **Finalidade:** Vista "Meus Pedidos" por portalToken. **Não é fonte de identidade.**
- **Escrevem:** PrePedidoService (_saveClientePortalPedidoResumo), ClientePortalRepository, CF syncPedidoStatusPublico (upsertClientePortalFromPedido), backfill_fontes_cliente_pedidos.js.
- **Leem:** ClientePortalRepository, MeusPedidosRepository.
- **Fluxos:** Meus Pedidos (portal).
- **Chave:** portalToken (aleatório).
- **Sincroniza com Hive:** Não.

---

### clientes_catalogo — USO ESPECÍFICO (cupons/roleta)

- **Path:** `lojas/{lojaId}/clientes_catalogo/{email}` e subcoleção `cupons/{codigo}`
- **Finalidade:** Cupons da roleta da sorte por email. Cache complementar ao doc `clientes`.
- **Escrevem:** PosPagamentoService (cupom roleta após pagamento webhook), CatalogoVendaService (cupom após venda local), ClienteAuthService (marcarCupomRoletaComoUsado).
- **Leem:** ClienteAuthService (getCuponsRoleta), perfil_cliente_screen_novo (mescla com cupons de clientes).
- **Fluxos:** Roleta, "Meus Cupons" (mesclado com clientes.cupons).
- **Chave:** email normalizado.
- **Sincroniza com Hive:** Não.

---

### clientes_web — LEGADO (catálogo admin)

- **Path:** `lojas/{lojaId}/clientes_web/{clienteId}`
- **Finalidade:** Autenticação do catálogo **interno/admin** (rota /catalogo). Login/cadastro por email sem senha. **Não usar para novas features do catálogo público.**
- **Escrevem:** ClienteWebService (loginOuCadastro, update).
- **Leem:** ClienteWebService, CatalogoScreen, ClienteLoginScreen, ClientePerfilScreen.
- **Fluxos:** CatalogoScreen (rota /catalogo) — app admin.
- **Chave:** doc id (Firestore add).
- **Sincroniza com Hive:** Não.

---

### estoque_clientes — DOMÍNIO ADMIN (sync/histórico)

- **Path:** `lojas/{lojaId}/estoque_clientes`
- **Finalidade:** Clientes do **admin** (tela Clientes, Nova Venda, sync). Histórico de compras. **Não é perfil do catálogo público.**
- **Escrevem:** ClientesFirestoreService (admin CRUD), PrePedidoService (_salvarOuAtualizarCliente, _adicionarPedidoAoHistoricoCliente — side-effect do pré-pedido para admin), PosPagamentoService (cupom roleta por telefone — quando cliente já existe em estoque).
- **Leem:** ClientesFirestoreService, FullSyncService, PrePedidoService (LimitsGuard).
- **Fluxos:** Admin, sync Firestore ↔ Hive, historico_clientes_screen.
- **Chave:** telefone (dígitos).
- **Box Hive:** `clientes_{lojaId}` (HiveBoxNames.clientes(lojaId)).
- **Sincroniza com Hive:** Sim.

---

### cupons_clientes (indicação)

- **Path:** `lojas/{lojaId}/cupons_clientes`
- **Finalidade:** Programa de indicação (primeira compra do indicado; cupom indicador).
- **Escrevem:** CuponsService (via PrePedidoService).
- **Leem:** PrePedidoService.
- **Sincroniza com Hive:** Não.

---

### Box Hive legada "clientes" (sem lojaId)

- **Nome:** `'clientes'` (string literal).
- **Finalidade:** Legado; importação Excel e bootstrap antigo; **não multi-loja**.
- **Arquivos:** main.dart, excel_import_service.dart, importar_clientes.dart.

---

## 2. Fluxos por coleção

| Fluxo | Coleção principal | Outras |
|-------|-------------------|--------|
| Catálogo público (PublicCatalogScreen, /loja) | clientes | clientes_portal, clientes_catalogo |
| Pré-pedido / checkout | clientes, clientes_portal | estoque_clientes (historico admin) |
| Meus Pedidos | clientes_portal | — |
| Roleta / Meus Cupons | clientes_catalogo + clientes | — |
| Catálogo admin (CatalogoScreen, /catalogo) | clientes_web | — |
| Admin (Clientes, Nova Venda) | estoque_clientes | — |

---

## 3. Paths Firestore por domínio

### Produtos
- `lojas/{lojaId}/estoque_produtos` – estoque oficial; sync Hive.
- `lojas/{lojaId}/produtos` – publicação/catálogo.
- `lojas/{lojaId}/draft_produtos` – rascunhos.

### Clientes
- Ver seção 1.

### Vendas
- `lojas/{lojaId}/estoque_vendas` – vendas oficiais; sync Hive.
- `lojas/{lojaId}/vendas` – legado/migração.

### Pedidos
- Centralizados em PedidoCollectionResolver / FSPaths: pre_pedidos, pedido_status_publico, etc.

### Autenticação
- Admin: `users/{uid}`, `usuarios/{email}`.
- Cliente catálogo: `lojas/{lojaId}/clientes` (ClienteAuthService). Catálogo admin legado: `clientes_web` (ClienteWebService).

---

## 4. Centralização de paths

- **FSPaths:** clientesCol, clientesCatalogoCol, clientesWebCol, clientesPortalCol, estoqueClientesCol.
- **Literais:** Alguns serviços ainda usam strings como `'estoque_clientes'`; preferir FSPaths quando possível.

---

## 5. Riscos e regras

- **Não** usar `clientes_web` para novas features do catálogo público.
- **Não** tratar `estoque_clientes` como perfil do catálogo.
- **Sempre** usar `clientes` como fonte de identidade no fluxo catálogo público.
- `clientes_portal` é espelho — mantido em sincronia por PrePedidoService e CF.
