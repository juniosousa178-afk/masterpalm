# Análise Completa: Perfil de Clientes no Catálogo Online (Web)

## 1. Visão Geral

O perfil do cliente no catálogo web (`PerfilClienteScreenNovo`) exibe dados do cliente logado. Esta análise identifica inconsistências de sincronização e sugere melhorias.

---

## 2. Fluxo Atual

### 2.1 Autenticação e Sessão

- **Serviço:** `ClienteAuthService`
- **Coleção Firestore:** `lojas/{lojaId}/clientes/{clienteId}`
- **Documento do cliente:** ID baseado em timestamp (`{millis}_{micro}`)
- **Sessão:** SharedPreferences armazena `clienteId` e `lojaId`
- **Verificação de loja:** `getClienteAutenticado` verifica se `lojaIdSalva == lojaId` (evita mistura entre lojas)

### 2.2 Abertura do Perfil

- O perfil usa `lojaId` de: `ClienteAuthService.getLojaId()` ?? `_resolvedLojaId` ?? `widget.lojaId`
- Path lido: `lojas/{lojaId}/clientes/{clienteId}` (sempre filtrado por loja)

---

## 3. Problemas Identificados

### 3.1 CUPONS DA ROLETA NÃO APARECEM NO PERFIL (CRÍTICO)

**Onde a roleta salva:**
- `roleta_web_widget_v3.dart` → `_salvarCupomNoPerfilCliente()`
- Path: `lojas/{lojaId}/clientes_catalogo/{clienteEmail}/cupons/{codigo}`
- Documento identificado por **email** do cliente

**Onde o perfil lê:**
- `perfil_cliente_screen_novo.dart` → `dados['cupons']`
- Path: `lojas/{lojaId}/clientes/{clienteId}`
- Documento identificado por **clienteId** (timestamp)

**Conclusão:** São coleções diferentes (`clientes_catalogo` vs `clientes`). Os cupons ganhos na roleta ficam em `clientes_catalogo` e **nunca aparecem** na seção "Meus Cupons" do perfil.

---

### 3.2 NÚMEROS DA SORTE – Fonte Incompleta

**O perfil exibe números da sorte de:**
- `dados['pedidos']` no doc `clientes` (array mantido por `gerarCupomNumeroSorte` Cloud Function)
- Esses pedidos vêm de compras via **Mercado Pago / checkout web** (pre_pedidos confirmados)

**Números NÃO exibidos:**
- Participações em campanhas do app admin (`CampaignEngineService` → `campanhas_sorteio/participantes`)
- Vendas feitas no app (nova_venda_modal) que geram número via `CampaignEngineService.onVendaConcluida`
- Path: `lojas/{lojaId}/campanhas_sorteio/{campanhaId}/participantes`

**Conclusão:** Clientes que compram no app admin e participam de campanhas não veem seus números da sorte no perfil web.

---

### 3.3 PEDIDOS / COMPRAS – O Que é Exibido

**O perfil busca pedidos em:**
1. `pre_pedidos` (query por `cliente.email` ou `cliente.id`) – pedidos do checkout web
2. `dados['pedidos']` no doc `clientes` – pedidos do Mercado Pago (gerarCupomNumeroSorte)

**O que NÃO é exibido:**
- Vendas do app admin (Hive/Firestore `vendas`)
- Sincronização: `pre_pedidos` e doc `clientes` usam `lojaId` no path – isolamento OK

**Conclusão:** Apenas compras via web/checkout aparecem. Compras feitas na loja física ou pelo app admin **não** aparecem no perfil.

---

### 3.4 Isolamento por lojaId

| Componente        | Path / Query                            | Isolamento lojaId |
|-------------------|------------------------------------------|-------------------|
| Doc cliente       | `lojas/{lojaId}/clientes/{id}`           | Sim (path)        |
| Cupons roleta     | `lojas/{lojaId}/clientes_catalogo/{email}/cupons` | Sim (path) |
| pre_pedidos       | `lojas/{lojaId}/pre_pedidos`             | Sim (path)        |
| Campanhas         | `lojas/{lojaId}/campanhas_sorteio`       | Sim (path)        |

O `lojaId` vem da sessão e da URL. Risco: se o usuário mudar manualmente a URL para outra loja, o perfil pode não encontrar o cliente (IDs diferentes por loja).

---

## 4. Sugestões de Melhorias

### 4.1 Unificar Armazenamento de Cupons (Prioridade Alta)

**Problema:** Roleta salva em `clientes_catalogo`, perfil lê de `clientes`.

**Soluções possíveis:**

1. **Opção A – Roleta salvar em `clientes`:**
   - Resolver `clienteId` a partir do email (buscar em `clientes` onde `email == X`).
   - Adicionar cupom em `clientes/{clienteId}` no array `cupons`, ou migrar para subcoleção consistente.
   - Manter `clientes_catalogo` apenas para leitura temporária e deprecar no futuro.

2. **Opção B – Perfil ler também de `clientes_catalogo`:**
   - No perfil, além de `dados['cupons']`, buscar `clientes_catalogo/{email}/cupons`.
   - Mesclar cupons das duas fontes e exibir em "Meus Cupons".

3. **Opção C – Migrar tudo para uma única estrutura:**
   - Definir uma única coleção/subcoleção para cupons.
   - Migrar dados existentes e adaptar roleta, perfil e Cloud Functions.

---

### 4.2 Incluir Números da Sorte das Campanhas no Perfil

**Problema:** Números gerados pelo `CampaignEngineService` não aparecem no perfil.

**Sugestão:**
- No perfil, buscar `lojas/{lojaId}/campanhas_sorteio/{campanhaId}/participantes` onde `clienteId == clienteId` ou `email == cliente.email`.
- Exibir na seção "Números da Sorte" junto com os números vindos de `clientes.pedidos`.

---

### 4.3 Incluir Vendas do App Admin no Perfil (Opcional)

**Problema:** Vendas feitas no app (loja física ou admin) não aparecem no perfil.

**Sugestão:**
- Expor endpoint/serviço que consulte Firestore `vendas` (ou equivalente) por `clienteId` ou `cliente.email` e `lojaId`.
- Adicionar seção "Compras na Loja" no perfil, separada de "Meus Pedidos" (checkout web).

---

### 4.4 Validação Explícita de lojaId

**Sugestão:**
- Antes de carregar o perfil, validar `cliente.lojaId == lojaIdAtual` (ou equivalente).
- Se forem diferentes, exibir mensagem clara e fazer logout.
- Exemplo: "Você está na loja X. Sua conta é da loja Y. Faça login na loja correta."

---

### 4.5 Padronizar Identificação do Cliente

**Problema:** Uso misto de `clienteId` e `email` como identificador.

**Sugestão:**
- Definir um identificador canônico (ex.: email) para todas as coleções de perfil.
- Mapear `clienteId` → email onde necessário.
- Manter consistência em: `clientes`, `clientes_catalogo`, `pre_pedidos`, campanhas.

---

### 4.6 Tratamento de Cupons “Frete Grátis”

**Status atual:** Roleta pode gerar cupom "FRETE_GRATIS"; estrutura de armazenamento segue desconto.

**Sugestão:**
- Garantir que o perfil exiba claramente cupons de "Frete Grátis" vs "Desconto %".
- Validar uso de cupom no checkout conforme tipo (frete vs percentual).

---

### 4.7 Logs e Monitoramento

**Sugestão:**
- Registrar falhas de busca (cliente não encontrado, cupons vazios, erro em campanhas).
- Usar Firebase Crashlytics ou equivalente para erros no perfil.
- Criar alertas para falhas recorrentes (ex.: roleta salvando, mas perfil sem cupons).

---

## 5. Resumo de Ações Prioritárias

| # | Ação                                                | Impacto | Esforço |
|---|------------------------------------------------------|---------|---------|
| 1 | Unificar leitura de cupons (roleta + perfil)         | Alto    | Médio   |
| 2 | Incluir números da sorte das campanhas no perfil     | Alto    | Médio   |
| 3 | Validar lojaId ao abrir perfil                       | Médio   | Baixo   |
| 4 | Padronizar identificador (email vs clienteId)        | Médio   | Alto    |
| 5 | Incluir vendas do app no perfil (opcional)           | Baixo   | Alto    |

---

## 6. Estrutura de Dados Atual (Referência)

```
lojas/{lojaId}/
├── clientes/{clienteId}              ← Perfil lê daqui (login ClienteAuthService)
│   ├── nome, email, telefone
│   ├── cupons: []                    ← gerarCupomNumeroSorte, não roleta
│   └── pedidos: [{numeroSorte, data, valor, ...}]
│
├── clientes_catalogo/{email}/        ← Roleta salva cupons aqui (NÃO lido pelo perfil)
│   └── cupons/{codigo}
│
├── clientes_web/{clienteId}          ← ClienteWebService (fluxo alternativo)
│   └── cupons: []
│
├── pre_pedidos/                     ← Perfil busca pedidos aqui (cliente.email / cliente.id)
├── campanhas_sorteio/{id}/
│   └── participantes/               ← CampaignEngine (números NÃO mostrados no perfil)
└── config/roleta_sorte
```

---

*Documento gerado em: análise do catálogo web e perfil de clientes.*
