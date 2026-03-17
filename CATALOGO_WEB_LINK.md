# 🌐 Link do Catálogo Web - MasterPalm

## 📍 **LINK CORRETO DA LOJA**

Para a loja `masterpalm@gmail.com`, o link correto do catálogo online é:

```
https://mastepalm.com.br/loja/masterpalm_gmail_com
```

### ⚠️ **IMPORTANTE: Domínio sem "R"**
- ✅ **Correto:** `mastepalm.com.br` (sem "r" em "maste")
- ❌ **Errado:** `mastepalm.com.br` (com "r" em "master")

---

## 🔧 **CORREÇÕES IMPLEMENTADAS**

### ✅ **1. Botão "Abrir Catálogo Online" Adicionado**

Foi adicionado um botão no AppBar do `PublicCatalogScreen` que:
- Aparece apenas quando **não está em modo preview** (`preview=false`)
- Está localizado no topo, ao lado do logo
- Ícone: 🌐 (ícone de navegador)
- Ao clicar, abre o catálogo web no navegador externo

**Código:** `lib/screens/public_catalog_screen.dart:1520-1554`

```dart
// 🌐 BOTÃO ABRIR CATÁLOGO WEB
if (!widget.preview)
  IconButton(
    icon: Icon(Icons.open_in_browser),
    tooltip: 'Abrir catálogo online',
    onPressed: () async {
      final lojaId = _resolvedLojaId ?? widget.lojaId;
      final url = 'https://mastepalm.com.br/loja/$lojaId';
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    },
  ),
```

---

## 🎯 **COMO USAR**

### **Opção 1: Usar o Botão no App**
1. Abra o app MasterPalm
2. Acesse o catálogo público (não preview)
3. Clique no ícone 🌐 no topo da tela
4. O navegador abrirá com o catálogo web completo

### **Opção 2: Acessar Diretamente**
Copie e cole no navegador:
```
https://mastepalm.com.br/loja/masterpalm_gmail_com
```

---

## 🔍 **VERIFICAR SE AS CONFIGURAÇÕES ESTÃO PUBLICADAS**

Para garantir que as configurações estão sendo recebidas no catálogo web:

### **1. Verificar no Firestore Console**

Acesse o Firebase Console e verifique:

```
✅ lojas/masterpalm_gmail_com/draft_config/config
   → Deve ter todos os campos (cores, banners, layout, etc.)

✅ lojas/masterpalm_gmail_com/config/config
   → Deve ter TODOS os mesmos campos do draft
   → Deve ter publishedAt (timestamp da publicação)
   → Deve ter publishedFrom: "draft"
```

### **2. Verificar no Catálogo Web**

1. Acesse `https://mastepalm.com.br/loja/masterpalm_gmail_com`
2. Abra o DevTools do navegador (F12)
3. Vá na aba **Console**
4. Procure por logs como:

```
✅ [CATÁLOGO] Tema carregado do Firestore
   theme.primaria: 4288086271
   Cor aplicada: #FF9700FF
```

Se esses logs aparecerem, as configurações estão sendo recebidas corretamente!

---

## ⚙️ **ESTRUTURA DE ROTAS DO CATÁLOGO WEB**

### **URLs Suportadas:**

```
https://mastepalm.com.br/loja/{lojaId}
   → Catálogo público da loja

https://mastepalm.com.br/loja/{lojaId}?preview=true
   → Preview do catálogo (lê de draft_config)

https://mastepalm.com.br/loja/{lojaId}?admin=1
   → Modo admin (mostra botões de publicação)
```

### **Exemplos:**

```
# Produção (lê de config/config)
https://mastepalm.com.br/loja/masterpalm_gmail_com

# Preview (lê de draft_config/config)
https://mastepalm.com.br/loja/masterpalm_gmail_com?preview=true

# Admin
https://mastepalm.com.br/loja/masterpalm_gmail_com?admin=1
```

---

## 🚨 **PROBLEMAS COMUNS E SOLUÇÕES**

### **Problema 1: Configurações não aparecem no site**

**Causa:** As configurações não foram publicadas de `draft_config` para `config`

**Solução:**
1. Abra o app MasterPalm
2. Vá em **Configurações da Loja**
3. Clique em **"PUBLICAR CATÁLOGO"**
4. Aguarde a mensagem: "Catálogo publicado com sucesso!"
5. Verifique os logs no console

**Logs esperados:**
```
🚀🚀🚀 [PUBLICAR] PUBLICANDO CATÁLOGO 🚀🚀🚀
📝 Salvando em draft_config...
✅ Draft salvo!
🌐 Publicando em config (LIVE)...
✅ Config LIVE publicado!
```

---

### **Problema 2: URL não carrega**

**Causa:** Domínio digitado errado ou servidor fora do ar

**Solução:**
1. Verifique se o domínio é `mastepalm.com.br` (sem "r")
2. Verifique se o servidor web está rodando
3. Tente acessar: `https://mastepalm.com.br` (homepage)

---

### **Problema 3: Cores/Banners estão incorretos**

**Causa:** Cache do navegador ou configuração antiga

**Solução:**
1. Limpe o cache do navegador (Ctrl + Shift + Delete)
2. Force reload (Ctrl + F5)
3. Ou abra em modo anônimo (Ctrl + Shift + N)
4. Verifique se você publicou as configurações recentemente

---

## 📊 **FLUXO COMPLETO DE PUBLICAÇÃO**

```
┌─────────────────────────────────────────────────────────┐
│  1. EDITAR CONFIGURAÇÕES NO APP                         │
│     (Tela de Configurações)                             │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│  2. SALVAR RASCUNHO                                     │
│     → lojas/{id}/draft_config/config                    │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│  3. CLICAR EM "PUBLICAR CATÁLOGO"                       │
│     → Executa _publicarTudo()                           │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│  4. PUBLICAÇÃO EM config/config (LIVE)                  │
│     → lojas/{id}/config/config                          │
│     → SetOptions(merge: true) ✅                         │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│  5. PUBLICAÇÃO DE PRODUTOS                              │
│     → lojas/{id}/produtos/{id}                          │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│  6. CATÁLOGO WEB LÊ DE config/config                    │
│     → https://mastepalm.com.br/loja/{id}                │
│     → Aplica cores, banners, layout                     │
└─────────────────────────────────────────────────────────┘
```

---

## 🎨 **CONFIGURAÇÕES DISPONÍVEIS NO CATÁLOGO WEB**

O catálogo web suporta as seguintes configurações:

### **Tema (theme)**
- `primaria` - Cor primária (botões, destaques)
- `fundo` - Cor de fundo
- `card` - Cor dos cards de produtos
- `texto` - Cor do texto principal
- `botaoTexto` - Cor do texto dos botões

### **Cores (colors)** - Sistema legado
- `bg` - Background
- `primary` - Primária
- `text` - Texto
- `btnText` - Texto de botões
- Cores de checkout (checkoutCard, checkoutFieldBg, etc.)

### **Mídia (media)**
- `logoUrl` - Logo da loja
- `banners` - Banners do carrossel
- Dimensões desktop/mobile (separadas)

### **Layout (layout)**
- `gridDesktopCols` - Colunas no desktop (padrão: 4)
- `gridMobileCols` - Colunas no mobile (padrão: 2)
- `cardBorderRadius` - Raio da borda dos cards
- `cardShowShadow` - Mostrar sombra nos cards

### **Identidade (identidade)**
- `nome` - Nome da loja
- `whatsapp` - WhatsApp para contato
- `slug` - Slug da loja

### **Pagamentos (payments)**
- Configurações de PIX, Mercado Pago, etc.

### **Fretes (fretes)**
- Opções de frete configuradas

### **Cupons (cupons)**
- Cupons de desconto ativos

---

## 📝 **NOTAS TÉCNICAS**

### **Modo Preview vs Produção**

| Modo | Query Param | Collection Lida | Uso |
|------|-------------|-----------------|-----|
| **Produção** | Nenhum | `config/config` | Clientes finais |
| **Preview** | `?preview=true` | `draft_config/config` | Testar antes de publicar |
| **Admin** | `?admin=1` | `config/config` | Mostrar botões admin |

### **Correções Aplicadas (2025-12-27)**

1. ✅ `catalog_publish_service.dart` - `merge: false` → `merge: true`
2. ✅ `admin_publish_fab.dart` - `merge: false` → `merge: true`
3. ✅ `admin_publish_bar.dart` - Bug crítico no path corrigido
4. ✅ `firestore_service.dart` - `merge: false` → `merge: true`
5. ✅ `produtos_service.dart` - `merge: false` → `merge: true`
6. ✅ Logs detalhados adicionados em todas as funções de publicação
7. ✅ Botão "Abrir Catálogo Online" adicionado ao `PublicCatalogScreen`

---

## 📞 **SUPORTE**

Se ainda tiver problemas:

1. **Verifique os logs do app:**
   - Procure por `[PUBLICAR]`, `[PUBLISH-CONFIG]`, `[ADMIN-FAB]`
   - Procure por mensagens de erro (`❌`)

2. **Verifique os logs do navegador:**
   - Abra DevTools (F12) → Console
   - Procure por `[CATÁLOGO]`

3. **Teste a URL diretamente:**
   ```
   https://mastepalm.com.br/loja/masterpalm_gmail_com
   ```

4. **Verifique o Firestore:**
   - `lojas/masterpalm_gmail_com/config/config` deve existir
   - Deve ter timestamp `publishedAt`

---

**Última atualização:** 2025-12-27
**Versão das correções:** 1.0
