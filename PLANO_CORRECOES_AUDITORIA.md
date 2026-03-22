# Plano de Correções — Auditoria Campanhas/Sorteios/Roleta/Globo

## ETAPA 1 — Eliminar duplicidade na Nova Venda

| Arquivo | Alteração |
|---------|-----------|
| `lib/services/vendas_service.dart` | Adicionar parâmetro opcional `void Function(String? numero)? onNumeroSorteGerado` em `registrarVendaMulti`; invocar com `resultado.numero` quando CampaignEngine retornar sucesso. |
| `lib/screens/nova_venda_modal.dart` | Remover chamada a `_registrarNumeroSorteio`; passar callback para `registrarVendaMulti` que recebe o numero e faz: 1) exibir dialog; 2) chamar `PosPagamentoService.enviarNotificacaoNumeroSorte` se cliente tiver contato. Remover import de `sorteio_numero_service.dart` se não for mais usado. Remover método `_registrarNumeroSorteio` ou marcá-lo deprecated. |

**Riscos:** Nenhum. Callback é opcional; callers existentes (order_review, pedido_publico, salvarVenda) não precisam mudar.

---

## ETAPA 2 — Corrigir campo ativo/ativa

| Arquivo | Alteração |
|---------|-----------|
| `lib/services/numero_sorte_service.dart` | Linha 17: `where('ativo', isEqualTo: true)` → `where('ativa', isEqualTo: true)` |

**Riscos:** Se algum documento no Firestore usar `ativo`, deixará de ser encontrado. Auditoria indica que o padrão é `ativa`. Manter fallback seria complexo; correção direta é o esperado.

---

## ETAPA 3 — Unificar configuração da Roleta

**Fonte oficial:** `config/roleta_sorte` (usada por RoletaSorteConfigScreen, carrinho web, nova_venda, roleta_web_widget)

| Arquivo | Alteração |
|---------|-----------|
| `lib/services/campanhas_sorteio_service.dart` | `carregarConfigRoleta` e `salvarConfigRoleta`: migrar de `campanhas_sorteio_config/roleta` para `config/roleta_sorte`. `registrarResultadoRoleta` continua em `roleta_vendas` (não é config). |
| `lib/screens/roleta_sorte_screen.dart` | Já usa CampanhasSorteioService.carregarConfigRoleta e salvarConfigRoleta — após migrar o service, passará a usar config/roleta_sorte automaticamente. |

**Compatibilidade:** Adicionar em CampanhasSorteioService leitura de fallback: se `config/roleta_sorte` não existir, tentar `campanhas_sorteio_config/roleta` uma vez e copiar para config/roleta_sorte (migração automática).

---

## ETAPA 4 — Corrigir cancelarParticipacao

| Arquivo | Alteração |
|---------|-----------|
| `lib/services/campaign_engine_service.dart` | Em `cancelarParticipacao`: além de `where('vendaId', isEqualTo: vendaId)`, adicionar busca por `where('pedidoId', isEqualTo: vendaId)` (vendaId pode ser pedidoId no contexto de catálogo). Evitar duplicar cancelamento: ao encontrar por vendaId, não buscar de novo por pedidoId para o mesmo doc. |

---

## ETAPA 5 — Padronizar schema de participantes

**Schema canônico:**
- `numeroSorte` (String) — número único
- `dataParticipacao` (Timestamp)
- `pedidoId` (String?) — vendaId ou pedidoId
- `clienteNome`, `clienteEmail`, `clienteTelefone`, `valorPedido`
- `campanhaId`, `sorteado`, `status`

**Compatibilidade de leitura:** CampaignEngine Participacao.fromFirestore já lê numeroSorte/numero, pedidoId/vendaId, dataParticipacao/criadoEm.

| Arquivo | Alteração |
|---------|-----------|
| `lib/services/campaign_engine_service.dart` | Participacao.toMap já usa schema canônico. listarParticipacoes: trocar orderBy('criadoEm') para orderBy('dataParticipacao') — com fallback se índice falhar. |
| `lib/services/sorteio_numero_service.dart` | Registrar com `dataParticipacao`, `pedidoId` (ou vendaId como alias). Hoje salva criadoEm, numeroSorte — adicionar dataParticipacao e pedidoId. Manter criadoEm por compatibilidade. |
| `lib/services/campanhas_sorteio_service.dart` | registrarParticipacao (se ainda usado) — verificar chamadas. |
| `lib/screens/campanha_participantes_screen.dart` | orderBy('criadoEm') → orderBy('dataParticipacao') com fallback. Ler numeroSorte e numeros[] (fallback para [numeroSorte]). |
| `functions/src/posPagamento.js` | Participantes: gravar dataParticipacao, numeroSorte (um número), pedidoId. Schema valorX/numeros[] é diferente — manter por agora para não quebrar Cloud Function; documentar como legado. |
| `functions/gerarCupomNumeroSorte.js` | Participantes: gravar dataParticipacao em vez de data. |

**Nota:** posPagamento.js usa lógica valorX (múltiplos números). Alterar para schema canônico exigiria mudança maior. Na Etapa 5, priorizar: CampaignEngine (já canônico), SorteioNumeroService (usado por pos_pagamento Dart), NumeroSorteService (leitura). posPagamento.js e gerarCupomNumeroSorte serão ajustes pontuais.

---

## ETAPA 6 — Validação

Revisão manual dos fluxos após implementação.
