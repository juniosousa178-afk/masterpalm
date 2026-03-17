# Análise de Erros e Riscos – Uso Multiusuário Simultâneo

**Data:** 12/02/2026  
**Objetivo:** Identificar erros atuais e potenciais quando o app é usado por vários usuários/dispositivos ao mesmo tempo.

---

## 1. Arquitetura Geral

- **Hive:** cache local por dispositivo (cada celular tem seu próprio banco)
- **Firestore:** fonte central compartilhada
- **Sync:** manual (ao abrir telas) ou após login; não existe tempo real

### Pontos críticos

- Sem listeners em tempo real do Firestore; dados podem ficar desatualizados
- Cada dispositivo mantém uma cópia local que pode divergir da central

---

## 2. Estoque e Vendas

### 2.1 Transação de estoque (Firestore)

**Situação:** `EstoqueTransactionService` usa `runTransaction` para baixa de estoque.

- Várias vendas simultâneas do mesmo produto são tratadas corretamente
- Estoque insuficiente é validado na transação

### 2.2 Fallback local (Hive)

**Problema:** Quando o Firestore falha (“Produto não encontrado”), o `VendasService` baixa o estoque só no Hive.

- A venda conclui localmente
- O Firestore não é atualizado
- Em outro dispositivo ou na web, o estoque continua o mesmo
- Risco: vender mais do que existe em estoque (sobrevenda)

**Sugestão:** Tratar a falha no Firestore como erro e não concluir a venda, em vez de fallback local.

### 2.3 Coleções de produtos

- `produtos`: usada por `EstoqueTransactionService` (baixa de estoque)
- `estoque_produtos`: usada por `ProdutosFirestoreService` (sync Hive ↔ Firestore)

Se um produto existir em apenas uma dessas coleções, podem ocorrer:

- Erro “Produto não encontrado”
- Falha de sincronização

---

## 3. Roleta da Sorte

### 3.1 Contadores sem transação

**Arquivo:** `roleta_web_widget_v3.dart`

```dart
updates['totalVendas'] = FieldValue.increment(1);
updates['vendasDesdePremio'] = ganhou ? 0 : FieldValue.increment(1);
await docRef.update(updates);
```

- `FieldValue.increment` é atômico no Firestore
- Mas a decisão “ganhou ou não” é feita antes, com base em `_vendasDesdePremio` em memória

**Problema:** Dois usuários podem girar ao mesmo tempo:

1. Ambos leem `vendasDesdePremio = 9` (frequência 10)
2. Ambos acham que ganharam
3. Ambos incrementam e atualizam `premios`

**Risco:** Mais prêmios concedidos do que o configurado pela frequência.

**Sugestão:** Usar `runTransaction` para ler `vendasDesdePremio`, decidir se ganhou e atualizar em uma única operação.

### 3.2 Código do cupom

- `_gerarCodigoCupom()` usa `Random()` (8 caracteres)
- Colisão improvável, mas possível
- Se colidir, o segundo cupom sobrescreve o primeiro no Firestore

**Sugestão:** Usar `doc().id` do Firestore ou UUID para garantir unicidade.

---

## 4. Campanhas e Sorteio

### 4.1 Geração de números

**Arquivo:** `campanhas_sorteio_service.dart`

- `_gerarNumeros` usa `runTransaction` no contador
- Geração de números da sorte é atômica

### 4.2 Registro de participação

- Várias vendas simultâneas podem registrar participação ao mesmo tempo
- Possível competição em leitura/escrita de documentos de campanha

---

## 5. Clientes

### 5.1 ID do cliente

**Arquivo:** `clientes_firestore_service.dart`

```dart
final clienteId = cliente.telefone.replaceAll(...) + '_' + cliente.nome.toLowerCase().replaceAll(' ', '_');
```

**Problemas:**

- Mesmo telefone + nome → mesmo ID; ok para deduplicação
- Telefone vazio ou igual entre clientes diferentes → risco de colisão
- Dois vendedores criando o mesmo cliente ao mesmo tempo podem gerar IDs diferentes (ex.: Hive key vs. telefone+nome)

### 5.2 Sync Firestore → Hive

- Match por `id` ou `telefone` + `nome`
- Clientes duplicados no Firestore podem gerar inconsistência no Hive

---

## 6. Produtos

### 6.1 Sync Firestore → Hive

**Arquivo:** `produtos_firestore_service.dart`

- Busca por `idFirebase` e depois por `slug`
- `firstWhere` lança exceção se houver mais de um produto com mesmo slug
- Produtos duplicados no Firestore podem quebrar o sync

### 6.2 Produtos em múltiplas coleções

- `produtos`, `estoque_produtos`, `draft_produtos`, `produtos` (live)
- Fluxos diferentes (app, catálogo, estoque) usam coleções diferentes
- Risco de inconsistência entre coleções

---

## 7. Vendas

### 7.1 Criação de venda

- Venda criada no Hive e depois sincronizada no Firestore
- `idFirebase` preenchido após sync
- Várias vendas simultâneas obtêm IDs diferentes no Firestore

### 7.2 Sync Firestore → Hive

- Evita duplicata checando `idFirebase`
- Limite de 100 vendas na sincronização
- Vendas antigas podem não ser trazidas para o Hive

---

## 8. Pré-pedidos e Pedidos Pendentes

### 8.1 Pedidos pendentes

- Criados com `add()` no Firestore
- ID automático; sem conflito direto
- Conclusão do pedido pode competir com baixa de estoque em outra venda

### 8.2 Catálogo web vs. app

- Catálogo: valida estoque no Firestore ou Hive
- App: usa transação no Firestore ou Hive (fallback)
- Dois canais podem tentar vender o mesmo estoque ao mesmo tempo
- Transação no Firestore protege o app; catálogo precisa garantir validation em transação ou regras

---

## 9. Hive e Sincronização

### 9.1 Última escrita vence

- Sync geralmente sobrescreve dados locais com os do Firestore
- Alterações feitas localmente antes do sync podem ser perdidas

### 9.2 Momento do sync

- Clientes: ao abrir `ClientesScreen`
- Vendas: ao abrir `VendasScreen`
- Produtos: ao abrir Estoque, Home (import), etc.
- Sem sync em tempo real; janelas longas de divergência

### 9.3 Conflitos de merge

- Sync de clientes faz merge por ID
- Sync de produtos atualiza existente ou adiciona novo
- Sem estratégia explícita de resolução de conflitos (ex.: timestamp, last-write-wins definido)

---

## 10. Outros Pontos

### 10.1 Contador de numeração (sorteio)

- Transação atômica
- Uso correto para múltiplos usuários

### 10.2 Sessão e loja

- `StoreResolverService` resolve loja por usuário
- Vendedores com lojas diferentes não compartilham dados
- Mesma loja em vários dispositivos: compartilham Firestore, mas Hive é local

### 10.3 Firestore Rules

- Precisam garantir que:
  - Apenas usuários autorizados alterem estoque
  - Regras de estoque imponham validações consistentes com o backend

---

## 11. Resumo de Prioridades

| Prioridade | Problema | Impacto | Mitigação sugerida |
|-----------|----------|---------|--------------------|
| ALTA | Fallback local de estoque sobrescreve sem atualizar Firestore | Sobrevenda | Remover fallback ou tratar como erro e não concluir venda |
| ALTA | Roleta: decisão “ganhou” sem transação | Prêmios a mais | Usar `runTransaction` para ler e atualizar contadores |
| MÉDIA | Cliente ID: telefone vazio ou duplicado | Conflitos / duplicação | Usar UUID ou ID do Firestore quando telefone vazio |
| MÉDIA | Sync não é em tempo real | Dados desatualizados | Avaliar listeners do Firestore para dados críticos |
| BAIXA | Cupom: possível colisão de código | Cupom sobrescrito | Usar ID único (ex.: UUID) |
| BAIXA | Produtos em múltiplas coleções | Inconsistência | Padronizar uso de `produtos` e `estoque_produtos` |

---

## 12. Recomendações Gerais

1. **Estoque:** Sempre usar transação no Firestore; evitar fallback que baixa só no Hive.
2. **Roleta:** Envolver leitura e atualização de contadores em `runTransaction`.
3. **Clientes:** Garantir IDs únicos (UUID ou documento do Firestore) quando identificadores fracos (ex.: telefone vazio).
4. **Sync:** Considerar listeners em tempo real para produtos, vendas e clientes.
5. **Coleções:** Documentar e padronizar qual coleção é fonte de verdade para cada entidade.
6. **Testes:** Simular múltiplos usuários vendendo o mesmo produto e girando a roleta ao mesmo tempo.

---

*Documento gerado com base na análise do código em 12/02/2026.*
