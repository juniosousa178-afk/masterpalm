# Endpoint and TLS Policy

**Status:** draft

## TLS

- TLS 1.2+ mínimo (preferir 1.3 quando suportado).
- Validação completa de certificado e hostname.
- Redirects HTTP→HTTPS: seguir apenas se policy permitir; default reject.

## Endpoints

| Tipo | Uso | Nesta sprint |
|------|-----|--------------|
| Public data plane | Produção futura | não configurado |
| Private endpoint | Integração futura | recomendado |
| Emulator | Testes locais | design only |
| Insecure (http://) | — | **proibido** |

## Override

- `endpoint override` apenas via descriptor PA; nunca hardcoded.
- Allowlist de hostnames por ambiente.
- Log redaction: nunca logar URL completa com query assinada.

Nenhum endpoint real configurado.
