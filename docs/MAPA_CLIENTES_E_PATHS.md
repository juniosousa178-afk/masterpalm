# Mapa de Clientes e Paths Firestore – MasterPalm

Documentação interna (Etapa 2 do plano seguro). Não altera runtime.

---

## 1. Coleções/estruturas de clientes

### estoque_clientes
- **Path:** `lojas/{lojaId}/estoque_clientes`
- **Finalidade:** Clientes do **admin** (tela Clientes, Nova Venda, sync). Fonte autoritativa para sync Firestore ↔ Hive.
- **Escrevem:** ClientesFirestoreService, FullSyncService (não escreve, só lê), PrePedidoService (_saveClienteAuto, _adicionarPedidoAoHistoricoCliente), PosPagamentoService (cupom roleta por telefone).
- **Leem:** ClientesFirestoreService (sync, stream, get, delete, search), FullSyncService, PrePedidoService, LimitsGuard (contagem).
- **Sincroniza com Hive:** Sim.
- **Box Hive:** `clientes_{lojaId}` (HiveBoxNames.clientes(lojaId)).
- **Risco:** Baixo (bem definido como “admin + sync”).

### clientes
- **Path:** `lojas/{lojaId}/clientes`
- **Finalidade:** **Autenticação e perfil do catálogo** (login/cadastro por email+senha), **carrinho abandonado**, **pré-pedido** (portalToken, endereço, indicação). Documento por clienteId (gerado) ou UID (em telas legadas com Firebase Auth).
- **Escrevem:** ClienteAuthService (cadastro, login, atualização, Google), PrePedidoService (portalToken, endereço, indicação), CarrinhoAbandonadoService (lembrete enviado), auth/cadastro_screen (Firebase Auth UID), SyncFirestoreScript (script legado Hive→Firestore).
- **Leem:** ClienteAuthService (login, cupons, perfil), PrePedidoService (_resolvePortalTokenForPedido, endereço, indicação), CarrinhoAbandonadoService (listar abandonados), auth/perfil_cliente_screen (por user.uid – legado), FirestoreCleanupScript, SyncFirestoreScript (stats), MigrarParaEstoque (migração clientes→estoque_clientes).
- **Sincroniza com Hive:** Não (admin usa estoque_clientes + Hive).
- **Box Hive:** Nenhuma (clientes do catálogo não usam box de clientes do admin).
- **Risco:** Médio (mesmo nome “clientes” para auth catálogo, carrinho e pré-pedido; scripts legados usam para sync).

### clientes_catalogo
- **Path:** `lojas/{lojaId}/clientes_catalogo/{email}` e subcoleção `cupons`
- **Finalidade:** Perfil do cliente no **catálogo por email**; cupons da roleta e “Meus Cupons”.
- **Escrevem:** ClienteAuthService (cupons roleta: usado/dataUso), PosPagamentoService (cupom roleta após pagamento), CatalogoVendaService (cupom roleta após confirmação de compra).
- **Leem:** ClienteAuthService (buscar cupons roleta), perfil_cliente_screen_novo (comentários), carrinho_sheet_web (comentário sobre fallback cupom).
- **Sincroniza com Hive:** Não.
- **Box Hive:** Nenhuma.
- **Risco:** Baixo (bem delimitado a cupons por email no catálogo).

### clientes_web
- **Path:** `lojas/{lojaId}/clientes_web/{clienteId}`
- **Finalidade:** Autenticação do **catálogo web** (login/cadastro por email, sem senha; modelo ClienteWeb).
- **Escrevem:** ClienteWebService (loginOuCadastro, update, logout).
- **Leem:** ClienteWebService (getClienteAutenticado, pedidos, etc.).
- **Sincroniza com Hive:** Não.
- **Box Hive:** Nenhuma.
- **Risco:** Baixo (isolado em ClienteWebService).

### clientes_portal
- **Path:** `lojas/{lojaId}/clientes_portal/{portalToken}` e subcoleção `pedidos`
- **Finalidade:** **Portal do cliente** (Meus Pedidos): perfil por portalToken, resumo de pedidos.
- **Escrevem:** ClientePortalRepository (savePedidoResumo, deletePedidoResumo); PrePedidoService (_saveClientePortalPedidoResumo).
- **Leem:** ClientePortalRepository (getPerfil, getUltimoEndereco, getPedidosDoCliente), MeusPedidosRepository (via ClientePortalRepository).
- **Sincroniza com Hive:** Não.
- **Box Hive:** Nenhuma.
- **Risco:** Baixo (uso concentrado em repositórios).

### cupons_clientes (indicação)
- **Path:** `lojas/{lojaId}/cupons_clientes` (coleção de cupons de indicação).
- **Finalidade:** Programa de indicação (primeira compra do indicado; cupom indicador).
- **Leem:** PrePedidoService (verificar se destinatário já recebeu cupom daquele indicador).
- **Escrevem:** CuponsService (criar cupons indicação) – chamado a partir de PrePedidoService.
- **Sincroniza com Hive:** Não. **Box Hive:** Nenhuma. **Risco:** Baixo.

### Box Hive legada "clientes" (sem lojaId)
- **Nome:** `'clientes'` (string literal).
- **Finalidade:** Legado; importação Excel e bootstrap antigo; **não multi-loja**.
- **Arquivos:** main.dart (openTyped<Cliente>('clientes')), excel_import_service.dart, importar_clientes.dart.
- **Risco:** Médio (confusão com coleção Firestore “clientes”; uso residual).

---

## 2. Paths Firestore por domínio

### Produtos
- `lojas/{lojaId}/estoque_produtos` – estoque oficial; sync Hive; baixa; listeners.
- `lojas/{lojaId}/produtos` – publicação/catálogo; draft→produtos; marketplace; alguns reads.
- `lojas/{lojaId}/draft_produtos` – rascunhos; cadastro_produto_screen; catalog_publish_service.

### Clientes
- Ver seção 1 (estoque_clientes, clientes, clientes_catalogo, clientes_web, clientes_portal).

### Vendas
- `lojas/{lojaId}/estoque_vendas` – vendas oficiais; sync Hive; importar; admin painel; LimitsGuard.
- `lojas/{lojaId}/vendas` – citado em sync_firestore_script, limpar_firestore, migrar_para_estoque (legado/migração).

### Pedidos / pré-pedidos
- Centralizados em **PedidoCollectionResolver** / **FSPaths**: pedidos, pre_pedidos, pedido_status_publico, pedidos_pendentes, pedidos_temp, pedido_temp, pedidos_catalogo, temp_orders, root.

### Catálogo
- Config e produtos: lojas/{lojaId}/config, estoque_produtos, produtos; clientes_catalogo para cupons.

### Autenticação / sessão
- Admin: `users/{uid}`, `usuarios/{email}` (store_id, etc.).
- Cliente catálogo: `lojas/{lojaId}/clientes` (ClienteAuthService); `clientes_web` (ClienteWebService).

---

## 3. Centralização de paths

- **Centralizados:** Pedidos (PedidoCollectionResolver, FSPaths); nomes de boxes Hive (HiveBoxNames).
- **Parcialmente centralizados:** FSPaths tem lojaDoc, produtosCol (produtos, não estoque_produtos), categorias, subcategorias e pedidos; **não** tem estoque_produtos, estoque_clientes, estoque_vendas, clientes, clientes_catalogo, clientes_web, clientes_portal.
- **Literais espalhados:** estoque_clientes, clientes, clientes_catalogo, clientes_web, clientes_portal, estoque_produtos, estoque_vendas, produtos, draft_produtos em vários serviços e telas.

---

## 4. Riscos de confusão

- Usar “clientes” (coleção) para auth catálogo + carrinho + pré-pedido + script legado pode levar a achar que é a mesma base do admin (que é estoque_clientes + Hive).
- MigrarParaEstoque documenta clientes→estoque_clientes; em produção o admin já usa estoque_clientes; quem ainda escreve em “clientes” é auth/catálogo e scripts.
- Box Hive `'clientes'` sem sufixo é legado; novo fluxo é clientes_{lojaId}.

---

## 5. Recomendação futura (não implementar agora)

1. Introduzir constantes ou FSPaths para: estoque_clientes, clientes, clientes_catalogo, clientes_web, clientes_portal, estoque_produtos, estoque_vendas e substituir literais gradualmente.
2. Documentar em código (ou este doc) qual coleção usar para cada fluxo (admin vs catálogo vs portal vs web).
3. Deprecar box `'clientes'` sem lojaId e migrar usos para HiveBoxNames.clientes(lojaId) quando possível.
4. Manter clientes (auth catálogo) e estoque_clientes (admin/sync) separados; não unificar sem plano de migração e regras.
