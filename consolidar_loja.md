# 🔧 Script para Consolidar Lojas

## Problema
Você tem 2 lojas no Firestore:
- `loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2` (loja técnica)
- `nathy-pratas-e-folheados` (loja slug)

Precisamos consolidar tudo em UMA loja.

## Solução Recomendada: Usar nathy-pratas-e-folheados

### Passo 1: No Firestore Console
1. Acesse: https://console.firebase.google.com
2. Vá em Firestore Database
3. Navegue até: `lojas/loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2`
4. **REMOVA** o campo `redirectTo` (delete esse campo)

### Passo 2: Copiar Produto "anel" para nathy-pratas-e-folheados
1. No Firestore, vá em: `lojas/loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2/produtos/loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2-anel`
2. Copie TODO o documento
3. Crie novo documento em: `lojas/nathy-pratas-e-folheados/produtos/nathy-pratas-e-folheados-anel`
4. Cole os dados
5. Atualize os campos:
   - `lojaId` = `nathy-pratas-e-folheados`
   - `id` = `nathy-pratas-e-folheados-anel`

### Passo 3: Copiar Draft Produtos
1. Vá em: `lojas/loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2/draft_produtos/loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2-anel`
2. Copie TODO o documento
3. Crie em: `lojas/nathy-pratas-e-folheados/draft_produtos/nathy-pratas-e-folheados-anel`
4. Cole e atualize `lojaId` e `id`

### Passo 4: Copiar Configurações
1. Vá em: `lojas/loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2/config/config`
2. Copie as configurações de:
   - `theme`
   - `media` (logo e banners)
   - `fretes`
   - `cupons`
   - etc
3. Cole em: `lojas/nathy-pratas-e-folheados/config/config`
4. Faça o mesmo para `draft_config/config`

### Passo 5: No App
1. Vá em "Configurações da Loja"
2. No campo "Slug (URL amigável)", digite: `nathy_pratas_e_folheados`
3. Clique em "PUBLICAR TUDO"

## ✅ Resultado Final
- Tudo consolidado em `nathy-pratas-e-folheados`
- URL: https://mastepalm.com.br/loja/nathy_pratas_e_folheados
- Todos os produtos aparecem
- Logo e banners funcionam
