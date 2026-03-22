# Relatório de Prontidão para Produção
**Módulos:** Campanhas, Sorteios, Roleta, Globo e Pós-Pagamento  
**Data:** 21/03/2025

---

## 1. Itens aprovados

| Item | Status |
|------|--------|
| Schema canônico (dataParticipacao, numeroSorte, pedidoId, vendaId) | ✅ App e functions alinhados |
| Fallback de leitura (criadoEm, numeros, nomeCliente, valorCompra) | ✅ CampaignEngine, Participacao.fromFirestore |
| Duplicidade por pedidoId/vendaId | ✅ Verificação antes de registrar |
| Cancelamento por vendaId e pedidoId | ✅ cancelarParticipacao busca ambos |
| Regra oficial de números (valorMinimo→1; valorX→múltiplos; aleatório 5 dígitos) | ✅ posPagamento, CampanhasSorteioService, gerarCupomNumeroSorte |
| Multi-loja no pós-pagamento (posPagamento) | ✅ resolveLojaAndPayment, getLojaIdFromDocPath |
| Índice Firestore participantes/dataParticipacao | ✅ firestore.indexes.json |
| Unificação da roleta (config/roleta_sorte) | ✅ Implementado |
| Script de migração legada | ✅ migrar_participantes_schema.js |
| mpWebhook multi-loja | ✅ mpWebhookHandler com resolveLojaAndPayment |

---

## 2. Riscos restantes

| Risco | Severidade | Descrição |
|-------|------------|-----------|
| **mercadopagoWebhook não exportado** | Média | `posPagamento.js` exporta `mercadopagoWebhook` (campanhas, números, email) mas não está em `index.js`. O `mpWebhook` (pagamento, estoque) está ativo. Se o MP apontar para `mpWebhook`, pagamentos aprovados não disparam registro em campanhas nem envio de números por email. |
| **Participantes sem dataParticipacao ocultos** | Baixa | `orderBy('dataParticipacao')` exclui docs sem o campo. A migração preenche; participantes não migrados ficam fora da listagem. |
| **sortearNumero só usa numeros[]** | Baixa | `CampanhasSorteioService.sortearNumero` busca apenas em `numeros`. Participantes com só `numeroSorte` (sem `numeros`) não seriam encontrados. Hoje novos registros gravam `numeros: [numeroSorte]`; migração preenche `numeroSorte`. |
| **Colisão de numeroSorte** | Muito baixa | Aleatório 5 dígitos (~90k possíveis). Em volume normal, probabilidade de colisão é baixa. `_numeroExiste` em CampaignEngine reduz, mas não elimina. |
| **buscarVencedorPorNumero sem fallback** | Baixa | `SorteioNumeroService.buscarVencedorPorNumero` usa só `numeroSorte`. Participantes antigos só com `numeros[]` não seriam encontrados. Migração mitiga. |

---

## 3. Ajustes pequenos recomendados

1. **Exportar mercadopagoWebhook** (se quiser campanhas/números via webhook MP):
   ```js
   // functions/index.js
   export { mercadopagoWebhook } from "./src/posPagamento.js";
   ```
   Configurar no Mercado Pago a URL do `mercadopagoWebhook` para o fluxo que envia números.

2. **Rodar migração** (se ainda não rodou):
   ```bash
   cd functions && npm run migrar:participantes:dry && npm run migrar:participantes
   ```

3. **Fallback em sortearNumero** (opcional, robustez):
   ```dart
   final lista = List<String>.from(p.data()['numeros'] ?? []);
   if (lista.isEmpty) {
     final ns = p.data()['numeroSorte']?.toString();
     if (ns == numeroSorteado) { /* vencedor */ }
   }
   ```

4. **Integrar campanhas ao mpWebhook** (alternativa ao mercadopagoWebhook): chamar `registrarParticipacaoCampanha` após aprovação no `mpWebhookHandler`, reutilizando a lógica de `posPagamento.js`, para centralizar em um webhook só.

---

## 4. Status final de prontidão

### **Pronto para homologação**

**Justificativa:**
- Fluxos principais (Nova Venda, Catálogo via app, pré-pedidos) estão corretos.
- Schema e regras unificados.
- Multi-loja no pós-pagamento coberto.
- Riscos restantes são de baixa severidade e têm mitigação (migração, fallbacks).

**Antes de produção:**
1. Executar migração de participantes (se houver dados legados).
2. Decidir: usar `mercadopagoWebhook` (campanhas via webhook) ou integrar campanhas ao `mpWebhook`.
3. Testar homologação com pagamento real em loja de teste.

---

*Relatório gerado por auditoria automatizada do código.*
