# ADR-034 — Secure Filesystem Reference Adapter

## Status
Accepted

## Contexto
O domínio de Persistent Artifacts precisava de um adapter físico opcional, manual e seguro, sem quebrar o baseline declarativo e sem auto-registro.

## Decisão
Adotar um adapter de filesystem confinado por root com:
- SHA-256 para conteúdo;
- escrita atômica por arquivo temporário;
- layout content-addressed;
- persistência de manifestos por namespace;
- deleção via quarentena opcional.

## Restrições
- sem alteração de bootstrap/core;
- sem auto-register no backend registry;
- sem vazamento de path absoluto em mensagens públicas;
- fail-closed para symlinks e traversal.

## Consequências
- maior segurança no boundary físico;
- superfície explícita de configuração;
- custo adicional de validação de path e digest.

## Alternativas consideradas
1. Write-through direto no core (rejeitado).
2. Adapter sem validação de symlink/traversal (rejeitado).
3. Secure erase como comportamento default (rejeitado nesta etapa).
