# Auditoria Técnica MasterPalm
**Projeto:** MasterPalm | **Versão:** 1.0.28+38 | **Data:** 06/03/2025  
**Tipo:** Auditoria de código – sem alterações aplicadas

---

## Observação sobre domínio oficial

**Domínio de produção correto:** `mastepalm.com.br`

- `mastepalm.com.br` = domínio oficial correto
- `masterpalm.com.br` = referência divergente/incorreta, deve ser revisada
- `masterpalm-58c46` = ID interno do projeto Firebase, não é erro

Toda auditoria e futuras correções devem tratar como problema real apenas a divergência entre referências e padronizar URLs públicas, deep links e App Links para `mastepalm.com.br`, sem quebrar o que já funciona.

---

## 1. Resumo executivo

Esta auditoria mapeou riscos de produção, inconsistências arquiteturais e pontos frágeis no MasterPalm (Flutter + Firebase + Hive). O foco foi em bugs ocultos, comportamento em rede lenta, divergências entre plataformas (Web/APK/Desktop), e possíveis vazamentos de dados entre lojas.

**Principais achados:**
- **Divergência de domínio:** Referências a `masterpalm.com.br` devem ser padronizadas para `mastepalm.com.br` (oficial). AndroidManifest já usa `mastepalm.com.br` (correto).
- **Fallback `'padrao'`:** Ainda presente em várias telas; pode apontar para loja inexistente no Firestore.
- **Erros silenciosos:** Dezenas de `catch (_) {}` que engolem erros sem feedback ao usuário.
- **Regras Firestore:** Regras distintas entre coleções de pedido; root `/pedidos` exige admin para escrita.
- **Índices vs coleções:** Possíveis divergências entre `firestore.indexes.json` e coleções reais.

---

## 2. Top 10 riscos do projeto

| # | Severidade | Risco | Impacto | Onde |
|---|------------|-------|---------|------|
| 1 | **ALTO** | Referências a `masterpalm.com.br` em vez de `mastepalm.com.br` (oficial) – divergência em código/docs | URLs quebradas, confusão em config | loja_config_screen, docs, possíveis referências em lib |
| 2 | **ALTO** | Fallback `'padrao'` em várias telas quando resolução de loja falha | Dados da loja errada ou loja inexistente | contas_receber, fornecedor, historico_clientes, notas_fiscais, admin_painel_web, etc. |
| 3 | **ALTO** | Escrita em root `/pedidos` exige `isAdminOrSystem()`; cliente/vendedor recebe `permission denied` (erro engolido) | Histórico global incompleto; possível perda de rastreabilidade | order_review_screen.dart:338, firestore.rules:497 |
| 4 | **ALTO** | `pedidos_pendentes` permite `update` para qualquer `isSignedIn()` | Risco de alteração indevida entre lojas | firestore.rules:483 |
| 5 | **MÉDIO** | Dezenas de `catch (_) {}` sem feedback ao usuário | Erros mascarados; dificuldade de diagnóstico em produção | 70+ arquivos em lib/ |
| 6 | **MÉDIO** | AutoSyncService usa `store_id`/`storeId` diretamente, sem `LojaIdAdapter` | Inconsistência com padronização lojaId | auto_sync_service.dart:73 |
| 7 | **MÉDIO** | Índices para `categoria`/`subcategoria` (singular); regras usam `categorias`/`subcategorias` (plural) | Queries podem falhar ou não usar índice | firestore.indexes.json vs firestore.rules |
| 8 | **MÉDIO** | READ_CONTACTS declarado no Android – Play Store pode exigir justificativa | Possível reprovação ou auditoria | AndroidManifest.xml:9 |
| 9 | **MÉDIO** | Fallback dinâmico para Hive na Web quando tipo da box não bate | Risco de perda de tipagem ou comportamento inesperado | main.dart (bootstrap) |
| 10 | **BAIXO** | E-mails de root admin hardcoded em firestore.rules | Exposição de e-mails sensíveis; manutenção frágil | firestore.rules:14–19 |

---

## 3. Achados por categoria

### 3.1 Multi-loja

| Achado | Severidade | Descrição | Arquivos |
|--------|------------|-----------|----------|
| Fallback `'padrao'` | ALTO | Quando StoreResolver falha, várias telas usam `lojaId = 'padrao'`, que pode não existir em Firestore | contas_receber_screen, fornecedor_screen, historico_clientes_screen, notas_fiscais_screen, admin_painel_web_screen, relatorio_ranking_clientes_screen |
| Uso misto lojaId/store_id/storeId | MÉDIO | Padronização parcial; LojaIdAdapter criado, mas AutoSyncService e outros ainda leem `store_id`/`storeId` direto | auto_sync_service.dart, relatorio_ranking_clientes_screen.dart |
| Múltiplos caminhos de resolução | MÉDIO | StoreResolver, LojaIdService, Hive sessao, Hive config – ordem e fallbacks não centralizados em todos os fluxos | store_resolver_service, loja_id_service, auto_sync_service |
| Loja vazia em rotas | MÉDIO | Rotas de relatório com `lojaId.isEmpty ? 'padrao'` – corrigido em parte via `_lojaIdRoute`, mas outras telas ainda usam `'padrao'` | main.dart, várias telas |

### 3.2 Firestore

| Achado | Severidade | Descrição | Arquivos |
|--------|------------|-----------|----------|
| Root `/pedidos` exige admin | ALTO | `order_review_screen` grava em `/pedidos`; regra permite apenas `isAdminOrSystem()`. Cliente/vendedor recebe erro e o `catch` ignora | order_review_screen.dart:336–345, firestore.rules:497 |
| Regras distintas para pedidos | ALTO | `pedidos_pendentes` permite update para `isSignedIn()`; pre_pedidos e pedidos exigem admin | firestore.rules:433–488 |
| Coleções duplicadas | MÉDIO | `pre_pedidos`, `pedidos_pendentes`, `pedidos_catalogo` com papéis parecidos; fluxos não unificados | pre_pedido_service, catalogo_venda_service, firestore.rules |
| Índices vs coleções | MÉDIO | Índices para `categoria`, `subcategoria` (singular); regras usam `categorias`, `subcategorias` | firestore.indexes.json |
| `pre_pedidos` index usa `dataCriacao` | BAIXO | Índice exige `dataCriacao`; código usa `createdAt`/`dataCadastro` em alguns pontos – validar campo real nos docs | firestore.indexes.json:184, pedido_publico_screen, public_catalog_screen |

### 3.3 Hive / Sync

| Achado | Severidade | Descrição | Arquivos |
|--------|------------|-----------|----------|
| Erros engolidos em sync | MÉDIO | Vários `catch (_) {}` em fluxos de sincronização | auto_sync_service, full_sync_service, vendas_firestore_service |
| Box dinâmica na Web | MÉDIO | Fallback quando tipo da box não corresponde – risco de perda de tipagem | main.dart |
| Risco de duplicação | BAIXO | Deduplicação e reconciliação existem; depende de lojaId correto | deduplicacao_clientes_service, reconciliacao_vendas_clientes_service |
| AutoSync sem LojaIdAdapter | MÉDIO | Lê `store_id`/`storeId` manualmente em vez de `normalizeFromBox` | auto_sync_service.dart:73 |

### 3.4 Pedidos / Catálogo / Checkout

| Achado | Severidade | Descrição | Arquivos |
|--------|------------|-----------|----------|
| Root `/pedidos` vs `lojas/{id}/pedidos` | ALTO | Duas coleções “pedidos”; OrderReview grava em root; CatalogoVenda em lojas | order_review_screen, catalogo_venda_service, firestore_catalog_impl |
| Fluxos similares implementados diferente | MÉDIO | pre_pedidos, pedidos_pendentes, pedidos_catalogo com lógica espalhada | pre_pedido_service, catalogo_venda_service |
| URLs hardcoded | BAIXO | `app.mastepalm.com.br` (correto). Validar se há referências a `masterpalm.com.br` incorretas | public_catalog_screen, checkout_service, canais_meta_widgets |

### 3.5 Web vs APK vs Desktop

| Achado | Severidade | Descrição | Arquivos |
|--------|------------|-----------|----------|
| `kIsWeb` em muitos pontos | MÉDIO | Comportamento diferente (avatar, App Check, OAuth, paths) – risco de bug em uma plataforma | main.dart, clientes_screen, loja_config_screen, public_catalog_screen |
| Avatar não salvo na Web | BAIXO | `if (kIsWeb) return null` – avatares só no mobile | clientes_screen.dart:297 |
| App Check desabilitado em Web em erro | BAIXO | Em falha, Web segue sem App Check – decisão consciente, mas reduz proteção | main.dart:198–236 |

### 3.6 Erros silenciosos

| Achado | Severidade | Descrição | Arquivos |
|--------|------------|-----------|----------|
| `catch (_) {}` vazios | MÉDIO | Mais de 70 ocorrências; erros ignorados sem log nem feedback | loja_id_service, store_resolver_service, order_review_screen, auto_sync_service, etc. |
| `catch (_)` com log mas sem retry | MÉDIO | Alguns logam; poucos oferecem retry ou mensagem ao usuário | Diversos serviços |
| Timeout sem tratamento | BAIXO | Timeouts tratados em parte (VendasScreen, ClientesScreen corrigidos); outras telas ainda sem tratamento adequado | Diversas telas |

### 3.7 Segurança

| Achado | Severidade | Descrição | Arquivos |
|--------|------------|-----------|----------|
| Root admin hardcoded | MÉDIO | E-mails em firestore.rules e lib (role_utils, login_screen, etc.) | firestore.rules:14–19, role_utils.dart, login_screen.dart |
| `verify_token` Meta hardcoded | BAIXO | `masterpalm_verify_2026` em canais_meta | canais_meta_screen, canais_meta_widgets |
| `pedidos_pendentes` update amplo | ALTO | `isSignedIn()` permite update – qualquer usuário autenticado | firestore.rules:483 |

### 3.8 Publicação / Produção

| Achado | Severidade | Descrição | Arquivos |
|--------|------------|-----------|----------|
| Referências `masterpalm.com.br` | ALTO | Domínio oficial é `mastepalm.com.br`. Referências a `masterpalm.com.br` devem ser corrigidas. AndroidManifest já usa `mastepalm.com.br` (correto) | loja_config_screen (subdominioDominioBase), docs, privacidade.html |
| READ_CONTACTS | MÉDIO | Play Store pode pedir justificativa para contatos | AndroidManifest.xml:9 |
| assetlinks | BAIXO | Configurado em firebase.json; verificar se `/well-known/assetlinks.json` está público para `mastepalm.com.br` | firebase.json, docs |
| Deep links | BAIXO | AndroidManifest já usa `mastepalm.com.br` e `www.mastepalm.com.br` (correto) | AndroidManifest.xml:87–92 |

---

## 4. Achados por severidade

### ALTO
1. Referências a `masterpalm.com.br` em vez de `mastepalm.com.br` (domínio oficial).
2. Fallback `'padrao'` em várias telas.
3. Root `/pedidos` exige admin; escrita por cliente/vendedor falha e erro é engolido.
4. `pedidos_pendentes` permite update para qualquer usuário autenticado.

### MÉDIO
5. Dezenas de `catch (_) {}` sem feedback ao usuário.
6. AutoSyncService sem LojaIdAdapter.
7. Índices `categoria`/`subcategoria` vs coleções `categorias`/`subcategorias`.
8. READ_CONTACTS no Android.
9. Fallback dinâmico Hive na Web.
10. Root admin hardcoded.
11. Comportamento diferente entre Web/APK por `kIsWeb`.

### BAIXO
12. `verify_token` Meta hardcoded.
13. `pre_pedidos` index e campo `dataCriacao`.
14. Avatar não salvo na Web.
15. URLs hardcoded em vários pontos.

---

## 5. Lista de arquivos impactados (principais)

### Multi-loja / LojaId
- `lib/core/loja_id_adapter.dart`
- `lib/services/loja_id_service.dart`
- `lib/services/store_resolver_service.dart`
- `lib/services/store_resolver_facade.dart`
- `lib/services/auto_sync_service.dart`
- `lib/screens/contas_receber_screen.dart`
- `lib/screens/fornecedor_screen.dart`
- `lib/screens/historico_clientes_screen.dart`
- `lib/screens/notas_fiscais_screen.dart`
- `lib/screens/admin_painel_web_screen.dart`
- `lib/screens/relatorio_ranking_clientes_screen.dart`

### Firestore
- `firestore.rules`
- `firestore.indexes.json`
- `lib/screens/order_review_screen.dart`
- `lib/services/catalogo_venda_service.dart`
- `lib/services/pre_pedido_service.dart`
- `lib/catalog/data/firestore_catalog_impl.dart`

### Pedidos
- `lib/services/pre_pedido_service.dart`
- `lib/services/catalogo_venda_service.dart`
- `lib/services/pos_pagamento_service.dart`
- `lib/screens/pedido_publico_screen.dart`
- `lib/screens/order_review_screen.dart`

### Segurança / Config
- `lib/utils/role_utils.dart`
- `lib/screens/login_screen.dart`
- `lib/config/app_check_config.dart`
- `lib/screens/configuracoes/canais_meta_screen.dart`
- `lib/screens/configuracoes/canais_meta_widgets.dart`

### Android / Web
- `android/app/src/main/AndroidManifest.xml`
- `firebase.json`
- `lib/main.dart`
- `web/index.html`

---

## 6. Ordem ideal de correção

1. **Validar domínio** – Confirmar se produção usa `mastepalm.com.br` ou `masterpalm.com.br` e ajustar AndroidManifest, firebase.json e deep links.
2. **Remover fallback `'padrao'`** – Replicar padrão de VendasScreen/ClientesScreen (LojaIdService.getWithTimeout + erro explícito) para as demais telas.
3. **Revisar regras Firestore** – Definir política consistente para pedidos; avaliar se root `/pedidos` deve existir e, se sim, qual regra de acesso.
4. **`pedidos_pendentes`** – Restringir update a belongsToStore ou admin.
5. **Substituir `catch (_) {}` críticos** – Em fluxos de pedido, sync e pagamento: log + feedback ao usuário; retry onde fizer sentido.
6. **Centralizar resolução de loja** – Usar LojaIdAdapter/normalizeFromBox em AutoSyncService e demais leituras de sessão.
7. **Validar índices Firestore** – Conferir coleções reais e campos usados nas queries; alinhar firestore.indexes.json.
8. **Documentar READ_CONTACTS** – Política de privacidade e, se necessário, declaração para a Play Store.

---

## 7. O que NÃO mexer agora

- **Models / Hive** – Não alterar estruturas de Cliente, Produto, Venda sem migração.
- **Coleções Firestore** – Não unificar pre_pedidos/pedidos_pendentes/pedidos_catalogo sem plano de migração.
- **Cloud Functions** – Não alterar assinaturas ou integrações sem testar webhooks (MP, Meta).
- **Fluxo de checkout** – Mudanças em CatalogoVendaService e PrePedidoService exigem testes completos de pagamento.

---

## 8. Dependências perigosas

- **contacts_service_plus** – Depende de READ_CONTACTS; Play Store pode exigir justificativa.
- **firebase_app_check** – Web com falhas de ativação pode rodar sem proteção.
- **hive** – Boxes dinâmicas na Web com fallback podem ocultar erros de schema.

---

## 9. Inconsistências de naming

| Contexto | Variações | Padrão sugerido |
|----------|-----------|-----------------|
| ID da loja | `lojaId`, `store_id`, `storeId` | Dart: `lojaId`; Firestore/Hive: `store_id` |
| Domínio público | `mastepalm.com.br` (correto), `masterpalm.com.br` (incorreto) | Padronizar para `mastepalm.com.br` |
| Coleções de pedido | `pre_pedidos`, `pedidos_pendentes`, `pedidos_catalogo`, `pedidos` | Documentar responsabilidade de cada uma |
| Campos de data | `dataCriacao`, `createdAt`, `dataCadastro`, `criadoEm` | Padronizar no domínio |

---

## 10. Inconsistências dev / homolog / prod

- **firebase.json** – Dois targets: `mastepalm` e `masterpalm-58c46`; `masterpalm-58c46` é ID do projeto Firebase.
- **Domínios** – Domínio oficial: `mastepalm.com.br`; `app.mastepalm.com.br` é o subdomínio do app (correto).
- **App Check** – Web com soft-fail; validar se em prod o fluxo sem App Check é aceitável.

---

## Riscos potenciais (validar)

1. **Queries com `dataCriacao`** – Verificar se docs em `pre_pedidos` usam esse campo ou `createdAt`/outro.
2. **Índice `categoria`** – Coleção em rules é `categorias`; subcollection é `subcategoria`. Verificar se algum código usa `categoria` como collection.
3. **Root `/pedidos`** – Confirmar se o uso por OrderReviewScreen é intencional ou legado a ser removido.
4. **Referências `masterpalm.com`** – Em subdomínios (ex: `nathypratasefolheados.masterpalm.com`); confirmar se o domínio base de subdomínios é `mastepalm.com` ou `masterpalm.com` e padronizar conforme política oficial.
