# Architecture Review #021 — Controlled Filesystem Backend Integration

## Escopo
Integração controlada entre Secure Filesystem Reference Adapter, PersistentArtifactBackendRegistry e PlatformPersistentArtifactProvider (Sprint 05.3.1 Parte 2).

## Arquitetura
```
SecureFilesystemBackendConfig
        ↓
SecureFilesystemBackendFactory.createRegistration()
        ↓
PersistentArtifactBackendRegistry.register()  (manual)
        ↓
PlatformPersistentArtifactProvider (physical ops explícitas)
        ↓
Adapter (dart:io confinado)
```

Fluxo declarativo (`evaluate` → engine → snapshot) permanece separado e sem I/O físico.

## Verificações
- Entrypoint principal (`masterpalm_platform.dart`) sem exports filesystem/dart:io
- Entrypoint opcional `masterpalm_platform_filesystem.dart` para adapter
- Bootstrap padrão com registry vazio
- Environment gate bloqueia produção para `localReference`
- Capabilities explícitas; backendId obrigatório
- Quarantine ≠ deletion; deleteContent unsupported para filesystem
- Telemetria sanitizada no observable provider

## Evidências
| Métrica | Baseline | Final |
|---------|----------|-------|
| Testes adapter | 124 | 124 |
| Testes integração | 0 | **123** |
| Testes PA | 690 | **813** (+123) |
| Suíte total | 2719 | **2842** (+123) |
| Guardian arquivos | 703 | **713** (+10) |
| Unresolved | 0 | 0 |

## Riscos residuais
- Locks locais não protegem multi-processo
- Recovery inspector minimalista (opt-in)
- Caller deve passar backendId explicitamente

## Decisão proposta

**GO WITH CONDITIONS — Explicit Local Backend Integration / Non-Production Only**

Condições:
1. Registro manual obrigatório; bootstrap permanece vazio
2. Produção bloqueada para filesystem reference adapter
3. Operações físicas nunca durante evaluate/publish snapshot
4. Não promover como storage distribuído ou durável
