# Análise: Tela Marketplaces / ERP

> **Arquivos:** `lib/screens/marketplaces_screen.dart`, `lib/services/marketplace_service.dart`

---

## 1. O que a tela faz

A tela **Marketplaces / ERP** permite configurar integrações com marketplaces para:

- **TikTok Shop** – App Key, App Secret, Access Token, Shop ID
- **Mercado Livre** – Access Token, Refresh Token
- **Shopee** – Partner ID, Partner Key, Shop ID, Access Token

Funcionalidades:
- Salvar credenciais no Firestore (`lojas/<lojaId>/config/marketplaces`)
- Sincronizar produtos com cada marketplace
- Guias de ajuda para obter credenciais
- Status visual (Configurado / Não configurado)

---

## 2. Erros identificados

### 2.1 **Shopee: sincronização não implementada**
**Local:** `marketplace_service.dart` linhas 416–424

```dart
// Implementação similar ao TikTok/ML
// API Shopee requer autenticação HMAC SHA256

return {
  'success': true,
  'sincronizados': 0,
  'erros': 0,
  'message': 'Sincronização Shopee em desenvolvimento',
};
```

A sincronização Shopee retorna sempre sucesso com 0 produtos.

---

### 2.2 **TikTok Shop: assinatura de API ausente**
**Local:** `marketplace_service.dart` linhas 291–293

```dart
// Criar assinatura (simplificado - em produção usar algoritmo correto)
// final sign = _gerarAssinaturaTikTok(appSecret, timestamp, '/api/products/create', productData);
```

A assinatura não é enviada; a API TikTok exige HMAC-SHA256.

---

### 2.3 **TikTok Shop: URL da API**
**Local:** `marketplace_service.dart` linha 17

```dart
static const String _tiktokShopBaseUrl = 'https://open-api.tiktokglobalshop.com';
```

A URL pode variar por região (US, UK, etc.). Falta suporte a múltiplas regiões.

---

### 2.4 **Mercado Livre: Refresh Token não usado**
**Local:** `marketplace_service.dart`

O `refresh_token` é salvo, mas não há renovação automática do Access Token (expira em ~6h).

---

### 2.5 **Mercado Livre: Client ID e Client Secret ausentes**
**Local:** `marketplaces_screen.dart`

O fluxo OAuth do ML exige Client ID e Client Secret para trocar o `code` por tokens. A tela só pede Access Token e Refresh Token, sem campos para App ID/Secret.

---

### 2.6 **Loading global bloqueia a tela**
**Local:** `marketplaces_screen.dart` linha 169

Ao sincronizar, `_loading = true` bloqueia toda a tela. O usuário não consegue ver outras seções ou usar o app durante a sincronização.

---

### 2.7 **Falta de `mounted` em operações assíncronas**
**Local:** `marketplaces_screen.dart` – `_salvar`, `_sincronizarProdutos`

Após `await`, não há checagem de `mounted` antes de `setState` ou `ScaffoldMessenger`, o que pode gerar erros se o widget for desmontado.

---

### 2.8 **Redirect URI inconsistente**
**Local:** Guia ML – `https://app.mastepalm.com.br/callback` vs `https://mastepalm.com.br/callback`

Há divergência entre `app.mastepalm` e `mastepalm` nos guias.

---

### 2.9 **Tratamento de erros genérico**
**Local:** `marketplaces_screen.dart`

Erros são exibidos como `Erro: $e`, sem tradução ou orientação para o usuário.

---

### 2.10 **Shopee: URL da API**
**Local:** `marketplace_service.dart` linha 17

```dart
static const String _shopeeBaseUrl = 'https://partner.shopeemobile.com';
```

A Shopee usa URLs diferentes por região (BR, etc.). Pode ser necessário ajustar.

---

## 3. Melhorias sugeridas para facilitar integração

### 3.1 UX / Interface

| # | Melhoria | Descrição |
|---|----------|-----------|
| 1 | Loading por marketplace | Loading apenas no card do marketplace em sincronização, sem bloquear a tela |
| 2 | Botão "Testar conexão" | Validar credenciais antes de salvar (chamada simples à API) |
| 3 | Indicador de última sincronização | Exibir data/hora da última sincronização por marketplace |
| 4 | Log de sincronização | Mostrar detalhes (sucessos, erros, produtos afetados) |
| 5 | Confirmação antes de sincronizar | Diálogo "Sincronizar X produtos?" antes de iniciar |
| 6 | Atalho para documentação | Links diretos para docs oficiais (TikTok, ML, Shopee) |

### 3.2 Funcionalidades

| # | Melhoria | Descrição |
|---|----------|-----------|
| 7 | OAuth para Mercado Livre | Fluxo OAuth no app (Client ID/Secret + redirect) para obter tokens |
| 8 | Renovação automática de token ML | Usar Refresh Token para renovar Access Token |
| 9 | Sincronização seletiva | Opção de sincronizar apenas produtos selecionados |
| 10 | Mapeamento de categorias | Seleção de categoria do marketplace por produto |
| 11 | Configuração de região | Escolha de região (BR, US, etc.) para TikTok e Shopee |
| 12 | Webhook / notificações | Configurar webhooks para pedidos em tempo real |

### 3.3 Validações e segurança

| # | Melhoria | Descrição |
|---|----------|-----------|
| 13 | Validação de campos obrigatórios | Impedir salvar com campos vazios quando o marketplace está ativo |
| 14 | Mascarar tokens sensíveis | Exibir apenas últimos caracteres (ex.: `***xyz`) |
| 15 | Opção de ocultar/mostrar token | Toggle para mostrar/ocultar tokens |
| 16 | Validação de formato | Verificar formato de Shop ID, Partner ID, etc. |

### 3.4 Integração técnica

| # | Melhoria | Descrição |
|---|----------|-----------|
| 17 | Implementar assinatura TikTok | HMAC-SHA256 conforme documentação oficial |
| 18 | Implementar sincronização Shopee | Autenticação HMAC e chamadas reais à API |
| 19 | Retry com backoff | Nova tentativa em caso de timeout ou erro 5xx |
| 20 | Timeout configurável | Ajustar timeout por operação (ex.: 60s para sync em massa) |
| 21 | Modo sandbox | Opção de testar em ambiente de homologação |
| 22 | Exportar/importar config | Backup e restauração de credenciais (criptografado) |

### 3.5 Feedback e diagnóstico

| # | Melhoria | Descrição |
|---|----------|-----------|
| 23 | Mensagens de erro amigáveis | Traduzir erros comuns (401, 403, timeout, etc.) |
| 24 | Sugestões de correção | Ex.: "Token expirado? Gere um novo no painel do ML" |
| 25 | Status de saúde da API | Indicar se a API do marketplace está operacional |
| 26 | Histórico de sincronizações | Listar últimas execuções e resultados |

### 3.6 ERP e pedidos

| # | Melhoria | Descrição |
|---|----------|-----------|
| 27 | Seção ERP dedicada | Campos para integração com ERPs (API key, URL, etc.) |
| 28 | Importação de pedidos | Exibir pedidos vindos dos marketplaces na tela |
| 29 | Sincronização bidirecional | Atualizar status de pedido no marketplace ao enviar |
| 30 | Mapeamento de status | Configurar mapeamento de status entre app e marketplace |

---

## 4. Resumo de prioridades

### Alta (erros críticos)
1. Implementar assinatura HMAC para TikTok Shop  
2. Implementar sincronização real da Shopee  
3. Adicionar renovação automática de token do Mercado Livre  
4. Corrigir checagem de `mounted` em operações assíncronas  
5. Loading por marketplace (não bloquear a tela inteira)  

### Média (facilita integração)
6. Botão "Testar conexão" por marketplace  
7. OAuth para Mercado Livre (Client ID/Secret)  
8. Mensagens de erro amigáveis  
9. Validação de campos obrigatórios  
10. Links para documentação oficial  

### Baixa (nice to have)
11. Sincronização seletiva  
12. Mapeamento de categorias  
13. Histórico de sincronizações  
14. Modo sandbox  
15. Seção ERP dedicada  

---

## 5. Estrutura de dados atual

### Firestore
```
lojas/{lojaId}/config/marketplaces
├─ tiktok_shop: { app_key, app_secret, access_token, shop_id, ativo }
├─ mercado_livre: { access_token, refresh_token, ativo }
├─ shopee: { partner_id, partner_key, shop_id, access_token, ativo }
└─ ultima_atualizacao: ISO8601
```

### Produtos (campos adicionados após sync)
- `tiktok_product_id`, `tiktok_synced_at`
- `mercadolivre_id`, `mercadolivre_permalink`, `mercadolivre_synced_at`
- `shopee_item_id`, `shopee_synced_at` (quando implementado)

---

## 6. Referências

- [TikTok Shop API](https://partner.tiktokshop.com/doc/page/262749)
- [Mercado Livre API](https://developers.mercadolivre.com.br/pt_br)
- [Shopee Open Platform](https://open.shopee.com/documents)
- `GUIA_MARKETPLACES_ERP.md` – documentação interna
