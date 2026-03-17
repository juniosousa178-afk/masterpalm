# 🔧 Diagnóstico e Solução - Catálogo Web

## ⚠️ IMPORTANTE: Você precisa PUBLICAR o catálogo!

As correções no código foram feitas, mas você precisa **publicar** o conteúdo do rascunho (draft) para o catálogo ao vivo (live) para que as mudanças apareçam no site.

---

## 📋 Checklist de Verificação

### 1️⃣ Publicar o Catálogo
- [ ] Abra o app Flutter
- [ ] Vá para a tela **Estoque**
- [ ] Clique no menu (três pontinhos ⋮) no canto superior direito
- [ ] Selecione **"🚀 Publicar TUDO no Live"**
- [ ] Confirme a publicação

**O que isso faz:**
- Copia `draft_config/config` → `config/config`
- Copia `draft_config/payments` → `config/payments`
- Copia `draft_produtos` → `produtos`
- Publica campanhas ativas

---

### 2️⃣ Verificar se Há Campanhas Ativas

As campanhas precisam estar cadastradas no Firestore:

**Caminho:** `lojas/{lojaId}/campanhas_sorteio`

**Campos necessários:**
```javascript
{
  nome: "Nome da Campanha",
  descricao: "Descrição da campanha",
  ativa: true,  // ⚠️ OBRIGATÓRIO ser true
  dataInicio: Timestamp,
  dataFim: Timestamp,  // ⚠️ Precisa ser >= hoje
  valorMinimo: 150.0,  // Valor mínimo para participar
  premios: [
    {
      label: "10% OFF",
      tipo: "percentual",
      valor: 10.0,
      ativo: true
    },
    // ... mais prêmios
  ]
}
```

**Se não tiver campanhas:**
1. Vá para a tela de **Campanhas e Sorteios** no app
2. Crie uma nova campanha
3. Ative a campanha
4. Configure os prêmios da roleta

---

### 3️⃣ Comandos para Executar (OBRIGATÓRIOS)

Execute estes comandos no terminal:

```bash
# 1. Limpar cache do Flutter
cd "C:\Users\Pichau\apk_nathy\temp_naty"
flutter clean

# 2. Buscar dependências
flutter pub get

# 3. Rebuild do app
flutter run
# OU para web:
flutter run -d chrome
```

---

## 🔍 Como Testar Cada Funcionalidade

### ✅ Testando a Roleta

1. **Pré-requisitos:**
   - Campanha ativa no Firestore com `ativa: true` e `dataFim >= hoje`
   - Carrinho com valor >= `valorMinimo` da campanha

2. **Passos:**
   - Acesse o catálogo web (URL: `/catalog/live` ou abrindo o app em modo live)
   - Adicione produtos ao carrinho (total >= R$ 150 ou o valor mínimo configurado)
   - No checkout, preencha **TODOS** os dados:
     - Nome completo
     - Email
     - Telefone
     - CEP e endereço completo
   - A roleta deve aparecer automaticamente

3. **Se a roleta não aparecer:**
   - Abra o console do navegador (F12)
   - Procure por mensagens com `[ROLETA]` ou `[CAMPANHA]`
   - Verifique se há erros relacionados ao lojaId

---

### ✅ Testando as Campanhas (Banners)

1. **Pré-requisitos:**
   - Pelo menos uma campanha ativa no Firestore

2. **Passos:**
   - Acesse o catálogo web
   - O banner de campanhas deve aparecer logo após os banners de produtos (carrossel)
   - Se houver mais de uma campanha, elas alternam automaticamente a cada 5 segundos

3. **Se os banners não aparecerem:**
   - Verifique no console (F12) se há mensagens `[CAMPANHAS]`
   - Confirme que as campanhas estão com `ativa: true` no Firestore

---

### ✅ Testando o Relatório Financeiro

1. **Fazer uma venda:**
   - Vá para **Vendas** no app
   - Clique em **Nova Venda**
   - Adicione produtos
   - **IMPORTANTE:** Preencha os valores de pagamento:
     - Dinheiro: R$ XX,XX
     - Pix: R$ XX,XX
     - Cartão: R$ XX,XX
   - Finalize a venda

2. **Verificar no relatório:**
   - Vá para **Relatório Financeiro**
   - Na seção "Forma de Pagamento (MÊS)", você deve ver:
     ```
     Dinheiro: R$ XX,XX
     Pix: R$ XX,XX
     Cartão: R$ XX,XX
     ```

3. **Se não aparecer:**
   - Vendas antigas (antes da correção) podem ter valores zerados
   - Faça uma NOVA venda para testar
   - Verifique se está na mesma loja (lojaId) tanto na venda quanto no relatório

---

## 🐛 Problemas Comuns e Soluções

### Problema 1: "lojaId não encontrado" ou "lojaId vazio"

**Solução:**
1. Verifique se você está logado no app
2. Verifique se a loja está selecionada
3. No código, o lojaId é resolvido por:
   ```dart
   final lojaId = await StoreResolverService.resolve();
   ```
4. Se necessário, defina manualmente o lojaId no Hive:
   ```dart
   final box = Hive.box('sessao');
   box.put('store_id', 'sua_loja_id');
   ```

---

### Problema 2: Roleta não aparece mesmo com campanha ativa

**Causas possíveis:**
- Valor do carrinho < valorMinimo da campanha
- Dados do cliente não preenchidos completamente
- Campo `ativa` da campanha = false
- Campo `dataFim` da campanha já passou

**Verificação no Firestore:**
```javascript
// Abra o console do Firestore e rode esta query:
db.collection('lojas')
  .doc('SEU_LOJA_ID')
  .collection('campanhas_sorteio')
  .where('ativa', '==', true)
  .where('dataFim', '>=', new Date())
  .get()
```

---

### Problema 3: Campanhas não aparecem no banner

**Solução:**
1. Verifique se existem campanhas ativas
2. Limpe o cache do navegador (Ctrl+Shift+Del)
3. Faça hard refresh (Ctrl+F5)
4. Verifique o console para mensagens de erro

---

### Problema 4: Vendas antigas não aparecem com pagamentos separados

**Explicação:**
- As vendas antigas foram criadas ANTES da implementação dos campos `pagamentoDinheiro`, `pagamentoPix`, `pagamentoCartao`
- Elas têm valores 0.0 por padrão
- **Solução:** Apenas novas vendas (após a correção) terão os valores separados

---

## 📱 Comandos Úteis para Diagnóstico

```bash
# Ver logs em tempo real (Flutter)
flutter run --verbose

# Ver logs do Firestore no console
# Adicione isto no código temporariamente:
FirebaseFirestore.instance.settings = Settings(
  persistenceEnabled: false,
);
FirebaseFirestore.instance.setLoggingEnabled(true);

# Verificar versão do Flutter
flutter --version

# Verificar devices conectados
flutter devices

# Limpar TUDO e reconstruir
flutter clean
flutter pub get
flutter pub upgrade
flutter run
```

---

## 🎯 Resumo das Ações OBRIGATÓRIAS

1. ✅ **PUBLICAR O CATÁLOGO** via app (Estoque → Menu → Publicar TUDO)
2. ✅ **Criar/Ativar campanhas** no Firestore se não existirem
3. ✅ **Executar flutter clean e flutter pub get**
4. ✅ **Rebuild do app** com flutter run
5. ✅ **Testar fazendo uma NOVA venda** (não venda antiga)
6. ✅ **Limpar cache do navegador** ao testar o catálogo web

---

## 📞 Se Ainda Não Funcionar

Se após seguir TODOS os passos acima ainda não funcionar:

1. **Capture os logs:**
   ```bash
   flutter run > logs.txt 2>&1
   ```

2. **Abra o console do navegador** (F12) e capture:
   - Erros em vermelho
   - Warnings em amarelo
   - Mensagens do Firestore

3. **Verifique o Firestore diretamente:**
   - Acesse o Firebase Console
   - Vá em Firestore Database
   - Navegue até `lojas/{lojaId}/`
   - Confirme que existem documentos em:
     - `config/config`
     - `config/payments`
     - `produtos/` (com produtos ativos)
     - `campanhas_sorteio/` (com campanhas ativas)

4. **Informe os detalhes:**
   - Mensagens de erro específicas
   - Screenshots do console
   - Screenshots do Firestore

---

**Data:** 2025-12-23
**Status:** ✅ Código corrigido - Aguardando publicação e testes
