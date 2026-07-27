# Dependency Security Review Plan

**Status:** draft — processo futuro, nenhuma dependência instalada nesta sprint.

## Escopo

Revisão de segurança antes de adicionar qualquer SDK ou cliente HTTP ao adapter.

## Processo proposto

1. Identificar pacote candidato no pub.dev (owner verificado).
2. Confirmar publicação oficial ou mirror aprovado.
3. Gerar SBOM a partir de `pubspec.lock`.
4. Analisar dependências transitivas (licenças, maintainer, idade).
5. Consultar advisories (OSV/GHSA) — **evidenceMissing** até execução.
6. Revisar código crítico: credential handling, HTTP, logging.
7. Fixar versão com caret restrito ou exact pin.
8. Definir política de atualização emergencial.
9. Security sign-off antes de merge do adapter.

## Entregáveis futuros

- Relatório de vulnerabilidades.
- Decisão approve/reject por pacote.
- Registro em evidence matrix (`dependencySecurityReviewApproved`).

## Restrições

- Não executar `dart pub add` nesta sprint.
- Não alterar `pubspec.yaml` / `pubspec.lock`.
