# Relatório Final – Manutenção Carrinho/Checkout Catálogo Web

**Data:** Março 2025  
**Escopo:** Carrinho, checkout e fluxos correlatos do catálogo público web  
**Status:** Pronto para produção controlada

---

## Resumo executivo

Foi concluída a manutenção de segurança e consistência do carrinho e do checkout do catálogo web público. As correções foram aplicadas em três fases (FASE 1, FASE 2 e Revisão Final), com foco em patch mínimo, preservação de fluxos estáveis e hardening defensivo. O analyzer passou sem erros novos. O sistema está classificado como **pronto para produção controlada**, com monitoramento recomendado no rollout inicial.

---

## Status final

| Item | Status |
|------|--------|
| FASE 1 (Bloqueadores) | Concluída |
| FASE 2 (Alta severidade) | Concluída |
| Revisão final (Médio/Baixo) | Concluída |
| Padronização telefone | Concluída |
| Analyzer | Sem erros novos |

---

## Arquivos alterados

| Arquivo | Escopo |
|---------|--------|
| `lib/screens/public_catalog/widgets/carrinho_sheet_web.dart` | Carrinho, validações, cupom, frete, PIX, formulário |
| `lib/screens/public_catalog_screen.dart` | Callbacks de checkout, PIX, persistência carrinho/formulário, `initialFormData` |

---

## Correções aplicadas por fase

### FASE 1 – Bloqueadores
- Validação de endereço não exige campos completos quando frete for retirada
- Fretes manuais preservados quando API retorna vazio; fallback com Retirada e Combinar
- `showPixQrDialog` e `mostrarModalSelecionarCupom` corrigidos/validados
- Cupom aplicado no carrinho repassado ao fluxo PIX (`cupomCodigo`, `desconto`)

### FASE 2 – Alta severidade
- CPF com validação real (dígitos verificadores, sequências repetidas bloqueadas)
- E-mail com validação de formato quando preenchido (campo opcional)
- Persistência assíncrona do formulário com debounce e save em `dispose`
- Embalagens Hive isoladas por loja (`embalagens_$lojaId`)
- Produtos sem peso: guard defensivo, mensagem clara, bloqueio do cálculo de frete
- Produtos sem preço: bloqueio de checkout com mensagem de erro
- Cupom no fluxo PIX: subtotal, frete, desconto e total coerentes
- Valor mínimo do cupom: regra com subtotal + frete quando `aplicarEm == 'total'`
- Carrinho sem login: persistência local (SharedPreferences) por `lojaId`
- Cupom marcado como usado: callback `onPedidoCriado` no PIX (cupom normal, roleta, cupom de indicação)

### Revisão final – Médio/Baixo
- JSON corrompido em `initialFormData`: parse defensivo, fallback seguro
- Parse seguro de `freteIndex` (int, num, String) em `initState`
- Telefone padronizado (10 dígitos mínimo)
- `firstWhere` em embalagens com guard para lista vazia
- Campos de validade de cupom: leitura resiliente (`dataFim`, `validade`, `dataValidade`, `dataExpiracao`, `expiraEm`)
- Exibição do prazo do frete: `?` corrigido para `-`
- Hardening PIX: log em falha de `onPedidoCriado`, sem quebra do fluxo
- Diálogo de login: bullets (`•`) em vez de `?`

---

## Regras finais consolidadas

| Regra | Valor |
|-------|-------|
| Telefone | Mínimo 10 dígitos (aceita fixo e celular) |
| CPF | 11 dígitos + validação real |
| E-mail | Opcional; quando preenchido, validação de formato |
| Endereço em retirada | Não obrigatório |
| Produto sem peso | Bloqueia cálculo de frete, exibe mensagem |
| Produto sem preço | Bloqueia checkout |
| Valor mínimo cupom | Subtotal + frete (quando `aplicarEm == 'total'`) |

---

## Riscos residuais aceitos

| Risco | Mitigação |
|-------|-----------|
| `onPedidoCriado` falha silenciosamente | Log em debug; fluxo de pagamento não interrompido |
| Cadastro cliente (`cadastro_screen_cliente`) sem validação de tamanho de telefone | Backend deve validar |
| Context após async em alguns pontos | Avisos pré-existentes; guards de `mounted` onde crítico |
| Telefone fixo (10 dígitos) em fluxos que priorizam celular | Regra aceita 10 e 11 dígitos |

---

## Checklist de smoke test

Antes do deploy, executar manualmente:

| # | Teste | Resultado esperado |
|---|-------|--------------------|
| 1 | Abrir catálogo | Carregamento e exibição dos produtos |
| 2 | Adicionar item ao carrinho | Item adicionado, contador atualizado |
| 3 | Abrir carrinho | Sheet abre com itens e formulário |
| 4 | Checkout com retirada | Finaliza sem exigir endereço completo |
| 5 | Checkout com entrega | Exige CEP e endereço; calcula frete |
| 6 | Checkout sem fretes da API | Fretes manuais (Retirada, Combinar) exibidos |
| 7 | Aplicar cupom | Cupom aplicado; desconto no total |
| 8 | PIX com cupom | Total correto; cupom marcado como usado |
| 9 | PIX sem cupom | Fluxo normal; QR gerado |
| 10 | Carrinho ao recarregar aba | Itens e formulário persistidos (usuário não logado) |
| 11 | Telefone com 10 dígitos | Aceito no cadastro e checkout |
| 12 | Telefone com 11 dígitos | Aceito no cadastro e checkout |
| 13 | Telefone inválido (< 10 dígitos) | Rejeitado com mensagem clara |

---

## Recomendação de rollout

1. **Produção controlada**
   - Liberar primeiro para grupo limitado de lojas/usuários.
   - Validar smoke test em produção antes de ampliar.

2. **Monitoramento**
   - **PIX:** Logs de `onPedidoCriado`, `registrarVendaCatalogo`, falhas no `showPixQrDialog`.
   - **Cupom:** Marcação de uso em cupom normal, roleta e cupom de indicação.
   - **Frete:** Erros de `_recalcularFreteSelecionado`, fretes zerados da API.
   - **Persistência:** Perda de carrinho/formulário ao recarregar, especialmente sem login.

3. **Ampliação**
   - Após período de observação (ex.: 48–72 h) sem incidentes relevantes, ampliar rollout.

---

## Observações pós-deploy

- Manter logs de debug (com TTL curto) para investigação de falhas.
- Se houver reclamações de telefone fixo bloqueado, rever regra (atualmente aceita 10 e 11 dígitos).
- Validar periodicamente que embalagens e fretes continuam isolados por loja em ambiente multi-loja.
- Em caso de inconsistência de cupom não marcado como usado, priorizar logs de `onPedidoCriado` e `CupomDescontoService.registrarUso`.
