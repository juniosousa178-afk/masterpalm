# Diagnóstico — Regras de `notas_fiscais` no Firestore

**ETAPA 14A — Somente leitura/análise. Nenhuma alteração em código nem em rules.**

---

## 1. Ocorrências no projeto

### 1.1 Termo `notas_fiscais`

| Arquivo | Linha | Contexto |
|---------|-------|----------|
| `lib/screens/home_screen.dart` | 53 | Import `notas_fiscais_screen.dart` |
| `lib/screens/home_screen.dart` | 1354 | Rota `/notas_fiscais` |
| `lib/main.dart` | 87 | Import `notas_fiscais_screen.dart` |
| `lib/main.dart` | 1608 | Rota `/notas_fiscais` → `NotasFiscaisScreen` |
| `lib/utils/last_route_observer.dart` | 27 | Rota `/notas_fiscais` |
| `lib/services/nota_fiscal_firestore_service.dart` | 36, 57, 152, 173 | Path Firestore `lojas/{lojaId}/notas_fiscais` |
| `lib/services/permissao_service.dart` | 23, 49, 70, 96, 122 | Permissão `notas_fiscais` (UI/vendedor) |
| `lib/screens/notas_fiscais_screen.dart` | 65 | Hive box `notas_fiscais_$lojaId` (local) |

### 1.2 Termo `nota_fiscal`

| Arquivo | Linha | Contexto |
|---------|-------|----------|
| `lib/main.dart` | 138 | Import `models/nota_fiscal.dart` |
| `lib/models/nota_fiscal.g.dart` | 3 | `part of 'nota_fiscal.dart'` |
| `lib/models/nota_fiscal.dart` | 1+ | Modelo `NotaFiscal` |
| `lib/services/nota_fiscal_firestore_service.dart` | 1, 5 | Import e uso do modelo |
| `lib/services/nota_fiscal_service.dart` | 1, 6+ | Serviço API Focus/Sebrae NFe |
| `lib/screens/notas_fiscais_screen.dart` | 8, 10, 11, 90, 102 | Uso de modelo e serviços |

### 1.3 Termo `nfe` / `NFe`

| Arquivo | Linha | Contexto |
|---------|-------|----------|
| `lib/services/nota_fiscal_service.dart` | 22, 53, 56, 78-91, 118, 180, 220 | API Focus NFe, endpoints `/nfe` |
| `lib/screens/notas_fiscais_screen.dart` | 1855-1858, 1872, 1926-1927, 1985-2034 | UI: Focus NFe, Sebrae NFe |

**Nota:** `nfe` no projeto é referência à API externa (Focus NFe, Sebrae NFe), não ao path Firestore.

---

## 2. Paths Firestore usados

### 2.1 Coleção principal: `lojas/{lojaId}/notas_fiscais/{notaId}`

| Origem | Tipo | Path | Campos usados p/ validar |
|--------|------|------|--------------------------|
| `nota_fiscal_firestore_service.dart` | **write** (set) | `lojas/{storeId}/notas_fiscais/{notaId}` | `storeId` de `StoreResolverService.resolve()` ou parâmetro `lojaId` |
| `nota_fiscal_firestore_service.dart` | **read** (get) | `lojas/{lojaId}/notas_fiscais` (query) | `lojaId` do parâmetro |
| `nota_fiscal_firestore_service.dart` | **delete** | `lojas/{storeId}/notas_fiscais/{notaId}` | `storeId` de `StoreResolverService` ou parâmetro |
| `nota_fiscal_firestore_service.dart` | **read** (stream) | `lojas/{storeId}/notas_fiscais` | `storeId` de `StoreResolverService` |

### 2.2 Outro path relacionado (config, não notas_fiscais)

| Origem | Tipo | Path | Observação |
|--------|------|------|------------|
| `nota_fiscal_service.dart` | read/write (transaction) | `lojas/{lojaId}/config/nota_fiscal_sequencial` | Sequencial de numeração — regra em `config/` |

**Validação no app:** O `lojaId` vem de `StoreResolverService.resolve()` (contexto da loja do usuário) e de `PermissaoService.possuiPermissao('notas_fiscais')` (admin/programador sempre, vendedor nunca). As rules do Firestore **não** conferem se o usuário pertence à loja.

---

## 3. Regra atual em `firestore.rules`

### Bloco copiado (linhas 376–382)

```javascript
      // ---- NOTAS FISCAIS (NOVO) ----
      match /notas_fiscais/{notaId} {
        // Permite leitura/escrita para: admin, programador ou qualquer usuário autenticado da loja
        allow read, write: if isSignedIn();
      }
```

### Por que está ampla

- `isSignedIn()` verifica apenas `request.auth != null`.
- Qualquer usuário autenticado pode ler e escrever em `notas_fiscais` de **qualquer** loja.
- O comentário fala em “admin, programador ou usuário autenticado da loja”, mas a rule não checa:
  - se o usuário é admin/programador, ou
  - se o usuário pertence à loja (`lojaId`).
- Ou seja, a regra está mais permissiva do que o comportamento desejado no app.

---

## 4. Tabela resumo: origem, tipo, path, validação

| Origem (arquivo) | Tipo | Path | Campos usados no app para “validar” |
|------------------|------|------|-------------------------------------|
| `nota_fiscal_firestore_service.dart` | read | `lojas/{lojaId}/notas_fiscais` | `lojaId` via `StoreResolverService.resolve()` |
| `nota_fiscal_firestore_service.dart` | write | `lojas/{lojaId}/notas_fiscais/{notaId}` | idem |
| `nota_fiscal_firestore_service.dart` | delete | `lojas/{lojaId}/notas_fiscais/{notaId}` | idem |
| `nota_fiscal_firestore_service.dart` | read (stream) | `lojas/{lojaId}/notas_fiscais` | idem |

**Obs.:** A validação acima é só no app; as rules atuais não usam `lojaId` nem pertencimento à loja.

---

## 5. Recomendação de regra ideal por path

### 5.1 `lojas/{lojaId}/notas_fiscais/{notaId}`

**Situação atual:** `isSignedIn()` — qualquer autenticado tem acesso total a qualquer loja.

**Regra recomendada:** Restringir ao admin/programador e a quem pertence à loja, alinhada a outras subcoleções sensíveis (ex.: `estoque_vendas`, `estoque_produtos`):

```javascript
      // ---- NOTAS FISCAIS ----
      match /notas_fiscais/{notaId} {
        allow read, write: if belongsToStore(lojaId);
      }
```

`belongsToStore(lojaId)` já existe nas rules e cobre:
- `isAdminOrSystem()` (admin/programador)
- `isSellerOfStore(lojaId)` (vendedor da loja)

**Impacto:** Mantém o comportamento desejado no app (admin/programador e vendedores da loja) e bloqueia acesso de usuários de outras lojas.

### 5.2 `lojas/{lojaId}/config/nota_fiscal_sequencial`

Usado por `nota_fiscal_service.dart` para sequencial de NFe. Já cai na regra de `config/{configId}`:

```javascript
match /config/{configId} {
  allow read: if resource != null;
  allow write: if isAdminOrSystem();
}
```

- **read:** público (para o catálogo e demais leituras de config).
- **write:** só admin/programador.

O sequencial é escrito via transaction; portanto, apenas admins/programadores podem alterar, o que é adequado. Nenhuma mudança necessária nesse path.

---

## 6. Validação ETAPA 14A

- **dart analyze:** Sem alteração de código — resultado esperado inalterado.
- **Build:** Não executado (etapa somente de diagnóstico).
- **Commit sugerido:** Apenas este arquivo `NOTAS_FISCAIS_RULES_DIAGNOSTICO.md` (sem mudanças em rules nesta etapa).
