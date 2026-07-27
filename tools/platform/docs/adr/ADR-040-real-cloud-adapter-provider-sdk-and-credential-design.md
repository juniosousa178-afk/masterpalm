# ADR-040 — Real Cloud Adapter Provider, SDK and Credential Design

## Status
Proposed

## Contexto

Sprint 05.3.2 encerrou o framework cloud offline com admission gate declarativo (31 critérios, todos sem `approved`). Sprint 05.3.3 Parte 1 produz pacote de design sem implementação.

## Problema

Selecionar conscientemente fornecedor, SDK, credenciais e semânticas operacionais antes de autorizar trabalho de adapter real.

## Decisão (proposta, não aprovada)

1. **Provider recomendado para revisão:** AWS S3 API como referência primária.
2. **SDK:** reviewRequired — preferir SDK oficial isolado atrás do bridge; fallback HTTP mínimo pós security review.
3. **Credenciais:** workload identity + short-lived; proibir long-lived keys.
4. **Rede:** private endpoint / emulator para integração futura; staging/production bloqueados.
5. **Semânticas:** documentadas em arquivos dedicados; mapeamento para status PA existentes.

## Alternativas rejeitadas (interino)

- Seleção automática de fornecedor sem revisão manual.
- Instalação de SDK nesta sprint.
- Cliente HTTP direto sem security review.

## Consequências

- Pacote completo para Architecture Review manual.
- `targetProviderSelected` permanece `false`.
- `realAdapterWorkAuthorized` permanece `false`.

## Pendências

- Aprovação manual de fornecedor e ADR.
- PoC de integração em ambiente isolado (Parte 2+).
- Owners operacionais formais.

## Restrições mantidas

Sem adapter, SDK, rede, credenciais, staging, production, release.
