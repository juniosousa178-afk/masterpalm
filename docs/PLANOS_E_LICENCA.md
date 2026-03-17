# Planos e licença – dois caminhos

O app reconhece acesso válido por **dois mecanismos**: o novo (planos em Firestore) e o legado (código no Hive atrelado ao deviceId). Não remover o legado enquanto houver uso em produção sem migração.

---

## 1. Caminho novo (planos em Firestore)

### Onde está

- **users/{uid}**: campos `currentPlanId`, `status`, `currentPeriodEnd` (espelho do plano).
- **users/{uid}/subscriptions**: subcoleção com `plan_id`, `status`, `current_period_end`.
- **PlanosService** (`lib/services/planos_service.dart`): lê plano atual; para e-mails root retorna `lifetime` sem ir ao Firestore.
- **LicenseManager** (`lib/services/license_manager.dart`): em `hasValidAccessFallbackLegacy()` consulta primeiro `users/{uid}` e depois `subscriptions`; se achar plano ativo e não expirado, grava cache local e retorna true.

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

1. Root (e-mails fixos) → true.
2. users/{uid} com plano ativo e não expirado → true e cache.
3. users/{uid}/subscriptions com plano ativo e não expirado → true e cache.
4. Cache local (ativado + expiresAt não expirado) → true.
5. Legado (codigo + deviceId) → true.
6. Caso contrário → false.

---

## 5. Ao alterar

- **PlanosService:** Se mudar lista de root ou planos, alinhar com LicenseManager (root) e com Firestore rules.
- **LicenseManager:** Se adicionar/remover fonte de “acesso válido”, manter a ordem acima e não quebrar offline (cache).
- **Telas de “Licença” ou “Plano”:** Consultar este doc para saber se tocam em Firestore, Hive ou ambos.
