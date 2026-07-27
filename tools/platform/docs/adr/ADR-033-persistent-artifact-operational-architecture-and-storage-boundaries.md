# ADR-033 — Persistent Artifact Operational Architecture and Storage Boundaries

## Status
Accepted

## Contexto
O domínio de Persistent Artifact Infrastructure precisa de hardening sem introduzir acoplamento com storage físico, adapters de rede ou writes fora do boundary declarativo.

## Decisão
Adotar arquitetura operacional em camadas com:
- resolução de fontes read-only (`latest/load`);
- avaliação declarativa;
- snapshot canônico e determinístico;
- store in-memory para testes e simulação;
- deleção bloqueada por legal hold.

## Consequências
- forte determinismo para replay e golden tests;
- baixo risco de efeitos colaterais em ambiente local;
- necessidade de adapters explícitos para cenários futuros de persistência física.

## Alternativas consideradas
1. Persistência física desde o core (rejeitada por risco e acoplamento).
2. Adaptadores opcionais já na primeira versão (adiada para sprint futuro).
3. Design exclusivamente orientado a integração externa (rejeitado por reduzir testabilidade local).

## Evidências de hardening
- suíte de replay, golden, mutation, malformed, stress e performance;
- audit files por componente;
- static security review no domínio.
