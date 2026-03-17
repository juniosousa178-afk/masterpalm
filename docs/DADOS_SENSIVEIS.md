# Dados sensíveis – onde ficam e quem acessa

Para LGPD, auditoria e futura exclusão/exportação. **Não remover dados nem telas;** só documentar.

---

## Firestore

| Caminho / coleção | Dado sensível | Quem lê/escreve |
|-------------------|---------------|------------------|
| **users/{uid}** | email, currentPlanId, status, store_id | Auth, StoreResolver, PlanosService, LicenseManager |
| **usuarios/{email}** | email, tipo (admin/programador), store_id | StoreResolver, permissões, app_start_router |
| **lojas/{lojaId}/config** | Config da loja (pagamentos, frete, etc.) | Catálogo, loja_config_screen, pagamentos_service |
| **lojas/{lojaId}/estoque_clientes** | nome, telefone, email, endereço | FullSync, SyncQueue, telas de clientes |
| **lojas/{lojaId}/clientes_catalogo** | Perfil e cupons do cliente (catálogo) | Checkout, roleta, perfil |
| **lojas/{lojaId}/vendedores** | UID, permissões, ativo | Permissão, StoreResolver (belongsToStore) |
| **lojas/{lojaId}/estoque_vendas** | Vendas (cliente, itens, valor) | Sync, relatórios, comissões |
| **lojas/{lojaId}/notas_fiscais** | Dados de NF (se houver CPF/endereço) | Tela de notas |
| **lojas/{lojaId}/canais** | Tokens WhatsApp, API keys (canais privados) | canais_service; apenas admin |

---

## Hive (local no dispositivo)

| Box | Dado sensível | Quem acessa |
|-----|----------------|-------------|
| **sessao** | store_id, usuario_logado (email), last_synced_loja_id | StoreResolver, LojaIdService, bootstrap, telas que precisam de loja |
| **config** | store_id, store_slug, configs gerais | Idem |
| **licenca** | currentPlanId, expiresAt, ativado, codigo (legado) | LicenseManager, PlanosService (cache) |
| **produtos_{lojaId}** | Produtos da loja (nome, preço, estoque) | Sync, PDV, estoque, catálogo offline |
| **clientes_{lojaId}** | Nome, telefone, email dos clientes | Sync, vendas, clientes_screen |
| **vendas_{lojaId}** | Vendas (cliente, itens, total) | Sync, relatórios, dashboard |

---

## Regras gerais

- **Leitura:** Só usuário autenticado da loja (ou admin/programador); catálogo público lê apenas config/produtos necessários.
- **Escrita:** Admin/programador ou vendedor com permissão; criação de cliente no catálogo com validação (tamanho, campos obrigatórios).
- **Exclusão/exportação (futuro):** Para atender LGPD, será necessário:
  - Listar todos os documentos/boxes acima que contêm dados do titular.
  - Implementar “exportar meus dados” (ler e gerar JSON/PDF) e “excluir minha conta” (apagar users, usuarios, e dados em lojas que forem do titular; limpar Hive local).

---

## Atualização

Ao criar nova coleção ou box que guarde e-mail, telefone, CPF, endereço ou token/API key, incluir neste doc.
