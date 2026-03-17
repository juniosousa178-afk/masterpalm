# Migração: masterpalm@gmail.com → masterpalm26@gmail.com

Guia para transferir os dados da loja do usuário antigo para o novo.

## Opção 1: Alterar email no Firebase Auth (recomendado)

Se você ainda tem acesso ao **masterpalm@gmail.com**:

1. Acesse [Firebase Console](https://console.firebase.google.com) → projeto `masterpalm-58c46`
2. **Authentication** → **Users** → localize o usuário `masterpalm@gmail.com`
3. Clique nos **3 pontos** → **Edit user**
4. Altere o **Email** para `masterpalm26@gmail.com`
5. Salve

O UID permanece o mesmo, então `users/{uid}`, `usuarios` e `lojas` continuam vinculados. Faça login com `masterpalm26@gmail.com` e a mesma senha.

---

## Opção 2: Vincular masterpalm26 ao store existente (manualmente no Firestore)

Se o usuário **masterpalm26@gmail.com** já existe no Firebase Auth (novo UID):

### 1. Identificar o store_id antigo

- No Firestore: `usuarios/masterpalm@gmail.com` → campo `store_id` (ex: `masterpalm` ou `nathy-pratas-e-folheados`)

### 2. Atualizar o novo usuário no Firestore

No Firestore Console:

**users/{uid_do_masterpalm26}**  
Adicione/atualize:
```
store_id: "<store_id_antigo>"
ownerOf: "<store_id_antigo>"
```

**usuarios/masterpalm26@gmail.com**  
Crie ou atualize com:
```
store_id: "<store_id_antigo>"
authUid: "<uid_do_masterpalm26>"
tipo: "programador"
email: "masterpalm26@gmail.com"
nome: "Master Palm"
```

### 3. Coleções da loja (já em lojas/{store_id})

Os dados ficam em `lojas/{store_id}/`:
- `config`, `draft_config`
- `produtos`, `estoque_vendas`, `clientes`
- `pre_pedidos`, `vendedores`
- etc.

Nada precisa ser copiado entre coleções de loja; basta apontar o novo usuário para o mesmo `store_id`.

---

## Opção 3: Script de migração (Node/Admin SDK)

Se preferir automatizar via script:

```javascript
const admin = require('firebase-admin');
admin.initializeApp();

const db = admin.firestore();

async function migrar() {
  const emailAntigo = 'masterpalm@gmail.com';
  const emailNovo = 'masterpalm26@gmail.com';

  // Buscar store_id do usuário antigo
  const docAntigo = await db.collection('usuarios').doc(emailAntigo).get();
  const storeId = docAntigo.data()?.store_id;
  if (!storeId) throw new Error('store_id não encontrado');

  // UID do masterpalm26 (obter no Firebase Auth)
  const userNovo = await admin.auth().getUserByEmail(emailNovo);
  const uidNovo = userNovo.uid;

  // Atualizar users/{uid}
  await db.collection('users').doc(uidNovo).set({
    store_id: storeId,
    ownerOf: storeId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // Criar/atualizar usuarios/masterpalm26@gmail.com
  await db.collection('usuarios').doc(emailNovo).set({
    store_id: storeId,
    authUid: uidNovo,
    email: emailNovo,
    tipo: 'programador',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  console.log('Migração concluída:', { storeId, uidNovo });
}
migrar().catch(console.error);
```

---

## Resumo

| Local                 | O que fazer                                                         |
|-----------------------|---------------------------------------------------------------------|
| Firebase Auth         | Alterar email OU manter novo usuário com senha conhecida            |
| users/{uid}           | Definir `store_id` = loja antiga                                    |
| usuarios/{email}      | Definir `store_id`, `authUid` para masterpalm26@gmail.com           |
| lojas/{store_id}      | Nenhuma alteração; continua com todos os dados                      |

Após a migração, abra o app, faça login com `masterpalm26@gmail.com` e confira se a loja antiga é carregada corretamente.
