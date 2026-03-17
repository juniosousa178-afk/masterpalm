# Migração de Segurança – Coleção `clientes`

## Estado Atual (pós-correção cirúrgica)

- **get**: `belongsToStore(lojaId)` – somente admin/vendedor (get público removido)
- **list**: `belongsToStore(lojaId) || request.query.limit <= 10` – login/cadastro por email
- **create/update/delete**: inalterados

## Melhorias Implementadas

1. **get público removido**: leitura por documentId exige `belongsToStore(lojaId)`
2. **CF getClienteCatalog**: catálogo obtém dados via callable (valida email)
3. **list limitado a 10**: evita dump completo em queries por email

## Próximos Passos (opcionais)

O fluxo de login/cadastro do catálogo (email/senha) ainda depende de leitura direta no Firestore, sem Firebase Auth. Para fechar completamente:

1. **Opção A – Firebase Auth para catálogo**
   - Usar `signInWithEmailAndPassword` / `createUserWithEmailAndPassword`
   - Armazenar `authUid` em `clientes`
   - Regra: `allow get: if belongsToStore(lojaId) || (request.auth != null && resource.data.authUid == request.auth.uid)`

2. **Opção B – Cloud Functions**
   - `loginClienteCatalog(lojaId, email, senha)` – valida e retorna dados
   - `getClienteCatalog(lojaId, clienteId)` – retorna doc sem `senhaHash`
   - App passa a usar essas CFs em vez de leitura direta
   - Regra: `allow get: if belongsToStore(lojaId)` (somente admin/vendedor)

## Fluxos que dependem de leitura em `clientes`

- Login (email/senha): `where('email', ...).limit(1)`
- Cadastro: verificação de email existente, `limit(1)`
- getClienteById, getCarrinho, getFavoritos, toggleFavorito
- perfil_cliente_screen_novo
- pre_pedido_service: atualização de endereço por `where('email', ...)`

Todos usam `limit(1)` ou `get()` por doc. O `limit <= 10` permite essas operações; `get` continua público até a migração acima.
