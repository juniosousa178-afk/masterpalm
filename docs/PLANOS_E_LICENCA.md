# Planos e licença – dois caminhos

O app reconhece acesso válido por **dois mecanismos**: o novo (planos em Firestore) e o legado (código no Hive atrelado ao deviceId). Não remover o legado enquanto houver uso em produção sem migração.

---

## 1. Caminho novo (planos em Firestore)

### Onde está

- **users/{uid}**: campos `currentPlanId`, `status`, `currentPeriodEnd` (espelho do plano).
- **users/{uid}/subscriptions**: subcoleção com `plan_id`, `status`, `current_period_end`.
- **PlanosService** (`lib/services/planos_service.dart`): precedência explícita em `fetchCurrentPlan` — root/programador (`RoleUtils`) → `manualOverride` / campos em `users/{uid}` → `usuarios/{email}` **somente se** `users/{uid}` não existir.
- **LicenseManager** (`lib/services/license_manager.dart`): `hasValidAccessFallbackLegacy()` — root (`RoleUtils`) → espelho `users/{uid}` → `subscriptions` **apenas** se não existir documento em `users/{uid}` (histórico não sobrepõe o canônico).
- **Lista root/programador (única no app):** `lib/utils/role_utils.dart` (`rootEmails`). Backend espelhado em `functions/src/rootAccounts.js` (`ROOT_ACCOUNT_EMAILS`).

### Planos conhecidos

- `lifetime`: acesso total, sem data de fim (root e planos vitalícios).
- `free_trial_90d`, `free_limited`, `pro_monthly`, `pro_yearly`: definidos em `PlanosService` / `LicenseManager` (PlanId).

### Quem escreve

- **StoreResolverService**: ao resolver loja, pode espelhar dados em users.
- **PlanosService**: espelha plano em users/{uid} (merge); cria/atualiza subscriptions.
- **Checkout/assinatura**: ao ativar plano pago, grava em subscriptions e/ou users.

---

## 2. Caminho legado (Hive + código por device)

### Onde está

- **Box Hive `licenca`**:
  - `codigo`: string (código de ativação).
  - Validação: `LicenseManager.isLicenseValid(deviceId, codigo)` compara com `base64Url(deviceId + '#MASTERPALM')`.
- **LicenseManager.hasValidAccessFallacyLegacy()**: depois de tentar Firestore e cache de plano, tenta esse código; se bater, retorna true.

### Quando usar / remover

- **Usar:** Manter enquanto existir cliente ativado só por código (sem plano no Firestore).
- **Remover:** Só quando não houver mais ninguém dependendo (ex.: migração em produção + período de carência). Ao remover, tirar o bloco 4 em `hasValidAccessFallbackLegacy()` e a tela de ativação por código, se existir.

---

## 3. Cache local (Hive `licenca`)

- **currentPlanId**, **expiresAt**, **ativado**: preenchidos quando Firestore (ou legado) valida acesso.
- **LicenseManager.cachePlanLocally()**: grava isso após validar por users ou subscriptions.
- Assim o app pode considerar “acesso válido” offline por um tempo, sem bater no Firestore a cada abertura.

---

## 4. Ordem de verificação (LicenseManager.hasValidAccessFallbackLegacy)

1. Root/programador (`RoleUtils.isRootEmail`, mesma lista que `rootAccounts.js` no backend) → true.
2. users/{uid} com plano ativo e não expirado → true e cache.
3. Se existe `users/{uid}` mas o espelho não validou acesso → **false** (não usar subscriptions para “escalar”).
4. Se **não** existe `users/{uid}`: users/{uid}/subscriptions (histórico) com plano ativo e não expirado → true e cache.
5. Hive/código legado não promove plano pago sozinho neste fluxo (ver implementação atual).
6. Caso contrário → false.

---

## 5. Ao alterar

- **Root/programador:** alterar em conjunto `role_utils.dart` (Dart) e `functions/src/rootAccounts.js` (Node).
- **PlanosService / LicenseManager:** manter a precedência documentada na secção 1 e 4.
- **Telas de “Licença” ou “Plano”:** Consultar este doc para saber se tocam em Firestore, Hive ou ambos.
