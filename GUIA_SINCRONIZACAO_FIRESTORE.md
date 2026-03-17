# 🚀 Guia Completo de Sincronização com Firestore

**Data:** 2025-12-23
**Objetivo:** Sincronizar TODOS os dados locais (Hive) com o Firestore e manter o banco limpo

---

## 📋 Índice

1. [Scripts Disponíveis](#scripts-disponíveis)
2. [Como Usar](#como-usar)
3. [Coleções Firestore](#coleções-firestore)
4. [Limpeza de Dados](#limpeza-de-dados)
5. [Troubleshooting](#troubleshooting)

---

## 🔧 Scripts Disponíveis

### 1. **Sync Firestore Script** (`lib/services/sync_firestore_script.dart`)

**Função:** Sincroniza TODOS os dados do Hive → Firestore

**Funcionalidades:**
- ✅ Sincroniza produtos
- ✅ Sincroniza clientes
- ✅ Sincroniza vendas
- ✅ Sincroniza categorias
- ✅ Sincroniza fornecedores
- ✅ Verifica/cria configurações básicas
- ✅ Usa batching para performance (450 docs por batch)

**Métodos:**
```dart
// Sincronizar TUDO
final results = await SyncFirestoreScript.syncTudo();

// Sincronizar apenas produtos
await SyncFirestoreScript.syncApenasProdutos();

// Sincronizar apenas vendas
await SyncFirestoreScript.syncApenasVendas();

// Ver estatísticas
final stats = await SyncFirestoreScript.getEstatisticas(lojaId);
```

---

### 2. **Firestore Cleanup Script** (`lib/services/firestore_cleanup_script.dart`)

**Função:** Remove coleções obsoletas e dados órfãos

**Funcionalidades:**
- ✅ Remove coleções obsoletas (não mais usadas)
- ✅ Remove documentos órfãos (sem lojaId ou lojaId errado)
- ✅ Limpa pedidos temporários antigos (>30 dias)
- ✅ Verifica integridade dos dados
- ✅ Modo DRY RUN (simulação antes de executar)

**Métodos:**
```dart
// Executar limpeza (DRY RUN = simulação)
final results = await FirestoreCleanupScript.executarLimpeza(
  lojaId: 'masterpalm_gmail_com',
  dryRun: true,  // true = apenas mostra, false = executa
);

// Listar coleções
await FirestoreCleanupScript.listarColecoes(lojaId);

// Verificar integridade
await FirestoreCleanupScript.verificarIntegridade(lojaId);
```

---

## 🎯 Como Usar

### Opção 1: Via Widget (Recomendado para Admins)

1. **Adicione o widget na tela de admin:**

```dart
import 'package:temp_naty/widgets/sync_firestore_button.dart';

// Na sua tela de admin:
child: Column(
  children: [
    const SyncFirestoreButton(),
    // ... outros widgets
  ],
),
```

2. **Clique nos botões:**
   - **"Sincronizar TUDO"** - Sincroniza todas as coleções
   - **"Só Produtos"** - Sincroniza apenas produtos
   - **"Só Vendas"** - Sincroniza apenas vendas

---

### Opção 2: Via Código Dart

```dart
import 'package:temp_naty/services/sync_firestore_script.dart';

// Em qualquer lugar do código:
Future<void> executarSync() async {
  final results = await SyncFirestoreScript.syncTudo();

  if (results['success'] == true) {
    print('✅ Sincronização completa!');
    print('Produtos: ${results['produtos']['synced']}');
    print('Clientes: ${results['clientes']['synced']}');
    print('Vendas: ${results['vendas']['synced']}');
  } else {
    print('❌ Erro na sincronização');
    print('Erros: ${results['errors']}');
  }
}
```

---

### Opção 3: Via Linha de Comando (Standalone)

```bash
cd C:\Users\Pichau\apk_nathy\temp_naty

# Sincronizar tudo
dart run scripts/sync_firestore.dart

# Sincronizar apenas produtos
dart run scripts/sync_firestore.dart produtos

# Sincronizar apenas vendas
dart run scripts/sync_firestore.dart vendas

# Ver estatísticas
dart run scripts/sync_firestore.dart stats

# Ver ajuda
dart run scripts/sync_firestore.dart help
```

---

## 📊 Coleções Firestore

### Estrutura no Firestore:

```
firestore/
├── lojas/                              # Coleção raiz de lojas
│   └── {lojaId}/                       # Ex: masterpalm_gmail_com
│       ├── (documento da loja)
│       ├── produtos/                   # ✅ ESSENCIAL - Produtos da loja
│       ├── clientes/                   # ✅ ESSENCIAL - Clientes da loja
│       ├── vendas/                     # ✅ ESSENCIAL - Vendas da loja
│       ├── categorias/                 # ✅ ESSENCIAL - Categorias
│       ├── fornecedores/               # ✅ ESSENCIAL - Fornecedores
│       ├── config/                     # ✅ ESSENCIAL - Configurações live
│       │   └── config (doc)
│       ├── draft_config/               # ✅ ESSENCIAL - Configurações rascunho
│       │   └── config (doc)
│       ├── settings/                   # ✅ ESSENCIAL - Settings gerais
│       │   └── general (doc)
│       ├── members/                    # ✅ ESSENCIAL - Membros da loja
│       ├── campanhas_sorteio/          # ✅ ESSENCIAL - Campanhas ativas
│       │   └── {campanhaId}/
│       │       └── participantes/      # Sub-coleção de participantes
│       ├── campanhas_sorteio_config/   # ✅ ESSENCIAL - Config da roleta
│       │   └── roleta (doc)
│       ├── cupons_premio/              # ✅ ESSENCIAL - Cupons gerados
│       ├── pedidos_temp/               # ✅ ESSENCIAL - Pedidos temporários
│       └── pedidos/                    # ✅ ESSENCIAL - Pedidos finalizados
│
├── users/                              # ✅ ESSENCIAL - Usuários do sistema
├── usuarios/                           # ✅ ESSENCIAL - Usuários legacy
└── pedidos_temp/                       # ✅ ESSENCIAL - Pedidos temp globais
```

---

### Coleções OBSOLETAS (podem ser removidas):

```
❌ draft_produtos       # Obsoleto - não é mais usado
❌ temp_orders          # Obsoleto - use pedidos_temp
❌ old_vendas           # Backup antigo
❌ cache                # Cache temporário
❌ logs                 # Logs antigos
❌ sessions             # Sessões antigas
❌ temp                 # Temporários diversos
```

---

## 🧹 Limpeza de Dados

### 1. Simulação (DRY RUN) - Sempre faça primeiro!

```dart
final results = await FirestoreCleanupScript.executarLimpeza(
  lojaId: 'masterpalm_gmail_com',
  dryRun: true,  // ⚠️ IMPORTANTE: apenas simula
);

print('Coleções obsoletas encontradas: ${results['colecoesObsoletas']}');
print('Documentos que seriam removidos: ${results['documentosRemovidos']}');
```

### 2. Execução REAL (somente após revisar a simulação!)

```dart
final results = await FirestoreCleanupScript.executarLimpeza(
  lojaId: 'masterpalm_gmail_com',
  dryRun: false,  // ⚠️ CUIDADO: remove de verdade!
);

print('✅ Coleções removidas: ${results['colecoesRemovidas']}');
print('✅ Documentos removidos: ${results['documentosRemovidos']}');
```

---

### 3. Verificar Integridade dos Dados

```dart
final stats = await FirestoreCleanupScript.verificarIntegridade('masterpalm_gmail_com');

print('Produtos: ${stats['colecoes']['produtos']}');
// Output: {total: 150, comLojaIdCorreto: 150, semLojaId: 0, lojaIdErrado: 0, integridade: 100%}
```

---

## 🧪 Fluxo Recomendado de Sincronização

### Primeira Sincronização Completa:

```bash
# 1. Verificar integridade local (opcional)
flutter run
# Verificar logs se há erros no Hive

# 2. Executar sincronização
dart run scripts/sync_firestore.dart

# OU via código:
await SyncFirestoreScript.syncTudo();
```

### Logs Esperados:

```
🚀 [SYNC-SCRIPT] Iniciando sincronização completa...
✅ [SYNC-SCRIPT] LojaId: masterpalm_gmail_com
📦 [SYNC-SCRIPT] Sincronizando produtos...
📦 [PRODUTOS] Total no Hive: 150
✅ [PRODUTOS] Batch committed: 150 produtos
✅ [PRODUTOS] Sincronizados: 150 | Erros: 0
👥 [SYNC-SCRIPT] Sincronizando clientes...
👥 [CLIENTES] Total no Hive: 50
✅ [CLIENTES] Sincronizados: 50 | Erros: 0
💰 [SYNC-SCRIPT] Sincronizando vendas...
💰 [VENDAS] Total no Hive: 300
✅ [VENDAS] Sincronizadas: 300 | Erros: 0
🏷️ [SYNC-SCRIPT] Sincronizando categorias...
✅ [CATEGORIAS] Sincronizadas: 10 | Erros: 0
🏭 [SYNC-SCRIPT] Sincronizando fornecedores...
✅ [FORNECEDORES] Sincronizados: 5 | Erros: 0
⚙️ [SYNC-SCRIPT] Verificando config...
ℹ️ [CONFIG] Config já existe, não sobrescrito
✅ [SYNC-SCRIPT] Sincronização completa!
📊 [SYNC-SCRIPT] Produtos: 150 | Clientes: 50 | Vendas: 300
```

---

### Manutenção Periódica (Mensal):

```bash
# 1. Verificar integridade
dart run scripts/sync_firestore.dart stats

# 2. Sincronizar apenas o que mudou
# (produtos e vendas mudam com frequência)
dart run scripts/sync_firestore.dart produtos
dart run scripts/sync_firestore.dart vendas

# 3. Limpar dados obsoletos (DRY RUN primeiro!)
# Via código:
await FirestoreCleanupScript.executarLimpeza(lojaId: 'xxx', dryRun: true);
# Se tudo ok, executar de verdade:
await FirestoreCleanupScript.executarLimpeza(lojaId: 'xxx', dryRun: false);
```

---

## 🐛 Troubleshooting

### Problema: "LojaId vazio, abortando"

**Causa:** StoreResolverService não conseguiu resolver o lojaId

**Solução:**
```dart
// Verificar sessão Hive
final sessao = Hive.box('sessao');
final lojaId = sessao.get('store_id');
print('LojaId na sessão: $lojaId');

// Se vazio, definir manualmente:
await sessao.put('store_id', 'masterpalm_gmail_com');
```

---

### Problema: "Erro ao sincronizar produto X"

**Causa:** Produto pode ter dados inválidos

**Solução:**
```bash
# Ver logs detalhados:
flutter run --verbose

# Verificar produto específico no Hive:
final box = Hive.box<Produto>('produtos_masterpalm_gmail_com');
final produto = box.getAt(X);
print('Produto: ${produto.nome}, Slug: ${produto.slug}');
```

---

### Problema: "Permission denied" no Firestore

**Causa:** Regras de segurança do Firestore bloqueando

**Solução:**
1. Abra Firebase Console → Firestore Database → Rules
2. Verifique se suas regras permitem escrita:
   ```javascript
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /lojas/{lojaId}/{document=**} {
         allow read, write: if request.auth != null;
       }
     }
   }
   ```

---

### Problema: Sincronização muito lenta

**Causa:** Muitos documentos sendo sincronizados

**Solução:**
- O script usa batching automático (450 docs por batch)
- Para muitos dados (>1000 docs), a sincronização pode demorar alguns minutos
- Acompanhe os logs para ver o progresso
- Considere sincronizar em partes:
  ```dart
  await SyncFirestoreScript.syncApenasProdutos();
  // Aguardar finalizar
  await SyncFirestoreScript.syncApenasVendas();
  ```

---

### Problema: Documentos órfãos após limpeza

**Causa:** Dados antigos sem lojaId correto

**Verificação:**
```dart
final stats = await FirestoreCleanupScript.verificarIntegridade('masterpalm_gmail_com');

// Se aparecer órfãos:
// stats['colecoes']['produtos']['semLojaId'] > 0
// stats['colecoes']['produtos']['lojaIdErrado'] > 0
```

**Solução:**
```dart
// Executar limpeza de órfãos (DRY RUN primeiro!)
await FirestoreCleanupScript.executarLimpeza(
  lojaId: 'masterpalm_gmail_com',
  dryRun: true,  // Ver o que seria removido
);

// Se ok, executar de verdade:
await FirestoreCleanupScript.executarLimpeza(
  lojaId: 'masterpalm_gmail_com',
  dryRun: false,
);
```

---

## ⚠️ AVISOS IMPORTANTES

### 1. **Backup Antes de Limpar**

```bash
# Fazer backup manual do Firestore via Firebase Console:
# 1. Abra Firebase Console
# 2. Vá em Firestore Database
# 3. Menu (3 pontos) → Export data
# 4. Escolha um bucket do Cloud Storage
# 5. Aguarde o export finalizar
```

### 2. **Sempre use DRY RUN primeiro**

```dart
// ❌ ERRADO (perigoso!):
await FirestoreCleanupScript.executarLimpeza(lojaId: xxx, dryRun: false);

// ✅ CERTO:
// Passo 1: Simulação
final results = await FirestoreCleanupScript.executarLimpeza(lojaId: xxx, dryRun: true);
print('O que seria removido: ${results['colecoesObsoletas']}');

// Passo 2: Revisar logs

// Passo 3: Executar se tudo ok
await FirestoreCleanupScript.executarLimpeza(lojaId: xxx, dryRun: false);
```

### 3. **Custos do Firestore**

- **Leituras:** Verificar integridade pode gerar muitas leituras
- **Escritas:** Sincronização completa gera 1 escrita por documento
- **Exclusões:** Limpeza gera 1 exclusão por documento

**Estimativa de custos:**
- Produtos: 150 docs × 1 escrita = 150 escritas
- Clientes: 50 docs × 1 escrita = 50 escritas
- Vendas: 300 docs × 1 escrita = 300 escritas
- **Total: ~500 escritas** (gratuito até 20.000/dia)

---

## 📊 Checklist Final

### Antes da primeira sincronização:
- [ ] Verificar que dados locais (Hive) estão corretos
- [ ] Verificar que lojaId está correto no Hive
- [ ] Fazer backup do Firestore (se já tiver dados)
- [ ] Testar com DRY RUN primeiro

### Durante a sincronização:
- [ ] Acompanhar logs no terminal
- [ ] Verificar se não há erros
- [ ] Aguardar finalização completa

### Após a sincronização:
- [ ] Verificar integridade dos dados
- [ ] Testar app (catálogo web, relatórios, etc.)
- [ ] Verificar no Firebase Console se os dados estão lá

### Limpeza periódica (mensal):
- [ ] Executar verificação de integridade
- [ ] Executar limpeza com DRY RUN
- [ ] Revisar o que seria removido
- [ ] Executar limpeza real se tudo ok
- [ ] Verificar integridade novamente

---

## 🎉 Resultado Esperado

Após sincronização completa, você terá:

- ✅ **Firestore 100% atualizado** com dados do Hive
- ✅ **Todos os produtos** sincronizados
- ✅ **Todos os clientes** sincronizados
- ✅ **Todas as vendas** sincronizadas
- ✅ **Categorias e fornecedores** sincronizados
- ✅ **Dados limpos** (sem coleções obsoletas)
- ✅ **100% isolado por loja** (cada loja tem seus dados separados)

**Benefícios:**
- 📱 **Multi-dispositivo:** Dados acessíveis de qualquer lugar
- ☁️ **Backup automático:** Firestore tem backup nativo
- 📊 **Relatórios avançados:** Pode usar Firestore para analytics
- 🔄 **Sincronização real-time:** Suporte futuro para updates em tempo real

---

**Documentação Criada em:** 2025-12-23
**Versão:** 1.0.0
