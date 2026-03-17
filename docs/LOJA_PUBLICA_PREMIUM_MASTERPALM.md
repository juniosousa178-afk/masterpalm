# Loja Pública Premium – Proposta de Evolução MasterPalm

Documento de design e priorização para evoluir a loja pública com aparência mais profissional e mini loja premium, **sem alterar regras de negócio ou núcleo transacional**.

---

# 1. VISÃO DA NOVA LOJA PÚBLICA

## Objetivo

Transformar a página pública do catálogo em uma **mini loja premium**: mais confiável, organizada e com hierarquia visual clara, priorizando **percepção de valor** e **conversão**.

## Princípios

- **Reaproveitamento**: Usar os widgets e fluxos já existentes.
- **Incremental**: Evolução por blocos, com baixo risco de regressão.
- **Dados existentes**: Usar apenas dados já presentes no Firestore/config (produtos, banners, categorias, cupons, campanhas).
- **Sem domínio próprio**: Manter o host atual (app.mastepalm.com.br/loja/xxx).

## Estado atual vs visão

| Aspecto | Estado atual | Visão premium |
|---------|--------------|---------------|
| Banner | Carrossel simples, altura fixa | Hero com overlay, transição suave, proporção 16:9 ou 2:1 |
| Identidade | Logo + nome no AppBar | Header com logo, nome, slogan opcional, selos (ex.: envio rápido) |
| Promoções | CampanhaBannerWidget abaixo do carrossel | Faixa de promoção em destaque ou bloco dedicado |
| Categorias | Chips horizontais no AppBar | Seção “Explorar por categoria” com ícones/cards |
| Produtos | Grid único | Seções: Novidades, Em promoção, Todos os produtos |
| Vistos recentemente | Lista horizontal | Mantido, com visual refinado |
| Contato | Footer com ícones | CTA WhatsApp fixo ou barra flutuante + footer |
| IA | CatalogChatWidget (flutuante) | Posição fixa (ex.: canto inferior direito), ícone mais visível |

---

# 2. BLOCOS VISUAIS RECOMENDADOS

## Hierarquia visual (de cima para baixo)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. HEADER / IDENTIDADE                                       │
│    Logo + Nome + Slogan opcional + Menu (drawer) + Carrinho  │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ 2. BANNER PRINCIPAL (HERO)                                   │
│    Carrossel de banners com overlay leve, indicadores        │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ 3. PROMOÇÕES EM DESTAQUE                                     │
│    CampanhaBannerWidget ou faixa com cupom/link ativo        │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ 4. BUSCA + FILTROS                                           │
│    Barra de pesquisa, chips de categoria                     │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ 5. CATEGORIAS EM DESTAQUE                                    │
│    Cards ou chips com ícones por categoria                   │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ 6. NOVIDADES (opcional)                                      │
│    Carrossel horizontal de produtos recentes (createdAt)     │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ 7. EM PROMOÇÃO (opcional)                                    │
│    Produtos com precoPromocional < preco                     │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ 8. VISTOS RECENTEMENTE (se houver)                           │
│    Mantém widget atual, visual refinado                      │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ 9. TODOS OS PRODUTOS                                         │
│    Grid principal + ordenação + paginação                    │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ 10. RODAPÉ                                                   │
│     Redes sociais, WhatsApp, pagamentos, links, FAQ          │
└─────────────────────────────────────────────────────────────┘

┌─────┐  CTA WhatsApp flutuante (opcional)
│ 📱  │  IA Chat flutuante (canto inferior direito)
└─────┘
```

## Detalhamento por bloco

### 1. Header / Identidade

- **Hoje**: AppBar com logo, menu, botão web, carrinho.
- **Evolução**: 
  - Logo maior e mais centralizada.
  - Nome da loja como título principal.
  - Campo opcional para slogan/frase curta (se houver no config).
  - Manter drawer e carrinho.
- **Dados**: `cfg['loja_nome']`, `cfg['logo']`, `cfg['slogan']` (novo campo opcional).
- **Risco**: Baixo – apenas layout e espaçamento.

### 2. Banner principal (Hero)

- **Hoje**: `CatalogBannerCarousel` com altura fixa.
- **Evolução**:
  - Desktop: altura ~40% viewport (como hoje).
  - Bordas arredondadas e sombra leve.
  - Gradiente overlay sutil no rodapé para legibilidade.
  - Indicadores de página mais visíveis.
- **Dados**: `cfg['banners']` ou `cfg['media']['banners']`.
- **Risco**: Baixo.

### 3. Promoções em destaque

- **Hoje**: `CampanhaBannerWidget` abaixo do carrossel.
- **Evolução**:
  - Card com borda colorida ou badge “Oferta”.
  - Se não houver campanha: faixa com cupom ativo na URL (quando houver `?cupom=`).
- **Dados**: Campanhas Firestore, cupons do config, query param `cupom`.
- **Risco**: Baixo.

### 4. Busca + filtros

- **Hoje**: `CatalogSearchBar` + `CatalogCategorySubcategoryFilters`.
- **Evolução**:
  - Barra de busca com placeholder mais direto.
  - Chips de categoria com estilo de “pill” ou cards pequenos.
- **Dados**: produtos (categorias extraídas).
- **Risco**: Baixo – apenas visual.

### 5. Categorias em destaque

- **Hoje**: Chips dentro do AppBar.
- **Evolução**:
  - Seção própria “Explorar por categoria” com cards ou chips maiores.
  - Ícone genérico por categoria (ou primeira letra) se não houver ícone no config.
- **Dados**: categorias extraídas dos produtos (sem persistência nova).
- **Risco**: Baixo.

### 6. Novidades (opcional)

- **Dados**: Produtos ordenados por `createdAt` ou `criadoEm` (se existir).
- **Evolução**: Carrossel horizontal, similar a “Vistos recentemente”.
- **Risco**: Baixo se os campos existirem; médio se forem inexistentes (omitir).

### 7. Em promoção (opcional)

- **Dados**: Produtos com `precoPromocional` < `preco`.
- **Evolução**: Carrossel ou grid compacto “Ofertas”.
- **Risco**: Baixo – apenas filtro nos produtos já carregados.

### 8. Vistos recentemente

- **Hoje**: `buildCatalogRecentSectionSliver`.
- **Evolução**: Mesmo bloco com espaçamento e tipografia ajustados.
- **Risco**: Baixo.

### 9. Todos os produtos

- **Hoje**: `CatalogSortFiltersSection` + grid + paginação.
- **Evolução**: Manter lógica, ajustar espaçamento e hierarquia visual.
- **Risco**: Baixo.

### 10. Rodapé

- **Hoje**: `CatalogFooter` completo.
- **Evolução**: Manter estrutura, refinando espaçamento e contraste.
- **Risco**: Baixo.

### CTA WhatsApp + IA

- **CTA WhatsApp**: Barra ou botão flutuante “Fale conosco” com `whatsappUrl`.
- **IA**: `CatalogChatWidget` em posição fixa, canto inferior direito, ícone mais evidente.
- **Risco**: Baixo – posicionamento e estilo.

---

# 3. PRIORIDADE DE IMPLEMENTAÇÃO

## Fase 1 – Baixo risco (1–2 dias)

| # | Bloco | Descrição | Impacto |
|---|-------|-----------|---------|
| 1 | Banner Hero | Overlay sutil, indicadores, bordas | Percepção premium |
| 2 | Header identidade | Espaçamento, hierarquia | Confiança |
| 3 | Promoções em destaque | Visual do CampanhaBannerWidget | Conversão |
| 4 | Categorias em destaque | Nova seção “Explorar por categoria” | Navegação |
| 5 | IA + CTA | Posição fixa e ícone do chat | Suporte e conversão |

## Fase 2 – ✅ Implementada (03/2025)

| # | Bloco | Descrição | Status |
|---|-------|-----------|--------|
| 6 | Novidades | Carrossel de produtos recentes | Usa `dataCriacao` (createdAt/criadoEm/dataCadastro). Seção não exibe se nenhum produto tiver data |
| 7 | Em promoção | Carrossel de produtos em promoção | Usa `emPromocao == true` (campo já processado em _processDocsToProducts) |
| 8 | Mais vendidos | — | Não implementado: sem campo `quantidadeVendida` nos produtos do catálogo público |

## Fase 3 – Refinamentos (1 dia)

| # | Bloco | Descrição |
|---|-------|-----------|
| 9 | Busca e filtros | Estilo “pill”, consistência |
| 10 | Rodapé | Espaçamento e contraste |
| 11 | Grid de produtos | Espaçamento e cards |

---

# 4. RISCOS E CUIDADOS

## Não fazer

- Alterar regras de negócio (checkout, pre-pedido, auth).
- Criar novas collections ou persistência.
- Mexer em vendas, estoque, sync, auth, Store Resolver.
- Implementar domínio próprio nesta etapa.
- Alterar assinaturas de funções críticas (ex.: `_addToCart`, `_openCartSheet`).

## Dependências de dados

| Bloco | Campo usado | Fallback |
|-------|-------------|----------|
| Novidades | `createdAt`, `criadoEm`, `dataCadastro` | Omitir se não existir |
| Em promoção | `precoPromocional` | Omitir se não houver produtos em promoção |
| Slogan | `cfg['slogan']` | Omitir |

## Performance

- Novas seções (Novidades, Em promoção) usam a mesma lista de produtos do Firestore.
- Evitar novas queries; filtrar/ordenar em memória.
- Manter cache existente (`_useCatalogCache`).

## Responsividade

- Mobile: manter layout atual, ajustar espaçamentos.
- Desktop: explorar mais colunas nos carrosséis (ex.: 4–5 itens visíveis).

## Rollback

- Cada fase pode ser entregue em PR separado.
- Feature flag `catalog_premium_layout` (config Firestore): quando `true`, aplica layout premium. Default `false` mantém layout original.

### Como ativar o layout premium (Fase 1)

No Firestore, em `lojas/{lojaId}/config` (ou onde o config do catálogo é armazenado), adicione:
```json
{ "catalog_premium_layout": true }
```
Opcional para slogan:
```json
{ "slogan": "Sua frase de destaque aqui" }
```

---

# 5. DOCUMENTAÇÃO CRIADA

**Arquivo:** `docs/LOJA_PUBLICA_PREMIUM_MASTERPALM.md`

**Conteúdo:**
1. Visão da nova loja pública
2. Blocos visuais recomendados (com hierarquia)
3. Prioridade de implementação (3 fases)
4. Riscos e cuidados

---

*Proposta baseada na análise do `public_catalog_screen.dart` e widgets de `lib/screens/public_catalog/`. Sem alterações de código aplicadas.*
