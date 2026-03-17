# Correções Multiusuário Aplicadas

**Data:** 12/02/2026  
**Objetivo:** Correções técnicas para uso em produção com múltiplos usuários simultâneos.

---

## 1. Lista das Correções Aplicadas

### 1.1 Estoque (CRÍTICO) ✅

- **Removido** fallback que baixava estoque apenas no Hive quando o Firestore falhava.
- **Comportamento atual:** Se a transação Firestore falhar (ex.: "Produto não encontrado"), a venda **falha** e a exceção é propagada ao usuário.
- **Removido** método `_baixarEstoqueLocalmente` do `VendasService`.
- **Garantia:** Toda baixa de estoque usa `runTransaction` no `EstoqueTransactionService` (já existia).

### 1.2 Roleta (CRÍTICO) ✅

- **Implementado** `runTransaction` no giro da roleta para evitar condição de corrida.
- **Novo fluxo:** `_executarGiroRoletaTransacao()` executa em uma única transação atômica:
  - Lê `vendasDesdePremio`, `frequenciaPremio`, `premios`
  - Valida se ganhou (`vendasDesdePremio >= frequenciaPremio - 1`)
  - Atualiza contadores e `premios`
  - Retorna `(ganhou, premioIndex)`
- **Removido** métodos obsoletos: `_sortearPremio`, `_ganhouPremio`, `_atualizarContadores`.

### 1.3 Identificação de Cliente (MÉDIO) ✅

- **Adicionado** campo `idFirebase` ao modelo `Cliente` (HiveField 10).
- **Lógica no sync:** 
  - Se `cliente.idFirebase` existe → usa esse ID.
  - Senão, busca doc existente por `telefone_nome` (formato antigo) para compatibilidade.
  - Se não encontrar → gera UUID v4.
- **Compatibilidade:** Clientes já existentes no Firestore com ID `telefone_nome` continuam funcionando.
- **Pacote:** `uuid: ^4.5.1` adicionado ao `pubspec.yaml`.

### 1.4 Listeners em Tempo Real (MÉDIO) ✅

- **Criado** `FirestoreCriticalListenerService` para dados críticos.
- **Listener de produtos:** Ao abrir `VendasScreen`, inicia listener em `estoque_produtos`. Quando há mudanças, executa sync Firestore → Hive.
- **Cancelamento:** O listener é cancelado no `dispose` da `VendasScreen`.

### 1.5 Produtos / Estoque (MÉDIO) ✅

- **Fonte única:** `EstoqueTransactionService._resolverProdutoRef` passou a usar a coleção `estoque_produtos` (antes usava `produtos`).
- **Consistência:** A mesma coleção usada pelo `ProdutosFirestoreService.syncFirestoreToHive` e pelo listener.

---

## 2. Arquivos Alterados

| Arquivo | Alterações |
|---------|------------|
| `lib/services/vendas_service.dart` | Removido fallback Hive e `_baixarEstoqueLocalmente` |
| `lib/widgets/roleta_web_widget_v3.dart` | Transação atômica no giro; removidos métodos obsoletos |
| `lib/models/cliente.dart` | Adicionado campo `idFirebase` |
| `lib/models/cliente.g.dart` | Regenerado pelo build_runner |
| `lib/services/clientes_firestore_service.dart` | ID único (UUID ou compat.), sync com idFirebase |
| `lib/services/firestore_critical_listener_service.dart` | Listener de produtos + **listener de permissões** |
| `lib/screens/vendas_screen.dart` | Sync inicial de produtos; listener de produtos |
| `lib/screens/home_screen.dart` | Listener de permissões (início/cancelamento) |
| `lib/services/estoque_transaction_service.dart` | Uso de `estoque_produtos`; mensagem de erro aprimorada |
| `pubspec.yaml` | Adicionado `uuid: ^4.5.1` |

---

## 3. Trechos Críticos de Código Modificados

### 3.1 VendasService – Remoção do fallback

```dart
// ANTES: try/catch com fallback para Hive
// DEPOIS: transação obrigatória, sem fallback
final txResults = await EstoqueTransactionService.baixarEstoqueTransactionBatch(...);
// Se falhar, exceção propaga ao usuário
```

### 3.2 RoletaWebWidgetV3 – Transação atômica

```dart
Future<(bool, int)?> _executarGiroRoletaTransacao() async {
  return await FirebaseFirestore.instance.runTransaction<(bool, int)>((transaction) async {
    final snap = await transaction.get(docRef);
    // ... ler vendasDesdePremio, decidir ganhou, atualizar
    transaction.update(docRef, {...});
    return (ganhou, premioIndex);
  });
}
```

### 3.3 ClientesFirestoreService – ID único

```dart
if (cliente.idFirebase != null && cliente.idFirebase!.isNotEmpty) {
  clienteId = cliente.idFirebase!;
} else {
  // Compat: buscar por telefone_nome
  final existing = await _db...doc(oldId).get();
  clienteId = existing.exists ? oldId : const Uuid().v4();
  cliente.idFirebase = clienteId;
  await cliente.save();
}
```

### 3.4 EstoqueTransactionService – Fonte única

```dart
// ANTES: collection('produtos')
// DEPOIS: collection('estoque_produtos')
final col = _db.collection('lojas').doc(lojaId).collection('estoque_produtos');
```

---

## 4. Correções dos Riscos Residuais (atualização 12/02/2026)

### 4.1 Produtos só no Hive ✅
- **Sync inicial:** `VendasScreen` agora executa `ProdutosFirestoreService.syncFirestoreToHive` ao abrir, garantindo que produtos estejam atualizados antes de vender.
- **Mensagem de erro:** `EstoqueTransactionService` exibe mensagem clara: *"Produto não encontrado no servidor. Verifique se o produto foi sincronizado ou sua conexão com a internet."*

### 4.2 Listeners de permissões ✅
- **FirestoreCriticalListenerService:** Adicionado `startPermissoesListener` e `cancelPermissoesListener`.
- **Admin:** Escuta `usuarios/{email}` e atualiza `plano_ativo` quando outro admin altera permissões.
- **Vendedor:** Escuta `lojas/{storeId}/vendedores/{uid}` para mudanças em tempo real.
- **Integração:** HomeScreen inicia o listener em `_carregarSessao` e cancela em `dispose`.

### 4.3 RoletaPremiosDialog (nova_venda_modal) ✅
- **Revisão:** O `RoletaPremiosDialog` usa giro aleatório local (sem Firestore para o sorteio). Não há condição de corrida pois não há recurso compartilhado.
- **Modelo diferente:** Enquanto `RoletaWebWidgetV3` usa frequência (1 em X ganha), o modal dá prêmio aleatório a todos. Mantido sem alteração.

---

## 5. Observações de Risco Residual (atuais)

1. **Produtos sem documento no Firestore:** Se o produto nunca foi sincronizado, a venda falhará com mensagem clara. É o comportamento esperado para evitar sobrevenda.

2. **Clientes antigos:** Clientes criados antes desta mudança podem não ter `idFirebase`. O sync mantém compatibilidade com o formato antigo por `telefone_nome`.

3. **Roleta – PremioIndex determinístico:** Quando o usuário ganha no RoletaWebWidgetV3, o prêmio é o primeiro disponível (não aleatório). Isso evita race condition.

4. **Schema Hive do Cliente:** Foi adicionado `HiveField(10)` para `idFirebase`. Clientes já salvos no Hive funcionarão com `idFirebase == null` até o próximo sync.

---

## 6. Comandos para Aplicar

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

---

*Correções aplicadas em 12/02/2026.*
