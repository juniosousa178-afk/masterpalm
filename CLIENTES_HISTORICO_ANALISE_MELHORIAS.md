# Análise: Telas Clientes e Histórico de Clientes

> **Arquivos:** `lib/screens/clientes_screen.dart`, `lib/screens/historico_clientes_screen.dart`

---

## 1. Erros identificados

### 1.1 **Inconsistência na resolução de lojaId**
**Clientes:** usa `StoreResolverService.resolve()`  
**Histórico:** usa `LojaIdService.get()`

As duas telas podem obter `lojaId` diferentes se os serviços retornarem valores distintos, causando dados incorretos ou vazios.

**Sugestão:** Padronizar para `StoreResolverService.resolve()` em ambas.

---

### 1.2 **Cliente.adicionarHistorico usa box errada**
**Local:** `lib/models/cliente.dart` linha 63

```dart
void adicionarHistorico(Venda venda) {
  final box = Hive.box<Venda>('vendas');  // ❌ Hardcoded 'vendas'
  historico ??= HiveList(box);
  ...
}
```

O app usa `vendas_$lojaId` para multi-loja. O box `'vendas'` pode não existir ou conter dados de outra loja.

**Sugestão:** Receber a `vendasBox` como parâmetro ou usar `vendas_$lojaId`.

---

### 1.3 **Cliente.vazioAsync usa box errada**
**Local:** `lib/models/cliente.dart` linha 72

```dart
final vendasBox = await Hive.openBox<Venda>('vendas');  // ❌ Deveria ser vendas_$lojaId
```

**Sugestão:** Usar `vendas_$lojaId` conforme o lojaId da sessão.

---

### 1.4 **Fonte de dados divergente: cliente.historico vs vendasBox**
**Clientes (aba Clientes):** usa `cliente.historico` (HiveList) para estatísticas, ordenação e visualização.  
**Clientes (aba Histórico):** usa `cliente.historico` expandido de todos os clientes.  
**Histórico de Clientes:** usa `vendasBox` diretamente (fonte de verdade).

Se a reconciliação não rodar ou falhar, `cliente.historico` pode estar vazio ou desatualizado, enquanto `vendasBox` tem as vendas. O usuário vê dados diferentes nas telas.

**Sugestão:** Unificar a fonte: usar `vendasBox` como principal e derivar o histórico do cliente a partir dela (como em Histórico de Clientes).

---

### 1.5 **visualizarHistorico com HiveList vazio**
**Local:** `clientes_screen.dart` linhas 516–517

```dart
final historico = cliente.historico ?? HiveList(vendasBox);
```

Se `cliente.historico` for null, cria um `HiveList(vendasBox)` vazio. As vendas do cliente em `vendasBox` não são filtradas automaticamente. O usuário vê "Nenhuma compra registrada" mesmo tendo vendas.

**Sugestão:** Buscar vendas do cliente em `vendasBox` por `clienteNome` quando `historico` for null ou vazio.

---

### 1.6 **importarExcel: result.files.single pode lançar**
**Local:** `clientes_screen.dart` linha 751

Se o usuário selecionar vários arquivos, `result.files.single` lança exceção.

**Sugestão:** Usar `result.files.firstOrNull` ou `result.files.isNotEmpty ? result.files.first : null`.

---

### 1.7 **Falta de checagem mounted**
**Local:** `clientes_screen.dart` – `_init`, `importarExcel`, `importarContatosWhatsApp`, `_abrirCadastroCliente`

Após `await`, não há verificação de `mounted` antes de `setState` ou `ScaffoldMessenger`.

---

### 1.8 **Excel: sheet.row(i) e sheet.maxRows**
**Local:** `clientes_screen.dart` linhas 760–762

```dart
for (int i = 1; i < sheet.maxRows; i++) {
  final row = sheet.row(i);
```

A API do pacote `excel` pode usar `sheet.rows` ou estrutura diferente. `sheet.maxRows` pode não refletir o número real de linhas com dados.

**Sugestão:** Usar `sheet.rows` ou `sheet.rows.skip(1)` se disponível, ou validar a API do pacote.

---

### 1.9 **File(cliente.avatarPath!) em plataforma Web**
**Local:** `clientes_screen.dart` linha 1587

```dart
final hasAvatar = !kIsWeb && cliente.avatarPath != null && File(cliente.avatarPath!).existsSync();
```

Em Web, `File` não existe (dart:io). O `!kIsWeb` evita o uso, mas o import de `dart:io` pode quebrar em Web.

**Sugestão:** Garantir que `dart:io` seja importado condicionalmente ou que o código Web não use `File`.

---

### 1.10 **Histórico de Clientes: sem sincronização Firestore**
**Local:** `historico_clientes_screen.dart` – `_init`

A tela não chama `VendasFirestoreService.syncFirestoreToHive` nem `ClientesFirestoreService.syncFirestoreToHive`. Se o usuário abrir Histórico antes de Clientes, pode ver dados desatualizados.

**Sugestão:** Incluir sync com Firestore no `_init`, como em Clientes.

---

### 1.11 **Data final antes da data inicial**
**Ambas as telas**

Não há validação para `dataFinal < dataInicial`. O filtro pode não retornar resultados ou se comportar de forma confusa.

**Sugestão:** Validar e, se necessário, trocar ou exibir aviso.

---

### 1.12 **Botão duplicado em Histórico de Clientes**
**Local:** `historico_clientes_screen.dart` linhas 398–410 e 481–499

O card tem `InkWell` no `onTap` e um `ElevatedButton` "Ver todas as compras" que fazem a mesma navegação. Redundante.

**Sugestão:** Manter apenas um (por exemplo, o `InkWell` em todo o card).

---

### 1.13 **TextField de busca sem controller (Histórico)**
**Local:** `historico_clientes_screen.dart` linhas 236–251

O campo de busca usa apenas `onChanged` e não tem `controller`. Em rebuilds, o valor pode ser perdido dependendo do contexto.

**Sugestão:** Usar `TextEditingController` e `controller.text` para o filtro.

---

## 2. Melhorias sugeridas

### 2.1 Clientes

| # | Melhoria | Descrição |
|---|----------|-----------|
| 1 | Unificar fonte de vendas | Usar `vendasBox` como fonte principal e derivar histórico por cliente |
| 2 | Indicador de importação | Loading durante importação Excel/WhatsApp |
| 3 | Validação de telefone | Formato e quantidade de dígitos antes de salvar |
| 4 | Validação de e-mail | Formato básico de e-mail |
| 5 | CEP automático | Buscar endereço por CEP (ViaCEP ou similar) |
| 6 | Confirmação ao excluir | Já existe; manter e garantir texto claro |
| 7 | Paginação/virtualização | Para listas grandes de clientes |
| 8 | Exportar clientes | Exportar lista para Excel |
| 9 | Duplicar cliente | Opção para duplicar cadastro |
| 10 | Semantics | Labels para acessibilidade |

### 2.2 Histórico de Clientes

| # | Melhoria | Descrição |
|---|----------|-----------|
| 11 | Sincronizar Firestore | Sync de vendas e clientes no `_init` |
| 12 | Resumo por período | Total de vendas e valor no período filtrado |
| 13 | Gráfico de evolução | Vendas ao longo do tempo |
| 14 | Filtro por valor | Mínimo/máximo de valor da venda |
| 15 | Ordenação por valor | Por valor total da venda |
| 16 | Atalho para cliente | Link para tela de Clientes ao tocar no cliente |
| 17 | Layout responsivo | Melhor uso em tablets |
| 18 | AppColors | Usar tema do app em vez de cores fixas |

### 2.3 Ambas

| # | Melhoria | Descrição |
|---|----------|-----------|
| 19 | Mensagens de erro amigáveis | Traduzir erros comuns |
| 20 | Empty state | Ilustração e texto quando não há dados |
| 21 | Pull-to-refresh | Atualizar dados com gesto |
| 22 | Tratamento de erros | Try/catch e feedback em operações async |

---

## 3. Resumo de prioridades

### Alta (erros que afetam dados)
1. Padronizar `StoreResolverService` para lojaId  
2. Corrigir `Cliente.adicionarHistorico` e `vazioAsync` para usar `vendas_$lojaId`  
3. Unificar fonte: usar `vendasBox` em Clientes (aba Histórico e visualizarHistorico)  
4. Corrigir `visualizarHistorico` quando `historico` for null/vazio  
5. Adicionar sync Firestore em Histórico de Clientes  

### Média (robustez e UX)
6. Tratar `result.files.single` com segurança  
7. Checagem `mounted` em operações assíncronas  
8. Controller para campo de busca no Histórico  
9. Validação de data final ≥ data inicial  
10. Remover botão duplicado no card do Histórico  

### Baixa (nice to have)
11. CEP automático  
12. Indicador de importação  
13. Exportar clientes  
14. Pull-to-refresh  

---

## 4. Fluxo atual

### Clientes
1. Aba **Clientes:** lista de clientes da loja, busca, ordenação, importação Excel/WhatsApp.  
2. Aba **Histórico:** vendas de todos os clientes, filtro por data e nome, ordenação.  
3. Ao tocar em um cliente: bottom sheet com histórico (`cliente.historico`).  
4. Estatísticas: total de clientes, vendas e valor a partir de `cliente.historico`.

### Histórico de Clientes
1. Lista clientes únicos com vendas no período.  
2. Filtros: data inicial, data final, nome.  
3. Ordenação: alfabética ou por data.  
4. Ao tocar: navega para `HistoricoClienteDetalheScreen` com vendas do cliente.

---

## 5. Dependências

- **Hive:** `clientes_$lojaId`, `vendas_$lojaId`
- **StoreResolverService / LojaIdService:** resolução da loja
- **ClientesFirestoreService:** sync clientes
- **VendasFirestoreService:** sync vendas
- **ReconciliacaoVendasClientesService:** vincula vendas a clientes
- **DeduplicacaoClientesService:** remove duplicatas
