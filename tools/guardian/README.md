# MasterPalm AI Guardian V4

Ferramenta de proteção contra mudanças perigosas.

## Uso

```bash
cd tools/guardian
dart pub get

# Diff working tree
dart run bin/guardian.dart --working-tree

# Staged
dart run bin/guardian.dart --staged

# Ficheiros explícitos
dart run bin/guardian.dart --files lib/services/vendas_service.dart

# Intervalo de commits
dart run bin/guardian.dart --base HEAD~1 --head HEAD

# JSON
dart run bin/guardian.dart --working-tree --report json

# Package resolution gate (Cryptographic Trust)
dart run bin/analyze_package.dart --cryptographic-trust --package ../platform
```

## Package resolution

O Guardian resolve imports `package:` usando o `package_config.json` do **package alvo**, não o seu próprio. Ver [docs/package_resolution.md](docs/package_resolution.md).

Gate de compatibilidade criptográfica: [docs/guardian-cryptography-compatibility-gate.md](docs/guardian-cryptography-compatibility-gate.md).

## Fontes

- `docs/engineering/`
- `docs/knowledge/`
- `docs/intelligence/`
- `docs/intelligence/ast/_data/ast_report.json`

## Decisão

- **GO** — pode continuar (com ressalvas documentadas)
- **NO-GO** — violação bloqueante ou risco vermelho sem mitigação

**Não executa commit, push, deploy ou writes em produção.**

## Testes

```bash
dart analyze
dart test
```
