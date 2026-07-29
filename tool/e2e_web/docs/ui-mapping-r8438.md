# Mapeamento UI — Web E2E R8.4.38 / R8.4.42

## Separação oficial (R8.4.42)

| Camada | Ferramenta | Responsabilidade |
|--------|------------|------------------|
| **Interação Flutter interna** | `integration_test` + `WidgetTester` | `enterText`, `tap` em `ValueKey('login-*')`, validação Auth Emulator |
| **Observação externa** | Playwright | rede, console, pageerror, ARIA, guards de produção |

**Login autoritativo:** `integration_test/r8442_web_login_emulator_test.dart`  
**Playwright NÃO** executa `submitLogin()` — removido em R8.4.42.

Execução:

```powershell
.\scripts\run_r8442_integration_login.ps1
```

## Keys estáveis (produção + QA)

| Key | Widget |
|-----|--------|
| `login-email` | campo e-mail |
| `login-password` | campo senha |
| `login-submit` | botão Entrar |
| `home-ready` | marcador QA home |
| `company-loaded` | empresa carregada |
| `navigation-ready` | navegação pronta |
| `qa-login-submit-dispatched` | submit disparado |
| `qa-auth-request-*` | estágios Auth |

## Mapeamento Playwright (observação)

| Tela | Rota | Seletor ARIA (observação) |
|------|------|---------------------------|
| Login | `/login` | `login-email`, `login-password`, `login-submit` |
| Home | `/home` | `home-ready`, `company-loaded` |

Semantics QA ativos somente com `MP_ENVIRONMENT=qa`.
