# Padrões UI e Async – MasterPalm

Documentação de convenções leves para uso de `context` após async e organização de estados visuais (loading/erro/empty/banner). **Não altera runtime.**

---

## 1. Objetivo

- Reduzir risco de uso de `context` após operações assíncronas (widget desmontado).
- Manter consistência nas telas que exibem loading, erro, empty e banners.
- Guiar próximas refatorações sem mudar regra de negócio.

---

## 2. Convenção: Async + Context

### Regra

- **Após qualquer `await`**, antes de usar `context` (incluindo `Navigator`, `ScaffoldMessenger`, `Theme.of(context)`, `showDialog`), verificar se o widget ainda está na árvore:
  - Em **State**: usar `if (!mounted) return;`
  - Em **StatelessWidget** com callback async: preferir passar `BuildContext` só até o primeiro `await`; depois do `await`, usar `if (!context.mounted) return;` (Flutter 3.7+) ou o padrão do projeto (ex.: `mounted` no State que chamou).

### Onde aplicar

- Métodos `async` em `State` que fazem `await` e em seguida:
  - `Navigator.of(context).push/pop`
  - `ScaffoldMessenger.of(context).showSnackBar`
  - `showDialog(context: context, ...)`
  - `Theme.of(context)`, `MediaQuery.of(context)` para decisão que afeta navegação/UI global

### O que não fazer

- Não remover `// ignore: use_build_context_synchronously` sem adicionar checagem `mounted`/`context.mounted` antes do uso de `context`.
- Não refatorar fluxos inteiros só para padronizar; fazer de forma local e segura.

---

## 3. Convenção: Estados visuais (loading / erro / empty / banner)

### Padrão recomendado

- **Loading:** um bloco único (ex.: `Scaffold` com `body: Center` + `CircularProgressIndicator` + textos). Pode ser extraído para widget privado no mesmo arquivo (ex.: `_XxxLoadingBody`).
- **Erro:** bloco com ícone, mensagem e botão "Tentar novamente". Callback `onRetry` permanece no State (ex.: `setState` + chamada ao método de init). Pode ser extraído para widget privado (ex.: `_XxxErroLojaBody`).
- **Empty:** ícone + título + subtítulo (e opcionalmente botão). Se não houver callback ou for único e simples, extrair para widget privado (ex.: `_XxxEmptyBody`).
- **Banner informativo** (ex.: "Sync falhou", "Sem conexão"): barra no topo com mensagem e botão de ação. Callback no State. Pode ser extraído (ex.: `_XxxSyncFalhouBanner`).

### Quando extrair para widget privado (no mesmo arquivo)

- **Sim:** bloco apenas visual, com no máximo um callback simples (`onRetry`, `onPressed`). Parâmetros: cores, textos, mensagem de erro.
- **Não:** bloco com muita lógica, vários callbacks, ou que usa muitos estados da tela (evitar passar dezenas de parâmetros).

### Nomenclatura sugerida

- `_XxxLoadingBody` – corpo da tela em loading.
- `_XxxErroLojaBody` / `_XxxErroBody` – corpo de erro com retry.
- `_XxxSyncFalhouBanner` / `_XxxOfflineBanner` – banner de aviso.
- `_XxxEmptyBody` / `_XxxEmptyStateFiltros` – estado vazio (lista ou filtros).

---

## 4. Referências no projeto

### Telas que já seguem bom padrão (referência)

| Tela | Async + mounted | Estados extraídos (widgets privados) |
|------|------------------|--------------------------------------|
| **vendas_screen** | Sim | Loading, Erro loja, Sync falhou, Empty filtros, Stat card, Info chip |
| **clientes_screen** | Sim | Loading, Erro loja, Sync falhou, Empty histórico |
| **pre_pedidos_screen** | Sim | Erro, Empty, Banner offline |

### Telas medianas (mounted ok, estados ainda inline)

- **estoque_screen:** muitos `if (!mounted) return`, mas loading/erro/empty inline.
- **produto_form_screen** / **produto_combo_form_screen:** mounted consistente; sem extração de estados visuais.
- **login_screen:** mounted consistente; fluxo de login complexo, não priorizar extração.

### Telas que merecem próxima atenção (auditar async + context)

- Telas com **muitos `await`** e **poucos** `if (!mounted) return` ou com `// ignore: use_build_context_synchronously`.
- Exemplos a auditar (sem aplicar mudanças em lote): **loja_config_screen**, **config_pagamentos_simples_screen**, **fretes_cupons_screen**, **planos_screen**, **notas_fiscais_screen**, **admin_usuarios_screen**, **cadastro_screen**, **register_screen**, **auth/login_screen**, **auth/perfil_cliente_screen_novo**.

---

## 5. Resumo das convenções

1. **Async + context:** Sempre `if (!mounted) return;` (ou `if (!context.mounted) return;`) após `await`, antes de usar `context`.
2. **Loading/erro/empty/banner:** Manter ordem clara no `build` (erro → loading → conteúdo); extrair blocos puramente visuais para widgets privados no mesmo arquivo quando tiver no máximo um callback simples.
3. **Não extrair:** Blocos com muita lógica, muitos callbacks ou forte acoplamento com estado; AppBar/FAB/tabs quando muito acoplados; métodos async centrais.
4. **Próximas etapas:** Corrigir uso de context após async onde faltar checagem; em seguida, considerar extração conservadora de loading/erro/empty em telas medianas (uma tela por vez).

---

*Documento criado na etapa de padronização segura MasterPalm. Apenas diagnóstico e convenções; nenhuma alteração de comportamento.*
