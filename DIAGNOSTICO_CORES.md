# 🔍 DIAGNÓSTICO: Cores Diferentes entre Preview e Web

## 🎨 **PROBLEMA IDENTIFICADO**

- **Preview (App):** Cores ROXAS corretas ✅
- **Web (Navegador):** Cores VERDES antigas ❌

---

## 📊 **POSSÍVEIS CAUSAS**

### **1. Cache do Navegador** ⭐ (Mais provável)
O navegador está usando configurações antigas armazenadas em cache.

### **2. Configurações não Publicadas**
As configurações podem estar apenas em `draft_config` e não em `config`.

### **3. Firestore não Atualizou**
O servidor pode ainda não ter processado a publicação.

---

## ✅ **SOLUÇÃO PASSO A PASSO**

### **PASSO 1: Limpar Cache do Navegador**

#### **Opção A: Hard Reload (Rápido)**
1. Abra o site no navegador
2. Pressione: **Ctrl + Shift + R** (ou **Ctrl + F5**)
3. Isso força o navegador a recarregar sem usar cache

#### **Opção B: Modo Anônimo (Recomendado)**
1. Abra uma janela anônima: **Ctrl + Shift + N**
2. Acesse: `https://mastepalm.com.br/loja/masterpalm_gmail_com`
3. Verifique se as cores roxas aparecem

#### **Opção C: Limpar Cache Completo**
1. Pressione **F12** para abrir DevTools
2. Clique com botão direito no ícone de **Reload** 🔄
3. Selecione **"Empty Cache and Hard Reload"**

---

### **PASSO 2: Verificar no Firestore Console**

1. Acesse: https://console.firebase.google.com/
2. Selecione seu projeto
3. Vá em **Firestore Database**
4. Navegue até:

```
lojas/masterpalm_gmail_com/config/config
```

5. Verifique os campos:
   - `theme.primaria` deve ser **4288086271** (roxo)
   - `colors.primary` deve ser **4288086271** (roxo)
   - Deve ter `publishedAt` com timestamp recente

---

### **PASSO 3: Forçar Nova Publicação**

Se as cores no Firestore estiverem erradas:

1. **Abra o App MasterPalm**
2. **Vá em "Configurações da Loja"**
3. **Verifique se as cores estão ROXAS**
4. **Clique em "Salvar Rascunho"**
5. **Clique em "PUBLICAR CATÁLOGO"** novamente
6. **Aguarde a mensagem:** "Catálogo publicado com sucesso!"
7. **Verifique os logs:**

```
🚀🚀🚀 [PUBLICAR] PUBLICANDO CATÁLOGO 🚀🚀🚀
LojaId: masterpalm_gmail_com
theme.primaria: 4288086271
Cor hex: #FF9700FF
📝 Salvando em draft_config...
✅ Draft salvo!
🌐 Publicando em config (LIVE)...
✅ Config LIVE publicado!
```

---

### **PASSO 4: Verificar no DevTools do Navegador**

1. **Abra o site:** `https://mastepalm.com.br/loja/masterpalm_gmail_com`
2. **Pressione F12** para abrir DevTools
3. **Vá na aba "Console"**
4. **Procure por:**

```
✅ [CATÁLOGO] Tema carregado do Firestore
   theme.primaria: 4288086271
   Cor aplicada: #FF9700FF
```

5. **Se o log mostrar um número diferente**, as configurações antigas estão sendo lidas

---

## 🔧 **COMANDOS DE DEBUG**

### **Ver qual configuração está sendo lida:**

No console do DevTools, execute:

```javascript
// Ver a cor primária atual
getComputedStyle(document.querySelector('.MuiButton-root, button')).backgroundColor

// Ver todas as configurações carregadas
console.log(localStorage.getItem('config'))
```

---

## 📋 **CHECKLIST DE VERIFICAÇÃO**

Execute cada item e marque:

- [ ] **1. Limpei o cache do navegador** (Ctrl + Shift + R)
- [ ] **2. Testei em modo anônimo** (Ctrl + Shift + N)
- [ ] **3. Verifiquei `config/config` no Firestore**
- [ ] **4. Confirmei que `theme.primaria = 4288086271`**
- [ ] **5. Verifiquei que `publishedAt` é recente**
- [ ] **6. Republicei as configurações no app**
- [ ] **7. Verifiquei os logs no console do navegador**

---

## 🎯 **VALORES ESPERADOS**

### **Cores Roxas (Corretas):**
```json
{
  "theme": {
    "primaria": 4288086271,    // #FF9700FF (roxo)
    "fundo": 4278716427,       // Fundo escuro
    "card": 4279505950,        // Card
    "texto": 4294309365,       // Texto claro
    "botaoTexto": 4278190080   // Texto botão
  }
}
```

### **Cores Verdes (Antigas - Erradas):**
```json
{
  "theme": {
    "primaria": 4283215696,    // Verde
    // ... outras cores antigas
  }
}
```

---

## 🚨 **SE NADA FUNCIONAR**

Execute este script no console do DevTools para forçar reload:

```javascript
// Limpar localStorage
localStorage.clear();

// Limpar sessionStorage
sessionStorage.clear();

// Forçar reload completo
window.location.reload(true);
```

---

## 📞 **PRÓXIMOS PASSOS**

1. **Tente o PASSO 1** (limpar cache) primeiro
2. Se não funcionar, **verifique o Firestore** (PASSO 2)
3. Se as cores no Firestore estiverem erradas, **republique** (PASSO 3)
4. Se ainda não funcionar, **me envie:**
   - Screenshot do Firestore mostrando `config/config`
   - Logs do console do navegador (F12 → Console)
   - Logs do app ao publicar

---

## ✅ **TESTE FINAL**

Após seguir os passos, verifique:

1. **Preview (App):** Cores roxas ✅
2. **Web (Navegador):** Cores roxas ✅
3. **Ambos devem estar iguais!**

---

**Última atualização:** 2025-12-27
**Prioridade:** ALTA - Cores incorretas afetam a experiência do usuário
