# VALIDAÇÃO TÉCNICA CIRÚRGICA – FASES 1–3

**Data:** 21/03/2025  
**Escopo:** Correções implementadas em pre_pedido_service, public_catalog_screen, functions (index.js, posPagamento.js), mpWebhookHandler

---

## 1. RESUMO EXECUTIVO DA VALIDAÇÃO

| Item | Status | Observação |
|------|--------|------------|
| Webhook em produção | OK | `mpWebhook` é o ativo; `posPagamento.js` **NÃO** está no caminho real |
| external_reference | OK | App envia `pedidoId` (pre_pedido doc id); consistente |
| portalToken/clientes_portal | OK | App grava na criação; CF complementa; fallbacks robustos |
| order_loja_index | OK | CF grava em syncPedidoStatusPublico; fallback varredura existe |
| Dupla escrita app+CF | RISCO BAIXO | Mesmo path e schema; CF pode sobrescrever; redundância útil |
| Duplicidade cliente | RISCO MÉDIO | Race em `_ensureClienteComPortalToken` pode gerar 2 docs por email |
| mpCatalogPayment metadata | FALTA | Não envia `metadata.lojaId` ao MP; webhook depende de order_loja_index |

**Conclusão:** O fluxo está funcional. As correções em `posPagamento.js` **não impactam produção** porque esse webhook não é exportado. O webhook real (`mpWebhook` → `mpWebhookHandler.js`) já estava correto para pre_pedidos e multi-tenant. A principal melhoria veio da FASE 1 (portalToken, clientes_portal).

---

## 2. WEBHOOK REAL EM PRODUÇÃO

### Função que recebe o webhook

| Função | Arquivo | Exportada em index.js? | URL em produção |
|--------|---------|------------------------|-----------------|
| **mpWebhook** | `functions/index.js` L1381 | ✅ SIM | `.../mpWebhook` |
| processMpWebhook | `functions/src/mpWebhookHandler.js` | (chamada por mpWebhook) | — |
| mercadopagoWebhook | `functions/src/posPagamento.js` | ❌ NÃO | N/A |
| posPagamento | (módulo) | ❌ NÃO | N/A |

**Evidência (index.js L1381–1398):**
```javascript
export const mpWebhook = onRequest(
  { cors: true, secrets: [S_MP_ACCESS_TOKEN], ... },
  corsWrap(async (req, res) => {
    const paymentId = body?.data?.id || query["data.id"] || ...;
    await processMpWebhook(paymentId, globalToken);
    return res.status(200).send("OK");
  })
);
```

Não há `export { mercadopagoWebhook } from "./src/posPagamento.js"` nem referência a posPagamento nos exports de index.js.

**Conclusão:** As alterações em `posPagamento.js` **não entram no fluxo de produção**. O webhook que processa pagamentos é `mpWebhook` → `processMpWebhook` em `mpWebhookHandler.js`.

---

## 3. VALIDAÇÃO DO EXTERNAL_REFERENCE / ORDER ID

### Onde é definido

| Etapa | Arquivo | Linha | Valor enviado |
|-------|---------|-------|----------------|
| Criação pre_pedido | `public_catalog_screen.dart` | 2067–2084 | `prePedido?['id']` = docRef.id |
| PIX (web) | `public_catalog_screen.dart` | 2149 | `'externalReference': pedidoId` |
| Preference (web) | `public_catalog_screen.dart` | 2155 | `'externalReference': pedidoId` |
| PIX (APK) | `public_catalog_screen.dart` | 2243 | `externalReference: pedidoId` |
| Preference (APK) | `public_catalog_screen.dart` | 2254, 2282, 2288 | `externalReference: pedidoId` |
| mpCatalogPayment (CF) | `functions/index.js` | 1274, 1331 | `external_reference: String(externalReference)` |

### Fluxo

1. App chama `PrePedidoService.criarPrePedido()`.
2. Firestore retorna `docRef.id` (ID do doc em `pre_pedidos`).
3. App usa `pedidoId = prePedido?['id']`.
4. App envia `externalReference: pedidoId` para `mpCatalogPayment` (web) ou MercadoPagoService (APK).
5. mpCatalogPayment repassa `external_reference` ao MP (PIX e preference).
6. Webhook recebe `payment.external_reference` = pre_pedido doc id.
7. mpWebhookHandler usa `orderId = payment.external_reference` e busca em `pre_pedidos`.

**Conclusão:** O `external_reference` corresponde corretamente ao ID do pre_pedido em todos os fluxos.

---

## 4. VALIDAÇÃO DO PORTALTOKEN E CLIENTES_PORTAL

### Onde cliente.portalToken é gravado

| Local | Condição | Arquivo/Linha |
|-------|----------|----------------|
| pre_pedido.cliente | `portalTokenFromSession != null` | `pre_pedido_service.dart` L328–329 |
| Chamadas criarPrePedido | Sempre que há cliente logado | `public_catalog_screen.dart` L2083, L1874 |

Fluxo WhatsApp: `portalTokenFromSession: clienteLogado?['portalToken']`  
Fluxo MP: `portalTokenFromSession: cliente?['portalToken']`

### Escritas em clientes_portal

| Escritor | Path | Momento | merge |
|----------|------|---------|-------|
| App `_saveClientePortalPedidoResumo` | `lojas/{lojaId}/clientes_portal/{portalToken}/pedidos/{pedidoId}` | Logo após criar pre_pedido (unawaited) | false |
| CF `upsertClientePortalFromPedido` | Mesmo path | Em `syncPedidoStatusPublico` (onDocumentWritten em pre_pedidos) | false |

### Ordem e race

1. App grava pre_pedido.
2. App dispara `_saveClientePortalPedidoResumo` (não bloqueia).
3. Firestore dispara `syncPedidoStatusPublico`.
4. Quem terminar por último sobrescreve; ambos usam schema compatível.

### Schemas

- **App:** `pedidoId`, `lojaId`, `status`, `dataCriacao`, `dataAtualizacao`, `total`, `itensResumo`, `codigoRastreio`, `freteNome`
- **CF:** `buildPedidoStatusPublico` → mesmos campos.

### Cenários em que o pedido pode não aparecer em "Meus Pedidos"

1. **Email vazio no pedido:** `_resolvePortalTokenForPedido` retorna null; sem gravação.
2. **Cliente não logado e sem cliente em `clientes`:** Depende de `_ensureClienteComPortalToken`; em falha ou race, pode não gravar.
3. **Ambos (app e CF) falharem:** Improvável; redundância reduz risco.

---

## 5. VALIDAÇÃO DO ORDER_LOJA_INDEX

### Onde é escrito

| Local | Momento | Arquivo/Linha |
|-------|---------|---------------|
| syncPedidoStatusPublico | OnWrite em pre_pedidos | `functions/index.js` L1869 |
| resolveLojaIdByOrderId | Ao encontrar pedido na varredura | `orderLojaIndex.js` L56, L67 |

### Onde é lido

| Local | Momento | Arquivo |
|-------|---------|---------|
| findLojaIdByOrderId | Quando lojaId não vem do payment | `mpWebhookHandler.js` L114–116 |
| resolveLojaIdByOrderId | Primeiro tenta índice; depois varre | `orderLojaIndex.js` L42–73 |

### Fluxo de resolução de lojaId no webhook

1. `resolveLojaAndPayment` → `lojaId` de `payment.metadata` (vazio para catálogo).
2. Se sem lojaId: `findLojaIdByOrderId(orderId)`.
3. `resolveLojaIdByOrderId`: 1) índice, 2) varre `pedidos`, 3) varre `pre_pedidos`.

### Comportamento em falhas

| Situação | Efeito |
|----------|--------|
| Índice não existe (novo pedido) | Varredura encontra o pre_pedido e grava o índice. |
| syncPedidoStatusPublico falha | Índice não é preenchido na criação; varredura resolve. |
| Webhook antes da CF | Varredura resolve; índice é preenchido na próxima escrita ou na varredura. |
| Pedidos antigos sem índice | Varredura funciona; performance pior com muitas lojas. |

**Conclusão:** O fluxo é seguro; o índice acelera, mas não é obrigatório.

---

## 6. VALIDAÇÃO DA DUPLA ESCRITA (APP + CF)

### Comparação

| Aspecto | App | CF |
|---------|-----|-----|
| Path | `lojas/{lojaId}/clientes_portal/{portalToken}/pedidos/{pedidoId}` | Igual |
| merge | false | false |
| Campos | pedidoId, lojaId, status, dataCriacao, dataAtualizacao, total, itensResumo, codigoRastreio, freteNome | buildPedidoStatusPublico (igual) |
| Momento | Após create, unawaited | OnWrite em pre_pedidos |

### Riscos

- **Sobrescrita com menos dados:** Não; schemas equivalentes.
- **Status divergente:** Não; ambos derivam do pre_pedido.
- **Timestamps:** CF usa `nowTs`; app usa `dataCriacao` do pedido e `FieldValue.serverTimestamp()` em `dataAtualizacao`. Pequena diferença sem impacto funcional.
- **Documentos duplicados:** Não; mesmo doc, mesma chave.

**Recomendação:** Manter dupla escrita; aumenta resiliência. Se quiser simplificar no futuro, remover escrita no app e deixar só a CF, mas a redundância atual é adequada.

---

## 7. RISCOS DE DUPLICIDADE DE CLIENTE

### `_ensureClienteComPortalToken` (pre_pedido_service.dart L159–206)

- Consulta por email antes de criar.
- Se existir: usa portalToken existente ou cria.
- Se não existir: cria novo doc.

**Race:** Duas requisições simultâneas podem passar `existente.docs.isEmpty` e criar dois clientes para o mesmo email.

### Coleções

| Coleção | Uso no catálogo | Risco de duplicidade |
|---------|------------------|----------------------|
| clientes | Principal; login/cadastro e fallback do portal | Possível por race em `_ensureClienteComPortalToken` |
| clientes_web | Não usado no catálogo | — |
| clientes_portal | Só leitura para "Meus Pedidos"; escrita por app/CF | Baixo |
| estoque_clientes | `_salvarOuAtualizarCliente`, `_adicionarPedidoAoHistoricoCliente` | Chave por telefone; outro modelo de cliente |

### Cenários de duplicidade

1. **Email:** Dois docs em `clientes` com mesmo email (race em `_ensureClienteComPortalToken`).
2. **Telefone:** `estoque_clientes` usa telefone; não interfere em `clientes`.
3. **portalToken:** Gerado de forma única; sem conflito direto.
4. **uid:** Catálogo não usa Firebase Auth; sem choque.

**Recomendação:** Reduzir race com transação ou id determinístico (ex.: hash de email) ao criar cliente em `_ensureClienteComPortalToken`.

---

## 8. CENÁRIOS END-TO-END E STATUS

| Cenário | Status | Observação |
|---------|--------|------------|
| Cliente novo se cadastra e compra | Funciona | Cadastro gera portalToken; checkout passa na sessão. |
| Cliente já logado compra | Funciona | portalToken na sessão; escrita imediata em clientes_portal. |
| Cliente compra via WhatsApp | Funciona | Mesmo fluxo de criarPrePedido com portalToken. |
| Cliente compra via Mercado Pago | Funciona | external_reference = pre_pedido id; mpWebhook processa. |
| Webhook com loja em metadata | Incerto | mpCatalogPayment não envia metadata; não se aplica ao catálogo. |
| Webhook sem metadata (order_loja_index) | Funciona | resolveLojaIdByOrderId usa índice ou varredura. |
| Pedido aparece em "Meus Pedidos" | Funciona | App e/ou CF gravam em clientes_portal. |
| Admin recebe notificação | Funciona | onPrePedidoCreated e mpWebhookHandler notificam. |
| Status atualiza para cliente | Funciona | syncPedidoStatusPublico atualiza clientes_portal quando pre_pedido muda. |

---

## 9. PROBLEMAS RESTANTES POR GRAVIDADE

### Críticos

- Nenhum.

### Altos

1. **mpCatalogPayment não envia metadata.lojaId**  
   - Impacto: Webhook depende de order_loja_index ou varredura.  
   - Correção: Incluir `metadata: { lojaId }` no body do PIX e da preference em `mpCatalogPayment`.

2. **posPagamento.js fora do fluxo**  
   - Impacto: Ajustes feitos ali não têm efeito em produção.  
   - Correção: Se for usar `mercadopagoWebhook`, exportá-lo em index.js; caso contrário, remover ou marcar como legado.

### Médios

3. **Race em `_ensureClienteComPortalToken`**  
   - Impacto: Possível duplicidade de cliente por email.  
   - Correção: Transação ou id baseado em email (ex.: hash) para garantir unicidade.

4. **status "paid" vs "confirmado"**  
   - mpWebhookHandler grava `status: "paid"`; pre_pedidos costumam usar "confirmado".  
   - syncPedidoStatusPublico propaga "paid" para clientes_portal. Funciona, mas naming pode ser padronizado depois.

### Baixos

5. **clientes_web e estoque_clientes**  
   - Não fazem parte do fluxo do catálogo; fragmentação permanece como débito técnico.

---

## 10. CORREÇÕES FINAIS RECOMENDADAS

### Prioridade 1: metadata em mpCatalogPayment

Adicionar `metadata: { lojaId }` nas chamadas PIX e preference em `functions/index.js`:

```javascript
// PIX (após L1274)
...(externalReference && { external_reference: String(externalReference) }),
metadata: { lojaId: String(lojaId) },

// Preference (após L1331)
...(externalReference && { external_reference: String(externalReference) }),
metadata: { lojaId: String(lojaId) },
```

### Prioridade 2: Decisão sobre posPagamento.js

- **Opção A:** Exportar `mercadopagoWebhook` se for usado como webhook alternativo.  
- **Opção B:** Documentar como legado e não usar; manter correções para futuro uso.

### Prioridade 3: Race em _ensureClienteComPortalToken

Usar transação ao criar cliente:

```dart
await _firestore.runTransaction((tx) async {
  final existente = await tx.get(_firestore
      .collection('lojas').doc(lojaId)
      .collection('clientes')
      .where('email', isEqualTo: emailNorm)
      .limit(1));
  if (existente.docs.isNotEmpty) { ... }
  tx.set(clientesRef, { ... });
});
```

Ou adotar doc id por email (ex.: hash) para evitar duplicatas.

---

**Validação baseada em:**  
- `lib/services/pre_pedido_service.dart`  
- `lib/screens/public_catalog_screen.dart`  
- `lib/repositories/cliente_portal_repository.dart`  
- `functions/index.js`  
- `functions/src/mpWebhookHandler.js`  
- `functions/src/posPagamento.js`  
- `functions/src/orderLojaIndex.js`  
