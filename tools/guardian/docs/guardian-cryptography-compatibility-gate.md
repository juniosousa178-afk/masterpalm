# Guardian Cryptography Compatibility Gate

| Campo | Valor |
|-------|-------|
| **Sprint** | 05.2.1 |
| **Data** | 2026-07-22 |
| **Relacionado** | AR-018, ADR-032 |
| **Decisão** | **GO** |

---

## 1. Contexto

A Sprint 05.2 concluiu com **GO WITH CONDITIONS — Verification Ready / Signing Non-Production**. Uma condição pendente era a integração do Guardian com `tools/platform`: o Guardian podia não resolver `package:crypto` e `package:cryptography` ao analisar adapters criptográficos.

## 2. Problema

O Guardian analisava código com o contexto de dependências incorreto — potencialmente o `package_config.json` do próprio Guardian em vez do package alvo (`masterpalm_platform`). Isso podia:

- falhar na resolução de `cryptography` (dependência direta da platform, não do Guardian);
- excluir adapters da análise por imports não resolvidos;
- produzir falsos negativos no gate de compatibilidade.

## 3. Causa raiz

Resolução de imports `package:` sem carregar o `.dart_tool/package_config.json` do package analisado (`tools/platform`). O Guardian depende de `masterpalm_platform` via path, mas isso não substitui o package graph completo do alvo (incluindo `cryptography` como dependência direta da platform).

## 4. Correção

Novo módulo `lib/package_resolution/`:

| Ficheiro | Função |
|----------|--------|
| `guardian_package_context.dart` | Carrega config do package alvo |
| `guardian_package_resolver.dart` | Resolve URIs via `PackageConfig.resolve()` |
| `guardian_package_import_scanner.dart` | Lista `lib/` e extrai imports |
| `guardian_package_analyzer.dart` | Orquestra análise e fingerprint |
| `guardian_cryptographic_adapter_paths.dart` | Paths normativos dos 10 adapters |
| `guardian_package_analysis_result.dart` | Resultado estruturado |
| `guardian_package_exceptions.dart` | Erros explícitos |
| `bin/analyze_package.dart` | CLI do gate |

**Não** foi adicionado `cryptography` ao Guardian para mascarar resolução — apenas `package_config` (resolução) e `crypto` (fingerprint SHA-256 do analyzer).

## 5. Arquivos afetados

**Criados:** módulo `package_resolution/`, `bin/analyze_package.dart`, testes, fixtures, `docs/package_resolution.md`, este documento.

**Alterados:** `pubspec.yaml` (deps `package_config`, `crypto`), `README.md`, `analysis_options.yaml`, `diff_analyzer.dart` (warning `!` removido).

**Não alterados:** `tools/platform/lib/`, Release Governance, fingerprints CT, goldens, wireNames, políticas.

## 6. Testes

| Suíte | Testes |
|-------|--------|
| Guardian (total) | 43 (+23 novos) |
| `test/package_resolution/` | Resolução, fixtures, determinismo |
| `test/guardian_cryptography_compatibility_gate_test.dart` | Integração real `tools/platform` |
| Platform CT | 603 |
| Platform total | 2023 |

## 7. Evidências

```
dart run bin/analyze_package.dart --cryptographic-trust --package ../platform
→ Files: 609, Unresolved: 0, Adapters: 10, Complete: true

dart analyze lib (platform) → No issues found
dart test (platform) → 2023 passed
dart analyze (guardian) → No issues found
dart test (guardian) → 43 passed
```

Versões lock: `crypto` 3.0.7, `cryptography` 2.9.0.

## 8. Riscos

| Risco | Mitigação |
|-------|-----------|
| Scanner regex incompleto | Complementa (não substitui) `dart analyze` |
| Fixture paths em CI | Testes de integração usam `../platform` real |
| `dart pub get` pré-requisito | Erro estruturado se config ausente |

## 9. Limitações

- Análise estática de imports; sem execução do compilador Dart
- Sem `dart pub get` automático nos testes
- Signing continua **non-production** (InMemoryEd25519 restrito a dev/test)

## 10. Decisão

**GO** — `crypto` e `cryptography` resolvidos; 10 adapters analisados; sem exclusão silenciosa; suítes Guardian e Platform verdes; análise determinística (5 execuções).

**Signing produtivo:** não aprovado (inalterado).

**Sprint 05.3:** pode iniciar após aceite deste gate.

---

*Sem commit, push ou deploy nesta sprint.*
