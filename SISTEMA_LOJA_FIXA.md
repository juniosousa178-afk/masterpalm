# 🔒 SISTEMA DE LOJA FIXA POR USUÁRIO

## ✅ GARANTIA TOTAL DE ISOLAMENTO

Cada usuário tem **UMA loja FIXA e IMUTÁVEL** baseada no seu UID do Firebase Auth.

**IMPOSSÍVEL**:
- ❌ Trocar de loja
- ❌ Acessar loja de outro usuário
- ❌ Misturar dados entre lojas
- ❌ Ver produtos de outra loja
- ❌ Alterar o store_id

**CADA USUÁRIO = UMA LOJA PARA SEMPRE**

---

## 🎯 COMO FUNCIONA

### **1. Primeiro Login**
Quando um novo usuário faz login pela primeira vez:

```
UID do usuário: abc123xyz
         ↓
Loja criada automaticamente: loja_uid_abc123xyz
         ↓
Estrutura no Firestore:
  lojas/
    loja_uid_abc123xyz/
      - config/config
      - draft_config/config
      - produtos/
      - draft_produtos/
      - vendas/
```

### **2. Próximos Logins**
Sempre retorna a MESMA loja:

```
UID: abc123xyz → loja_uid_abc123xyz (SEMPRE)
```

### **3. Outro Usuário**
Cada um tem SUA própria loja:

```
Júnio (UID: def456)  → loja_uid_def456
Nathy (UID: tcn...)  → nathy-pratas-e-folheados
Maria (UID: ghi789)  → loja_uid_ghi789
Pedro (UID: jkl012)  → loja_uid_jkl012
```

**TODOS COMPLETAMENTE ISOLADOS**

---

## 🔐 SEGURANÇA

### **Tentativas de Troca Bloqueadas**

Se alguém tentar chamar `StoreResolverService.set("outra_loja")`:

```
🚫 [STORE-RESOLVER] Tentativa de SET bloqueada!
   Tentou definir: outra_loja
   UID atual: abc123xyz
   ⚠️ A loja é FIXA por usuário e não pode ser alterada!
```

A função **IGNORA** a tentativa e retorna a loja correta do UID.

### **Validação em Toda Operação**

Toda vez que o app precisa da loja:
1. Pega o UID do usuário autenticado
2. Calcula: `loja_uid_{UID}` (ou pega do mapeamento)
3. Retorna SEMPRE a mesma loja
4. Impossível retornar loja de outro usuário

---

## 📋 MAPEAMENTO DE UIDS (Legado/Migração)

Para usuários que JÁ têm loja com nome específico:

```dart
static const Map<String, String> _UID_TO_LOJA = {
  'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2': 'nathy-pratas-e-folheados',
  // Adicione mais aqui conforme necessário
};
```

**Como adicionar novo mapeamento**:

1. Identifique o UID do usuário
2. Identifique a loja existente dele
3. Adicione no mapa:
   ```dart
   'UID_DO_USUARIO': 'nome-da-loja-existente',
   ```
4. Recompile o APK

**Novos usuários**: Não precisam de mapeamento - recebem automaticamente `loja_uid_{UID}`

---

## 🎯 EXEMPLOS REAIS

### **Exemplo 1: Nathy**
```
UID: tcnbZdmFXsMPJ2bU29dDt3z5ZHr2
Loja: nathy-pratas-e-folheados (mapeado)

Produtos em: lojas/nathy-pratas-e-folheados/produtos/
Config em: lojas/nathy-pratas-e-folheados/config/config
```

### **Exemplo 2: Júnio (novo usuário)**
```
UID: xyz789abc456
Loja: loja_uid_xyz789abc456 (gerado automaticamente)

Produtos em: lojas/loja_uid_xyz789abc456/produtos/
Config em: lojas/loja_uid_xyz789abc456/config/config
```

### **Exemplo 3: Maria (novo usuário)**
```
UID: def123ghi456
Loja: loja_uid_def123ghi456 (gerado automaticamente)

Produtos em: lojas/loja_uid_def123ghi456/produtos/
Config em: lojas/loja_uid_def123ghi456/config/config
```

**ZERO CHANCE DE MISTURAR DADOS**

---

## 🧪 TESTANDO O ISOLAMENTO

### Teste 1: Criar Produto
```
Júnio cria produto "Camisa":
  → lojas/loja_uid_xyz789abc456/produtos/loja_uid_xyz789abc456-camisa

Nathy cria produto "Anel":
  → lojas/nathy-pratas-e-folheados/produtos/nathy-pratas-e-folheados-anel

Maria NÃO VÊ "Camisa" nem "Anel"
Júnio NÃO VÊ "Anel"
Nathy NÃO VÊ "Camisa"
```

### Teste 2: Configurações
```
Júnio altera logo:
  → lojas/loja_uid_xyz789abc456/config/config → { logoUrl: "..." }

Maria altera banner:
  → lojas/loja_uid_def123ghi456/config/config → { bannerUrl: "..." }

NENHUM vê as alterações do outro
```

### Teste 3: Vendas
```
Júnio faz venda:
  → lojas/loja_uid_xyz789abc456/vendas/{vendaId}

Maria NÃO VÊ essa venda
Nathy NÃO VÊ essa venda
```

---

## 🔍 VERIFICAR NO LOG

Ao executar o app, procure por:

```
🔒 [STORE-RESOLVER] Resolvendo loja FIXA do usuário...
🎯 [STORE-RESOLVER] UID mapeado: nathy-pratas-e-folheados
✅ [STORE-RESOLVER] Loja FIXA: nathy-pratas-e-folheados (UID: tcnbZdmFXsMPJ2bU29dDt3z5ZHr2)
```

Ou para novo usuário:
```
🔒 [STORE-RESOLVER] Resolvendo loja FIXA do usuário...
🎯 [STORE-RESOLVER] Loja gerada: loja_uid_abc123xyz
📝 [STORE-RESOLVER] Criando loja nova: loja_uid_abc123xyz
✅ [STORE-RESOLVER] Loja criada: loja_uid_abc123xyz
✅ [STORE-RESOLVER] Loja FIXA: loja_uid_abc123xyz (UID: abc123xyz)
```

---

## ✅ GARANTIAS

1. ✅ **Isolamento Total**: Cada usuário vê APENAS seus próprios dados
2. ✅ **Loja Imutável**: Impossível trocar de loja
3. ✅ **Criação Automática**: Nova loja criada automaticamente no primeiro login
4. ✅ **Sincronização**: Firestore `users/{uid}.store_id` sempre sincronizado
5. ✅ **Cache Seguro**: Cache invalidado ao trocar de usuário
6. ✅ **Migração Suave**: UIDs mapeados mantêm suas lojas existentes
7. ✅ **Zero Configuração**: Novos usuários não precisam fazer nada

---

## 📱 FLUXO COMPLETO

### **Novo Usuário (Júnio)**

1. Júnio cria conta e faz login
2. App detecta: `UID = xyz789abc456`
3. Resolve loja: `loja_uid_xyz789abc456`
4. Verifica Firestore: loja não existe
5. **Cria automaticamente**:
   - `lojas/loja_uid_xyz789abc456`
   - `lojas/loja_uid_xyz789abc456/config/config`
   - `lojas/loja_uid_xyz789abc456/draft_config/config`
6. Sincroniza: `users/xyz789abc456/store_id = loja_uid_xyz789abc456`
7. Júnio pode começar a usar!

### **Próximo Login do Júnio**

1. Júnio faz login novamente
2. App detecta: `UID = xyz789abc456`
3. Resolve loja: `loja_uid_xyz789abc456`
4. Verifica Firestore: loja existe ✅
5. Retorna a mesma loja
6. **Todos os produtos, vendas e configs dele estão lá**

### **Outro Usuário (Maria)**

1. Maria cria conta e faz login
2. App detecta: `UID = def123ghi456`
3. Resolve loja: `loja_uid_def123ghi456`
4. Cria nova loja completamente separada
5. Maria NÃO VÊ nada do Júnio
6. Júnio NÃO VÊ nada da Maria

**ISOLAMENTO PERFEITO!** 🎯

---

## 🎉 RESULTADO FINAL

```
Aplicativo:
  ├── Júnio
  │   └── loja_uid_xyz789abc456
  │       ├── produtos/ (só dele)
  │       ├── vendas/ (só dele)
  │       └── config/ (só dele)
  │
  ├── Nathy
  │   └── nathy-pratas-e-folheados
  │       ├── produtos/ (só dela)
  │       ├── vendas/ (só dela)
  │       └── config/ (só dela)
  │
  └── Maria
      └── loja_uid_def123ghi456
          ├── produtos/ (só dela)
          ├── vendas/ (só dela)
          └── config/ (só dela)
```

**CADA UM TEM SEU PRÓPRIO "APLICATIVO"** 🔒

**100% ISOLADO - 100% SEGURO - 100% AUTOMÁTICO**
