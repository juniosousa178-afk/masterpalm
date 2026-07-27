# Guardian Scope Attribution

## Evidências distintas

Esta sprint distingue quatro evidências independentes. Não devem ser misturadas.

| # | Evidência | Comando / origem | Escopo |
|---|-----------|------------------|--------|
| 1 | Guardian package tests | `cd tools/guardian && dart test` | Pacote Guardian |
| 2 | Guardian package analyze | `cd tools/guardian && dart analyze` | Pacote Guardian |
| 3 | Guardian targeted `tools/platform` analysis | `dart run bin/analyze_package.dart --package ../platform` | `tools/platform` exclusivamente |
| 4 | Guardian repository-wide analysis | `dart run bin/guardian.dart --simulation` (repo root) | Diff git do aplicativo Flutter |

## Comando direcionado oficial

```bash
cd tools/guardian
dart run bin/analyze_package.dart --package ../platform --json
```

Gate Cryptographic Trust (subset normativo):

```bash
cd tools/guardian
dart run bin/analyze_package.dart --cryptographic-trust --package ../platform --json
```

Cobertura cloud framework (programático, testes):

```dart
const analyzer = GuardianPackageAnalyzer();
await analyzer.analyzeCloudFrameworkPackage(platformRoot);
```

## Package root e package config

| Campo | Valor |
|-------|-------|
| Package root | `tools/platform` |
| Package config | `tools/platform/.dart_tool/package_config.json` |
| Pubspec | `tools/platform/pubspec.yaml` |
| Package name | `masterpalm_platform` |

Resolução usa o `package_config` do alvo, nunca o do Guardian.

## Resultado targeted (5 execuções)

| Execução | Files | Unresolved | Complete | Fingerprint |
|----------|-------|------------|----------|-------------|
| 1 | 772 | 0 | true | `7ca8d89e21b9b15af0d7f0a6c48f268d099044beac5e34884b0190b6d3463666` |
| 2 | 772 | 0 | true | `7ca8d89e21b9b15af0d7f0a6c48f268d099044beac5e34884b0190b6d3463666` |
| 3 | 772 | 0 | true | `7ca8d89e21b9b15af0d7f0a6c48f268d099044beac5e34884b0190b6d3463666` |
| 4 | 772 | 0 | true | `7ca8d89e21b9b15af0d7f0a6c48f268d099044beac5e34884b0190b6d3463666` |
| 5 | 772 | 0 | true | `7ca8d89e21b9b15af0d7f0a6c48f268d099044beac5e34884b0190b6d3463666` |

Determinismo: **confirmado** (fingerprint e file list idênticos).

## Matriz de atribuição — repository-wide

| Finding | Código | Arquivo | Módulo | Severity | Escopo 05.3.2 | Justificativa |
|---------|--------|---------|--------|----------|---------------|---------------|
| F-01 | G001 | (global) | repositório | info | out-of-scope | Regra de processo; não relacionada a cloud framework |
| F-02 | G004 | `lib/services/notificacao_vendas_service.dart` | vendas/notificações | yellow | out-of-scope | Path fora de `tools/platform`; alteração Firestore em app Flutter |
| F-03 | G014 | `lib/services/notificacao_vendas_service.dart` | vendas | yellow | out-of-scope | Path fora de `tools/platform`; domínio venda/PDV |
| F-04 | risk | `lib/core/venda_cancelada_alerta_gate.dart` | vendas | red | out-of-scope | Novo arquivo app Flutter; sem relação com cloud PA |
| F-05 | risk | `lib/widgets/notificacao_pedido_listener.dart` | notificações | red | out-of-scope | Widget app Flutter |
| F-06 | risk | `test/m39_hotfix_alerta_venda_cancelada_test.dart` | vendas/testes | red | out-of-scope | Teste app Flutter |

Nenhum finding repository-wide pertence a `tools/platform` ou `tools/guardian` nesta análise.

## Resumo

| Métrica | Valor |
|---------|-------|
| Findings em `tools/platform` (targeted) | **0** |
| Findings fora de `tools/platform` (repository-wide) | **6+ risk entries, 3 rule violations** |
| Findings no Guardian package | **0** |
| Targeted unresolved | **0** |
| Targeted complete | **true** |
| Targeted fingerprint | `7ca8d89e21b9b15af0d7f0a6c48f268d099044beac5e34884b0190b6d3463666` |
| Repository-wide status | GO (simulação) com findings em app Flutter |
| realAdapterWorkAuthorized | **false** |

## Conclusão de escopo

A análise direcionada comprova que `tools/platform` está completo e limpo.
Os findings repository-wide pertencem exclusivamente ao aplicativo Flutter
(vendas/notificações) e **não invalidam** o fechamento do Cloud Framework.
