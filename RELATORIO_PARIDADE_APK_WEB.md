# Relatório: Paridade APK vs Web vs Catálogo vs Desktop

**Projeto:** MasterPalm  
**Data:** 07/03/2025  
**Versão:** 1.0.27+36

---

## 1. Estrutura geral do projeto

| Plataforma | Localização | Descrição |
|------------|-------------|-----------|
| **App Flutter (APK)** | `lib/`, `android/`, `ios/` | Código Dart compartilhado; builds Android e iOS |
| **Site Web** | `web/`, `build/web/` | Flutter Web; servido via Firebase Hosting |
| **Catálogo Web** | Mesmo build em `build/web/` | Rota `/loja/{slug}` → `PublicCatalogScreen` |
| **App Desktop** | `windows/`, `macos/`, `linux/` | Flutter Desktop; build via `--desktop` em `deploy-completo.sh` |

### URLs principais (Firebase Hosting)
- **App Web (admin):** `app.mastepalm.com.br` → SPA Flutter
- **Catálogo público:** `/loja/{slugOuId}` (ex.: `/loja/nathy-pratas-e-folheados`)
- **Link curto:** `/c/{linkCurto}` → Cloud Function `redirectCatalogo` → redireciona para `/loja/{slug}`
- **OAuth MP:** `/mp-oauth`, `/mp-oauth-callback`
- **Páginas estáticas:** `/privacidade`, `/download`, etc.

---

## 2. Mapa de funcionalidades por plataforma

| Funcionalidade | APK | Web (Admin) | Catálogo Web | Desktop |
|----------------|-----|-------------|--------------|---------|
| Login / Cadastro | ✅ | ✅ | — | ✅ |
| Home / Dashboard | ✅ | ✅ | — | ✅ |
| **Vendas** | ✅ | ✅ | — | ✅ |
| Nova venda / PDV | ✅ | ✅ | — | ✅ |
| Análise vendas IA | ✅ | ✅ | — | ✅ |
| **Estoque** | ✅ | ✅ | — | ✅ |
| Cadastro produto | ✅ | ✅ | — | ✅ |
| Importação Excel/CSV | ✅ | ✅ | — | ✅ |
| Importação PDF | ✅ | ⚠️ Desabilitado | — | ✅ |
| **Código de barras** | ✅ | ⚠️ Câmera pode falhar | — | ⚠️ Depende de câmera |
| **Pedidos / Pré-pedidos** | ✅ | ✅ | — | ✅ |
| **Clientes** | ✅ | ✅ | — | ✅ |
| Avatar local | ✅ | ⚠️ Não salvo localmente | — | ✅ |
| **Catálogo interno** | ✅ | ✅ | — | ✅ |
| **Catálogo público** (loja online) | ✅ | ✅ | ✅ | ✅ |
| Carrinho + checkout | — | — | ✅ | — |
| Banners, busca, filtros | — | — | ✅ | — |
| Integração WhatsApp | — | — | ✅ | — |
| Integração Mercado Pago | — | — | ✅ | — |
| **Pagamentos** (config) | ✅ | ✅ | — | ✅ |
| OAuth MP (web flow) | — | ✅ | — | — |
| **Relatórios** | ✅ | ✅ | — | ✅ |
| **Financeiro** (contas, NF) | ✅ | ✅ | — | ✅ |
| Fretes / Cupons | ✅ | ✅ | — | ✅ |
| Campanhas / Sorteio | ✅ | ✅ | — | ✅ |
| Roleta da sorte | ✅ | ✅ | — | ✅ |
| Metas / Comissões | ✅ | ✅ | — | ✅ |
| Vendedores | ✅ | ✅ | — | ✅ |
| Fornecedores | ✅ | ✅ | — | ✅ |
| **Backup local** | ✅ | ❌ Não disponível | — | ✅ |
| **Notificações push (FCM)** | ✅ | ❌ | — | ❌ |
| Verificar atualização | ✅ | ⚠️ Snackbar "sempre atual" | — | ✅ |
| Planos / In-app purchase | ✅ | ⚠️ Apenas link externo | — | ⚠️ |
| Configurações loja | ✅ | ✅ | — | ✅ |
| Canais Meta (WhatsApp, IG) | ✅ | ✅ | — | ✅ |
| Admin (usuários, sync, master) | ✅ | ✅ | — | ✅ |
| Marketplaces / ERP | ✅ | ✅ | — | ✅ |
| Carrinhos abandonados | ✅ | ✅ | — | ✅ |
| **Modo offline / Hive** | ✅ | ⚠️ IndexedDB | — | ✅ |
| **Connectivity listener** | ✅ | ❌ Não inicia | — | ✅ |

**Legenda:** ✅ Totalmente funcional | ⚠️ Parcial / limitado | ❌ Não disponível

---

## 3. Funcionalidades que existem no APK mas não (ou parcialmente) no Web

### 3.1 Totalmente indisponíveis no Web
| Feature | Motivo | Onde está no código |
|---------|--------|---------------------|
| Backup local | Web não tem filesystem local | `backup_screen.dart` – `if (kIsWeb)` retorna tela vazia |
| Notificações push (FCM) | FCM não suporta web (ou não configurado) | `fcm_pedido_service.dart` – `if (kIsWeb) return` |
| Listener de conectividade | Otimizado para mobile | `sync_queue_service.dart` – `if (!kIsWeb) startConnectivityListener()` |

### 3.2 Parcialmente limitadas no Web
| Feature | Limitação | Onde está no código |
|---------|-----------|---------------------|
| Código de barras | Câmera pode falhar; `mobile_scanner` com restrições no navegador | `barcode_scanner_screen.dart` – mensagem "Na versão web a leitura pode não estar disponível" |
| Importação PDF | Throw explícito no web | `estoque_screen.dart` – `if (kIsWeb) throw "Importação de PDF não disponível..."` |
| Avatar do cliente | Não salva localmente | `clientes_screen.dart` – `if (kIsWeb) return null` |
| Planos / compra in-app | In-app purchase só mobile; web usa link externo | `planos_screen.dart` – `if (kIsWeb) return false` |
| Verificar atualização | Snackbar informa que web sempre está atual | `home_screen.dart` – `if (kIsWeb)` |
| Admin publish FAB/Bar | Oculta no web | `admin_publish_fab.dart`, `admin_publish_bar.dart` |
| Catalog thumbnail local | Retorna null no web | `catalog_thumbnail_service.dart` – `if (kIsWeb) return null` |
| Cloud sync (produtos) | Não inicia no web | `cloud_sync_service.dart` – `if (kIsWeb)` branch |

---

## 4. Catálogo Web (público) – o que existe

O **catálogo público** é uma experiência dedicada para o cliente final:

- **Rota:** `/loja/{slug}` ou `/loja/{storeId}`
- **Query params:** `?ref=vendedorId`, `?indicacao=clienteId`, `?page=dicas`
- **Funcionalidades:**
  - Listagem de produtos com busca e filtros
  - Carrinho
  - Checkout (cadastro obrigatório)
  - Integração WhatsApp
  - Integração Mercado Pago (PIX, cartão, boleto)
  - Banners e páginas customizadas
  - Tracking de vendedor e indicação

O catálogo **não** inclui:
- Gestão de vendas, estoque, clientes, relatórios
- Configurações da loja
- Cadastro de produtos
- Qualquer tela administrativa

---

## 5. Desktop

- **Build:** `deploy-completo.sh --desktop`
- **Plataformas:** Windows, macOS, Linux
- **Funcionalidades:** Mesmas do APK (usa o mesmo `MyApp`)
- **Diferenças:** Sem FCM; sem in-app purchase nativo; câmera (código de barras) depende do hardware

---

## 6. Sugestões de implementação das features faltantes no Web

| Feature | Onde implementar | Sugestão |
|---------|------------------|----------|
| Backup | `lib/screens/backup_screen.dart` | Adicionar exportação para arquivo (download) via `dart:html` / `file_picker`; manter mensagem explicando que backup “local” é diferente |
| Notificações | `lib/services/fcm_pedido_service.dart` | Avaliar Web Push (Firebase Cloud Messaging para Web) ou alternativas (OneSignal, etc.) |
| Código de barras | `lib/screens/barcode_scanner_screen.dart` | Manter tentativa com `mobile_scanner`; adicionar fallback de input manual no web |
| Importação PDF | `lib/screens/estoque_screen.dart` | Usar `pdf` + `pdf_text` no web para extrair texto e parsear tabelas, ou manter apenas Excel/CSV |
| Avatar do cliente | `lib/screens/clientes_screen.dart` | Já usa Firebase Storage; garantir upload no web e exibição via URL |
| Planos | `lib/screens/planos_screen.dart` | Web: manter link para checkout externo; não depender de in-app purchase |
| Verificar atualização | `lib/screens/home_screen.dart` | Web: manter snackbar informativa; opcionalmente checar versão via API e avisar usuário para F5 |
| Admin publish | `lib/widgets/admin_publish_*.dart` | Avaliar se faz sentido exibir no web (ex.: para revisar antes de publicar) |
| Catalog thumbnails | `lib/services/catalog_thumbnail_service.dart` | Web: usar sempre URLs remotas (Firebase Storage/CDN) em vez de cache local |
| Connectivity | `lib/services/sync_queue_service.dart` | Web: usar `navigator.onLine` e evento `online`/`offline` para notificar usuário |

---

## 7. Resumo executivo

| Aspecto | Status |
|---------|--------|
| **Paridade Web Admin vs APK** | ~90% – faltam backup, FCM, algumas limitações (PDF, barcode, avatar) |
| **Catálogo Web** | Completo para compra; sem gestão |
| **Desktop** | Paridade com APK; sem FCM e sem in-app purchase |
| **Prioridade sugerida** | 1) Backup web (export); 2) Barcode fallback manual; 3) PDF import ou manter Excel; 4) Web Push (opcional) |

---

## 8. Rotas principais (referência)

```
/                     → AppStartRouter (splash/login/home)
/login                → LoginScreen
/register             → RegisterScreen
/home                 → HomeScreen
/vendas               → VendasScreen
/estoque              → EstoqueScreen
/clientes             → ClientesScreen
/pedidos              → PrePedidosScreen
/catalogo             → CatalogoScreen (interno)
/loja/{id}            → PublicCatalogScreen (catálogo público)
/relatorios           → RelatoriosScreen
/config/pagamentos    → ConfigPagamentosSimplesScreen
/campanhas_sorteio    → CampanhasSorteioScreen
/fretes_cupons        → FretesCuponsScreen
/metas_comissoes      → MetasComissoesScreen
...
```
