# 🎯 Como Criar Campanhas e Ativar Roleta no Firestore

## 🚨 PROBLEMA: Campanhas e Roleta Não Aparecem

**Causa mais comum:** Não existem campanhas criadas no Firestore para a sua loja.

---

## ✅ Solução: Criar Campanhas Manualmente no Firestore

### Passo 1: Abrir o Firebase Console

1. Acesse: https://console.firebase.google.com/
2. Selecione seu projeto (masterpalm-58c46)
3. Clique em **Firestore Database** no menu lateral

### Passo 2: Navegar até a Coleção Correta

No Firestore, navegue seguindo esta estrutura:

```
lojas
  └── {SEU_LOJA_ID}  (ex: masterpalm_gmail_com)
      └── campanhas_sorteio  ← CRIAR ESTA COLEÇÃO
```

**Para encontrar seu lojaId:**
- Vá em **Firestore Database**
- Expanda a coleção `lojas`
- Você verá documentos como `masterpalm_gmail_com` ou similar
- Esse é o seu lojaId!

### Passo 3: Criar uma Campanha

Dentro de `lojas/{SEU_LOJA_ID}/campanhas_sorteio`, clique em **"Adicionar documento"**:

#### Campos Obrigatórios:

| Campo | Tipo | Valor Exemplo | Descrição |
|-------|------|---------------|-----------|
| **nome** | string | `"Promoção de Natal"` | Nome da campanha |
| **descricao** | string | `"Concorra a prêmios incríveis!"` | Descrição curta |
| **ativa** | boolean | `true` | ⚠️ OBRIGATÓRIO SER `true`! |
| **dataInicio** | timestamp | `2025-12-01 00:00:00` | Data de início |
| **dataFim** | timestamp | `2025-12-31 23:59:59` | ⚠️ Precisa ser FUTURO! |
| **dataSorteio** | timestamp | `2026-01-05 20:00:00` | Data do sorteio |
| **premioDescricao** | string | `"Vale-compras R$ 500"` | Descrição do prêmio |
| **valorMinimo** | number | `100.00` | Valor mínimo de compra |
| **valorX** | number | `50.00` | A cada R$ X gera 1 número |
| **status** | string | `"aberta"` | Status da campanha |

#### Como Adicionar no Firebase Console:

1. Clique em **"Adicionar documento"**
2. Deixe o **ID do documento** como "Geração automática de ID"
3. Para cada campo:
   - Clique em **"Adicionar campo"**
   - Digite o **nome do campo**
   - Selecione o **tipo** correto (string, boolean, number, timestamp)
   - Digite o **valor**

#### ⚠️ ATENÇÃO ESPECIAL:

- **ativa**: Precisa ser `boolean` com valor `true` (não string "true")
- **dataFim**: Precisa ser tipo `timestamp` com data FUTURA
- **Tipos numéricos**: Use `number`, não `string`

---

## 🎰 Configurar a Roleta

Agora configure os prêmios da roleta:

### Passo 1: Navegar até a Config da Roleta

```
lojas
  └── {SEU_LOJA_ID}
      └── campanhas_sorteio_config  ← CRIAR ESTA COLEÇÃO
          └── roleta  ← CRIAR ESTE DOCUMENTO (ID FIXO: "roleta")
```

### Passo 2: Criar o Documento "roleta"

ID do documento: **`roleta`** (fixo, não pode ser outro nome)

#### Campos:

```javascript
{
  ativo: true,  // boolean
  valorMinimo: 150.0,  // number - valor mínimo para ativar roleta
  premios: [  // array
    {
      label: "10% OFF",
      tipo: "percentual",
      valor: 10.0,
      ativo: true
    },
    {
      label: "Frete Grátis",
      tipo: "frete_gratis",
      valor: 0.0,
      ativo: true
    },
    {
      label: "R$ 20 OFF",
      tipo: "valor",
      valor: 20.0,
      ativo: true
    },
    {
      label: "Gire Novamente",
      tipo: "gire_novamente",
      valor: 0.0,
      ativo: true
    },
    {
      label: "Não foi dessa vez",
      tipo: "sem_premio",
      valor: 0.0,
      ativo: true
    }
  ]
}
```

#### Como Adicionar Array no Firebase Console:

1. Crie o documento com ID: `roleta`
2. Adicione campo `ativo` (boolean): `true`
3. Adicione campo `valorMinimo` (number): `150.0`
4. Adicione campo `premios` (array):
   - Clique em **"Adicionar campo"**
   - Nome: `premios`
   - Tipo: **array**
   - Clique no array para expandi-lo
   - Para cada prêmio, clique em **"Adicionar item ao array"**:
     - Tipo: **map**
     - Dentro do map, adicione:
       - `label` (string): "10% OFF"
       - `tipo` (string): "percentual"
       - `valor` (number): 10.0
       - `ativo` (boolean): true

---

## 🧪 Testar se Está Funcionando

### 1. Verificar os Logs

Após criar as campanhas, execute o app:

```bash
flutter run -d chrome
```

Você deve ver nos logs:

```
📱 [CATALOG] Renderizando catálogo para loja: masterpalm_gmail_com (preview: false)
🎯 [CAMPANHAS] Carregando campanhas para loja: masterpalm_gmail_com
🎯 [CAMPANHAS] Encontradas 1 campanhas ativas
🎰 [ROLETA] Carregando config para loja: masterpalm_gmail_com
✅ [ROLETA] Config carregada: valorMinimo=150.0, premios=5
```

### 2. Ver Campanhas no Catálogo

- Abra o catálogo web
- Logo após o banner principal (imagem grande), deve aparecer um **banner roxo/rosa** com a campanha
- Se houver múltiplas campanhas, elas alternam automaticamente a cada 5 segundos

### 3. Ver a Roleta no Checkout

1. Adicione produtos ao carrinho (total >= R$ 150 ou o valorMinimo configurado)
2. Clique no ícone do carrinho
3. Preencha **TODOS** os campos do formulário:
   - Nome completo
   - CPF
   - Email
   - Telefone
   - CEP
   - Endereço completo (rua, número, bairro, cidade, estado)
4. A roleta deve aparecer automaticamente ao final do formulário

---

## 🐛 Troubleshooting

### Problema: "0 campanhas ativas" nos logs

**Causas:**

1. **Campo `ativa` é string em vez de boolean**
   - ❌ Errado: `ativa: "true"` (string)
   - ✅ Certo: `ativa: true` (boolean)

2. **Campo `dataFim` é string em vez de timestamp**
   - ❌ Errado: `dataFim: "2025-12-31"` (string)
   - ✅ Certo: `dataFim: Timestamp(2025-12-31)` (timestamp)

3. **Data `dataFim` já passou**
   - Verifique se a data é futura
   - O sistema compara com a data atual

4. **Campanha está em outra loja**
   - Certifique-se de criar em `lojas/{SEU_LOJA_ID_CORRETO}/campanhas_sorteio`

### Problema: Roleta não aparece

**Causas:**

1. **Valor do carrinho < valorMinimo**
   - Veja no log: `valorMinimo=150.0`
   - Adicione mais produtos

2. **Dados do cliente não preenchidos**
   - Preencha TODOS os campos do checkout

3. **Config da roleta não existe**
   - Crie o documento `lojas/{lojaId}/campanhas_sorteio_config/roleta`

4. **Não há campanha ativa**
   - A roleta só aparece se houver pelo menos 1 campanha ativa

---

## 📋 Checklist Completo

- [ ] Encontrei meu lojaId no Firestore
- [ ] Criei a coleção `lojas/{lojaId}/campanhas_sorteio`
- [ ] Criei pelo menos 1 campanha com:
  - [ ] `ativa: true` (boolean, não string)
  - [ ] `dataFim` (timestamp) com data FUTURA
  - [ ] `valorMinimo` (number)
- [ ] Criei a coleção `lojas/{lojaId}/campanhas_sorteio_config`
- [ ] Criei o documento `roleta` (ID fixo) com:
  - [ ] `ativo: true`
  - [ ] `valorMinimo` (number)
  - [ ] `premios` (array de maps)
- [ ] Executei `flutter clean && flutter pub get && flutter run`
- [ ] Vi os logs confirmando campanhas carregadas
- [ ] Testei no catálogo web e vi o banner de campanhas
- [ ] Adicionei produtos (valor >= valorMinimo)
- [ ] Preenchi TODOS os campos do checkout
- [ ] Vi a roleta aparecer

---

## 🎉 Resultado Final

Quando tudo estiver configurado:

1. **Banner de Campanhas:** Aparece logo após o carrossel de imagens no topo
2. **Roleta:** Aparece no checkout após preencher todos os dados
3. **Isolamento por Loja:** Cada loja vê apenas suas próprias campanhas

---

**Data:** 2025-12-23
**Status:** ✅ Guia completo para configuração manual
