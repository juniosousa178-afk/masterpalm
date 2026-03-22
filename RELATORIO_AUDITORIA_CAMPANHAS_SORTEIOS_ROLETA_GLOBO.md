# RELATÓRIO DE AUDITORIA TÉCNICA
## Campanhas, Sorteios, Roleta da Sorte e Globo da Sorte

**Data:** 21 de março de 2026  
**Escopo:** Módulos Campanhas, Sorteios, Roleta da Sorte, Globo da Sorte + integração com Nova Venda, Pré-pedidos e Catálogo.

---

## 1. Escopo auditado

### Módulos analisados
- **Campanhas de sorteio** — criação, listagem, participantes, histórico
- **Sorteios** — geração de números, participação, realização do sorteio
- **Roleta da Sorte** — configuração, giro, prêmios, cupons
- **Globo da Sorte** — sorteio público com animação de dígitos

### Integrações verificadas
- Nova Venda (modal APK)
- Pré-pedidos (catálogo → confirmação vendedor)
- Catálogo (checkout web, carrinho)
- Pós-pagamento (webhook Mercado Pago)
- Cloud Functions (gerarCupomNumeroSorte, posPagamento)

### Limites da análise
- Não foram analisados módulos fora do escopo (estoque, relatórios financeiros, etc.).
- Testes automatizados não foram executados; análise baseada exclusivamente em código.

---

## 2. Arquivos encontrados

| Arquivo | Responsabilidade | Módulo | Criticidade |
|---------|------------------|--------|-------------|
| `lib/models/campanha_sorteio.dart` | Modelo CampanhaSorteio, TicketSorteio | Campanhas | Alta |
| `lib/models/cupom_cliente.dart` | Cupom da roleta (Firestore) | Roleta | Média |
| `lib/models/cupom_premio.dart` | Cupom prêmio (Hive) | Roleta legado | Média |
| `lib/services/campanhas_sorteio_service.dart` | CRUD campanhas, participantes, roleta config (config/roleta antigo) | Campanhas, Roleta | Crítica |
| `lib/services/campaign_engine_service.dart` | Participação centralizada (nova venda, catálogo) | Campanhas/Sorteios | Crítica |
| `lib/services/numero_sorte_service.dart` | Busca participantes, geração sequencial | Globo, Histórico | Crítica |
| `lib/services/sorteio_numero_service.dart` | Registro participação (nova venda, pos_pagamento) | Sorteios | Crítica |
| `lib/services/globo_sorte_service.dart` | API externa Globo da Sorte (não usada no fluxo principal) | Globo | Baixa |
| `lib/services/globo_sorteio_params_resolver.dart` | Resolve lojaId/campanhaId para tela Globo | Globo | Média |
| `lib/services/pos_pagamento_service.dart` | Pós-pagamento, número sorte, SorteioNumeroService | Sorteios | Crítica |
| `lib/services/catalogo_venda_service.dart` | Venda catálogo, CampaignEngine, cupom roleta | Catálogo, Campanhas | Crítica |
| `lib/services/vendas_service.dart` | Nova venda APK, CampaignEngine | Nova Venda | Crítica |
| `lib/services/cupons_service.dart` | Criar cupom roleta, indicação | Roleta | Média |
| `lib/screens/campanhas_sorteio_list_screen.dart` | Lista campanhas | Campanhas | Média |
| `lib/screens/campanha_sorteio_form_screen.dart` | Criar/editar campanha | Campanhas | Média |
| `lib/screens/campanha_participantes_screen.dart` | Participantes (schema antigo: numeros, criadoEm) | Campanhas | Alta |
| `lib/screens/campanha_sorteio_historico_screen.dart` | Histórico participantes + vencedores | Campanhas/Sorteios | Alta |
| `lib/screens/globo_sorteio_screen.dart` | Tela do Globo (sortear dígitos) | Globo | Crítica |
| `lib/screens/roleta_sorte_screen.dart` | Roleta APK (usa campanhas_sorteio_config) | Roleta | Alta |
| `lib/screens/roleta_sorte_config_screen.dart` | Config roleta (usa config/roleta_sorte) | Roleta | Alta |
| `lib/screens/nova_venda_modal.dart` | Nova venda, SorteioNumeroService + VendasService | Nova Venda | Crítica |
| `lib/widgets/roleta_web_widget_v3.dart` | Roleta no catálogo web | Roleta, Catálogo | Alta |
| `lib/widgets/campanha_banner_widget.dart` | Banner campanha no home | Campanhas | Baixa |
| `lib/widgets/resultado_roleta_card.dart` | Card resultado roleta | Roleta | Baixa |
| `lib/screens/public_catalog/widgets/carrinho_sheet_web.dart` | Carrinho web, roleta, campanha | Catálogo, Roleta | Crítica |
| `lib/main.dart` | Rotas, inicialização | Geral | Média |
| `lib/app_routes.dart` | Rotas dinâmicas | Geral | Baixa |
| `functions/gerarCupomNumeroSorte.js` | Cloud Function (schema legado) | Campanhas | Média |
| `functions/src/posPagamento.js` | Webhook MP, registrar participação (schema valorX) | Sorteios | Crítica |

---

## 3. Funcionamento atual por módulo

### 3.1 Campanhas

**Fluxo atual:**
- Campanhas são criadas via `CampanhaSorteioFormScreen`, salvas em `lojas/{lojaId}/campanhas_sorteio`.
- Campos: `nome`, `descricao`, `dataInicio`, `dataFim`, `dataSorteio`, `valorMinimo`, `valorX`, `ativa`, `status`.
- **Problema:** Existem múltiplos schemas de campanha e participantes (ver seção 4).

**Origem de dados:** Firestore `lojas/{lojaId}/campanhas_sorteio`.

**Persistência:** Firestore apenas (sem Hive para campanhas).

**Atualização de UI:** StreamBuilder em listas e histórico.

**Dependências:** LojaId resolvido por contexto/sessão.

**Pontos frágeis:**
- Campo `ativa` vs `ativo` divergente entre serviços (NumeroSorteService usa `ativo` — **bug**).
- CampanhasSorteioService.salvarCampanha não persiste `ativa` em alguns fluxos de edição.

---

### 3.2 Sorteios

**Fluxo atual:**
- Participação é registrada por **quatro caminhos diferentes** com schemas incompatíveis:
  1. **CampaignEngineService** (VendasService, CatalogoVendaService) — 1 número/venda, `dataParticipacao`, `pedidoId`
  2. **SorteioNumeroService** (NovaVendaModal, PosPagamentoService) — 1 número/venda, `criadoEm`, sem `pedidoId`
  3. **CampanhasSorteioService.registrarParticipacao** (não chamado no fluxo principal atual)
  4. **posPagamento.js** (Cloud Function) — múltiplos números por valorX, `numeros` array, `data`

**Origem de dados:** Firestore `campanhas_sorteio/{id}/participantes`.

**Persistência:** Firestore. Duplicidade de gravação na Nova Venda (CampaignEngine + SorteioNumero).

**Pontos frágeis:**
- **DUPLICIDADE CRÍTICA:** Nova venda chama VendasService (→ CampaignEngine) e _registrarNumeroSorteio (→ SorteioNumeroService). Mesma venda gera **duas participações** com números diferentes.
- NumeroSorteService.getCampanhaAtiva usa `where('ativo')`; demais usam `where('ativa')`. Se documento tiver só `ativa`, NumeroSorteService não encontra campanha.

---

### 3.3 Roleta da Sorte

**Fluxo atual:**
- **Duas configurações distintas:**
  - `config/roleta_sorte` — usada por RoletaSorteConfigScreen, carrinho web, nova_venda, roleta_web_widget
  - `campanhas_sorteio_config/roleta` — usada por RoletaSorteScreen (APK)
- Roleta da Sorte e Campanha de Sorteio são funções separadas, mas a nomenclatura confunde.
- Cupons da roleta vão para `cupons_clientes` (Firestore) ou `estoque_clientes` + `clientes_catalogo/cupons`.

**Origem de dados:** Firestore `config/roleta_sorte` ou `campanhas_sorteio_config/roleta` (inconsistente).

**Persistência:** Firestore. CupomPremio (Hive) parece legado.

**Pontos frágeis:**
- RoletaSorteScreen e RoletaSorteConfigScreen usam documentos diferentes. Configurar em uma tela não reflete na outra.

---

### 3.4 Globo da Sorte

**Fluxo atual:**
- Tela carrega participantes via `NumeroSorteService.getParticipantesParaSorteio` (orderBy `dataParticipacao`).
- Sorteia dígito a dígito (5 rodadas). Rodadas 1–3: número que não existe; rodada 4: número existente (vencedor).
- Salva histórico em `historico_sorteios` com campo `data` (Timestamp).
- GloboSorteService (API externa) existe mas não é utilizada no fluxo principal.

**Origem de dados:** Firestore participantes. Loja/campanha via GloboSorteioParamsResolver (URL ou Firestore).

**Pontos frágeis:**
- NumeroSorteService usa `ativo` na query — pode não retornar campanhas.
- Participantes com schema antigo (SorteioNumeroService: `criadoEm`, sem `dataParticipacao`) podem não aparecer ou causar erro em orderBy.

---

## 4. Fluxo técnico ponta a ponta

### Nova Venda (APK)

1. Usuário finaliza venda → `_finalizarVenda` → `_executarFinalizacaoVenda`
2. `VendasService.registrarVendaMulti` → salva Hive, Firestore, **CampaignEngineService.onVendaConcluida**
3. `_registrarNumeroSorteio` → **SorteioNumeroService.registrarNumeroEmCampanhas**
4. **Efeito:** Duas participações na mesma campanha, dois números diferentes para a mesma venda.

### Catálogo (checkout direto)

1. CatalogoVendaService.registrarVendaCatalogo → Hive, pedido Firestore, **CampaignEngineService.onVendaConcluida**
2. Cupom roleta salvo em `clientes_catalogo/{email}/cupons`
3. **Efeito:** Uma participação por venda (correto neste fluxo).

### Catálogo (pedido pendente → confirmação com pagamento)

1. CatalogoVendaService.finalizarPedidoComPagamento → venda, pedido, **CampaignEngineService.onVendaConcluida**
2. **Efeito:** Uma participação (correto).

### Pós-pagamento (webhook Mercado Pago)

1. posPagamento.js `processarPosPagamento` → `registrarParticipacaoCampanha`
2. Usa schema **valorX** ( múltiplos números por R$ X), grava `numeros` array, `data`, `nomeCliente`
3. PosPagamentoService (Dart) também chama SorteioNumeroService — **se usado em algum fluxo**, pode duplicar.

### Globo da Sorte

1. Carrega participantes orderBy `dataParticipacao`
2. Participantes sem `dataParticipacao` (SorteioNumeroService, posPagamento.js) não entram na ordenação ou podem falhar.
3. Sorteia e salva em `historico_sorteios` com `data`.

---

## 5. Erros encontrados

### 5.1 Críticos

| # | Localização | Causa | Impacto | Severidade |
|---|-------------|-------|---------|------------|
| 1 | `lib/screens/nova_venda_modal.dart` L1318–1324 | Nova venda chama VendasService (CampaignEngine) E SorteioNumeroService | Duplicidade de participação: mesma venda gera 2 números, 2 registros. Cliente pode ganhar com número que não deveria existir. | Crítica |
| 2 | `lib/services/numero_sorte_service.dart` L17 | `where('ativo', isEqualTo: true)` — campo correto é `ativa` | NumeroSorteService nunca encontra campanhas se documento usar `ativa`. Globo e histórico não funcionam. | Crítica |
| 3 | `lib/screens/roleta_sorte_screen.dart` vs `roleta_sorte_config_screen.dart` | RoletaSorteScreen lê `campanhas_sorteio_config/roleta`; ConfigScreen lê/escreve `config/roleta_sorte` | Configurações divergentes. Admin configura em uma tela e a roleta APK usa outra. | Crítica |
| 4 | `lib/services/campaign_engine_service.dart` L404–408 | cancelarParticipacao busca só `vendaId`, não `pedidoId` | Participações salvas com pedidoId (CampaignEngine) não são canceladas ao estornar. | Crítica |
| 5 | Schemas de participantes | CampaignEngine: dataParticipacao, numeroSorte, pedidoId. SorteioNumero: criadoEm, numeroSorte. posPagamento.js: data, numeros[]. CampanhasSorteio: numeros[], criadoEm | CampanhaParticipantesScreen espera `numeros` e `criadoEm`. Histórico espera `dataParticipacao`. Globo espera `numeroSorte`. Dados ficam invisíveis ou quebram ordenação. | Crítica |

### 5.2 Médios

| # | Localização | Causa | Impacto |
|---|-------------|-------|---------|
| 6 | `functions/gerarCupomNumeroSorte.js` L121–128 | Participante salvo com `data` em vez de `dataParticipacao` | Histórico/Globo com orderBy dataParticipacao não inclui esses participantes. |
| 7 | `lib/services/campanhas_sorteio_service.dart` L256–265 | salvarHistoricoSorteio usa `registradoEm` | Historico tab usa orderBy `data`. Documentos com `registradoEm` não entram. |
| 8 | posPagamento.js L88 | `lojaId = 'masterpalm'` hardcoded | Webhook não funciona para outras lojas. |
| 9 | CampanhaParticipantesScreen L30 | orderBy `criadoEm` | Participantes do CampaignEngine não têm criadoEm; têm dataParticipacao. Lista vazia ou erro de índice. |
| 10 | CupomPremio (Hive) vs CupomCliente (Firestore) | Dois modelos de cupom | Risco de inconsistência; CupomPremio pode ser legado não utilizado. |

### 5.3 Leves

| # | Localização | Causa | Impacto |
|---|-------------|-------|---------|
| 11 | GloboSorteService | API externa não configurada/ usada | Sem impacto no fluxo atual. |
| 12 | RoletaSorteScreen L88–113 | _girarRoleta não verifica se já girou nesta compra | Pode permitir múltiplos giros (depende do fluxo de uso). |
| 13 | Vários catch sem rethrow | Erros engolidos em try/catch | Dificulta diagnóstico. |

---

## 6. Erros silenciosos encontrados

### 6.1 Try/catch que engolem exceção

- `lib/services/catalogo_venda_service.dart` L724–726: catch em CampaignEngine não propaga erro.
- `lib/services/vendas_service.dart` L600–603: catch em CampaignEngine não propaga.
- `lib/services/pos_pagamento_service.dart` L166–170: catch ao marcar posPagamentoProcessado falha silenciosamente.
- `lib/services/campaign_engine_service.dart` L396–398: `_verificarDuplicidade` retorna `false` em erro — permite continuar e possivelmente duplicar.

### 6.2 Retorno silencioso sem feedback

- `CampaignEngineService._getCampanhaAtiva` retorna `null` em erro (L352).
- `NumeroSorteService.getCampanhaAtiva` retorna `null` em erro (L32) — sem log.
- `SorteioNumeroService.registrarNumeroEmCampanhas` retorna `false` silenciosamente se nenhuma campanha.

### 6.3 Null tratado como fluxo válido

- `idVenda.isEmpty` em CampaignEngine (L189): gera participação com vendaId vazio; comentário diz "usar timestamp" mas não implementa.
- Participantes sem `dataParticipacao`: orderBy pode falhar ou excluir documentos.

### 6.4 Campos não serializados / incompatíveis

- CampaignEngine toMap usa `dataParticipacao`; listarParticipacoes usa orderBy `criadoEm` (L427) — campo não existe no toMap.
- CampanhasSorteioService.salvarHistoricoSorteio grava `registradoEm`; Historico tab usa orderBy `data`.

### 6.5 Race conditions e duplicidade

- Clique duplo em "Finalizar venda" pode executar _executarFinalizacaoVenda duas vezes.
- `_processandoCheckout` em carrinho_sheet_web existe, mas nova_venda_modal não tem proteção equivalente.

### 6.6 setState após dispose / mounted

- Vários `if (!mounted) return` após await — uso correto. Porém, `_salvarVendaEmBackground` não verifica mounted antes de callback.

### 6.7 Query Firestore fraca ou ambígua

- NumeroSorteService: `ativo` em vez de `ativa`.
- Index para `participantes` com orderBy `dataParticipacao` pode não existir (não está em firestore.indexes.json).

### 6.8 Inconsistência de ID

- posPagamento usa `externalReference` como vendaId; pode não corresponder ao venda.key do Hive no catálogo.

---

## 7. Problemas de sincronização

### 7.1 Com Nova Venda

- **Duplicidade:** Nova venda registra participação duas vezes (CampaignEngine + SorteioNumero).
- **IDs:** VendasService usa `venda.key.toString()`; CampaignEngine salva como `pedidoId`. Consistente.
- **Pré-pedido:** Pré-pedido confirmado gera venda manual; participação vem do momento da criação da venda, não da confirmação do pré-pedido. Se vendedor criar venda a partir do pré-pedido, CampaignEngine é chamado na criação da venda.

### 7.2 Com Pré-pedidos

- Pré-pedido não gera participação diretamente. Participação surge quando a venda é criada (nova venda ou conversão).
- Fluxo: Cliente faz pré-pedido → Vendedor confirma com vendaId → A venda já deve ter sido criada antes, com participação. Sem integração explícita pré-pedido → campanha.

### 7.3 Com Catálogo

- Catálogo usa CampaignEngineService corretamente (uma participação por venda).
- Roleta no catálogo usa `config/roleta_sorte`; cupons vão para `clientes_catalogo/cupons`.
- Risco: Catálogo público pode exibir campanha ativa enquanto lista de participantes usa schema antigo e mostra dados incorretos.

---

## 8. Persistência e consistência de dados

### Hive

- Campanhas/sorteios não usam Hive.
- CupomPremio (Hive, typeId 14) — possível legado.
- Vendas, clientes, produtos usam Hive por loja.

### Firestore

- **Campanhas:** `lojas/{lojaId}/campanhas_sorteio`
- **Participantes:** `campanhas_sorteio/{id}/participantes` — schemas mistos.
- **Histórico sorteios:** `campanhas_sorteio/{id}/historico_sorteios` — campos `data` e `registradoEm` usados por escritores diferentes.
- **Roleta:** `config/roleta_sorte` e `campanhas_sorteio_config/roleta` (duplicado).
- **Cupons:** `cupons_clientes`, `estoque_clientes`, `clientes_catalogo/{email}/cupons`.

### Fonte da verdade

- Não há uma única fonte. Múltiplos serviços escrevem participantes com estruturas diferentes.
- Roleta tem duas fontes de configuração.

---

## 9. Divergências de regra de negócio

### Regras ausentes

- Validação de pré-pedido para participação em campanha (se pré-pedido deve ou não participar).
- Regra explícita: uma venda = uma participação. Hoje não é garantido.

### Regras conflitantes

- **Valor mínimo vs valorX:** CampanhasSorteioService e posPagamento usam valorX (múltiplos números por valor). CampaignEngine e SorteioNumero usam valor mínimo (1 número). Campanhas criadas com valorX podem não refletir isso no CampaignEngine.
- **Campo ativo/ativa:** Diverge entre serviços.

### Regras incompletas

- Cancelamento de participação não cobre `pedidoId`.
- Histórico de sorteios com dois formatos de documento (`data` vs `registradoEm`).

---

## 10. Avaliação arquitetural

### Pontos fortes

- CampaignEngineService centraliza lógica de participação (quando usado sozinho).
- Idempotência por vendaId no CampaignEngine (quando não duplicado por outro serviço).
- Separação roleta vs campanha no conceito (roleta = prêmio imediato; campanha = sorteio futuro).

### Pontos fracos

- Quatro caminhos de registro de participação com schemas diferentes.
- Duas configurações de roleta (config vs campanhas_sorteio_config).
- Lógica de negócio misturada em telas (nova_venda_modal).
- Ausência de camada de repositório única para participantes.

### Dívida técnica

- Unificar schema de participantes.
- Remover SorteioNumeroService da nova venda ou migrar tudo para CampaignEngine.
- Consolidar config da roleta em um único documento.
- Padronizar ativo/ativa e dataParticipacao/criadoEm/data.

---

## 11. Classificação de saúde por módulo

| Módulo | Nota (0–10) | Critérios |
|--------|-------------|-----------|
| Campanhas | 5 | Criação/edição ok; participantes com schema fragmentado; telas divergentes. |
| Sorteios | 4 | Duplicidade crítica na nova venda; múltiplos schemas; NumeroSorteService com bug `ativo`. |
| Roleta da Sorte | 5 | Funcional, mas duas configs; cupons em múltiplos destinos. |
| Globo da Sorte | 6 | Funcional quando participantes têm schema novo; depende de NumeroSorteService (bug ativo). |

---

## 12. Fila priorizada de correções

### Prioridade altíssima
1. Remover chamada a SorteioNumeroService em nova_venda_modal (manter apenas CampaignEngine).
2. Corrigir NumeroSorteService: `ativo` → `ativa`.
3. Unificar config da roleta: um único documento (preferir `config/roleta_sorte`).

### Prioridade alta
4. Corrigir cancelarParticipacao para buscar também por `pedidoId`.
5. Unificar schema de participantes (dataParticipacao, numeroSorte, pedidoId em todos os fluxos).
6. Corrigir salvarHistoricoSorteio para usar campo `data` (ou ajustar query do histórico).
7. Corrigir gerarCupomNumeroSorte e posPagamento.js para usar schema unificado.

### Prioridade média
8. Remover lojaId hardcoded em posPagamento.js.
9. Atualizar CampanhaParticipantesScreen para schema novo (numeroSorte, dataParticipacao).
10. Revisar índices Firestore para participantes (dataParticipacao).

### Prioridade baixa
11. Adicionar proteção contra clique duplo em finalizar venda.
12. Padronizar tratamento de erros (evitar catch que engole exceção).
13. Documentar diferença roleta vs campanha.

---

## 13. Conclusão executiva

### O que está bom
- CampaignEngineService desenhado para ser o ponto central de participação.
- Catálogo e pré-pedido integram com campanha quando a venda é criada.
- Roleta e campanha estão separadas conceitualmente.
- Globo da Sorte funciona quando os dados estão no schema correto.

### O que está quebrado
- **Duplicidade na nova venda:** Duas participações por venda, dois números.
- **NumeroSorteService:** Uso de `ativo` impede encontrar campanhas com `ativa`.
- **Roleta:** Duas configs distintas (APK vs web/config screen).

### O que está mascarado
- Participantes com schemas antigos (numeros[], criadoEm) não aparecem corretamente em todas as telas.
- Histórico com `registradoEm` não é exibido na aba que usa orderBy `data`.

### O que pode explodir em produção
- Cliente com dois números para a mesma compra — risco de reclamação e sorteio incorreto.
- Globo da Sorte vazio ou com erro quando NumeroSorteService não encontra campanha.
- Configuração de roleta feita em uma tela não refletida na outra.

### O que corrigir primeiro
1. Remover duplicidade na nova venda (SorteioNumeroService).
2. Corrigir NumeroSorteService (`ativa`).
3. Unificar schema de participantes e configuração da roleta.

---

*Relatório gerado com base em análise estática do código. Recomenda-se validação com testes de integração e em ambiente de homologação.*
