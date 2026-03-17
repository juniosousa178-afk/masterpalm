# TODO / FIXME / BACKLOG — Levantamento de dívida técnica (somente leitura)

**Data do levantamento:** ETAPA 9  
**Regra:** Nenhum arquivo de código foi alterado. Apenas leitura e registro.

---

## 1. Resumo por categoria

| Categoria              | Quantidade aprox. |
|------------------------|-------------------|
| Estabilidade           | ~70 (erros em catch, sync, router) |
| Código morto / limpeza | ~150 (debugPrint informativos, candidatos a logD) |
| Observação             | ~100 (print em scripts CLI, tools) |

---

## 2. TODO

| Arquivo | Linha | Texto encontrado | Categoria sugerida |
|---------|-------|------------------|--------------------|
| lib/catalog/data/firestore_catalog_impl.dart | 242 | `// TODO: integrar com CatalogoVendaService/PrePedidoService para` | Estabilidade |
| lib/scripts/repair_historico_clientes.dart | 50 | `// 3. Limpar TODO o historico de todos os clientes` | Observação (uso da palavra "todo" em português, não marcador) |

---

## 3. FIXME

Nenhuma ocorrência encontrada.

---

## 4. HACK

Nenhuma ocorrência encontrada.

---

## 5. print( — código da aplicação (exceto lib/core/logger.dart e .dart_tool)

| Arquivo | Linha | Texto encontrado | Categoria sugerida |
|---------|-------|------------------|--------------------|
| tool/sync_web_version.dart | 11 | `print('Erro: pubspec.yaml não encontrado');` | Observação |
| tool/sync_web_version.dart | 18 | `print('Erro: versão não encontrada no pubspec.yaml');` | Observação |
| tool/sync_web_version.dart | 24 | `print('Versão do pubspec: $version');` | Observação |
| tool/sync_web_version.dart | 32 | `print('  manifest.json atualizado');` | Observação |
| tool/sync_web_version.dart | 45 | `print('  index.html atualizado');` | Observação |
| tool/sync_web_version.dart | 48 | `print('Versão web sincronizada: $version');` | Observação |
| check_config.dart | 6 | `print('🔍 Verificando configuração do catálogo...\n');` | Observação |
| check_config.dart | 10 | `print('✅ Firebase inicializado\n');` | Observação |
| check_config.dart | 14-78 | Diversos prints de diagnóstico | Observação |
| scripts/sync_firestore.dart | 20-192 | Diversos prints (CLI) | Observação |
| scripts/migrate_add_publicar_catalogo.dart | 7-68 | Diversos prints (CLI) | Observação |
| scripts/clear_local_store_cache.dart | 9-69 | Diversos prints (CLI) | Observação |
| scripts/clear_local_hive.dart | 9-100 | Diversos prints (CLI) | Observação |
| run_sync.dart | 16-98 | Diversos prints (CLI) | Observação |
| tool/find_unreferenced.dart | 140-151 | Diversos prints | Observação |

*Nota: lib/core/logger.dart usa `print` intencionalmente dentro de `kDebugMode` — não é dívida técnica.*

---

## 6. debugPrint( — código da aplicação (lib/)

### 6.1 clientes_screen.dart (8 ocorrências)

| Linha | Texto encontrado | Categoria sugerida |
|-------|------------------|--------------------|
| 158 | `debugPrint('✅ Clientes sincronizados do Firestore');` | Código morto / limpeza |
| 160 | `debugPrint('⚠️ Erro ao sincronizar clientes do Firestore: $e');` | Estabilidade |
| 168 | `debugPrint('✅ Vendas sincronizadas do Firestore');` | Código morto / limpeza |
| 170 | `debugPrint('⚠️ Erro ao sincronizar vendas do Firestore: $e');` | Estabilidade |
| 179 | `debugPrint('✅ $n vendas vinculadas ao histórico');` | Código morto / limpeza |
| 181 | `debugPrint('⚠️ Erro ao reconciliar vendas: $e');` | Estabilidade |
| 187 | `debugPrint('⚠️ Erro ao deduplicar clientes: $e');` | Estabilidade |
| 1732 | `debugPrint('Erro ao imprimir pedido: $e');` | Estabilidade |

### 6.2 app_start_router.dart (38 ocorrências)

| Linha | Texto encontrado | Categoria sugerida |
|-------|------------------|--------------------|
| 41 | `debugPrint('🔄 [ROUTER] Iniciando verificação de sessão');` | Código morto / limpeza |
| 47 | `debugPrint('❌ [ROUTER] Sem usuário logado → /login');` | Código morto / limpeza |
| 54 | `debugPrint('✅ [ROUTER] Usuário logado: $email (uid: $uid)');` | Observação (possível dado sensível) |
| 62-625 | Diversos debugPrint de fluxo do router | Código morto / limpeza / Estabilidade |

### 6.3 roleta_web_widget_v3.dart (11 ocorrências)

| Linha | Texto encontrado | Categoria sugerida |
|-------|------------------|--------------------|
| 72-115 | debugPrint de config da roleta | Código morto / limpeza |
| 267 | `debugPrint('❌ [ROLETA-V3] Erro na transação: $e');` | Estabilidade |
| 283 | `debugPrint('🎉 [ROLETA-V3] Prêmio ganho: ...');` | Código morto / limpeza |

### 6.4 pre_pedidos_screen.dart (10 ocorrências)

| Linha | Texto encontrado | Categoria sugerida |
|-------|------------------|--------------------|
| 115 | `debugPrint('⚠️ [PRE-PEDIDOS] Erro ao verificar acesso: $e');` | Estabilidade |
| 175 | `debugPrint('Erro ao abrir WhatsApp: $e');` | Estabilidade |
| 2301-2396 | debugPrint de processamento de item e erro | Código morto / limpeza / Estabilidade |

### 6.5 cliente_auth_service.dart (18 ocorrências)

| Linha | Texto encontrado | Categoria sugerida |
|-------|------------------|--------------------|
| 272-739 | Diversos debugPrint de erros e fluxo | Estabilidade / Código morto / limpeza |

### 6.6 estoque_screen.dart (41 ocorrências)

| Linha | Texto encontrado | Categoria sugerida |
|-------|------------------|--------------------|
| 124-1984 | Diversos debugPrint (setup, sync, debug, lote, parse) | Estabilidade / Código morto / limpeza |

### 6.7 fornecedor_screen.dart (2 ocorrências)

| Linha | Texto encontrado | Categoria sugerida |
|-------|------------------|--------------------|
| 87 | `debugPrint('✅ Fornecedores sincronizados do Firestore');` | Código morto / limpeza |
| 89 | `debugPrint('⚠️ Erro ao sincronizar fornecedores do Firestore: $e');` | Estabilidade |

### 6.8 vendas_screen.dart (5 ocorrências)

| Linha | Texto encontrado | Categoria sugerida |
|-------|------------------|--------------------|
| 137-2040 | debugPrint de sync e impressão | Código morto / limpeza / Estabilidade |

### 6.9 produtos_firestore_service.dart (24 ocorrências)

| Linha | Texto encontrado | Categoria sugerida |
|-------|------------------|--------------------|
| 21-386 | Diversos debugPrint de sync | Código morto / limpeza / Estabilidade |

### 6.10 fornecedores_firestore_service.dart (18 ocorrências)

| Linha | Texto encontrado | Categoria sugerida |
|-------|------------------|--------------------|
| 18-222 | Diversos debugPrint de sync | Código morto / limpeza / Estabilidade |

### 6.11 clientes_firestore_service.dart (parcial, 10+ ocorrências)

| Linha | Texto encontrado | Categoria sugerida |
|-------|------------------|--------------------|
| 25-161 | Diversos debugPrint de sync | Código morto / limpeza / Estabilidade |

### 6.12 Demais arquivos lib/

- **nova_venda_modal.dart** — 5 debugPrint (sorteio, pagamentos, erros)
- **globo_sorteio_screen.dart** — 3 debugPrint
- **estoque_screen_v2.dart** — 4 debugPrint
- **cadastro_catalogo_screen.dart** — 1 debugPrint
- **pedido_publico_screen.dart** — ~20 debugPrint (produto, venda, notificações)
- **config_pagamentos_screen.dart** — 1 debugPrint
- **fretes_cupons_screen_v2.dart** — 4 debugPrint
- **marketplaces_screen.dart** — 1 debugPrint
- **metas_comissoes_screen.dart** — 2 debugPrint
- **precificacao_universal_screen.dart** — 2 debugPrint
- **order_review_screen.dart** — 4 debugPrint
- **roleta_sorte_config_screen.dart** — 2 debugPrint
- **produto_form_screen.dart** — 12 debugPrint (debug carregar/salvar)
- **catalago_screen.dart** — 4 debugPrint
- **fretes_cupons_screen.dart** — 6 debugPrint

---

## 7. Arquivos excluídos do levantamento

- **.dart_tool/** — código gerado automaticamente pelo Flutter
- **lib/core/logger.dart** — `print` é intencional (implementação do logger sob `kDebugMode`)

---

## 8. Totais consolidados

| Tipo | Quantidade |
|------|------------|
| TODO | 1 (real) + 1 (falso positivo: "TODO o historico" em pt-BR) |
| FIXME | 0 |
| HACK | 0 |
| print (scripts/tools/check_config) | ~90 |
| debugPrint (lib/) | ~220 |

### Totais por categoria sugerida

| Categoria | Descrição |
|-----------|-----------|
| **Estabilidade** | Erros em catch, sync, router — candidatos a logE/logW |
| **Código morto / limpeza** | debugPrint informativos — candidatos a logD ou remoção |
| **Observação** | print em scripts CLI e tools — uso legítimo para saída de console |

---

*Este relatório é somente leitura. Nenhum arquivo de código foi alterado (ETAPA 9).*
