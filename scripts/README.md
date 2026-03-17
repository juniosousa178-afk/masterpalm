# Scripts de Gerenciamento do Firestore

Este diretório contém scripts administrativos para gerenciar o Firebase/Firestore do MasterPalm.

## Scripts Disponíveis

### 1. cleanup_firestore.js
Script para limpar o Firestore removendo todos os dados de teste, mantendo apenas o usuário root (masterpalm@gmail.com) e sua loja.

### 2. verify_cleanup.js
Script para verificar o estado atual do Firestore após a limpeza.

### 3. fix_master_config.js
Script para corrigir a configuração master removendo usuários deletados da lista de acesso ilimitado.

### 4. disable_recaptcha_auth.js
**Obrigatório para APK Android** quando o login manual mostra "Erro de token (reCAPTCHA)".

Desabilita o reCAPTCHA Enterprise no login com e-mail/senha do Firebase Auth.

```bash
node scripts/disable_recaptcha_auth.js
```

Requer: `scripts/serviceAccountKey.json` (chave de serviço do Firebase com permissão "Firebase Authentication Admin").

---

## cleanup_firestore.js - Detalhes

### O que o script faz:

✅ **MANTÉM:**
- Usuário root: `masterpalm@gmail.com`
- Loja do root: `masterpalm_gmail_com` ou `loja_uid_[UID]`
- Configurações master em `/app_config`
- Planos de assinatura em `/planos`

❌ **REMOVE:**
- Todos os outros usuários do Firebase Authentication
- Todos os outros documentos em `/usuarios`
- Todas as outras lojas em `/lojas` (com todas as subcoleções)
- Todos os pré-pedidos em `/pre_pedidos`
- Todos os checkouts em `/checkout_planos`
- Todas as campanhas em `/campanhas_sorteio`
- Todas as assinaturas (exceto do root)
- Todos os clientes globais em `/clientes_globais`

### Como usar:

1. **Instalar dependências:**
   ```bash
   cd scripts
   npm install
   ```

2. **Executar o script:**
   ```bash
   node cleanup_firestore.js
   ```

   Ou usando npm:
   ```bash
   npm run cleanup
   ```

3. **Confirmar a operação:**
   - O script pedirá confirmação antes de executar
   - Digite `CONFIRMAR` (em maiúsculas) para prosseguir
   - Qualquer outra resposta cancelará a operação

### ⚠️ AVISO IMPORTANTE:

**Esta operação NÃO PODE SER DESFEITA!**

Certifique-se de:
- Fazer backup dos dados importantes antes de executar
- Verificar que realmente deseja remover todos os dados de teste
- Confirmar que o usuário `masterpalm@gmail.com` existe no Firebase

### Requisitos:

- Node.js instalado (versão 14 ou superior)
- Arquivo `serviceAccountKey.json` na pasta `scripts/`
- Permissões de administrador no projeto Firebase

### Exemplo de saída:

```
⚠️  ATENÇÃO! Este script irá:
   - Deletar TODOS os usuários exceto masterpalm@gmail.com
   - Deletar TODAS as lojas exceto a do root
   - Deletar TODOS os pedidos, checkouts, campanhas
   - Esta ação NÃO PODE SER DESFEITA!

Digite "CONFIRMAR" para continuar: CONFIRMAR

🧹 Iniciando limpeza do Firestore...

1️⃣ Buscando usuário root...
✅ Usuário root encontrado: masterpalm@gmail.com (UID: xxx)

2️⃣ Limpando usuários do Firebase Authentication...
   ❌ Deletado: natypolylopes1997@gmail.com
   ❌ Deletado: juniosousa178@gmail.com
✅ 96 usuários removidos do Authentication

3️⃣ Limpando coleção /usuarios...
✅ 95 usuários removidos de /usuarios

4️⃣ Limpando coleção /lojas...
✅ 50 lojas removidas

...

✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ LIMPEZA CONCLUÍDA COM SUCESSO!
✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Resumo:
   - Usuários Auth removidos: 96
   - Documentos /usuarios removidos: 95
   - Lojas removidas: 50
   - Assinaturas removidas: 10
   - Usuário mantido: masterpalm@gmail.com

✨ Firestore pronto para novos cadastros!
```

### Solução de problemas:

**Erro: "Cannot find module 'firebase-admin'"**
- Execute: `npm install` na pasta scripts/

**Erro: "serviceAccountKey.json not found"**
- Certifique-se de que o arquivo está em `scripts/serviceAccountKey.json`
- Faça o download da chave no Firebase Console > Project Settings > Service Accounts

**Erro: "Permission denied"**
- Verifique se a service account tem permissões de administrador
- Verifique se as regras do Firestore permitem operações administrativas
