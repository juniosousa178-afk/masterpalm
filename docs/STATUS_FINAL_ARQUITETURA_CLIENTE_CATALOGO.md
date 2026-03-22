# Status Final — Arquitetura do Cliente do Catálogo

**Documento de fechamento técnico.** Referência para evitar regressões.

**Data:** Março 2026  
**Escopo:** Fluxo cliente do catálogo público — cadastro, checkout, pre_pedido, clientes_portal, webhook, Meus Pedidos.

**Documentos relacionados:**
- `docs/MAPA_CLIENTES_E_PATHS.md` — Mapa detalhado de coleções e paths
- `FASE4_UNIFICACAO_MODELO_CLIENTE_CATALOGO.md` — Diagnóstico e plano FASE 4

---

## 1. Resumo executivo

A auditoria e estabilização do fluxo de cliente do catálogo foram concluídas. O fluxo end-to-end está funcional: cadastro → checkout → pre_pedido → clientes_portal → webhook → status → Meus Pedidos.

**Arquitetura consolidada:**
- **clientes** = fonte principal da identidade do catálogo público
- **clientes_portal** = espelho derivado para "Meus Pedidos"
- **clientes_catalogo** = uso específico (cupons roleta)
- **clientes_web** = legado (catálogo admin)
- **estoque_clientes** = domínio admin (sync, histórico)

Correções aplicadas, documentação atualizada e regras definidas. O que permanece como legado ou risco aceitável está explicitado neste documento.

---

## 2. Arquitetura final aprovada

| Coleção | Papel | Chave | Uso |
|---------|-------|-------|-----|
| **clientes** | **FONTE PRINCIPAL** | clienteId (ec_xxx ou timestamp) | Identidade, login, perfil, portalToken |
| **clientes_portal** | Espelho derivado | portalToken | Meus Pedidos |
| **clientes_catalogo** | Uso específico | email | Cupons da roleta |
| **clientes_web** | Legado | doc id | Catálogo admin (rota /catalogo) |
| **estoque_clientes** | Domínio admin | telefone | Sync Hive, histórico admin |

---

## 3. Fonte principal da verdade

**Para o fluxo catálogo público (PublicCatalogScreen, /loja):**

```
lojas/{lojaId}/clientes
```

- **Serviço:** ClienteAuthService
- **Leitura:** CF getClienteCatalog (validação email, retorno seguro)
- **Chave lógica:** clienteId; login por email; Meus Pedidos via portalToken

---

## 4. Coleções derivadas, específicas e legadas

### Derivada
- **clientes_portal** — Espelho para Meus Pedidos. Mantido em sincronia por PrePedidoService e CF syncPedidoStatusPublico. Não é fonte de identidade.

### Uso específico
- **clientes_catalogo** — Cupons da roleta por email. Cache complementar. Perfil mescla cupons de clientes + clientes_catalogo.

### Legadas
- **clientes_web** — Catálogo interno/admin (rota /catalogo). ClienteWebService. Não usar para novas features do catálogo público.
- **clientes.pedidos** — Array de pedidos legados (MP/antigo) no doc clientes. Usado como fallback na mescla de Meus Pedidos.

### Domínio separado
- **estoque_clientes** — Admin, sync Hive, histórico. Não é perfil do catálogo. PrePedidoService e PosPagamentoService escrevem como side-effect para historico admin.

---

## 5. Fluxo final do cliente

```
Cadastro/Login (ClienteAuthService)
        │
        ▼
   clientes (identidade, portalToken)
        │
        ▼
Checkout (carrinho, endereço)
        │
        ▼
PrePedidoService.criarPrePedido()
        │
        ├─► pre_pedidos (doc criado)
        ├─► clientes (endereço atualizado)
        ├─► clientes_portal (savePedidoResumo — Meus Pedidos)
        └─► estoque_clientes (historico admin, side-effect)
        │
        ▼
Pagamento (PIX/Cartão) — external_reference = pre_pedido.id
        │
        ▼
Webhook MP → mpWebhook → processMpWebhook
        │
        ├─► pre_pedidos (status atualizado)
        ├─► pedido_status_publico
        ├─► clientes_portal (upsertClientePortalFromPedido — CF)
        └─► Cupom roleta → clientes_catalogo + estoque_clientes (quando aplicável)
        │
        ▼
Meus Pedidos (MeusPedidosRepository → clientes_portal)
Perfil (getDadosCompletos → clientes; cupons → clientes + clientes_catalogo)
```

---

## 6. O que foi corrigido nas fases anteriores

### Auditoria campanhas/sorteios/roleta
- Duplicidade removida em Nova Venda (CampaignEngine único)
- Campo ativo/ativa corrigido
- Config roleta unificada em `config/roleta_sorte`
- cancelarParticipacao com pedidoId
- Schema canônico de participantes

### Validação técnica portal/Meus Pedidos
- external_reference = pre_pedido ID validado
- mpCatalogPayment, posPagamento multi-loja
- syncPedidoStatusPublico → clientes_portal
- resolveClientePortalTarget (clientes)
- order_loja_index

### Hardening / Blindagem
- metadata.lojaId no pagamento (mpCatalogPayment)
- _ensureClienteComPortalToken contra duplicidade (clienteIdPorEmail determinístico)
- OrderReviewScreen guarda lojaId
- EstoqueTransactionService log no catch

### FASE 4 conservadora
- docs/MAPA_CLIENTES_E_PATHS.md reescrito
- Comentários FONTE PRINCIPAL, LEGADO, ESPELHO em firestore_paths, serviços, repositórios

### FASE 4C — Revisão leitores
- perfil_cliente_screen_novo documentado (origem de cada dado)
- getDadosCompletos, getPedidosDoCliente, _mesclarCupons, _buscarPedidosCompletos com comentários FASE 4

---

## 7. O que ficou como compatibilidade/legado

| Item | Tratamento |
|------|------------|
| clientes_web | Legado; CatalogoScreen (rota /catalogo) continua funcionando |
| clientes.pedidos | Fallback na mescla de Meus Pedidos; pedidos legados MP |
| Cupons em clientes + clientes_catalogo | Mescla mantida; sem migração |
| posPagamento.js (CF) | Marcado legado; mpWebhook é o ativo |
| Escrita em estoque_clientes (pre_pedido) | Side-effect para historico admin; mantido |
| Cupom roleta em estoque_clientes (por telefone) | Mantido quando cliente existe; dual com clientes_catalogo |

---

## 8. O que não deve ser alterado sem nova auditoria

- **clientes_portal** — Não alterar estrutura nem lógica de _resolvePortalTokenForPedido
- **vínculo clienteId ↔ portalToken** — Resolução em PrePedidoService e CF resolveClientePortalTarget
- **CF syncPedidoStatusPublico** — Grava em clientes_portal; sem ela Meus Pedidos fica vazio
- **getClienteCatalog** — Única leitura segura de clientes para o app; valida email
- **clienteIdPorEmail** — Usado em _ensureClienteComPortalToken para evitar duplicidade
- **external_reference** — Deve ser pre_pedido doc id em todo o fluxo de pagamento

---

## 9. Regras para novas features

1. **Identidade do catálogo público** — Usar `clientes` como fonte principal. ClienteAuthService.
2. **Meus Pedidos** — Continuar usando `clientes_portal`. Não criar nova fonte para pedidos do catálogo.
3. **clientes_web** — Não usar para novas features do catálogo público. Destinado ao catálogo admin (rota /catalogo).
4. **estoque_clientes** — Não tratar como perfil principal do cliente do catálogo. Domínio admin.
5. **Cupons/roleta** — Manter uso específico em `clientes_catalogo` até nova decisão. Perfil mescla clientes + clientes_catalogo.
6. **Novas escritas** — Não escrever identidade em clientes_web. Não criar fluxos que dependam de estoque_clientes para perfil do catálogo.

---

## 10. Riscos remanescentes aceitáveis

| Risco | Severidade | Aceitação |
|-------|------------|-----------|
| clientes_portal depende da CF | Média | App não tem permissão para gravar; CF é a responsável. Monitorar falhas. |
| Cliente novo sem portalToken no pedido | Baixa | _ensureClienteComPortalToken cria cliente com token; CF usa portalToken do pedido quando app passou. |
| Cupons em duas coleções | Baixa | Documentado; mescla no perfil; migração opcional futura. |
| clientes.pedidos legado | Baixa | Fallback na mescla; não bloqueia. |
| posPagamento.js não no webhook ativo | Baixa | mpWebhook é o ativo; campanhas/números via webhook em backlog. |

---

## 11. Próximos passos opcionais futuros

1. **Migração cupons** — Unificar cupons de clientes_catalogo em clientes (Etapa D FASE 4).
2. **metadata.lojaId no mpCatalogPayment** — Facilitar resolução da loja no webhook.
3. **Regra Firestore clientes_portal** — Avaliar escrita pelo app (limitada) como redundância; hoje só CF.
4. **Deprecar clientes.pedidos** — Se todos os pedidos passarem a existir em clientes_portal.
5. **Alinhar posPagamento.js** — Se webhook de campanhas/números for priorizado.

---

*Documento consolidado a partir do estado real implementado. Não refatorar código sem nova auditoria.*
