# Plano de Alinhamento — Cloud Functions e Migração Legada

## ETAPA 1 — Auditoria (Concluída)

### posPagamento.js — registrarParticipacaoCampanha

| Aspecto | Atual | Schema Canônico | Divergência |
|---------|-------|-----------------|-------------|
| Regra | valorX: múltiplos números por R$50 | valorMinimo: 1 número por venda | Crítica |
| Campos gravados | clienteId, nomeCliente, clienteEmail, clienteTelefone, valorCompra, dataCompra, numeros[], criadoEm | dataParticipacao, pedidoId, vendaId, valorPedido, numeroSorte, status, sorteado, clienteNome | Múltiplas |
| pedidoId/vendaId | Não grava | Obrigatório | Crítica |
| dataParticipacao | Não grava | Obrigatório | Crítica |
| Coleção | campanhas_sorteio/{id}/participantes | Idem | OK |
| Geração números | Sequencial (counter) | App usa aleatório 5 dígitos | Média |

### gerarCupomNumeroSorte.js

| Aspecto | Atual | Schema Canônico | Divergência |
|---------|-------|-----------------|-------------|
| Campos gravados | clienteId, numeroSorte, pedidoId, clienteNome, clienteEmail, data | + dataParticipacao, vendaId, valorPedido, valorCompra, clienteTelefone, status, sorteado | data→dataParticipacao |
| data | FieldValue.serverTimestamp() | dataParticipacao | Campo errado |
| Número | 6 dígitos (100000-999999) | 5 dígitos (10000-99999) | Média |
| Falta | valorPedido, clienteTelefone, status, sorteado | — | Média |

---

## ETAPA 2 — Alterações Aplicadas

### functions/src/posPagamento.js

- **processarPosPagamento**: obtém `pedidoId` (pedidoDoc.id) e `vendaId` (pedidoData.vendaId \|\| externalReference); passa ambos para `registrarParticipacaoCampanha`.
- **registrarParticipacaoCampanha**: assinatura `(lojaId, cliente, valorCompra, pedidoId, vendaId)`.
- Regra: 1 número por venda quando valorMinimo > 0; fallback valorX quando valorMinimo ausente.
- Verificação de duplicidade por pedidoId e vendaId antes de registrar.
- Schema gravado: `dataParticipacao`, `pedidoId`, `vendaId`, `valorPedido`, `numeroSorte`, `status`, `sorteado`, `clienteNome`, `nomeCliente`, `clienteEmail`, `clienteTelefone`, `campanhaId`, `clienteId`, `origem`, `numeros`, `criadoEm`, `valorCompra`.
- Função `gerarNumeroSorteAleatorio()` — 5 dígitos (10000–99999).

### functions/gerarCupomNumeroSorte.js

- `gerarNumeroSorte()` alterada para 5 dígitos.
- Participantes gravam schema canônico: `dataParticipacao`, `vendaId`, `valorPedido`, `valorCompra`, `clienteTelefone`, `status`, `sorteado`, `campanhaId`, `origem`, `nomeCliente`, `numeros`, `criadoEm`.

---

## ETAPA 3 — Script de Migração

**Arquivo:** `functions/scripts/migrar_participantes_schema.js`

- Itera `lojas` → `campanhas_sorteio` → `participantes`.
- Se `dataParticipacao` ausente: preenche com `criadoEm` ou `data` (legado).
- Se `numeroSorte` ausente e `numeros[0]` existe: preenche `numeroSorte = numeros[0]`.
- Idempotente; `--dry-run` para simular.
- `--loja ID` para restringir a uma loja.

**Comandos:**
```bash
cd functions
npm run migrar:participantes:dry    # Simular
npm run migrar:participantes        # Executar
node ./scripts/migrar_participantes_schema.js --loja masterpalm --dry-run
```

---

## ETAPA 4 — Validação e Instruções

### Arquivos alterados

| Arquivo | Alterações |
|---------|------------|
| `functions/src/posPagamento.js` | `processarPosPagamento`, `registrarParticipacaoCampanha`, `gerarNumeroSorteAleatorio` |
| `functions/gerarCupomNumeroSorte.js` | Schema participantes, 5 dígitos |
| `functions/scripts/migrar_participantes_schema.js` | Novo script |
| `functions/package.json` | Scripts `migrar:participantes`, `migrar:participantes:dry` |

### Riscos restantes

1. **Número sequencial vs aleatório**: campanhas antigas com múltiplos números (valorX) continuam usando `gerarNumerosCampanha`; novos usam aleatório. Colisões de número são possíveis; o app já lida com isso.
2. **lojaId hardcoded**: `buscarPagamentoMercadoPago` ainda usa `lojaId = 'masterpalm'`; multi-loja precisa derivar do externalReference.
3. **gerarCupomNumeroSorte**: verifica duplicidade por pedidoId antes de registrar (mitigado).

### Instruções de deploy

1. **Functions:**
   ```bash
   cd functions
   npm install
   firebase deploy --only functions
   ```

2. **Migração legada (após deploy):**
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="./serviceAccount.json"
   npm run migrar:participantes:dry
   npm run migrar:participantes
   ```
