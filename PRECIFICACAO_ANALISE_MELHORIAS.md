# Análise: Tela de Precificação Universal

> **Arquivo:** `lib/screens/precificacao_universal_screen.dart`

---

## 1. Erros identificados

### 1.1 **Campo "Preço Pretendido" perde valor ao rolar a lista**
**Local:** linhas 663–679

O `TextField` de "Preço Pretendido" não usa `controller` nem `initialValue`. Em listas com `SliverChildBuilderDelegate`, os itens são recriados ao rolar. Ao sair da tela e voltar, o valor digitado pode ser perdido.

```dart
TextField(
  // Sem controller nem initialValue
  onChanged: (value) => setState(() => item['precoPretendido'] = parseCentavos(value)),
  ...
)
```

**Sugestão:** Usar um `TextEditingController` por item (ex.: `Map<String, TextEditingController>`) ou `TextFormField` com `initialValue` e `key: ValueKey(item['nome'])` para manter o valor.

---

### 1.2 **Produto novo sem `lojaId`**
**Local:** linhas 279–294

Ao criar um novo `Produto` com `estoqueBox!.add()`, o `lojaId` não é definido. O modelo usa `lojaId = ''` como padrão. A sincronização com Firestore pode depender desse campo.

```dart
Produto(
  ...
  lojaId = '',  // implícito - não definido
)
```

**Sugestão:** Obter `lojaId` em `_init` e passar ao criar o produto: `lojaId: lojaId`.

---

### 1.3 **Produto existente: `precoSugerido` não é atualizado**
**Local:** linhas 274–278

Ao atualizar produto existente, apenas `precoUnitario` e `precoFinal` são alterados. O `precoSugerido` calculado não é aplicado, deixando o produto inconsistente.

```dart
produtoExistente
  ..precoUnitario = custo
  ..precoFinal = precoFinal;
// precoSugerido não é atualizado
```

**Sugestão:** Incluir `..precoSugerido = precoSugerido` e, se fizer sentido, `..custoReal = custo`.

---

### 1.4 **Vazamento de memória nos controllers do bottom sheet**
**Local:** linhas 336–338, 341–333

Em `adicionarProdutoManual()`, `nomeController`, `custoController` e `quantidadeController` são criados e nunca descartados. Ao fechar o bottom sheet, os controllers continuam na memória.

**Sugestão:** Chamar `controller.dispose()` ao fechar o sheet ou usar um `StatefulWidget` interno que faça o dispose no `dispose()`.

---

### 1.5 **`importarExcel`: múltiplos `setState` no loop**
**Local:** linhas 132–148

Dentro do `for`, cada produto adicionado dispara um `setState`, causando rebuilds desnecessários.

```dart
for (var row in sheet.rows.skip(1)) {
  ...
  setState(() {
    produtos.add({...});
  });
  count++;
}
```

**Sugestão:** Acumular em uma lista temporária e chamar `setState` uma vez ao final.

---

### 1.6 **Falta de checagem `mounted` em operações assíncronas**
**Local:** `_init`, `importarExcel`, `exportarPDF`

Após `await`, não há verificação de `mounted` antes de `setState` ou `ScaffoldMessenger`, o que pode gerar erro se o widget for desmontado.

---

### 1.7 **`result.files.single` pode lançar exceção**
**Local:** linha 125

Se o usuário selecionar vários arquivos ou nenhum, `result.files.single` pode lançar. O código já trata `result == null`, mas não o caso de múltiplos arquivos.

**Sugestão:** Usar `result.files.firstOrNull` ou `result.files.isNotEmpty ? result.files.first : null`.

---

### 1.8 **Fórmula de markup ambígua**
**Local:** linhas 169–170

```dart
double precoSemTaxa = totalCustos * (markup / 100);
return precoSemTaxa * 1.05;
```

Com `markup = 150`, o preço é `totalCustos * 1.5 * 1.05`. Isso equivale a 50% de margem, não 150%. O rótulo "Markup (%)" pode induzir a erro.

**Sugestão:** Documentar a fórmula (ex.: "Markup 150 = preço 1,5x o custo") ou ajustar o cálculo conforme a regra de negócio desejada.

---

### 1.9 **Excel: estrutura de colunas fixa**
**Local:** linhas 133–136

As colunas são fixas: 0 = nome, 1 = custo, 2 = quantidade. Planilhas com outra ordem quebram a importação.

**Sugestão:** Detectar cabeçalhos na primeira linha ou permitir mapeamento de colunas.

---

### 1.10 **Produto novo sem campos obrigatórios para Firestore**
**Local:** linhas 279–294

O `Produto` criado não define `idFirebase`, `slug`, etc. Se houver sincronização automática com Firestore, pode ser necessário preencher esses campos.

---

## 2. Melhorias sugeridas

### 2.1 UX / Interface

| # | Melhoria | Descrição |
|---|----------|-----------|
| 1 | Persistir valor do Preço Pretendido | Usar controller ou initialValue para não perder o valor ao rolar |
| 2 | Indicador de progresso na importação | Mostrar loading durante importação de Excel |
| 3 | Validação de Excel | Validar estrutura (ex.: primeira linha como cabeçalho) antes de importar |
| 4 | Feedback ao confirmar | Indicar quantos produtos foram atualizados vs criados |
| 5 | Desfazer | Opção de desfazer a última precificação |
| 6 | Busca/filtro na lista | Filtrar produtos por nome quando a lista for grande |

### 2.2 Cálculo e regras

| # | Melhoria | Descrição |
|---|----------|-----------|
| 7 | Documentar fórmula | Tooltip ou ajuda explicando markup, gastos fixos, MEI, etc. |
| 8 | Prévia em tempo real | Atualizar preço sugerido ao alterar parâmetros |
| 9 | Múltiplas fórmulas | Permitir escolher fórmula (markup, margem, etc.) |
| 10 | Arredondamento configurável | Arredondar para R$ X,99 ou múltiplos de R$ 5 |
| 11 | Taxa fixa de 5% | Tornar a taxa de 1.05 configurável (ex.: taxa de cartão) |

### 2.3 Dados e integração

| # | Melhoria | Descrição |
|---|----------|-----------|
| 12 | Sincronizar com Firestore | Garantir que novos/atualizados produtos sejam enviados ao Firestore |
| 13 | Importar do estoque atual | Opção de carregar produtos já cadastrados no estoque |
| 14 | Template Excel para download | Oferecer modelo de planilha para importação |
| 15 | Exportar Excel | Exportar resultado da precificação em Excel |
| 16 | Histórico de precificações | Registrar alterações de preço para auditoria |

### 2.4 Validações e robustez

| # | Melhoria | Descrição |
|---|----------|-----------|
| 17 | Validar custo > 0 | Impedir custo zero ou negativo |
| 18 | Validar markup > 0 | Impedir markup zero ou negativo |
| 19 | Tratamento de erros na importação | Exibir linhas com erro e motivo |
| 20 | Confirmação ao limpar | Já existe; manter e garantir que o texto esteja claro |
| 21 | Disposar controllers | Corrigir vazamento de memória nos bottom sheets |

### 2.5 Acessibilidade e usabilidade

| # | Melhoria | Descrição |
|---|----------|-----------|
| 22 | Semantics | Adicionar labels para leitores de tela |
| 23 | Formato de entrada de preço | Máscara ou hint para centavos (ex.: "2250 = R$ 22,50") |
| 24 | Teclado numérico | Usar `keyboardType: TextInputType.number` onde fizer sentido |
| 25 | Ordenação da lista | Ordenar por nome, custo ou preço |

---

## 3. Resumo de prioridades

### Alta (erros que afetam o uso)
1. Persistir valor do Preço Pretendido (controller/initialValue)  
2. Atualizar `precoSugerido` no produto existente  
3. Definir `lojaId` ao criar produto novo  
4. Corrigir vazamento de memória nos controllers do bottom sheet  
5. Checagem `mounted` em operações assíncronas  

### Média (melhora a experiência)
6. Um único `setState` na importação Excel  
7. Tratar `result.files.single` com segurança  
8. Documentar/clarificar fórmula de markup  
9. Indicador de progresso na importação  
10. Sincronização com Firestore  

### Baixa (nice to have)
11. Template Excel para download  
12. Importar do estoque atual  
13. Múltiplas fórmulas de precificação  
14. Histórico de precificações  
15. Arredondamento configurável  

---

## 4. Fluxo atual

1. Usuário configura: Frete, Markup %, Gastos Fixos %, MEI %, Embalagem R$  
2. Adiciona produtos: manual ou importação Excel (nome, custo, quantidade)  
3. Para cada produto: vê custo e preço sugerido; pode informar preço pretendido  
4. Ao confirmar: atualiza produtos no Hive (existente) ou cria novos  
5. Pode exportar PDF com o relatório  

---

## 5. Dependências

- **Hive** – `produtos_$lojaId`
- **StoreResolverService** – resolução da loja ativa
- **Produto** – modelo com custoReal, precoSugerido, precoFinal, etc.
- **Excel** – importação
- **Printing** – exportação PDF
