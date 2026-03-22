# ENTREGA — Correções Finais de Hardening

**Data:** 21/03/2025  
**Escopo:** metadata.lojaId, posPagamento.js, _ensureClienteComPortalToken

---

## 1. RESUMO EXECUTIVO

As 3 correções foram implementadas:

| Correção | Status | Arquivos |
|----------|--------|----------|
| 1. metadata.lojaId no pagamento | ✅ | MercadoPagoService, public_catalog_screen, payment_gateway_service |
| 2. posPagamento.js como legado | ✅ | functions/src/posPagamento.js |
| 3. Blindar _ensureClienteComPortalToken | ✅ | pre_pedido_service, cliente_auth_helpers |

**Nota:** O `mpCatalogPayment` em `functions/index.js` **já tinha** `metadata: { lojaId }` para PIX e preference. A alteração foi feita apenas no fluxo APK (MercadoPagoService direto).

---

## 2. ARQUIVOS ALTERADOS

| Arquivo | Alteração |
|---------|-----------|
| `lib/services/mercadopago_service.dart` | Parâmetro `lojaId` em `criarPreferencia` e `criarPagamentoPix`; envio de `metadata: { lojaId }` ao MP |
| `lib/screens/public_catalog_screen.dart` | Passagem de `lojaId` nas chamadas a MercadoPagoService (APK) |
| `lib/services/payment_gateway_service.dart` | `lojaId` em `_processarMercadoPago` e repasse para MercadoPagoService |
| `functions/src/posPagamento.js` | Bloco de comentários no topo marcando como legado |
| `lib/services/pre_pedido_service.dart` | `_ensureClienteComPortalToken` com id determinístico + transação |
| `lib/services/cliente_auth_helpers.dart` | Função `clienteIdPorEmail(lojaId, email)` para id determinístico |

---

## 3. CORREÇÃO 1 — metadata.lojaId

### Fluxos de pagamento

| Fluxo | Ponto de criação | metadata.lojaId |
|-------|------------------|-----------------|
| Web (PIX) | mpCatalogPayment (CF) | ✅ Já presente |
| Web (preference) | mpCatalogPayment (CF) | ✅ Já presente |
| APK (PIX) | MercadoPagoService.criarPagamentoPix | ✅ Incluído |
| APK (preference) | MercadoPagoService.criarPreferencia | ✅ Incluído |
| PaymentGatewayService (admin) | _processarMercadoPago → MercadoPagoService | ✅ Incluído |

### Trechos principais

**mercadopago_service.dart — criarPagamentoPix:**
```dart
lojaId: lojaId,  // novo parâmetro opcional
// ...
if (lojaId != null && lojaId.isNotEmpty) 'metadata': {'lojaId': lojaId},
```

**mercadopago_service.dart — criarPreferencia:**
```dart
lojaId: lojaId,  // novo parâmetro opcional
// ...
if (lojaId != null && lojaId.isNotEmpty) 'metadata': {'lojaId': lojaId},
```

**public_catalog_screen.dart — chamadas APK:**
```dart
paymentData = await MercadoPagoService.criarPagamentoPix(
  // ...
  lojaId: lojaId,
);
// e
paymentData = await MercadoPagoService.criarPreferencia(
  // ...
  lojaId: lojaId,
  // ...
);
```

---

## 4. CORREÇÃO 2 — posPagamento.js

### Decisão

Marcado como **legado / não em uso em produção** com aviso explícito no código.

### Comentário adicionado

```javascript
/**
 * ⚠️ LEGADO / NÃO EM USO EM PRODUÇÃO
 *
 * O webhook mercadopagoWebhook deste arquivo NÃO está exportado em index.js.
 * O fluxo real de pós-pagamento em produção é:
 *   mpWebhook (index.js) → processMpWebhook (mpWebhookHandler.js)
 *
 * Use mpWebhookHandler.js para alterações no processamento de pagamentos.
 * Este arquivo é mantido para referência, fallback futuro ou migração.
 * NÃO configure o Mercado Pago para chamar mercadopagoWebhook - use mpWebhook.
 *
 * Funcionalidades históricas:
 * - Webhook do Mercado Pago (mercadopagoWebhook - não deployado)
 * - Baixa de estoque
 * - Geração de número da sorte
 * - Envio de Email e WhatsApp
 */
```

### Motivo

O arquivo não foi removido porque:
- Pode ser útil como referência de lógica (campanhas, números da sorte).
- O mpWebhookHandler já cobre o fluxo principal.
- Remover sem migração poderia gerar perda de referência.

---

## 5. CORREÇÃO 3 — _ensureClienteComPortalToken

### Estratégia

- **Doc id determinístico:** `clienteIdPorEmail(lojaId, email)` gera `ec_` + hash SHA256 truncado (28 chars), para que todas as execuções concorrentes usem o mesmo doc.
- **Transação Firestore:** `runTransaction` para leitura e gravação atômicas.
- **Resultado:** Duas requisições simultâneas para o mesmo email escrevem no mesmo doc; a segunda encontra o doc criado pela primeira ou sobrescreve com os mesmos dados, sem duplicidade.

### Trechos principais

**cliente_auth_helpers.dart:**
```dart
String clienteIdPorEmail(String lojaId, String email) {
  final norm = email.trim().toLowerCase();
  if (norm.isEmpty) return gerarClienteId();
  final input = '$lojaId:$norm';
  final digest = sha256.convert(utf8.encode(input));
  final b64 = base64UrlEncode(digest.bytes).replaceAll('=', '');
  return 'ec_${b64.substring(0, 28.clamp(0, b64.length))}';
}
```

**pre_pedido_service.dart — _ensureClienteComPortalToken:**
```dart
final docId = clienteIdPorEmail(lojaId, emailNorm);
return _firestore.runTransaction<String?>((tx) async {
  final snap = await tx.get(docRef);
  if (snap.exists) { /* retorna portalToken existente */ }
  tx.set(docRef, { /* novo cliente */ });
  return portalToken;
});
```

### Riscos remanescentes

1. **Cadastro vs checkout simultâneos:** Se o cadastro criar um cliente com id aleatório e o checkout chamar `_ensureClienteComPortalToken` ao mesmo tempo, pode haver dois docs para o mesmo email (um com id aleatório e outro com `ec_xxx`). Janela de tempo curta e pouco provável.
2. **Id `ec_xxx`:** Novos clientes criados por este fallback usam prefixo `ec_`; clientes antigos continuam com ids gerados por timestamp. Sem impacto em fluxos atuais.

---

## 6. COMO TESTAR CADA CORREÇÃO

### Correção 1 — metadata.lojaId

1. **Web:** Checkout pelo catálogo (PIX ou cartão) e confirmar no MP que `metadata.lojaId` está presente.
2. **APK:** Repetir o fluxo de checkout no app.
3. **Webhook:** Simular webhook com pagamento aprovado; checar que `mpWebhookHandler` usa `payment.metadata?.lojaId` quando existir.

### Correção 2 — posPagamento.js

1. Abrir `functions/src/posPagamento.js` e confirmar o aviso de legado no topo.
2. Conferir em `index.js` que não há `export` de `mercadopagoWebhook`.

### Correção 3 — _ensureClienteComPortalToken

1. **Sequencial:** Cliente novo, sem cadastro prévio, faz compra; verificar doc único em `clientes` com id `ec_xxx`.
2. **Concorrência:** Duas abas/dispositivos com mesmo email novo, checkout ao mesmo tempo; deve existir apenas um doc para esse email.
3. **Compatibilidade:** Cliente já cadastrado (id aleatório) faz compra; deve seguir usando o doc existente, sem criar `ec_xxx`.

---

## 7. RISCOS REMANESCENTES

| Risco | Gravidade | Mitigação |
|-------|-----------|-----------|
| Duplicidade cadastro + checkout simultâneos | Baixa | Janela curta; aceitável por enquanto |
| Clientes `ec_xxx` misturados com ids antigos | Nenhuma | Sem impacto funcional |
| Metadata em preference do MP | Média | Verificar se o MP repassa metadata da preference para o pagamento |

---

## 8. PRÓXIMOS PASSOS RECOMENDADOS

1. Conferir na documentação do MP se a preference repassa `metadata` para o pagamento criado.
2. Rodar backfill em `order_loja_index` para pedidos antigos sem índice.
3. Revisar FASE 4 da auditoria (fragmentação de cliente) em momento posterior.
