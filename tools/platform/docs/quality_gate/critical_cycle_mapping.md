# Mapeamento — criticalCycleCount vs graph.cycle.count

**Domínio:** Quality Gates — Architecture Risk (QG011)
**Política:** `quality-gate-release-v1` (candidate)
**Última atualização:** 2026-07-21

## Resumo executivo

Não existe métrica autoritativa de **ciclos críticos** no contrato publicado de `MetricsSnapshot`. A métrica disponível `graph.cycle.count` mede o **total de ciclos** no grafo de dependências, não ciclos classificados como críticos.

O target `criticalCycleCount` retorna resolução `unsupported` com limitation `providerCapabilityGap`. A regra QG011 na política candidate v1 permanece definida normativamente, mas **não pode ser avaliada** com evidência autoritativa nesta sprint.

---

## Fonte real disponível

| Campo | Valor |
|-------|-------|
| **Target normativo** | `QualityGateRuleTarget.criticalCycleCount` |
| **Métrica mapeada (incorreta)** | ~~`graph.cycle.count`~~ — **não utilizada** para este target |
| **Métrica de ciclos totais** | `graph.cycle.count` |
| **Resolver** | `MetricsQualityGateTargetResolver` |
| **Arquivo** | `lib/quality_gate/quality_gate_target_registry.dart` |

### Semântica de `graph.cycle.count`

| Atributo | Valor |
|----------|-------|
| **ID** | `graph.cycle.count` |
| **Domínio** | Metrics / Graph |
| **Unidade** | contagem inteira (ciclos) |
| **Semântica** | Número total de ciclos detectados no grafo de dependências publicado |
| **Autoritatividade** | Sim, para ciclos totais |
| **Classificação crítica** | Não — não distingue ciclos críticos de não-críticos |

---

## Comportamento do target `criticalCycleCount`

Quando uma regra referencia `criticalCycleCount`, o resolver retorna:

```dart
QualityGateTargetResolution(
  status: QualityGateTargetResolutionStatus.unsupported,
  evidenceType: QualityGateEvidenceType.unavailable,
  limitations: [
    QualityGateLimitation(
      limitationId: 'metrics.criticalCycleCount.unsupported',
      type: QualityGateLimitationType.providerCapabilityGap,
      severity: QualityGateLimitationSeverity.warning,
      description:
          'criticalCycleCount has no authoritative metrics source; '
          'graph.cycle.count measures total cycles, not critical cycles',
    ),
  ],
)
```

### Efeito na regra QG011

| Atributo da regra | Valor |
|------------------|-------|
| ruleId | QG011 |
| requirement | `required` |
| severity | `critical` |
| missingDataPolicy | `unavailable` |

Para regra **required** com target **unsupported**, o `QualityGateRuleEvaluator` produz status terminal conforme requirement:

- Status: `error` (required + unsupported)
- Impacto: contribui para decisão `unavailable` ou `failed` conforme agregação

**Importante:** o sistema **não** converte silenciosamente `graph.cycle.count` em `criticalCycleCount`. A divergência semântica é explícita.

---

## Target alternativo: `cycleCount`

O target `cycleCount` **está suportado** e resolve para `graph.cycle.count`:

| Target | Métrica | Status |
|--------|---------|--------|
| `cycleCount` | `graph.cycle.count` | `resolved` quando métrica disponível |
| `criticalCycleCount` | — | `unsupported` |

Estes targets **não são intercambiáveis**.

---

## Limitação na política candidate v1

A regra QG011 declara:

> Critical cycle count must be zero.

Sem fonte autoritativa, a regra não pode cumprir a intenção normativa original ("ciclos críticos"). Opções futuras (fora desta sprint):

1. **Metrics Engine** publicar métrica oficial (ex.: `graph.cycle.critical_count`)
2. **Nova versão de política** (`quality-gate-release-v2`) com regra reformulada
3. **Tornar QG011 optional** com `missingDataPolicy: skip` até métrica existir
4. **Substituir** por `cycleCount` com threshold documentado (mudança semântica — requer ADR)

Nesta sprint: **nenhuma alteração ao Metrics Engine**; limitação documentada e comportamento `unsupported` mantido.

---

## Comportamento quando indisponível

| Cenário | Resolução | Evidência | Limitation |
|---------|-----------|-----------|------------|
| Métrica crítica inexistente | `unsupported` | `unavailable` | `metrics.criticalCycleCount.unsupported` |
| Metrics snapshot ausente | `unavailable` | `unavailable` | fonte metrics indisponível |
| Métrica `graph.cycle.count` ausente | Não afeta QG011 | — | QG011 não usa esta métrica |

---

## Referências

- `lib/quality_gate/quality_gate_target_registry.dart` — `MetricsQualityGateTargetResolver`
- `lib/quality_gate/policies/quality_gate_release_policy_v1.dart` — regra QG011
- `docs/quality_gate/quality_gate_traceability_matrix.md` — rastreabilidade
- `docs/architecture-reviews/AR-013-quality-gates-foundation.md` — risco R-QG-002
