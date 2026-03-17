# SRE - Timeouts e Retry HTTP

## 1. Timeouts padrão por tipo

| Tipo | Duração | Uso |
|------|---------|-----|
| `HttpTimeouts.payment` | 20s | APIs de pagamento (Ton, MercadoPago, PagSeguro, InfinitePay) |
| `HttpTimeouts.cloudFunction` | 30s | Cloud Functions (createPreference, gerarCupomNumeroSorte) |
| `HttpTimeouts.freight` | 20s | APIs de frete (Melhor Envio, Frenet, SuperFrete) |
| `HttpTimeouts.external` | 15s | APIs externas (ViaCEP, etc) |
| `HttpTimeouts.quick` | 10s | Validações e health checks |
| `HttpTimeouts.standard` | 15s | Genérico |

## 2. Retry exponencial

**Onde é seguro:**
- `GET` – leituras são idempotentes (getWithRetry)
- `GET` consulta pagamento/cobrança – não altera estado
- `GET` validação de credenciais

**Onde NÃO aplicar retry:**
- `POST` criar cobrança PIX – duplicaria cobrança
- `POST` criar pagamento – duplicaria pagamento
- `POST` gerar cupom – pode duplicar registros
- `DELETE` – operação destrutiva

## 3. Operações críticas (sem retry)

| Serviço | Operação | Timeout |
|---------|----------|---------|
| TonService | criarCobrancaPix | 20s |
| TonService | cancelarCobranca | 20s |
| MercadoPagoService | criarPagamentoPix | 20s |
| MercadoPagoService | estornarPagamento | 20s |
| InfinitePayService | criar cobrança | 20s |
| gerarCupomNumeroSorte | Cloud Function | 30s |

## 4. Helpers reutilizáveis

```dart
// GET com timeout (sem retry)
HttpClientHelper.get(url, timeout: HttpTimeouts.external);

// GET com retry exponencial (3 tentativas, backoff 500ms)
HttpClientHelper.getWithRetry(url, timeout: HttpTimeouts.payment);

// POST com timeout (sem retry - operações de criação)
HttpClientHelper.post(url, body: data, timeout: HttpTimeouts.payment);

// POST com retry (apenas para operações idempotentes)
HttpClientHelper.postWithRetry(url, body: data, timeout: HttpTimeouts.cloudFunction);
```

## 5. Idempotência em operações críticas

- **MercadoPago** `criarPagamentoPix`: usa `X-Idempotency-Key` (timestamp) – retry com mesma key não duplica
- **Ton/InfinitePay**: não expõem idempotency key – **não retry** em criação de cobrança

## 6. Serviços integrados

| Serviço | Integração |
|---------|------------|
| TonService | HttpClientHelper (timeout + getWithRetry em consultas) |
| MercadoPagoService | HttpClientHelper (timeout + getWithRetry em consultas) |
| public_catalog_screen | gerarCupomNumeroSorte, ViaCEP |
| pagamentos_service | finalizarOAuthNoBackend |
| MpFunctionsClient | Já usa timeout de 30s |
