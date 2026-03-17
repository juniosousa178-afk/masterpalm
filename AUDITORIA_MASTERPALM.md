# AUDITORIA COMPLETA — MasterPalm

**Data:** 10/03/2025  
**Escopo:** Funcionalidades realmente existentes e integradas no código (sem inventar ou listar planejados).

---

## ETAPA 1 — MAPEAR TELAS

### Telas principais (acessíveis por rotas / menu)

| Tela | Arquivo | Função | Funcionalidades |
|------|---------|--------|-----------------|
| **Splash** | `splash_screen.dart` | Tela inicial de carregamento | Exibe logo e aguarda bootstrap |
| **Login** | `login_screen.dart` | Autenticação admin/vendedor | Login e-mail/senha, Google, recuperação de senha |
| **Cadastro (admin)** | `cadastro_screen.dart` | Cadastro de novo usuário admin | Formulário de cadastro |
| **Registro** | `register_screen.dart` | Registro de nova conta | Fluxo de registro com plano |
| **Verificação de e-mail** | `verify_email_screen.dart` | Verificação de e-mail | Link de verificação, redirecionamento |
| **Router inicial** | `app_start_router.dart` | Define tela inicial pós-login | Verificação de sessão, plano, role, loja |
| **Home** | `home_screen.dart` | Dashboard e menu principal | Cards (Estoque, Cliente, Vendas, Loja), menu lateral, migração/importação, plano, notificações |
| **Vendas** | `vendas_screen.dart` | Listagem e gestão de vendas | Lista vendas, nova venda (modal), edição, sugestões IA |
| **Nova Venda (modal)** | `nova_venda_modal.dart` | Fluxo de venda no balcão | Múltiplos produtos, cliente, frete, desconto, múltiplas formas de pagamento, roleta da sorte, fiado, combos, variações |
| **Clientes** | `clientes_screen.dart` | Cadastro e lista de clientes | CRUD clientes, histórico, exportação Excel, sugestões IA |
| **Estoque** | `estoque_screen.dart` | Gestão de produtos e estoque | Lista produtos, cadastro/edição, categorias/subcategorias, import/export Excel/CSV, fotos, combos, sugestões IA |
| **Cadastro Produto** | `cadastro_produto_screen.dart` | Formulário de produto | Campos de produto |
| **Produto Form** | `produto_form_screen.dart` | Formulário completo de produto | Edição avançada de produto |
| **Produto Combo Form** | `produto_combo_form_screen.dart` | Cadastro de combo | Itens do combo, preço |
| **Fornecedores** | `fornecedor_screen.dart` | Cadastro de fornecedores | CRUD fornecedores |
| **Histórico Clientes** | `historico_clientes_screen.dart` | Histórico de compras do cliente | Lista vendas por cliente |
| **Histórico Cliente Detalhe** | `historico_cliente_detalhe_screen.dart` | Detalhe de uma venda no histórico | Detalhes da venda |
| **Backup** | `backup_screen.dart` (web: `backup_screen_web.dart`, mobile: `backup_screen_mobile.dart`) | Backup e restauração | Backup manual, restauração, agendamento (mobile) |
| **Relatórios** | `relatorios_screen.dart` | Menu de relatórios | Acesso a relatórios financeiros, vendedor, etc. |
| **Relatório Financeiro** | `relatorio_financeiro_screen.dart` | Relatório financeiro | Gráficos e totais |
| **Relatórios Financeiros** | `relatorios_financeiros_screen.dart` | Consolidado financeiro e metas | Financeiro + metas, sugestões IA |
| **Relatório Vendedor** | `relatorio_vendedor_screen.dart` | Performance por vendedor | Vendas por vendedor |
| **Relatório Mais Vendidos** | `relatorio_mais_vendidos_screen.dart` | Produtos mais vendidos | Ranking por quantidade/faturamento |
| **Relatório Ranking Clientes** | `relatorio_ranking_clientes_screen.dart` | Ranking de clientes | Clientes por valor comprado |
| **Relatório Lucratividade Produto** | `relatorio_lucratividade_produto_screen.dart` | Lucro por produto | Margem por produto |
| **Precificação Universal** | `precificacao_universal_screen.dart` | Ajuste em massa de preços | Reajuste por margem/categoria |
| **Pedidos (Pré-pedidos)** | `pre_pedidos_screen.dart` | Pedidos do catálogo e pendentes | Lista pré-pedidos, status, converter em venda, limpar, sugestões IA |
| **Catálogo (admin)** | `catalago_screen.dart` | Configuração do catálogo interno | Produtos no catálogo |
| **Cadastro Catálogo** | `cadastro_catalogo_screen.dart` | Cadastro de item no catálogo | Adicionar produto ao catálogo |
| **Config Catálogo** | `config_catalogo_screen.dart` | Configurações do catálogo | Opções do catálogo |
| **Catálogo Público (Web/Loja)** | `public_catalog_screen.dart` | Loja online pública | Grid produtos, carrinho, checkout, cadastro cliente, WhatsApp, Mercado Pago, PIX, banners, dicas, recentes, filtros |
| **Loja Config** | `loja_config_screen.dart` | Configurações da loja | Slug, dados da loja, catálogo |
| **Pre-config Loja** | `loja_preconfig_screen.dart` | Pré-configuração pós-registro | Config inicial da loja |
| **Onboarding Loja** | `onboarding_loja_screen.dart` | Tour de configuração | Passos iniciais |
| **Planos** | `planos_screen.dart` | Escolha/gestão de plano | Planos free_trial_90d, free_limited, pagos |
| **Plano** | `plano_screen.dart` | Tela de plano | Detalhes do plano |
| **Permissões** | `permissoes_screen.dart` | Gestão de permissões por vendedor | Liberar/bloquear telas por vendedor |
| **Visualizar Permissões** | `visualizar_permissoes_screen.dart` | Ver permissões do usuário | Somente leitura |
| **Vendedores** | `vendedores_screen.dart` | Cadastro e gestão de vendedores | Lista, cadastro, edição, permissões |
| **Admin Usuários** | `admin_usuarios_screen.dart` | Gestão de usuários (root) | Usuários e planos (master) |
| **Admin Sync** | `admin_sync_screen.dart` | Sincronização manual | Sync Firestore ↔ Hive |
| **Config Pagamentos** | `config_pagamentos_screen.dart` | Configuração de gateways | Mercado Pago, etc. |
| **Config Pagamentos Simples** | `config_pagamentos_simples_screen.dart` | Config pagamentos simplificada | Fluxo simples |
| **Diagnóstico** | `diagnostico_app_screen.dart` | Diagnóstico técnico | App Check, store_id, logs |
| **Ajuda** | `ajuda_screen.dart` | Ajuda ao usuário | Conteúdo de ajuda |
| **Config PIN** | `config_pin_screen.dart` | Alterar PIN (programador) | PIN de segurança |
| **Health Check** | `debug/health_check_screen.dart` | App Check / saúde | Token App Check |
| **Test Checkout** | `services/test_checkout.dart` | Teste de checkout MP | Teste de pagamento |
| **Campanhas Sorteio** | `campanhas_sorteio_screen.dart` | Lista de campanhas de sorteio | Navegação para sorteios |
| **Campanha Sorteio Form** | `campanha_sorteio_form_screen.dart` | Criar/editar campanha | Formulário campanha |
| **Campanha Sorteio Histórico** | `campanha_sorteio_historico_screen.dart` | Histórico de campanhas | Lista de campanhas |
| **Globo Sorteio** | `globo_sorteio_screen.dart` | Globo da sorte (sorteio) | Girar globo, sortear |
| **Roleta da Sorte** | `roleta_sorte_screen.dart` | Roleta de prêmios | Girar roleta, prêmios (%, valor, frete grátis, brinde) |
| **Roleta Config** | `roleta_sorte_config_screen.dart` | Configurar roleta | Valor mínimo, prêmios, frequência |
| **Fretes e Cupons** | `fretes_cupons_screen.dart` | Regras de frete e cupons | Cupons de desconto, frete |
| **Canais Meta** | `configuracoes/canais_meta_screen.dart` | WhatsApp, Instagram, Messenger | Configuração de canais |
| **Metas e Comissões** | `metas_comissoes_screen.dart` | Metas e comissões de vendedores | Metas, comissões, sugestões IA |
| **Notas Fiscais** | `notas_fiscais_screen.dart` | Gestão de notas fiscais | Lista e cadastro de NF |
| **Contas a Receber** | `contas_receber_screen.dart` | Contas a receber | Parcelas, status |
| **Carrinhos Abandonados** | `carrinhos_abandonados_screen.dart` | Carrinhos não finalizados | Lista por loja |
| **Histórico Movimentação Estoque** | `historico_movimentacao_estoque_screen.dart` | Movimentações de estoque | Entradas/saídas |
| **Subcategorias** | `subcategorias_screen.dart` | CRUD subcategorias | Subcategorias de produtos |
| **Dicas IA** | `dicas_ia_screen.dart` | Chat de dicas com IA | Chat Gemini para marketing |
| **Textos WhatsApp IA** | `textos_whatsapp_ia_screen.dart` | Geração de textos para WhatsApp | IA para mensagens |
| **Análise Vendas IA** | `analise_vendas_ia_screen.dart` | Perguntas sobre vendas (IA) | Chat com dados de vendas |
| **Global Search** | `global_search_screen.dart` | Busca global | Busca em produtos/clientes/vendas |
| **Barcode Scanner** | `barcode_scanner_screen.dart` | Leitura de código de barras | Scanner para produto |
| **Marketplaces** | `marketplaces_screen.dart` | Integrações ERP/Marketplaces | Tela de marketplaces |
| **Consolidar Lojas** | `consolidate_stores_screen.dart` | Consolidar dados de lojas | Merge de lojas (específico) |
| **Master Login** | `master_login_screen.dart` | Login master (root) | Acesso config master |
| **Master Config** | `master_config_screen.dart` | Configurações globais do sistema | Remote Config, etc. |
| **Site Config** | `site_config_screen.dart` | Configuração do site (root) | Config site público |
| **Onboarding App** | `onboarding_app_screen.dart` | Tour do app (primeira vez) | Passos iniciais no app |

### Telas do fluxo do catálogo público (cliente final)

| Tela | Arquivo | Função | Funcionalidades |
|------|---------|--------|-----------------|
| **Login Cliente (loja)** | `auth/login_screen_cliente.dart` | Login do cliente no portal | E-mail/senha |
| **Cadastro Cliente (loja)** | `auth/cadastro_screen_cliente.dart` | Cadastro no portal | Registro cliente loja |
| **Perfil Cliente** | `auth/perfil_cliente_screen_novo.dart` | Perfil do cliente | Editar dados, pedidos |
| **Redefinir Senha Cliente** | `auth/redefinir_senha_cliente_screen.dart` | Recuperar senha (portal) | Fluxo de recuperação |
| **Redefinir Senha Cliente Loja** | `redefinir_senha_cliente_loja_screen.dart` | Redefinir senha na loja | Redefinição no contexto loja |
| **Pedido Público** | `pedido_publico_screen.dart` | Visualização de pedido por link | Status do pedido (link /pedido/xxx) |
| **Order Review** | `order_review_screen.dart` | Revisão do pedido (temp order) | Revisar antes de pagar |
| **Pagamento Resultado** | `pagamento_resultado_screen.dart` | Resultado do pagamento (sucesso/falha/pendente) | Retorno MP, mensagem |
| **Visualizar Produto Catálogo** | `visualizar_produto_catalogo_screen.dart` | Ver produto do catálogo | Detalhe produto |
| **Catálogo Dicas** | `public_catalog/catalog_dicas_screen.dart` | Dicas no catálogo | Conteúdo de dicas |

### Rotas dinâmicas (app_routes / main)

- `/loja`, `/loja/{slug}` — Catálogo público (Web e app).
- `/sucesso`, `/pagamento/sucesso`, `/checkout/success` — Sucesso pagamento.
- `/falha`, `/pagamento/falha`, `/checkout/failure` — Falha pagamento.
- `/pagamento/pendente`, `/checkout/pending` — Pagamento pendente.
- `/pedido/{orderId}` — Pedido público ou OrderReview.

---

## ETAPA 2 — FUNCIONALIDADES REAIS DO SISTEMA (por categoria)

### AUTENTICAÇÃO
- Login e-mail/senha (Firebase Auth)
- Login com Google
- Cadastro de novo usuário (RegisterScreen)
- Verificação de e-mail (VerifyEmailScreen)
- Recuperação de senha
- Logout com limpeza de sessão e cache multi-tenant
- Auth para cliente do portal (LoginScreenCliente, CadastroScreenCliente, RedefinirSenhaCliente)
- Perfil cliente (PerfilClienteScreenNovo) com dados no Firestore (lojas/{id}/clientes)

### VENDAS (balcão / Nova Venda)
- Criação de venda com múltiplos produtos
- Seleção de produto por nome/slug/ID, com variações e combos (VariacaoSelectionSheet, ComboVariacaoSelectionSheet)
- Cliente opcional (autocomplete/getOrCreate)
- Frete (valor manual)
- Desconto (percentual)
- Múltiplas formas de pagamento (Pix, Dinheiro, Cartão) com valores parciais
- Cálculo automático de subtotal e total
- Validação de pagamento completo (soma dos pagamentos = total) ou registro como fiado (conta a receber)
- Baixa automática no estoque (EstoqueTransactionService, MovimentacaoEstoqueService)
- Sincronização com Firestore (VendasFirestoreService)
- Edição de venda (desfaz estoque antigo e registra nova)
- Integração com campanhas/sorteio (número da sorte)
- Roleta da sorte no checkout (prêmio aplicado ao pedido)
- Fiado (conta a receber com vencimento)

### ESTOQUE
- Cadastro de produto (ProdutoFormScreen, CadastroProdutoScreen)
- Edição de produto
- Categorias e subcategorias (SubcategoriasScreen, modelos Categoria, Subcategoria)
- Controle de quantidade (estoque simples e por tamanho/cor)
- Estoque por variações (tamanho/cor) e combos
- Baixa automática no estoque na venda (VendasService + EstoqueTransactionService)
- Histórico de movimentação (HistoricoMovimentacaoEstoqueScreen, MovimentacaoEstoqueService)
- Importação Excel/CSV (estoque_screen)
- Exportação Excel (estoque_screen)
- Fotos de produtos (ImagePicker, upload)
- Produtos com opção “publicar no catálogo”
- Produto combo (ProdutoComboFormScreen)

### CLIENTES
- Cadastro de cliente (ClientesScreen)
- Edição e exclusão
- Histórico de compras (HistoricoClientesScreen, HistoricoClienteDetalheScreen) com HiveList
- Autocomplete de cliente na venda (getOrCreate, busca por nome)
- Reconciliação vendas–clientes (ReconciliacaoVendasClientesService)
- Exportação Excel (clientes_screen, export_excel)
- Importação de clientes (importar_clientes, excel_import_service)
- Cliente no portal (Firestore lojas/{id}/clientes, ClienteAuthService, ClienteWebService)

### RELATÓRIOS
- Relatório financeiro (RelatorioFinanceiroScreen, RelatoriosFinanceirosScreen)
- Relatório por vendedor (RelatorioVendedorScreen)
- Mais vendidos (RelatorioMaisVendidosScreen)
- Ranking de clientes (RelatorioRankingClientesScreen)
- Lucratividade por produto (RelatorioLucratividadeProdutoScreen)
- Metas e comissões (MetasComissoesScreen) com metas e comissões por vendedor

### PERMISSÕES E ROLES
- Roles: programador, admin, vendedor (users/usuarios no Firestore, RoleUtils)
- Permissões por vendedor (PermissaoService, PermissoesScreen): estoque, vendas, clientes, fornecedores, precificação, relatórios, histórico_cliente, backup, catálogo, canais, cupons, etc.
- Restrição de acesso no menu (HomeScreen usa PermissaoService.todas() e combinadas)
- Root por e-mail (masterpalm26@gmail.com, etc.) com acesso Master Config e Admin Usuários
- FirestoreCriticalListenerService para atualização em tempo real de permissões
- VisualizarPermissoesScreen (somente leitura)

### BACKUP
- Backup manual (BackupScreen – web e mobile)
- Backup automático agendado (BackupAutoService em backup_auto_service_io.dart: 3h, retenção 7 dias, zip, notificação local)
- Restauração a partir do backup
- Migração de dados (Hive → novas coleções) e Importar do Firestore (produtos, clientes, fornecedores, vendas + reconciliação)

### IA (Gemini via Cloud Functions)
- Sugestão de descrição de produto (AiLojaService.sugerirDescricao)
- Sugestão de título de produto (sugerirTitulo)
- Variações de descrição (feed, WhatsApp, Instagram) (sugerirVariacoesDescricao)
- Chat de dicas (DicasIaScreen – chatDicas)
- Textos para WhatsApp (TextosWhatsAppIaScreen)
- Análise de vendas – “pergunte sobre vendas” (AnaliseVendasIaScreen)
- Sugestões IA em telas: vendas, clientes, estoque, pedidos, financeiro, metas (widgets _SugestoesIa*)
- Limite de uso de IA (IaUsoLimiteService)
- Preferência de modelo (Gemini; OpenAI desabilitado no código)

### CATÁLOGO PÚBLICO (LOJA ONLINE)
- Catálogo por loja (PublicCatalogScreen com lojaId/slug)
- Resolução de slug para store_id (main.dart _resolveSlugToStoreIdIfNeeded)
- Grid de produtos com paginação (Firestore + cache CatalogCacheService)
- Carrinho (local/temp_order)
- Checkout com cadastro/login obrigatório (cliente)
- Cálculo de frete (FreteService, SuperfreteService)
- Cupons de desconto (CuponsService, CupomDescontoService)
- Pagamento: WhatsApp (link), Mercado Pago (checkout), PIX (QR)
- Banners no catálogo (CatalogBannerCarousel, CampanhaBannerWidget)
- Dicas no catálogo (CatalogDicasScreen)
- Seção “recentes” (CatalogRecentService)
- Filtros e busca (CatalogSearchFiltersBar)
- Tracking de vendedor (?ref=) para comissão
- Indicação (?indicacao=) para programa de indicação (IndicacaoConfigService)
- Tema do catálogo (CatalogThemeExtension, cores por loja)
- Cache em disco (CatalogCacheService, catalog_cache_disk_store)
- Publicação/ocultação por produto (publicadoNoCatalogo, exibir_no_catalogo)

### PRÉ-PEDIDOS / PEDIDOS DO CATÁLOGO
- Criação de pré-pedido no catálogo (PrePedidoService: Firestore pre_pedidos ou pedidos)
- Status de pedido (PedidoStatusPublicoRepository, pedido_status_publico)
- Tela de pedidos unificada (PrePedidosScreen: pré-pedidos + pendentes)
- Converter pré-pedido em venda (baixa estoque, VendasService, PosPagamentoService quando pago)
- Notificação de novo pedido (FcmPedidoService, NotificacaoPedidoListener) e abertura em “Ver pedido”
- E-mail ao cliente (PedidoClienteEmailService)
- Link público do pedido (/pedido/{id}?loja=) (PedidoPublicoScreen)
- Cupom e prêmio da roleta no pedido (premioRoleta no doc)

### PAGAMENTOS
- Configuração de gateways (ConfigPagamentosScreen, ConfigPagamentosSimplesScreen)
- Mercado Pago (MercadoPagoService, checkout, webhook, OAuth)
- PIX (geração de QR no catálogo)
- Contas a receber (ContasReceberScreen, modelo ContaReceber)
- Notas fiscais (NotasFiscaisScreen, NotaFiscalService, NotaFiscalFirestoreService)

### FRETES E CUPONS
- Tela Fretes e Cupons (FretesCuponsScreen)
- Regras de frete e cupons de desconto (CupomService, CupomDescontoService, FreteService)

### CAMPANHAS E SORTEIOS
- Campanhas de sorteio (CampanhasSorteioScreen, CampanhaSorteioFormScreen, CampanhaSorteioHistoricoScreen, CampanhaParticipantesScreen, CampanhasSorteioListScreen)
- Globo da sorte (GloboSorteioScreen, GloboSorteService)
- Roleta da sorte (RoletaSorteScreen, RoletaSorteConfigScreen, prêmios: %, valor, frete grátis, brinde, “tente novamente”)
- Número da sorte por venda (SorteioNumeroService, NumeroSorteService)
- CampaignEngineService (integração campanhas com vendas)

### INTEGRAÇÕES / CANAIS
- Canais Meta (CanaisMetaScreen, CanaisService): WhatsApp, Instagram, Messenger
- WhatsApp (link para envio de pedido/catálogo)
- Deep links (DeepLinkHandler, app_links)
- Mercado Pago (checkout, webhook, OAuth)
- ViaCEP (ViaCepService)
- Superfrete (SuperfreteService) para frete
- TON (TonService) – integração Telegram (código presente)
- E-mail (EmailService, mailer)
- Firebase (Auth, Firestore, Storage, Functions, FCM, Remote Config, App Check, Crashlytics, Analytics)

### NOTIFICAÇÕES
- Push local (NotificacaoService – flutter_local_notifications)
- Notificação de novo pedido (FcmPedidoService) e abertura na tela de pedidos
- Centro de notificações (NotificacaoCentroService, NotificacaoCentroSheet)
- Notificação de backup concluído (BackupAutoService)

### MULTI-LOJA
- Loja ativa por sessão (LojaIdService, StoreResolverService, StoreResolverFacade)
- Boxes Hive por loja (HiveBoxNames: clientes(lojaId), vendas(lojaId), produtos(lojaId), etc.)
- Firestore paths por loja (lojas/{lojaId}/...)
- Troca de loja (root: last_loja_id; vendedor: store_id do usuário)

### PLANOS E LICENÇA
- Planos (PlanosService, PlanId: free_trial_90d, free_limited, pagos)
- Verificação de plano no router (AppStartRouter) e na Home (avisos 15/10/5/0 dias)
- Tela de planos (PlanosScreen) e assinatura
- Licença (LicenseManager, hasValidAccessFallbackLegacy) para admin
- Migração trial → free_limited ao expirar

### EXPORTAÇÃO / IMPORTAÇÃO
- Exportar estoque para Excel (estoque_screen)
- Importar estoque de Excel/CSV (estoque_screen)
- Exportar clientes para Excel (clientes_screen, export_excel)
- Importar clientes (importar_clientes, ExcelImportService)
- Importar vendas do Firestore (ImportarVendasFirestoreService, menu “Importar dados”)

### OUTROS
- Busca global (GlobalSearchScreen)
- Scanner de código de barras (BarcodeScannerScreen, mobile_scanner)
- Modo escuro (darkModeNotifier, theme_notifier)
- Verificar atualização do app (AppUpdateService, UpdateCheckWrapper, UpdateAppDialog)
- Diagnóstico (DiagnosticoAppScreen, App Check, store_id)
- Master Config (MasterConfigScreen, Remote Config)
- Admin Usuários e Planos (root)
- Site Config (root)
- Consolidação de lojas (ConsolidateStoresScreen – uso restrito por UID)
- Marketplaces/ERP (MarketplacesScreen, MarketplaceService)

---

## ETAPA 3 — O QUE ESTÁ PARCIALMENTE IMPLEMENTADO

| Funcionalidade | Status | Motivo |
|----------------|--------|--------|
| **Catálogo WhatsApp** | Parcial | Existe geração de link do catálogo e envio de pedido por WhatsApp; tela de “pedidos” é a PrePedidosScreen (admin). Falta um “app de pedidos” dedicado só para o lojista no WhatsApp (ex.: lista de pedidos só por canal). |
| **CatalogoVendaService** | Parcial | Flag `kEnableCatalogoVendaService = false`. Quando ativa, notifica admin após gravar pedido no Firestore; integração opcional. |
| **UserProfileResolver unificado** | Parcial | Flag `kEnableUnifiedUserProfileResolver = false`. Resolver de perfil (users/usuarios) existe mas não é o fluxo padrão do router. |
| **Cache do catálogo em disco** | Parcial | Existe sanitização e auditoria desligadas por flags (kEnableCatalogDiskCacheSanitize, kEnableCatalogDiskCacheAuditLogs). Cache em disco está implementado e em uso. |
| **Marketplaces / ERP** | Parcial | Tela MarketplacesScreen e MarketplaceService existem; integrações concretas (APIs externas) podem estar limitadas ou em configuração. |
| **Consolidar Lojas** | Parcial | Funcionalidade disponível apenas para um UID específico (Naty Pratas); não é recurso geral. |
| **Roleta no catálogo** | Parcial | Roleta ativa na Nova Venda (balcão) e prêmio salvo no pré-pedido; no fluxo do catálogo público a roleta pode estar apenas em parte do fluxo (ex.: pós-checkout ou em telas específicas). |

---

## ETAPA 4 — FUNCIONALIDADES PLANEJADAS MAS NÃO IMPLEMENTADAS

- **IA de marketing “automática”** (ex.: geração automática de posts para redes) — existe IA para descrição, título, textos WhatsApp e chat de dicas; não há “geração automática de posts” ou agendamento de publicações.
- **Rotina automática de “roleta da sorte” no catálogo** — roleta está no balcão e em pré-pedidos; fluxo completo “cliente gira roleta no catálogo e aplica cupom” pode não estar em todas as etapas do checkout público.
- **Integração completa com Instagram/Messenger** — Canais Meta (tela e serviço) existem; integração de API oficial (envio/recebimento de mensagens) pode depender de configuração externa ou ainda não estar totalmente implementada.
- **Strict product resolution em produção** — `kStrictProductResolution` só ativa em debug; em release o fallback por nome/slug continua; “resolução apenas por ID” não é obrigatória em produção.

*(Itens listados são os que aparecem no código como flags, comentários ou serviços esqueléticos; não foram feita busca exaustiva por TODOs no resto do repositório.)*

---

## ETAPA 5 — MAPA FINAL DO SISTEMA

**MASTERPALM HOJE POSSUI:**

| Módulo | Status |
|--------|--------|
| Controle de vendas (balcão) | ✔ |
| Múltiplos produtos, frete, desconto, múltiplas formas de pagamento | ✔ |
| Controle de estoque (incl. variações e combos) | ✔ |
| Cadastro de clientes e histórico | ✔ |
| Relatórios (financeiro, vendedor, mais vendidos, ranking, lucratividade) | ✔ |
| Metas e comissões | ✔ |
| Controle de vendedores e permissões | ✔ |
| Backup (manual + automático) e importação Firestore | ✔ |
| Catálogo público (Web/app) com carrinho e checkout | ✔ |
| Pré-pedidos e pedidos do catálogo com notificação | ✔ |
| Pagamentos (Mercado Pago, PIX, fiado, contas a receber) | ✔ |
| Campanhas e sorteios (globo, roleta, número da sorte) | ✔ |
| IA (descrição, título, textos WhatsApp, dicas, análise de vendas) | ✔ (com limite de uso) |
| Fretes e cupons | ✔ |
| Canais Meta (WhatsApp, Instagram, Messenger) – configuração | ✔ |
| Multi-loja (sessão, Hive, Firestore por loja) | ✔ |
| Planos e licença | ✔ |
| Notas fiscais e contas a receber | ✔ |
| Exportação/importação (estoque, clientes, vendas) | ✔ |
| Marketing (campanhas, roleta, cupons) | ✔ |
| Catálogo WhatsApp (link + pedidos) | Parcial |
| Marketplaces/ERP | Parcial |
| IA de marketing (posts automáticos) | Não implementado |
| Resolução estrita de produto só por ID em produção | Não ativo (só em debug) |

---

## ETAPA 6 — ANÁLISE DE DIFERENCIAL

Comparado a apps como **Stoqui**, **Kyte POS** e **MarketUP**, o MasterPalm hoje se destaca pelo seguinte (tudo com base no que está no código):

1. **Catálogo público Web + app**  
   Loja online com URL por loja (/loja/slug), carrinho, checkout, cadastro de cliente, PIX e Mercado Pago, banners, dicas e cache. Muitos ERPs/POS não oferecem loja pública integrada ao mesmo app.

2. **Pré-pedidos e notificação em tempo real**  
   Pedidos vindos do catálogo viram pré-pedidos com status e notificação push (FCM) para o lojista; conversão em venda com baixa de estoque e opção de pagamento. Fluxo “pedido pelo cliente → aviso no celular do lojista” é um diferencial operacional.

3. **IA integrada (Gemini)**  
   Sugestão de descrição/título de produto, textos para WhatsApp, chat de dicas e “pergunte sobre vendas” com limite de uso. Diferencial em relação a POS que não têm IA no próprio app.

4. **Roleta da sorte e campanhas**  
   Roleta configurável (valor mínimo, prêmios, frequência) no checkout; globo da sorte; número da sorte por venda; campanhas de sorteio. Focado em engajamento e promoção, não só em estoque/venda.

5. **Multi-loja e multi-vendedor**  
   Sessão por loja, dados isolados por loja (Hive + Firestore), vendedores com permissões granulares (estoque, vendas, clientes, relatórios, catálogo, etc.). Adequado para redes ou lojas com equipe.

6. **Metas e comissões**  
   Telas de metas e comissões por vendedor, com tracking de venda (VendaTracking) e referência de vendedor no link do catálogo (?ref=). Diferencial para gestão de equipe comercial.

7. **Portal do cliente**  
   Cliente da loja com login/cadastro, perfil e pedidos no Firestore (lojas/{id}/clientes), token de portal e recuperação de senha. Experiência de “minha conta” ligada ao catálogo.

8. **Indicação e cupons**  
   Parâmetro ?indicacao= no link do catálogo, cupons de desconto e prêmio da roleta aplicados ao pedido. Programa de indicação e promoção já ligados ao fluxo.

9. **Offline-first e sincronização**  
   Hive local, SyncQueueService, AutoSyncService, importação/exportação e migração de dados. Pensado para uso com falha de rede e múltiplos dispositivos.

10. **Stack técnica**  
    Firebase (Auth, Firestore, Functions, FCM, Remote Config, App Check), planos e licença, verificação de atualização do app, diagnóstico e modo escuro. Posiciona o produto como app completo e controlado.

Em resumo: o diferencial está na **combinação de POS + loja online + pré-pedidos + IA + campanhas/roleta + multi-loja e permissões + metas/comissões**, com foco em pequeno varejo e equipe de vendas, e não só em controle de estoque ou PDV isolado.

---

*Relatório gerado com base exclusivamente no código do repositório (lib/, rotas, serviços, modelos e telas). Nenhuma funcionalidade foi inventada; itens parciais ou não implementados foram indicados conforme flags e uso real no código.*
