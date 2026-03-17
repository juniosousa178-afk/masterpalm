# Análise: Tela de Fretes e Cupons

> **Arquivo principal:** `lib/screens/fretes_cupons_screen.dart`  
> **Nota:** O menu lateral usa `FretesCuponsScreenV2`; a rota `/fretes_cupons` usa `FretesCuponsScreen`.

---

## 1. O que a tela faz

A tela **Fretes e Cupons** permite configurar:

### 1.1 Provedor de frete
- **Manual** – fretes fixos (ex.: Retirada R$ 0, Entrega R$ 10)
- **Correios** – API própria (usuário/senha)
- **Melhor Envio** – token de API
- **Frenet** – token de API

Para provedores automáticos: CEP de origem, peso da embalagem e credenciais específicas.

### 1.2 Fretes manuais
- Lista de opções (nome + valor em R$)
- Ex.: "Retirada", "Entrega local"
- Usados no catálogo público quando o provedor é manual

### 1.3 Embalagens
- Tipos de embalagem (nome, peso em g, prioridade, dimensões)
- Usadas no cálculo de frete automático

### 1.4 Cupons de desconto
- Código, tipo (percentual ou valor fixo)
- Onde aplicar: produtos ou total
- Opção de frete grátis

### 1.5 Fluxo de dados
- **Hive:** `config` e `config_<slug>` (local)
- **Firestore:** `lojas/<slug>/draft_config/config` e `lojas/<slug>/config/fretes`
- **CloudSyncService:** push do perfil para sincronizar com o catálogo

---

## 2. Erros a corrigir

### 2.1 Embalagens: perda de dimensões ao carregar do Hive
**Local:** `_bootstrap()` linhas 214–231

Ao carregar embalagens do Hive, só são lidos `id`, `nome`, `peso` e `tamanho`. Os campos `altura`, `largura` e `comprimento` não são carregados.

```dart
// Atual – falta altura, largura, comprimento
return {
  'id': e['id']?.toString() ?? '',
  'nome': e['nome']?.toString() ?? '',
  'peso': ...,
  'tamanho': ...,
};
```

**Correção:** Incluir `altura`, `largura` e `comprimento` no mapeamento.

---

### 2.2 `_descricaoPrioridade`: possível erro com lista vazia
**Local:** linha 1110

```dart
_embalagens.map((e) => e['tamanho'] as int).reduce((a, b) => a > b ? a : b)
```

Se `_embalagens` estiver vazia, `reduce` lança exceção.

**Correção:** Tratar lista vazia ou usar `fold` com valor inicial.

---

### 2.3 `_descricaoPrioridade`: cast de `tamanho`
**Local:** linha 1107

`e['tamanho']` pode vir como `num` do Hive/JSON. O cast `as int` pode falhar.

**Correção:** Usar `(e['tamanho'] as num?)?.toInt() ?? 0`.

---

### 2.4 API Correios em HTTP
**Local:** linha 358

```dart
'http://ws.correios.com.br/calculador/CalcPrecoPrazo.asmx/...'
```

Uso de HTTP pode ser bloqueado em produção (mixed content, políticas de segurança).

**Correção:** Usar HTTPS se disponível ou documentar a restrição.

---

### 2.5 Inconsistência de telas
O menu usa `FretesCuponsScreenV2`, mas a rota `/fretes_cupons` usa `FretesCuponsScreen`. Duas telas diferentes para a mesma funcionalidade.

**Correção:** Padronizar para uma única tela (V2 ou unificar).

---

### 2.6 Cupons: sem sincronização com Firestore
Os cupons são salvos em Hive e `draft_config`, mas não na collection `lojas/<slug>/cupons` usada pelo `CupomDescontoService`. O catálogo público faz fallback para essa collection quando `cfg['cupons']` está vazio.

**Problema:** Cupons criados na tela podem não aparecer no catálogo se o fluxo depender da collection Firestore.

**Correção:** Sincronizar cupons com `lojas/<slug>/cupons` ou garantir que o config (Hive/draft) seja sempre a fonte principal.

---

### 2.7 Adicionar frete: validação fraca
**Local:** `_buildPaneFretesManuais()` linha 747

Ao adicionar frete, só se exige `nome.isEmpty`. Valor vazio é aceito (vira 0).

**Correção:** Validar valor ou avisar quando for 0.

---

### 2.8 LayoutBuilder com `action` nulo
**Local:** `_Section` linha 1150

```dart
if (action == null) return titleWidget;
```

Quando `action` é nulo, o `LayoutBuilder` retorna só o título. O `child` continua sendo exibido, mas o layout pode ficar inconsistente em alguns casos.

---

## 3. Melhorias sugeridas

### 3.1 UX / Interface

| # | Melhoria | Descrição |
|---|----------|-----------|
| 1 | Loading nos botões | Mostrar spinner ao testar APIs (Melhor Envio, Frenet, Correios) e ao salvar |
| 2 | Máscara de CEP | Formatar CEP como `00000-000` |
| 3 | Confirmação ao excluir | Diálogo antes de remover frete, cupom ou embalagem |
| 4 | Estado vazio | Mensagens claras quando não há fretes, cupons ou embalagens |
| 5 | Feedback de salvamento | Snackbar de sucesso/erro mais visível e informativo |

### 3.2 Funcionalidades

| # | Melhoria | Descrição |
|---|----------|-----------|
| 6 | Editar cupom | Permitir edição em vez de só adicionar/remover |
| 7 | Editar frete manual | Editar itens da lista de fretes |
| 8 | Editar embalagem | Editar embalagens existentes |
| 9 | Data de validade do cupom | Campo opcional `dataFim` para cupons |
| 10 | Valor mínimo do cupom | Campo opcional `valorMinimo` para cupom |
| 11 | Toggle ativo/inativo | Ativar/desativar cupom sem excluir |

### 3.3 Validações

| # | Melhoria | Descrição |
|---|----------|-----------|
| 12 | Validar CEP | Verificar formato e existência (ex.: ViaCEP) |
| 13 | Validar percentual | Limitar cupom percentual a 0–100% |
| 14 | Validar dimensões | Garantir altura, largura e comprimento > 0 ao adicionar embalagem |

### 3.4 Acessibilidade e responsividade

| # | Melhoria | Descrição |
|---|----------|-----------|
| 15 | Semantics | Labels para leitores de tela em botões e campos |
| 16 | Layout responsivo | Em tablets/desktop, usar grid ou colunas para formulários |
| 17 | Scroll em diálogos | Garantir que o guia de configuração role em telas pequenas |

### 3.5 Integração e dados

| # | Melhoria | Descrição |
|---|----------|-----------|
| 18 | Sincronizar cupons com Firestore | Criar/atualizar em `lojas/<slug>/cupons` ao salvar |
| 19 | Carregar cupons do Firestore | Fallback para cupons da collection quando config vazio |
| 20 | Indicador de provedor configurado | Badge “API configurada” quando token/credenciais estão preenchidos |

### 3.6 Tratamento de erros

| # | Melhoria | Descrição |
|---|----------|-----------|
| 21 | Mensagens de erro amigáveis | Traduzir erros de API (timeout, 401, rede) |
| 22 | Tratamento de exceções | Try/catch em operações assíncronas com feedback ao usuário |

---

## 4. Resumo de prioridades

### Alta (erros)
1. Carregar `altura`, `largura` e `comprimento` das embalagens no bootstrap  
2. Proteger `_descricaoPrioridade` contra lista vazia  
3. Tratar `tamanho` como `num` antes de usar como `int`  
4. Unificar ou documentar uso de FretesCuponsScreen vs V2  

### Média (melhorias importantes)
5. Loading nos botões de teste e salvar  
6. Máscara de CEP  
7. Confirmação ao excluir  
8. Sincronizar cupons com Firestore  
9. Editar cupom/frete/embalagem  

### Baixa (nice to have)
10. Data de validade e valor mínimo do cupom  
11. Semantics e layout responsivo  
12. Mensagens de erro mais amigáveis  

---

## 5. Arquivos relacionados

- `lib/screens/fretes_cupons_screen.dart` – tela principal
- `lib/screens/fretes_cupons_screen_v2.dart` – tela usada no menu
- `lib/screens/public_catalog/catalog_config_service.dart` – `parseFretes`, `parseCupons`
- `lib/services/cupom_desconto_service.dart` – cupons no Firestore
- `lib/services/cloud_sync_service.dart` – sincronização
- `lib/utils/moeda_input_formatter.dart` – formatação de moeda
