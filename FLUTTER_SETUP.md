# Flutter / FVM – Setup e comandos

Este projeto usa **FVM** para fixar a versão do Flutter. Não use o Flutter global.

## Versão oficial

- **Flutter 3.24.0** (via `.fvmrc`)

## Primeiro uso (clone novo)

```powershell
fvm install
fvm use
fvm flutter pub get
```

## Comandos recomendados

Use sempre `fvm flutter` e `fvm dart`:

| Ação | Comando |
|------|---------|
| Dependências | `fvm flutter pub get` |
| Testes | `fvm flutter test` |
| Build APK release | `fvm flutter build apk --release` |
| Build web | `fvm flutter build web --release` |
| Rodar app | `fvm flutter run` |
| Análise | `fvm flutter analyze` |
| Limpar | `fvm flutter clean` |
| Doctor | `fvm flutter doctor -v` |

## Scripts do projeto

Os scripts `scripts/build.ps1` e `build-and-deploy.sh` já usam FVM.

## IDE (VS Code / Cursor)

O `.vscode/settings.json` aponta para `.fvm/flutter_sdk`. Após `fvm use`, a IDE usa o Flutter correto.

## Por que FVM?

- Evita conflito entre Flutter global e o que o projeto precisa
- Garante que `flutter pub get`, `flutter test` e `flutter build` usem o mesmo SDK
- A API do tema (CardTheme/DialogTheme) e o Gradle estão alinhados ao Flutter 3.24.0
