# Plano de Estabilização Final — Campanhas/Sorteios/Roleta/Globo

## ETAPA 1 — Multi-Loja no Pós-Pagamento ✅

### Correções aplicadas
- **posPagamento.js**: removido `buscarPagamentoMercadoPago` com lojaId fixo; usa `resolveLojaAndPayment` de `mpWebhookHandler.js`.
- Fluxo: tenta token global (`MP_ACCESS_TOKEN` ou `functions.config().mp.access_token`), depois itera lojas com token até encontrar o payment.
- **getLojaIdFromDocPath**: helper para extrair lojaId do path do pedido (suporta `lojas/X/pedidos/Y` e `lojas/X/vendas/V/pedidos/Z`).

### Arquivos alterados
| Arquivo | Alteração |
|---------|-----------|
| `functions/src/mpWebhookHandler.js` | Export de `resolveLojaAndPayment` |
| `functions/src/posPagamento.js` | Import de `resolveLojaAndPayment`, remoção de `buscarPagamentoMercadoPago`, uso de `getLojaIdFromDocPath` |

---

## ETAPA 2 — Regra Oficial de Números da Sorte ✅

### Regra final adotada
1. **valorMinimo > 0**: 1 número por venda quando valor >= valorMinimo.
2. **valorMinimo == 0** e **valorX > 0**: floor(valor / valorX) números (legado).
3. **Geração**: sempre **aleatório 5 dígitos** (10000–99999).

### Arquivos alterados
| Arquivo | Alteração |
|---------|-----------|
| `functions/src/posPagamento.js` | Números sempre aleatórios (não mais sequenciais) |
| `lib/services/campanhas_sorteio_service.dart` | Regra unificada, `_gerarNumerosAleatorios`, schema canônico em participantes |

### Módulos alinhados
| Módulo | Regra |
|--------|-------|
| CampaignEngine | valorMinimo, 1 número (já correto) |
| SorteioNumeroService | valorMinimo, 1 número (já correto) |
| CampanhasSorteioService | valorMinimo→1; fallback valorX; aleatório |
| posPagamento (functions) | valorMinimo→1; fallback valorX; aleatório |
| gerarCupomNumeroSorte | 1 número (já correto) |

---

## ETAPA 3 — Validação Final ✅

### Riscos restantes
1. **mercadopagoWebhook**: não está exportado em `index.js`; para usar, incluir `export { mercadopagoWebhook } from "./src/posPagamento.js"` e configurar no MP.
2. **Token global**: `posPagamento` usa `process.env.MP_ACCESS_TOKEN` ou `functions.config().mp.access_token`; configurar se houver conta MP única.
3. **Colisão de números**: aleatórios podem colidir; probabilidade baixa para volume normal. App já trata busca por numeroSorte.

### Roteiro de testes manuais

1. **Multi-loja (mercadopagoWebhook)**
   - Configurar webhook no MP apontando para `mercadopagoWebhook`.
   - Criar pedido em Loja A, pagar via MP.
   - Verificar: pedido atualizado, estoque baixado, participação em campanha da Loja A (não de outra loja).

2. **Regra de números**
   - Campanha com valorMinimo=50, valorX=50.
   - Venda de R$ 100 → deve gerar 1 número (valorMinimo > 0).
   - Campanha com valorMinimo=0, valorX=50.
   - Venda de R$ 150 → deve gerar 3 números aleatórios.

3. **Pedido público (CampanhasSorteioService)**
   - Tela de pedido público, finalizar compra com valor >= valorMinimo.
   - Verificar participante com dataParticipacao, numeroSorte, status.

4. **Path do pedido**
   - Pedido em `lojas/X/vendas/V/pedidos/Z` → lojaId extraído corretamente.
