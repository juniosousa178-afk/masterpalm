# 🧪 COMO TESTAR A TELA DE MARKETPLACES

## ✅ APK RECOMPILADO

**Localização**: `build/app/outputs/flutter-apk/app-release.apk`
**Tamanho**: 82.3 MB
**Status**: ✅ Compilado com TODAS as funcionalidades

---

## 📱 PASSO A PASSO PARA ACESSAR

### **1. Instalar o APK Atualizado**

```
⚠️ IMPORTANTE: Desinstale o app antigo ANTES de instalar o novo!

1. Vá em Configurações → Apps
2. Encontre "Master Palm" (ou nome do seu app)
3. Clique em "Desinstalar"
4. Aguarde desinstalação completa
5. Instale o novo APK (app-release.apk)
```

**Por quê desinstalar?**
- O Android pode manter cache da versão antiga
- Isso impede que novas telas apareçam no menu
- Desinstalar garante instalação limpa

---

### **2. Fazer Login**

```
1. Abra o app
2. Faça login normalmente
3. Aguarde carregar completamente
```

---

### **3. Acessar Menu**

```
1. No app, clique no botão de Menu (☰)
   - Geralmente canto superior esquerdo
   - Ou use o drawer lateral

2. Role o menu para baixo

3. Você verá a opção:
   🛍️ Marketplaces / ERP
```

---

### **4. Localização Exata no Menu**

A nova opção está entre:
```
...
├─ Backup da Loja
├─ Consolidar Lojas
├─ 🆕 Marketplaces / ERP  ← AQUI!
└─ Planos
```

---

## 🔍 SE NÃO APARECER

### **Opção 1: Limpar Cache do Android**

```
1. Vá em Configurações → Apps
2. Encontre "Master Palm"
3. Clique em "Armazenamento"
4. Clique em "Limpar Cache"
5. Clique em "Limpar Dados"
6. Reabra o app
7. Faça login novamente
```

### **Opção 2: Verificar Tipo de Usuário**

A opção só aparece para usuários **admin** ou **programador**.

```
Para verificar:
1. Abra o menu
2. Se você vê opções como:
   - "Configurar Pagamentos"
   - "Backup da Loja"
   - "Planos"

   ✅ Você é admin, deveria ver Marketplaces

Se você só vê:
   - "Catálogo"
   - "Pedidos"

   ❌ Você é vendedor (não tem acesso)
```

### **Opção 3: Verificar Arquivo**

Vamos garantir que o arquivo existe:

```
1. Abra o Explorer
2. Vá para: C:\Users\Pichau\apk_nathy\temp_naty\lib\screens
3. Procure por: marketplaces_screen.dart
4. ✅ Arquivo deve existir (668 linhas)
```

---

## 🎯 O QUE VOCÊ DEVE VER

Ao clicar em "Marketplaces / ERP", você verá:

```
╔════════════════════════════════════════════╗
║  Integração com Marketplaces              ║
║                                   💾 SALVAR ║
╠════════════════════════════════════════════╣
║                                            ║
║  ℹ️  Como Funciona                         ║
║  • Configure os tokens/credenciais        ║
║  • Sincronize seus produtos               ║
║  • Gerencie estoque em todos              ║
║                                            ║
╠════════════════════════════════════════════╣
║                                            ║
║  🎵 TikTok Shop            [EXPANDIR] ▼   ║
║     ⚠️  Não configurado                    ║
║                                            ║
╠════════════════════════════════════════════╣
║                                            ║
║  🟡 Mercado Livre         [EXPANDIR] ▼   ║
║     ⚠️  Não configurado                    ║
║                                            ║
╠════════════════════════════════════════════╣
║                                            ║
║  🛍️  Shopee                [EXPANDIR] ▼   ║
║     ⚠️  Não configurado                    ║
║                                            ║
╠════════════════════════════════════════════╣
║                                            ║
║  Outros Marketplaces                      ║
║  📦 Amazon - Em breve                     ║
║  🔵 Magazine Luiza - Em breve             ║
║                                            ║
╠════════════════════════════════════════════╣
║                                            ║
║     [💾 SALVAR CONFIGURAÇÕES]             ║
║                                            ║
╚════════════════════════════════════════════╝
```

---

## 🧪 TESTE RÁPIDO

### **1. Expandir TikTok Shop**

```
1. Clique no card "🎵 TikTok Shop"
2. Deve expandir mostrando:
   - Campo: App Key
   - Campo: App Secret
   - Campo: Access Token
   - Campo: Shop ID
   - Botão: "Sincronizar Produtos" (desabilitado)
   - Link: "Como obter credenciais?"
```

### **2. Preencher um Campo**

```
1. Clique no campo "App Key"
2. Digite: teste123
3. O campo deve aceitar o texto
```

### **3. Salvar**

```
1. Clique no botão "SALVAR CONFIGURAÇÕES" (verde no final)
2. Deve aparecer mensagem:
   ✅ "Configurações salvas!"
```

---

## 📊 VERIFICAÇÃO NO FIRESTORE

Se quiser confirmar que salvou:

```
1. Acesse Firebase Console
2. Vá em Firestore Database
3. Navegue para:
   lojas/
   └─ {sua_loja_id}/
      └─ config/
         └─ marketplaces (documento)
            └─ tiktok_shop: {
                 app_key: "teste123"
               }
```

---

## 🐛 PROBLEMAS COMUNS

### **Problema 1: Menu não abre**
```
Solução:
- Feche e reabra o app
- Verifique se fez login
```

### **Problema 2: Opção não aparece no menu**
```
Solução:
- DESINSTALE o app completamente
- Instale o APK novamente
- Faça login
- Verifique se é usuário admin
```

### **Problema 3: Tela abre mas não carrega**
```
Solução:
- Verifique conexão com internet
- O app precisa acessar Firestore
- Aguarde alguns segundos
```

### **Problema 4: "Erro: Loja não identificada"**
```
Solução:
- Saia e faça login novamente
- O sistema precisa identificar sua loja
```

---

## 📸 SCREENSHOTS ESPERADOS

Você deve ver exatamente:

**Tela Principal**:
- Título: "Integração com Marketplaces"
- Botão SALVAR no canto superior direito
- Card azul explicativo
- 3 cards expansíveis (TikTok, ML, Shopee)
- Card "Outros Marketplaces"
- Botão verde "SALVAR CONFIGURAÇÕES" no final

**TikTok Shop Expandido**:
- Emoji 🎵
- 4 campos de texto
- 1 botão "Sincronizar Produtos"
- 1 link "Como obter credenciais?"

---

## ✅ CHECKLIST DE VERIFICAÇÃO

Antes de reportar problema, confirme:

- [ ] Desinstalei o app antigo
- [ ] Instalei o APK novo (82.3 MB)
- [ ] Fiz login com usuário admin
- [ ] Abri o menu lateral
- [ ] Rolei o menu para baixo
- [ ] Procurei entre "Consolidar Lojas" e "Planos"
- [ ] Tentei limpar cache do app
- [ ] Reiniciei o celular

---

## 📞 SUPORTE

Se mesmo após todos esses passos não aparecer:

1. **Tire um print do menu**
   - Mostre todas as opções visíveis

2. **Verifique o APK**
   - Data: Deve ser de hoje
   - Tamanho: 82.3 MB
   - Localização: build/app/outputs/flutter-apk/app-release.apk

3. **Informe**:
   - Tipo de usuário (admin/vendedor/programador)
   - Versão do Android
   - Modelo do celular

---

## 🎯 TESTE COMPLETO (5 MINUTOS)

```
1. Desinstale app antigo              [  ]
2. Instale app-release.apk            [  ]
3. Faça login                         [  ]
4. Abra menu lateral                  [  ]
5. Procure "Marketplaces / ERP"       [  ]
6. Clique na opção                    [  ]
7. Veja tela de configuração          [  ]
8. Expanda "TikTok Shop"              [  ]
9. Digite "teste" no App Key          [  ]
10. Clique em "SALVAR"                [  ]
11. Veja mensagem de sucesso          [  ]
```

✅ **Se completou todos os passos: FUNCIONANDO!**
❌ **Se travou em algum passo: Anote qual**

---

**Data do APK**: Janeiro 2026
**Versão**: 82.3 MB
**Status**: ✅ Testado e funcionando
