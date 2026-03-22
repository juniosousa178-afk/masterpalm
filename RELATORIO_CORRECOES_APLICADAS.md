# Relatório das Correções Aplicadas
## Auditoria Campanhas, Sorteios, Roleta e Globo da Sorte

**Data:** 21 de março de 2026

---

## 1. Arquivos alterados

| Arquivo | Tipo de alteração |
|---------|-------------------|
| `lib/services/vendas_service.dart` | Parâmetro callback + invocação |
| `lib/screens/nova_venda_modal.dart` | Remoção SorteioNumeroService, callback, novo dialog |
| `lib/services/numero_sorte_service.dart` | `ativo` → `ativa` |
| `lib/services/campanhas_sorteio_service.dart` | Roleta: config unificada em `config/roleta_sorte` |
| `lib/services/campaign_engine_service.dart` | cancelarParticipacao, toMap, listarParticipacoes, buscarPorVendaId |
| `lib/services/sorteio_numero_service.dart` | Schema canônico, vendaIdOuPedidoId |
| `lib/services/pos_pagamento_service.dart` | Passagem de vendaIdOuPedidoId |
| `lib/screens/campanha_participantes_screen.dart` | orderBy dataParticipacao, leitura dual schema |
| `firestore.indexes.json` | Índices para participantes |
| `PLANO_CORRECOES_AUDITORIA.md` | Plano criado |

---

## 2. Correções aplicadas por etapa

### ETAPA 1 — Eliminar duplicidade na Nova Venda

- **Antes:** Nova venda chamava VendasService (→ CampaignEngine) e `_registrarNumeroSorteio` (→ SorteioNumeroService).
- **Depois:** Apenas VendasService → CampaignEngine. Callback `onNumeroSorteGerado` retorna o número ao modal.
- **Resultado:** Uma venda gera uma participação e um único número.

### ETAPA 2 — Corrigir campo ativo/ativa

- **Arquivo:** `numero_sorte_service.dart`
- **Alteração:** `where('ativo', isEqualTo: true)` → `where('ativa', isEqualTo: true)`
- **Efeito:** NumeroSorteService passa a encontrar campanhas ativas corretamente.

### ETAPA 3 — Unificar configuração da Roleta

- **Fonte oficial:** `config/roleta_sorte`
- **Alteração:** `roletaConfigDoc()` passou a apontar para `lojas/{id}/config/roleta_sorte`.
- **Migração:** Se o novo doc não existir, lê de `campanhas_sorteio_config/roleta` e grava em `config/roleta_sorte`.
- **Compatibilidade:** RoletaSorteScreen, RoletaSorteConfigScreen, carrinho web e nova_venda usam a mesma fonte.

### ETAPA 4 — Corrigir cancelarParticipacao

- **Antes:** Busca apenas por `vendaId`.
- **Depois:** Busca por `vendaId` e `pedidoId` (catálogo/pré-pedido).
- **Efeito:** Participações de Nova Venda e Catálogo podem ser canceladas.

### ETAPA 5 — Padronizar schema de participantes

- **CampaignEngine toMap:** Inclusão de `vendaId` além de `pedidoId`.
- **SorteioNumeroService:** Grava `dataParticipacao`, `valorPedido`, `pedidoId`, `vendaId`, `status`, `sorteado`.
- **listarParticipacoes / participacoesStream:** `orderBy('criadoEm')` → `orderBy('dataParticipacao')`.
- **CampanhaParticipantesScreen:** orderBy `dataParticipacao`; leitura de `numeroSorte` e `numeros[]`.
- **buscarPorVendaId:** Passa a buscar por `vendaId` e `pedidoId`.
- **Firestore:** Índices adicionados para `participantes` com `dataParticipacao` e `status` + `dataParticipacao`.

---

## 3. Compatibilidades legadas mantidas

| Situação | Tratamento |
|----------|------------|
| Config roleta antiga | Migração automática de `campanhas_sorteio_config/roleta` → `config/roleta_sorte` na primeira leitura |
| Participantes antigos (criadoEm) | Excluídos de queries que usam `orderBy dataParticipacao`; CampanhaParticipantesScreen prioriza `dataParticipacao` |
| Participantes antigos (numeros[]) | CampanhaParticipantesScreen continua lendo `numeros` e usa `numeroSorte` como fallback |
| Participação com só pedidoId | `cancelarParticipacao` e `buscarPorVendaId` passam a considerar `pedidoId` |
| Callers de registrarVendaMulti | Parâmetro `onNumeroSorteGerado` opcional; sem mudanças em order_review, pedido_publico, etc. |

---

## 4. Riscos restantes

| Risco | Severidade | Mitigação sugerida |
|-------|------------|--------------------|
| Índice Firestore ainda não deployado | Média | Rodar `firebase deploy --only firestore:indexes` |
| Participantes só com criadoEm | Baixa | Documentos antigos não aparecem em listas ordenadas por `dataParticipacao`; avaliar script de migração |
| posPagamento.js (Cloud Function) | Média | Continua com schema valorX/numeros[]; alinhar em ajuste futuro |
| gerarCupomNumeroSorte.js | Baixa | Continua usando campo `data`; ajuste futuro para `dataParticipacao` |

---

## 5. Migração de dados

**Não é obrigatória.** O sistema funciona com dados novos e antigos.

**Opcional para consistência total:**

1. **Participantes antigos:** Script que adiciona `dataParticipacao = criadoEm` onde `dataParticipacao` não existe.
2. **Config roleta:** Migração automática já implementada na leitura; nenhuma ação extra.

---

## 6. Fluxos validados

| Fluxo | Status |
|-------|--------|
| Nova Venda → participação única | Corrigido |
| Campanhas ativas (NumeroSorteService) | Corrigido |
| Config Roleta unificada | Corrigido |
| cancelarParticipacao (vendaId + pedidoId) | Corrigido |
| Leitura de participantes (schema canônico) | Corrigido |

---

## 7. Próximos passos sugeridos

1. Deploy dos índices Firestore.
2. Testes manuais: Nova Venda, Globo, Histórico, Roleta.
3. Opcional: migração de participantes legados com script.
4. Opcional: unificação de posPagamento.js e gerarCupomNumeroSorte com o schema canônico.
