# Validação Manual — Motor de Crescimento IA e IA do Catálogo

Documento de validação e checklist para os módulos **Motor de Crescimento IA (Etapa 2)** e **IA do Catálogo (Etapa 1)**.  
Foco em teste manual, cenários esperados, fallbacks e ajustes de UX, sem alterar núcleo do sistema.

---

## 1. Checklist de Teste Manual

### 1.1 Motor de Crescimento IA

| # | Cenário | Passos | Resultado esperado | Fallback / nota |
|---|---------|--------|--------------------|-----------------|
| 1 | Abrir painel | Menu → IA → Motor de Crescimento IA | Tela carrega; mostra métricas (ticket médio, produtos parados, estoque baixo) e lista de oportunidades | Loja vazia: "Nenhuma loja ativa" |
| 2 | Painel sem oportunidades | Entrar em loja sem produtos parados ou estoque baixo | Card "Tudo em ordem! Nenhuma oportunidade no momento." com ícone ✓ e mensagem clara | — |
| 3 | Painel com oportunidades | Loja com produtos parados (30 dias sem venda) ou estoque baixo | Lista agrupada por tipo (Produtos parados / Estoque baixo) com botão "Ver sugestão" | — |
| 4 | Pull-to-refresh | Arrastar para baixo no painel | Lista recarrega e oportunidades atualizam | — |
| 5 | Abrir detalhe (produto parado) | Clicar em "Ver sugestão" em um produto parado | Tela "Sugestão de campanha" com: card da oportunidade, sugestão (promoção, cupom sugerido), 3 blocos de texto (promoção, WhatsApp, Instagram) e botão "Executar campanha" desabilitado | — |
| 6 | Abrir detalhe (estoque baixo) | Clicar em "Ver sugestão" em produto com estoque baixo | Mesma estrutura; sugestão de urgência/reposição (sem percentual de desconto) | — |
| 7 | Carregamento da sugestão | Ao abrir detalhe | Indicador "Gerando sugestão…" até retorno | — |
| 8 | Erro ao gerar sugestão | Sem conexão ou erro no AiLojaService | Mensagem "Não foi possível gerar a sugestão."; botão "Voltar" para retornar ao painel | Fallback local sempre existe |
| 9 | Copiar texto | Clicar no ícone copiar em qualquer bloco de texto | Texto copiado; SnackBar "X copiado" | — |
| 10 | Botão Executar campanha | Clicar ou passar o mouse no botão | Nada (botão desabilitado); tooltip "Em breve" | — |
| 11 | Voltar | Botão voltar no AppBar | Retorna ao painel de oportunidades | — |

### 1.2 IA do Catálogo

| # | Cenário | Passos | Resultado esperado | Fallback / nota |
|---|---------|--------|--------------------|-----------------|
| 1 | Chat desabilitado | Abrir catálogo com `catalogo_ia_habilitado: false` | Nenhum FAB de chat visível | Widget retorna SizedBox.shrink |
| 2 | Chat habilitado | Configurar `catalogo_ia_habilitado: true` no config da loja | FAB (ícone de chat) no canto inferior direito | — |
| 3 | Abrir chat | Clicar no FAB | Painel de chat abre; mensagem inicial do assistente com exemplos | — |
| 4 | Perguntar "qual é mais barato?" | Digitar e enviar | Resposta com produtos ordenados por preço; chips de produtos abaixo | — |
| 5 | Perguntar "tem colar?" | Digitar e enviar | Resposta com produtos que contêm "colar" em nome/categoria/descrição; chips de produtos | — |
| 6 | Perguntar "promoção" | Digitar e enviar | Resposta com produtos em promoção (`emPromocao: true`); chips | — |
| 7 | Perguntar termo inexistente | Ex.: "xyz123" | Mensagem: "Não encontrei produtos com essa busca. Tente termos como nome, categoria ou \"mais barato\"." | — |
| 8 | Enviar pergunta vazia | Deixar campo vazio e enviar | Campo não envia (ignora) | — |
| 9 | Toque em chip de produto | Clicar em um chip de produto sugerido | Callback `onProdutoTap` chamado (se configurado); navegação depende da implementação | — |
| 10 | Botão "Falar no WhatsApp" | Quando há resposta com produtos | Botão visível; placeholder (onPressed vazio) | Etapa futura |
| 11 | Fechar chat | Clicar no X | Painel fecha; volta ao FAB | — |
| 12 | Chat com catálogo vazio | Loja sem produtos | Perguntas retornam "Não encontrei produtos…" | — |

---

## 2. Cenários Principais e Fallbacks

### 2.1 Motor de Crescimento IA

| Cenário | Resultado esperado | Fallback |
|---------|--------------------|----------|
| **Loja sem sessão** | "Nenhuma loja ativa. Configure a loja nas Configurações." | Rota usa `_lojaIdRoute` |
| **Sem oportunidades** | Card "Tudo em ordem! Nenhuma oportunidade no momento." | — |
| **IA indisponível** | Sugestão ainda aparece; textos vêm do fallback local (ex.: "🔥 Promoção especial! X com desconto.") | MotorCrescimentoSugestorService usa fallbacks |
| **Erro genérico na sugestão** | "Não foi possível gerar a sugestão." | FutureBuilder.hasError |

### 2.2 IA do Catálogo

| Cenário | Resultado esperado | Fallback |
|---------|--------------------|----------|
| **Chat desabilitado** | Widget não aparece | `habilitado: false` |
| **Catálogo vazio** | Perguntas retornam "Não encontrei produtos…" | CatalogIaService |
| **Busca sem resultado** | "Não encontrei produtos com essa busca. Tente termos como nome, categoria ou \"mais barato\"." | CatalogIaService.responder |
| **Produtos sem preço** | Chips aparecem; preço vazio ou "—" | CatalogIaService._fmtPreco |

---

## 3. Ajustes de UX Sugeridos (Seguros)

### 3.1 Motor de Crescimento IA

| Sugestão | Tipo | Prioridade | Descrição |
|----------|------|------------|-----------|
| Mensagem estado vazio | Microcopy | Baixa | Melhorar "Nenhuma oportunidade detectada" para "Tudo em ordem! Nenhuma oportunidade no momento." |
| Erro com ação | Feedback | Baixa | Na tela de erro da sugestão, adicionar botão "Tentar novamente" ou "Voltar" |
| Botão Executar | Microcopy | Baixa | Tooltip ou texto: "Em breve" para indicar que está desabilitado |
| SnackBar copiado | Feedback | Baixa | Manter "X copiado" (já ok) |

### 3.2 IA do Catálogo

| Sugestão | Tipo | Prioridade | Descrição |
|----------|------|------------|-----------|
| Placeholder do campo | Microcopy | Baixa | Manter "Pergunte sobre produtos…" (já adequado) |
| Mensagem inicial | Microcopy | Baixa | Incluir exemplo: "qual está em promoção?" |
| Estado sem resultados | Microcopy | Baixa | Manter mensagem atual (já clara) |
| Botão WhatsApp | Feedback | Baixa | Manter desabilitado; tooltip "Em breve" (opcional) |

---

## 4. Aplicação de Ajustes (Opcional)

Aplicar apenas ajustes muito pequenos e seguros:

- [x] Motor: mensagem de estado vazio mais amigável — **aplicado**
- [x] Motor: botão "Voltar" na tela de erro da sugestão — **aplicado**
- [x] Motor: tooltip "Em breve" no botão Executar — **aplicado**
- [x] Catálogo: adicionar "qual está em promoção?" na mensagem inicial — **aplicado**

---

## 5. Validação Final

| Item | Motor de Crescimento | IA do Catálogo |
|------|----------------------|----------------|
| Sem alteração de regra | ✅ | ✅ |
| Sem automação real | ✅ | ✅ |
| Sem Firestore/Sync/auth | ✅ | ✅ |
| Estados vazios tratados | ✅ | ✅ |
| Mensagens de fallback | ✅ | ✅ |
| Botões desabilitados claros | ✅ (Executar) | ✅ (WhatsApp placeholder) |
| Feedback ao copiar | ✅ | — |
| Fluxo conservador | ✅ | ✅ |

---

**Versão:** 1.0  
**Data:** Mar 2025  
**Escopo:** Validação e UX. Sem alterar núcleo do sistema.
