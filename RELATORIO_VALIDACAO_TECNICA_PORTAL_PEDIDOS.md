# Relatório de Validação Técnica — portalToken, Meus Pedidos e Pós-Pagamento Multi-Loja

**Escopo:** pre_pedido_service, public_catalog_screen, functions (index, posPagamento), fluxo MP catálogo, clientes_portal, external_reference, webhook  
**Data:** 21/03/2025

---

## 1. Itens validados com sucesso

| Item | Validação |
|------|-----------|
| **external_reference = pre_pedido ID** | App cria pre_pedido → obtém `docRef.id` → passa como `externalReference` em PIX e preference. `mpCatalogPayment` encaminha para o MP. Consistente. |
| **mpCatalogPayment** | Recebe `externalReference` do body e envia ao MP. Usado na web (CORS) e como fallback no APK. |
| **posPagamento multi-loja** | Usa `resolveLojaAndPayment` e `resolveLojaIdByOrderId`. Busca em pre_pedidos e pedidos. Suporta catálogo (pre_pedido) e legado (vendaId). |
| **order_loja_index** | `syncPedidoStatusPublico` grava `writeOrderLojaIndex` a cada create/update de pre_pedido. `resolveLojaIdByOrderId` lê o índice com fallback. |
| **syncPedidoStatusPublico** | Trigger em `pre_pedidos` grava em `pedido_status_publico` e `clientes_portal` (via `upsertClientePortalFromPedido`) e em `order_loja_index`. |
| **resolveClientePortalTarget** | Busca por clienteId, email em `clientes` ou usa `portalToken` em `pedido.cliente` (ex.: `portalTokenFromSession`). |
| **portalToken no pre_pedido** | `cliente.portalToken` é preenchido quando `portalTokenFromSession` existe. CF consegue resolver sem doc em `clientes`. |
| **Meus Pedidos** | `MeusPedidosRepository` → `ClientePortalRepository` → `clientes_portal/{portalToken}/pedidos`. Exige `portalToken` da sessão. |
| **createPreference (lojas/pedidos)** | `external_reference: orderId`, `metadata: { lojaId }`. Fluxo distinto do catálogo. |

---

## 2. Lacunas encontradas

| Lacuna | Detalhe |
|--------|---------|
| **mpCatalogPayment sem metadata.lojaId** | Não envia `metadata: { lojaId }` nem `notification_url`. Webhook depende de URL do MP e de `resolveLojaAndPayment` para lojaId. |
| **clientes_portal — regras bloqueiam app** | Regras: `allow create, update, delete: if belongsToStore(lojaId)`. Cliente do catálogo não é `belongsToStore`. `_saveClientePortalPedidoResumo` falha (permission denied). Gravação depende só da CF. |
| **mercadopagoWebhook não exportado** | `posPagamento.js` exporta `mercadopagoWebhook`, mas não está em `index.js`. Não está deployado. |
| **Webhook oficial = mpWebhook** | Só `mpWebhook` está exportado. `mercadopagoWebhook` (campanhas, números, e-mail) não está em uso. |
| **Meus Pedidos sem portalToken** | Se `portalToken` for vazio, `getPedidosDoCliente` retorna `[]`. Cliente novo sem login/sessão não terá pedidos visíveis até CF gravar e o cliente ter portalToken. |
| **Resolução de portalToken para cliente novo** | `_resolvePortalTokenForPedido` cria cliente em `clientes` quando necessário. CF `resolveClientePortalTarget` não cria cliente; se não achar em `clientes` nem `portalToken` em `pedido.cliente`, retorna `null` e não grava. |

---

## 3. Riscos por severidade

### Alta
| Risco | Descrição |
|-------|-----------|
| **clientes_portal depende só da CF** | App não consegue gravar (belongsToStore). Se `syncPedidoStatusPublico` falhar ou atrasar, "Meus Pedidos" fica vazio. Sem redundância da escrita pelo app. |
| **Cliente sem doc em clientes e sem portalToken no pedido** | Checkout sem login, com e-mail novo. `_salvarOuAtualizarCliente` cria em `clientes`, mas pode não ter portalToken antes da CF. Se `resolveClientePortalTarget` não encontrar cliente (por atraso) e `pedido.cliente.portalToken` estiver vazio, `clientes_portal` não é preenchido. |

### Média
| Risco | Descrição |
|-------|-----------|
| **Webhook MP não especificado no mpCatalogPayment** | `notification_url` não é enviada. MP usa a configurada no painel. Se estiver errada ou antiga, o webhook pode não chegar ou ir para outro endpoint. |
| **Fragmentação clientes vs clientes_portal** | `clientes`, `clientes_web`, `clientes_portal`, `clientes_catalogo` com propósitos diferentes. Risco de pedido em pre_pedidos sem espelho em clientes_portal se a resolução de portalToken falhar. |

### Baixa
| Risco | Descrição |
|-------|-----------|
| **Campanhas/números não no webhook ativo** | `mpWebhook` não registra participação em campanhas nem envia números. Só `mercadopagoWebhook` faz isso, e não está deployado. Pagamentos do catálogo não geram número da sorte via webhook. |
| **posPagamento pronto mas não usado** | `posPagamento.js` trata pre_pedidos, multi-loja e campanhas, mas não é acionado porque o webhook em uso é o mpWebhook. |

---

## 4. Recomendações objetivas

1. **Webhook MP**
   - Confirmar no painel do MP que a URL do webhook aponta para `mpWebhook`.
   - Decidir: exportar `mercadopagoWebhook` para campanhas/números ou adicionar essa lógica no `mpWebhookHandler`.

2. **clientes_portal**
   - Avaliar regra para permitir escrita pelo app quando `request.resource.data.portalToken` coincidir com o token da sessão e os dados forem limitados (evitar abusos), mantendo a CF como fonte principal.
   - Ou aceitar a dependência da CF e garantir monitoramento de falhas em `syncPedidoStatusPublico`.

3. **mpCatalogPayment**
   - Incluir `metadata: { lojaId }` na preferência/PIX para facilitar a resolução da loja no webhook.

4. **Pedidos sem portalToken**
   - Garantir que `_salvarOuAtualizarCliente` defina `portalToken` em `clientes` antes da CF rodar, e que o pre_pedido seja criado com `cliente.portalToken` quando houver sessão ou cliente criado.

5. **Order_loja_index**
   - Executar backfill se houver pedidos antigos: `npm run backfill:order-loja-index` (ou equivalente).

---

## 5. Status final

### **Quase pronto para produção**

**Justificativa:**
- Fluxo principal funciona: external_reference correto, multi-loja no posPagamento, order_loja_index, syncPedidoStatusPublico.
- Lacuna crítica: gravação em clientes_portal depende apenas da CF; app não tem permissão.
- Risco médio: URL do webhook e metadata lojaId não estão explícitos no mpCatalogPayment.
- Riscos de fragmentação e de campanhas via webhook continuam, mas com impacto limitado.

**Antes de homologação/produção:**
1. Validar em ambiente de homologação: checkout → pagamento MP → webhook processando → pedido em "Meus Pedidos".
2. Garantir que clientes novos recebam portalToken e que o pre_pedido inclua `cliente.portalToken` sempre que possível.
3. Verificar no painel do MP a URL e os eventos do webhook.
4. Rodar backfill de order_loja_index se houver pedidos antigos.

---

*Relatório gerado por auditoria do código.*
