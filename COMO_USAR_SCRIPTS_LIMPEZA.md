# 📚 Como Usar os Scripts de Limpeza

## ✅ Status Atual do Sistema

**Data da última limpeza:** 28/12/2025
**Status:** ✅ LIMPO E PRONTO PARA PRODUÇÃO

### Estado do Firestore:
- **Usuários:** 2 (apenas masterpalm@gmail.com)
- **Lojas:** 2 (apenas lojas do root)
- **Pedidos:** 0 (vazio)
- **Checkouts:** 0 (vazio)
- **Campanhas:** 0 (vazio)
- **Clientes:** 0 (vazio)

---

## 🔧 Scripts Disponíveis

### Localização
Todos os scripts estão em: `C:\Users\Pichau\apk_nathy\temp_naty\scripts\`

### Lista de Scripts

#### 1. **cleanup_firestore.js** - Limpeza Completa
Remove TODOS os dados de teste, mantendo apenas masterpalm@gmail.com

**Como usar:**
```bash
cd C:\Users\Pichau\apk_nathy\temp_naty\scripts
node cleanup_firestore.js
# Digite: CONFIRMAR
```

**Ou use o atalho:**
```bash
run_cleanup.bat
```

**O que faz:**
- ❌ Remove todos os usuários (exceto masterpalm@gmail.com)
- ❌ Remove todas as lojas (exceto lojas do root)
- ❌ Remove todos os pedidos
- ❌ Remove todos os checkouts
- ❌ Remove todas as campanhas
- ❌ Remove todos os clientes
- ✅ Mantém configurações master
- ✅ Mantém planos de assinatura

---

#### 2. **verify_cleanup.js** - Verificação
Verifica o estado atual do Firestore

**Como usar:**
```bash
cd C:\Users\Pichau\apk_nathy\temp_naty\scripts
node verify_cleanup.js
```

**O que mostra:**
- 📋 Lista de usuários
- 🏪 Lista de lojas
- ⚙️ Configurações master
- 💳 Planos de assinatura
- 📦 Status das coleções vazias

**Quando usar:**
- Após qualquer limpeza
- Para verificar integridade dos dados
- Para conferir se há dados de teste

---

#### 3. **fix_master_config.js** - Correção Master Config
Remove usuários deletados da lista de acesso ilimitado

**Como usar:**
```bash
cd C:\Users\Pichau\apak_nathy\temp_naty\scripts
node fix_master_config.js
```

**Quando usar:**
- Após deletar usuários manualmente
- Se a lista de acesso ilimitado estiver inconsistente

---

#### 4. **final_cleanup.js** - Limpeza Final
Remove documentos órfãos que podem ter sido criados

**Como usar:**
```bash
cd C:\Users\Pichau\apk_nathy\temp_naty\scripts
node final_cleanup.js
```

**Quando usar:**
- Após cleanup_firestore.js
- Se houver documentos órfãos

---

#### 5. **clear_local_hive.dart** - Limpeza Local
Limpa dados locais do Hive (cache do app)

**Como usar:**
```bash
cd C:\Users\Pichau\apk_nathy\temp_naty
flutter run scripts/clear_local_hive.dart
```

**O que faz:**
- 🗑️ Limpa cache de clientes
- 🗑️ Limpa cache de vendas
- 🗑️ Limpa cache de produtos
- 🗑️ Limpa cache de usuários
- 🗑️ Limpa sessão local
- ✅ Mantém configurações essenciais

**Quando usar:**
- Após reinstalar o app
- Para forçar sincronização com Firestore
- Quando há dados inconsistentes localmente

---

## 🎯 Cenários de Uso

### Cenário 1: Limpeza Completa Pela Primeira Vez
Você quer remover TODOS os dados de teste e começar do zero.

**Passos:**
```bash
# 1. Limpeza do Firestore
cd scripts
node cleanup_firestore.js
# Digite: CONFIRMAR

# 2. Limpeza final de órfãos
node final_cleanup.js

# 3. Verificação
node verify_cleanup.js

# 4. (Opcional) Limpeza local
cd ..
flutter run scripts/clear_local_hive.dart
```

---

### Cenário 2: Verificar Estado Atual
Você quer apenas ver como está o Firestore.

**Passos:**
```bash
cd scripts
node verify_cleanup.js
```

---

### Cenário 3: Novo Teste - Limpar Novamente
Você fez novos testes e quer limpar novamente.

**Passos:**
```bash
cd scripts
run_cleanup.bat
# ou
node cleanup_firestore.js
# Digite: CONFIRMAR
```

---

### Cenário 4: Resetar App Localmente
O app está com cache antigo e você quer resetar.

**Passos:**
```bash
# 1. Parar o app
# 2. Limpar cache local
flutter run scripts/clear_local_hive.dart

# 3. Reiniciar o app
flutter run -d windows
```

---

## ⚠️ AVISOS IMPORTANTES

### 🚨 NUNCA Execute em Produção
Estes scripts são DESTRUTIVOS e devem ser usados apenas em:
- ✅ Ambiente de desenvolvimento
- ✅ Fase de testes
- ✅ Antes do lançamento oficial

### 🚨 Não Há Backup Automático
Os scripts NÃO fazem backup antes de deletar. Se precisar:
```bash
# Exportar usuários (antes de limpar)
firebase auth:export backup_usuarios.json --project masterpalm
```

### 🚨 Confirme o Projeto Firebase
Sempre verifique que está no projeto correto:
```bash
firebase projects:list
firebase use masterpalm
```

---

## 📊 Checklist Pós-Limpeza

Após executar a limpeza completa, verifique:

- [ ] Verificação executada (`node verify_cleanup.js`)
- [ ] Apenas 2 usuários em /usuarios (masterpalm@gmail.com e UID)
- [ ] Apenas 2 lojas em /lojas (loja_uid_... e masterpalm_gmail_com)
- [ ] Master config mantido com MP configurado
- [ ] Coleções de teste vazias (pre_pedidos, checkouts, campanhas, clientes)
- [ ] App reiniciado após limpeza local (se executou clear_local_hive.dart)

---

## 🆘 Solução de Problemas

### Erro: "Cannot find module 'firebase-admin'"
**Solução:**
```bash
cd scripts
npm install
```

### Erro: "serviceAccountKey.json not found"
**Solução:**
Copie a chave de serviço para a pasta scripts:
```bash
cp functions/serviceAccountKey.json scripts/
```

### Erro: "Permission denied"
**Solução:**
Verifique as regras do Firestore ou use a service account correta.

### Dados ainda aparecem após limpeza
**Solução:**
```bash
# Execute a limpeza final
cd scripts
node final_cleanup.js

# Verifique novamente
node verify_cleanup.js
```

---

## 📞 Próximos Passos Após Limpeza

1. **Configurar Planos de Assinatura**
   - Login como masterpalm@gmail.com
   - Acesse "Planos de Assinatura"
   - Crie os planos desejados

2. **Testar Fluxo Completo**
   - Cadastrar novo usuário
   - Testar seleção de plano
   - Testar checkout Mercado Pago

3. **Documentar Configurações**
   - Anotar chaves MP usadas
   - Documentar planos criados
   - Salvar configurações importantes

---

**✨ Sistema limpo e pronto para produção!**

*Última atualização: 28/12/2025*
