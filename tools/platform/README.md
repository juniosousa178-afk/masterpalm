# MasterPalm Platform Core

Infraestrutura compartilhada para ferramentas de engenharia (Guardian, AST Engine, Intelligence).

## Estrutura

- `core/` — `PlatformCore`, `ProviderRegistry`, `PlatformBootstrap`
- `interfaces/` — contratos de providers
- `providers/` — implementações concretas (ex.: `FileSystemAstProvider`)
- `models/` — modelos imutáveis compartilhados
- `config/` — configuração centralizada
- `exceptions/` — exceções da plataforma
- `utils/` — paths, ficheiros, JSON, datas, logger

## Uso

```dart
import 'package:masterpalm_platform/masterpalm_platform.dart';

final platform = PlatformBootstrap.forRepo('/path/to/repo');
final ast = platform.ast();
final complexity = ast.complexityForFile('lib/main.dart');
```

## Regras

- Módulos acedem dados apenas via `PlatformCore` e interfaces de provider.
- Registo de providers via `ProviderRegistry` (DI por instância, sem estado global).
- Engines futuros (Metrics, History, Score, Report) registam providers nesta sprint apenas como contratos.
