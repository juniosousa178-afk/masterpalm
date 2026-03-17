# 📱 COMO USAR - GUIA RÁPIDO

## ✅ **APK COMPILADO**

**Localização**: `build/app/outputs/flutter-apk/app-release.apk`
**Tamanho**: 81.9 MB

---

## 🚀 **INSTALAÇÃO**

### **Passo 1: Desinstalar App Antigo** (IMPORTANTE!)
1. Vá em Configurações → Apps
2. Encontre o app
3. Desinstale completamente
4. **Isso é importante para limpar cache antigo**

### **Passo 2: Instalar Novo APK**
1. Transfira o APK para o celular
2. Instale
3. Aceite as permissões

---

## 🔐 **PRIMEIRO USO**

### **1. Fazer Login**
- Use seu email e senha Firebase

### **2. Acessar Menu Lateral**
- Toque no ícone ☰ (hambúrguer) no topo esquerdo

### **3. Encontrar "Consolidar Lojas"**
No menu lateral, procure por:
```
Configurar Pagamentos
Sincronizar Firestore
Backup da Loja
► Consolidar Lojas  ← AQUI!
Planos
```

### **4. Executar Consolidação**
1. Toque em **"Consolidar Lojas"**
2. Leia a explicação na tela
3. Toque no botão **"INICIAR CONSOLIDAÇÃO"**
4. Aguarde (poucos segundos)
5. Verifique os resultados

### **5. Publicar Tudo**
1. Volte ao menu lateral
2. Toque em **"Configurações do Catálogo"**
3. Verifique o campo **"Slug"** (deve ser `nathy_pratas_e_folheados`)
4. Toque em **"PUBLICAR TUDO"**
5. Aguarde a publicação

### **6. FECHAR E REABRIR O APP**
- Importante para aplicar todas as mudanças
- Force close e abra novamente

---

## ✅ **VERIFICAR SE FUNCIONOU**

### **Estoque deve mostrar 3 produtos**:
- anel
- brinco
- colar

### **Preview deve mostrar 3 produtos**

### **Site público deve funcionar**:
`https://mastepalm.com.br/loja/nathy_pratas_e_folheados`

### **Logo e banners devem aparecer**

---

## 🔒 **SISTEMA DE LOJA FIXA**

Cada usuário tem SUA loja PERMANENTE:

**Você (Nathy)**:
- UID: `tcnbZdmFXsMPJ2bU29dDt3z5ZHr2`
- Loja: `nathy-pratas-e-folheados` (SEMPRE)

**Júnio (exemplo)**:
- UID: `abc123xyz`
- Loja: `loja_uid_abc123xyz` (SEMPRE)

**Cada usuário NÃO VÊ os dados do outro!**

---

## 📍 **ONDE ESTÁ CADA COISA**

### **Menu Lateral** (☰)
```
└─ Loja (cliente)
└─ Configurações do Catálogo
└─ Estoque
└─ Vendas
└─ Pré-Pedidos
└─ Pedidos Pendentes
└─ Clientes
└─ Fornecedores
└─ Precificação
└─ Notas Fiscais
└─ Campanhas & Sorteios
└─ Fretes & Cupons
└─ Configurar Pagamentos
└─ Sincronizar Firestore
└─ Backup da Loja
└─ 🎯 Consolidar Lojas ← AQUI!
└─ Planos
└─ Migrar Dados
└─ Importar do Firestore
└─ Sair
```

---

## 🎯 **PARA NOVOS USUÁRIOS**

Quando alguém novo criar uma conta:

1. **Loja criada automaticamente** no primeiro login
2. Nome da loja: `loja_uid_{UID_DO_USUARIO}`
3. **Não precisa fazer nada** - tudo automático
4. **Completamente isolado** de outros usuários

**Exemplo**:
- Júnio cria conta
- Loja criada: `loja_uid_abc123xyz`
- Júnio adiciona produtos
- **Você NÃO VÊ os produtos dele**
- **Ele NÃO VÊ seus produtos**

---

## ⚠️ **SE ALGO DER ERRADO**

1. Desinstale o app completamente
2. Reinstale
3. Faça login
4. Execute consolidação novamente
5. Publique tudo novamente

---

## 📞 **LOGS PARA DEBUG**

Para ver os logs:
```bash
cd "C:\Users\Pichau\apk_nathy\temp_naty"
flutter run --release
```

Procure por:
```
🔒 [STORE-RESOLVER] Resolvendo loja FIXA do usuário...
🎯 [STORE-RESOLVER] UID mapeado: nathy-pratas-e-folheados
✅ [STORE-RESOLVER] Loja FIXA: nathy-pratas-e-folheados
```

Se aparecer essas linhas, está funcionando! ✅

---

## 🎉 **PRONTO!**

Agora você tem:
- ✅ Loja fixa e imutável por usuário
- ✅ Consolidação automática de dados
- ✅ Interface fácil no menu
- ✅ Isolamento total entre usuários
- ✅ Impossível misturar dados

**TUDO FUNCIONANDO!** 🚀
