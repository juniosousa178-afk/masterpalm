# E2E Web isolado — MasterPalm R8.4.33

## Pré-requisitos

- Flutter SDK
- Node.js 20+
- Firebase CLI (`firebase emulators:start --only firestore,auth`)

## Passos

```powershell
# 1) Emulator (terminal separado) — config isolada com regras abertas só para seed local
Push-Location tool/e2e_web
firebase emulators:start --only firestore,auth --project masterpalm-r8433-web-e2e-local
Pop-Location

# 2) E2E completo
.\scripts\run_web_e2e_isolated.ps1
```

## O que valida

- **PackageInfo Web** via Playwright + `tool/e2e_web/web_runtime_probe.dart`
- **Estoque não reverte** (Firestore emulator, T+5s)
- **Revenda 3 linhas** persistem no pedido sintético

## Não publicar

- `build/web-qa-e2e` e `build/web-probe` são artefatos locais (gitignored).
