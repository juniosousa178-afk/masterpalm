# 🌐 Como Fazer Deploy das Modificações para o Catálogo Web

## ⚠️ IMPORTANTE: Diferença entre Deploy de Dados vs Deploy de Código

### O que o botão "Publicar Catálogo" faz:
- ✅ Sincroniza **dados dos produtos** (preços, nomes, estoque, variações) do Hive para o Firestore
- ✅ Atualiza a coleção `lojas/{lojaId}/produtos` no Firebase
- ❌ **NÃO** atualiza o código do site (HTML/CSS/JavaScript gerado pelo Flutter)

### O que você precisa fazer para aplicar as modificações de código:
- 🔧 Rebuild completo da aplicação web
- 🚀 Redeploy do site para o servidor

---

## 🔧 Modificações Aplicadas ao Código:

### 1. **Filtro de Produtos Publicados** (CORRIGIDO)
- **Arquivo:** `public_catalog_screen.dart` linha 313
- **O que foi feito:** Adicionado filtro `.where('publicadoNoCatalogo', isEqualTo: true)`
- **Resultado:** Agora apenas produtos marcados como "publicados" aparecerão no catálogo

### 2. **Suporte a Variações** (CORRIGIDO)
- **Arquivo:** `public_catalog_screen.dart` linha 3068
- **O que foi feito:** Adicionado verificação `hasVariacoes` para abrir modal de seleção
- **Resultado:** Produtos com variações (tamanho + cor) abrirão o modal de seleção

---

## 🚀 PASSO A PASSO: Deploy do Catálogo Web

### Opção 1: Build e Deploy Local (RECOMENDADO)

#### 1️⃣ Build da Aplicação Web
```bash
flutter clean
flutter pub get
flutter build web --release
```

**O que este comando faz:**
- Limpa arquivos antigos
- Baixa dependências atualizadas
- Compila todo o código Dart para JavaScript otimizado
- Gera os arquivos HTML/CSS/JS na pasta `build/web/`

#### 2️⃣ Deploy no Firebase Hosting (se estiver usando)
```bash
firebase deploy --only hosting
```

**OU**, se estiver usando outro servidor:
- Copie todo o conteúdo da pasta `build/web/` para o seu servidor web
- Substitua os arquivos antigos pelos novos

---

### Opção 2: Rebuild Rápido para Teste (apenas desenvolvimento)

Se você estiver rodando o catálogo web localmente para teste:

```bash
# Parar o servidor atual (Ctrl+C)
flutter run -d chrome --release
```

**⚠️ ATENÇÃO:** Isso funciona apenas para teste local! Para o site público, você DEVE fazer o build e deploy completo (Opção 1).

---

## ✅ Verificação Pós-Deploy:

### 1. Produtos Não Publicados (CORRIGIDO ✅)
- ✅ Produtos com `publicadoNoCatalogo = false` NÃO devem aparecer
- ✅ Apenas produtos marcados para publicação aparecem

### 2. Variações (CORRIGIDO ✅)
- ✅ Produtos com variações devem abrir modal ao clicar "Adicionar"
- ✅ Modal deve mostrar opções de tamanho e cor
- ✅ Seleção deve adicionar produto ao carrinho com tamanho/cor escolhidos

### 3. Teste Completo:
1. Abra o catálogo web no navegador
2. Limpe o cache (Ctrl+Shift+Delete ou Ctrl+F5)
3. Procure um produto COM variações
4. Clique em "Adicionar ao Carrinho"
5. ✅ Modal de seleção deve abrir
6. Escolha tamanho e cor
7. ✅ Produto deve ser adicionado com as variações escolhidas
8. Finalize a compra
9. ✅ WhatsApp deve incluir tamanho e cor na mensagem

### 4. Teste de Produtos Não Publicados:
1. No app desktop, marque um produto como "Não publicar no catálogo"
2. Salve e clique em "Publicar Catálogo"
3. Abra o catálogo web
4. ✅ Produto NÃO deve aparecer na lista

---

## 🐛 Troubleshooting:

### Problema: "Ainda não funcionou após o deploy"
**Causa:** Cache do navegador está mostrando versão antiga
**Solução:**
```bash
# No navegador, pressione:
Ctrl + Shift + Delete  # Limpar cache
# OU
Ctrl + F5              # Forçar reload sem cache
```

### Problema: "Produtos não publicados ainda aparecem"
**Causa:** Dados antigos no Firestore sem o campo `publicadoNoCatalogo`
**Solução:**
1. No app desktop, entre na edição de cada produto
2. Salve novamente (mesmo sem alterar nada)
3. Clique em "Publicar Catálogo"
4. Faça novo deploy do web (flutter build web)

### Problema: "Modal de variações não abre"
**Causa 1:** Web não foi reconstruído após a modificação no código
**Solução:** Execute `flutter build web --release` novamente

**Causa 2:** Produto não tem variações no Firestore
**Solução:**
1. Verifique no Firebase Console se o produto tem o campo `variacoes`
2. Se não tiver, edite e salve o produto no app desktop
3. Clique em "Publicar Catálogo"

---

## 📊 Estrutura de Dados Esperada no Firestore:

### Produto COM Variações:
```json
{
  "nome": "Camiseta Básica",
  "ativo": true,
  "publicadoNoCatalogo": true,
  "quantidade": 15,
  "tamanhos": ["P", "M", "G"],
  "cores": ["Vermelho", "Azul", "Verde"],
  "variacoes": {
    "P": {
      "Vermelho": 3,
      "Azul": 2
    },
    "M": {
      "Vermelho": 4,
      "Verde": 3
    },
    "G": {
      "Azul": 3
    }
  }
}
```

### Produto SEM Publicação:
```json
{
  "nome": "Produto Teste",
  "ativo": true,
  "publicadoNoCatalogo": false,  // ❌ NÃO aparece no catálogo
  "quantidade": 10
}
```

---

## 🎯 Resumo do Fluxo Completo:

```
1. Modificar código Dart (✅ JÁ FEITO)
   ↓
2. flutter build web --release (⚠️ VOCÊ PRECISA FAZER)
   ↓
3. Deploy para servidor (⚠️ VOCÊ PRECISA FAZER)
   ↓
4. Limpar cache do navegador
   ↓
5. Testar funcionalidades
```

---

**🔑 Ponto Chave:**
O botão "Publicar Catálogo" no app **NÃO** faz deploy do código. Ele apenas sincroniza os **dados dos produtos** para o Firestore. Para aplicar modificações no **código do site**, você DEVE fazer o build e deploy conforme instruções acima.

---

**Data:** 2026-01-17
**Modificações Aplicadas:**
- ✅ Filtro por `publicadoNoCatalogo` (linha 313)
- ✅ Verificação de `hasVariacoes` no botão Adicionar (linha 3068)
