# Package Resolution — Guardian

O Guardian resolve imports `package:` usando o **package graph do package alvo**, nunca o `package_config.json` do próprio Guardian.

## Fluxo

```
GuardianPackageContext.load(packageRoot)
    ↓ lê <packageRoot>/.dart_tool/package_config.json
GuardianPackageResolver.resolve(uri, context)
    ↓ usa PackageConfig.resolve()
GuardianPackageImportScanner
    ↓ lista lib/**/*.dart e extrai imports/exports
GuardianPackageAnalyzer
    ↓ produz GuardianPackageAnalysisResult
```

## Regras

| Comportamento | Detalhe |
|---------------|---------|
| Package config | Sempre do diretório raiz do package analisado |
| Monorepo | Cada package tem o seu próprio `package_config.json` |
| Package aninhado | `load()` usa o `pubspec.yaml` e config no root passado |
| Import não resolvido | Registrado em `unresolvedImports`; `isComplete = false` |
| Config ausente | `GuardianPackageConfigMissingException` |
| Config inválido | `GuardianPackageConfigInvalidException` |
| Offline | Após `dart pub get` no package alvo, sem rede |
| Segurança | Apenas leitura de ficheiros fonte; sem executar código analisado |

## Cryptographic Trust Gate

```bash
cd tools/guardian
dart run bin/analyze_package.dart --cryptographic-trust --package ../platform
```

Valida:

- `package:crypto/crypto.dart` resolvido
- `package:cryptography/cryptography.dart` resolvido
- `package:cryptography/dart.dart` resolvido
- 10 adapters/serviços normativos presentes em `lib/cryptographic_trust/`

## Troubleshooting

| Sintoma | Causa provável | Correção |
|---------|----------------|----------|
| `package_config.json not found` | `dart pub get` não executado no package alvo | `cd tools/platform && dart pub get` |
| `unresolved import package:cryptography/...` | Config do Guardian usado em vez do alvo | Usar `GuardianPackageContext.load(platformRoot)` |
| Adapters em falta | Path incorreto ou ficheiro removido | Verificar `GuardianCryptographicAdapterPaths` |
| Análise incompleta silenciosa | — | O Guardian **não** silencia erros; ver `throwIfIncomplete()` |

## Limitações

- Resolução estática por regex (imports/exports com aspas simples)
- Não executa o analisador Dart completo (`dart analyze`)
- Não resolve `dart:` nem imports relativos como dependências externas
- Não invoca `dart pub get` automaticamente
