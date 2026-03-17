# 🎯 Como Ativar a Roleta e Campanhas - Passo a Passo

## ✅ Status Atual
- ✅ Código integrado e compilando sem erros
- ✅ Roleta funcionando
- ✅ Sistema de cupons implementado
- ⚠️ **FALTA**: Criar índice no Firestore e criar campanha de teste

---

## 📋 Passo 1: Deploy do Índice Firestore

O índice composto já foi adicionado ao arquivo `firestore.indexes.json`. Agora precisa fazer o deploy:

### Opção A: Deploy via Firebase CLI (Recomendado)

```bash
# No terminal, na pasta do projeto:
firebase deploy --only firestore:indexes
```

**Resultado esperado:**
```
✔ Deploy complete!
✔ Firestore indexes deployed successfully
```

### Opção B: Criar Manualmente no Console Firebase

Se não tiver Firebase CLI instalado ou der erro:

1. Acesse: https://console.firebase.google.com
2. Selecione seu projeto
3. Vá em **Firestore Database** → **Indexes** → **Composite**
4. Clique em **Create Index**
5. Preencha:
   - **Collection ID**: `campanhas_sorteio`
   - **Scope**: Collection
   - Campo 1:
     - Field path: `ativa`
     - Order: Ascending
   - Campo 2:
     - Field path: `dataFim`
     - Order: Ascending
   - Query scope: Collection
6. Clique em **Create**
7. Aguarde 2-5 minutos para o índice ser criado

---

## 📋 Passo 2: Criar Campanha de Teste

Após o índice estar criado, você precisa criar uma campanha de sorteio no Firestore:

### Via Firebase Console:

1. Acesse: https://console.firebase.google.com
2. Vá em **Firestore Database**
3. Navegue até: `/lojas/{SUA_LOJA_ID}/campanhas_sorteio`
4. Clique em **Add document**
5. **Document ID**: `campanha_teste` (ou auto-ID)
6. Adicione os seguintes campos:

```javascript
// Campos obrigatórios:
{
  "nome": "Super Sorteio de Natal",
  "descricao": "Concorra a prêmios incríveis!",
  "ativa": true,
  "valorMinimo": 0,
  "premios": [
    "10% de desconto",
    "15% de desconto",
    "R$ 20 de desconto",
    "Frete grátis",
    "5% de desconto",
    "R$ 10 de desconto"
  ],
  "dataInicio": [Timestamp de hoje - clique no ícone de relógio],
  "dataFim": [Timestamp daqui 30 dias],
  "createdAt": [Timestamp atual]
}
```

### Explicação dos Campos:

- **nome**: Nome da campanha (aparece no banner)
- **descricao**: Descrição curta
- **ativa**: `true` para ativar, `false` para desativar
- **valorMinimo**: Valor mínimo do carrinho para poder girar (0 = sem mínimo)
- **premios**: Array com os prêmios da roleta (6-8 prêmios recomendado)
- **dataInicio**: Data de início da campanha
- **dataFim**: Data de término (campanha só aparece se dataFim > hoje)
- **createdAt**: Data de criação

### Formatos de Prêmios Aceitos:

A roleta detecta automaticamente o tipo pelo texto do prêmio:

```javascript
// Desconto percentual (ex: 10% de desconto)
"10% de desconto"     → tipo: 'percentual', valor: 10.0

// Desconto em valor fixo (ex: R$ 20 de desconto)
"R$ 20 de desconto"   → tipo: 'valor', valor: 20.0

// Frete grátis
"Frete grátis"        → tipo: 'frete_gratis', valor: 0.0
```

---

## 📋 Passo 3: Testar o Sistema

Após criar o índice e a campanha:

### 1. Reiniciar o App

```bash
# Parar o app (Ctrl+C no terminal)
# Rodar novamente:
flutter run
```

### 2. Verificar Banner de Campanhas

1. ✅ Abra o catálogo público (link de catálogo web da loja)
2. ✅ **Deve aparecer** um banner no topo com:
   - Nome da campanha
   - Descrição
   - Dias restantes
   - Valor mínimo (se houver)

Se o banner **NÃO aparecer**:
- Verifique se o índice foi criado no Firebase Console
- Verifique se a campanha tem `ativa: true`
- Verifique se `dataFim` é maior que a data atual
- Veja os logs no terminal para erros

### 3. Testar Roleta no Carrinho

1. ✅ Adicione produtos ao carrinho
2. ✅ Clique em "Ver Carrinho" ou no ícone do carrinho
3. ✅ **Deve aparecer** a roleta antes dos botões de finalizar compra
4. ✅ Clique em "Girar a Roleta"
5. ✅ Aguarde a animação (4 segundos)
6. ✅ **Deve aparecer** um modal mostrando:
   - Código do cupom (ex: PREMIO-1234)
   - Descrição do prêmio
   - Validade: 60 dias
   - Aviso: "Use na sua PRÓXIMA compra"
   - Aviso: "Uso único"

Se a roleta **NÃO aparecer**:
- Confirme que o banner está aparecendo (passo 2)
- Verifique os logs para mensagem "✅ Campanha ativa encontrada"
- Adicione `debugPrint` em `_verificarCampanhaAtiva()` se necessário

### 4. Testar Uso do Cupom na Próxima Compra

1. ✅ **Copie o código do cupom** (ex: PREMIO-1234)
2. ✅ Feche o carrinho
3. ✅ Adicione NOVOS produtos ao carrinho (ou mantenha os atuais)
4. ✅ Abra o carrinho novamente
5. ✅ No campo "Cupom de desconto", digite o código
6. ✅ Clique em "Aplicar"
7. ✅ **Deve mostrar**:
   - Mensagem: "🎉 Desconto de XX% aplicado!"
   - Subtotal atualizado com desconto
   - Código do cupom exibido
8. ✅ Finalize a compra (WhatsApp ou Mercado Pago)
9. ✅ Cupom deve ser marcado como "usado"

### 5. Testar Uso Único

1. ✅ Tente usar o **mesmo cupom** novamente
2. ✅ **Deve mostrar erro**: "Cupom já foi utilizado em XX/XX/XXXX"

### 6. Testar Expiração

Para testar expiração (opcional):
1. No Firestore, edite manualmente um cupom gerado
2. Altere `dataExpiracao` para uma data passada
3. Tente usar o cupom
4. **Deve mostrar erro**: "Cupom expirado em XX/XX/XXXX"

---

## 🔧 Troubleshooting

### Banner não aparece

**Causa:** Índice não foi criado ou campanha inválida

**Solução:**
```bash
# Ver logs:
flutter run --verbose

# Procure por:
❌ Erro ao carregar campanhas: [cloud_firestore/failed-precondition]
```

Se ainda mostrar `failed-precondition`:
- O índice não foi criado corretamente
- Aguarde alguns minutos e tente novamente
- Crie manualmente no Console Firebase (Opção B do Passo 1)

### Roleta não aparece

**Causa:** Banner não carregou ou `_campanhaAtivaId` está null

**Solução:**
1. Confirme que o banner está aparecendo primeiro
2. Adicione debug print em `public_catalog_screen.dart:2791`:
```dart
Future<void> _verificarCampanhaAtiva() async {
  try {
    debugPrint('🔍 Buscando campanha ativa...');
    final snapshot = await FirebaseFirestore.instance
      .collection('lojas')
      .doc(widget.lojaId)
      .collection('campanhas_sorteio')
      .where('ativa', isEqualTo: true)
      .where('dataFim', isGreaterThanOrEqualTo: Timestamp.now())
      .limit(1)
      .get();

    debugPrint('📊 Campanhas encontradas: ${snapshot.docs.length}');

    if (snapshot.docs.isNotEmpty) {
      if (mounted) {
        setState(() {
          _campanhaAtivaId = snapshot.docs.first.id;
        });
        debugPrint('✅ Campanha ativa: $_campanhaAtivaId');
      }
    } else {
      debugPrint('⚠️ Nenhuma campanha ativa encontrada');
    }
  } catch (e) {
    debugPrint('❌ Erro ao verificar campanha: $e');
  }
}
```

3. Rode novamente e veja os logs

### Cupom não valida

**Causa:** Código incorreto ou cupom expirado/usado

**Verificações:**
1. Confirme que o código está correto (case-insensitive)
2. Verifique se começa com "PREMIO-"
3. No Firestore, veja a coleção `/lojas/{lojaId}/cupons_premio`
4. Confira os campos:
   - `usado: false`
   - `dataExpiracao` > data atual

### Desconto não aplica

**Causa:** Tipo de cupom incorreto

**Solução:**
1. Verifique o campo `tipo` do cupom no Firestore:
   - `percentual` → desconto em %
   - `valor` → desconto em R$
   - `frete_gratis` → desconto no frete
2. Verifique o campo `valorDesconto`

---

## 📊 Estrutura Firestore Final

```
/lojas
  /{lojaId}
    /campanhas_sorteio
      /{campanhaId}
        - nome: string
        - descricao: string
        - ativa: boolean ✅ INDEXADO
        - valorMinimo: number
        - premios: string[]
        - dataInicio: Timestamp
        - dataFim: Timestamp ✅ INDEXADO
        - createdAt: Timestamp

    /cupons_premio
      /{cupomId}
        - codigo: string (ex: "PREMIO-1234")
        - tipo: string (percentual|valor|frete_gratis)
        - valorDesconto: number
        - dataExpiracao: Timestamp (+60 dias)
        - usado: boolean
        - dataUso: Timestamp | null
        - vendaId: string | null
        - premioOriginal: string
        - lojaId: string
        - clienteEmail: string | null
        - dataCriacao: Timestamp
```

---

## 🎯 Comandos Úteis

```bash
# Deploy do índice
firebase deploy --only firestore:indexes

# Ver status dos índices
firebase firestore:indexes

# Rodar app
flutter run

# Rodar com logs detalhados
flutter run --verbose

# Build web
flutter build web

# Limpar cache
flutter clean && flutter pub get
```

---

## ✅ Checklist Final

Antes de considerar completo, verifique:

- [ ] Índice criado no Firestore (passo 1)
- [ ] Campanha criada com `ativa: true` (passo 2)
- [ ] Banner aparece no catálogo (passo 3.2)
- [ ] Roleta aparece no carrinho (passo 3.3)
- [ ] Cupom é gerado ao girar (passo 3.3)
- [ ] Cupom pode ser aplicado na próxima compra (passo 3.4)
- [ ] Desconto é aplicado corretamente (passo 3.4)
- [ ] Cupom marcado como usado após compra (passo 3.4)
- [ ] Cupom não pode ser usado novamente (passo 3.5)
- [ ] Cupom expira após 60 dias (opcional - passo 3.6)

---

## 🎊 Pronto!

Após seguir esses passos, o sistema de roleta e cupons estará 100% funcional!

**Data:** 21/12/2025
**Status:** Aguardando deploy do índice e criação de campanha
**Próximo Passo:** Execute o Passo 1 (Deploy do índice)
