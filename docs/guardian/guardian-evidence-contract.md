# Guardian G009 — contrato guardian-evidence.json

Schema version 1. O campo `command` é **metadado apenas** — o Guardian nunca o executa.

## Campos

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `schemaVersion` | sim | Deve ser `1` |
| `baseHead` | sim | HEAD lógico do candidato (`17fb382…`) |
| `functionalPatchSha256` | sim | SHA-256 do patch funcional R845 |
| `guardianPatchSha256` | não | SHA-256 do patch Guardian R847 (metadado) |
| `candidatePatchSha256` | não | Alias legado de `functionalPatchSha256` |
| `firestoreRulesSha256` | sim | Hash de `firestore.rules` no COMBINED |
| `testFiles` | sim | Lista `{path, sha256}` dos testes emulator |
| `passed` / `failed` / `skipped` / `exitCode` | sim | Resultado real da execução |

O SHA do patch Guardian **não** invalida evidência de Rules quando o patch Guardian não altera `firestore.rules`. A unidade validada para Rules é o **COMBINED_TARGET** (R845 + R847), mas o hash funcional referencia apenas R845.

## Validação fail-closed

Rejeita quando: schema desconhecido, `baseHead` divergente, `functionalPatchSha256` divergente, hash de rules/testes divergente, `exitCode != 0`, `failed > 0`, JSON inválido, ficheiro ausente.

## Uso

```text
dart run tools/guardian/bin/guardian.dart \
  --files <manifesto R845+R847> \
  --base-head 17fb382f2eee598e5bf1dd55acba7f5e328dd4ab \
  --functional-patch-sha256 76470C9517C5C2355ECB307435187E97A994F73694236CBEE8EED06A2599680C \
  --evidence qa_reports/guardian-evidence-r847.json
```
