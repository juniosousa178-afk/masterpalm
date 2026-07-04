# Política de artefatos — QA Bot MasterPalm (M0.1)

Documentação apenas. Nenhuma exclusão automática nesta fase.

## Identidade de run

Cada execução recebe um `runId` UTC compartilhado (`yyyyMMdd_HHmmss`) usado em:

| Artefato | Padrão de nome |
|----------|----------------|
| Run JSON | `tools/qa_bot/artifacts/run_<runId>.json` |
| Smoke stdout NDJSON | `tools/qa_bot/artifacts/smoke_stdout_<runId>.jsonl` |
| Smoke stderr | `tools/qa_bot/artifacts/smoke_stderr_<runId>.log` |
| QA Report | `qa_reports/QA_REPORT_<runId>.md` |

O orquestrador **nunca** lê artefatos de runs anteriores para calcular o resultado da run atual.

## Classificação

### Evidências de execução (persistir)

- `run_<runId>.json` — snapshot estruturado da run (fonte do relatório)
- `smoke_stdout_<runId>.jsonl` — NDJSON bruto do reporter Flutter
- `smoke_stderr_<runId>.log` — stderr do processo smoke
- `qa_reports/QA_REPORT_<runId>.md` — relatório humano

### Temporários / investigação

- Arquivos prefixados `m01_investigation_*` ou similares — capturas manuais de diagnóstico
- Podem coexistir com runs oficiais; não são referenciados pelo orquestrador

## Colisão e retenção

- Nomes timestampados UTC reduzem colisão na mesma máquina (granularidade 1s).
- Runs subsequentes **não sobrescrevem** runs anteriores (novo `runId` a cada execução).
- Retenção/rotação: **não implementada** em M0.1 — planejar para fase futura (ex.: manter últimos N runs).

## Futuro (não implementado)

- Cleanup opt-in por idade ou contagem
- `.gitignore` dedicado quando o QA Bot for versionado
