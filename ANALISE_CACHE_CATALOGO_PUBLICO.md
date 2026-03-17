# Análise: Cache do Catálogo Público — Redução de Leituras Firestore

**Data:** 12/02/2026  
**Projeto:** MasterPalm

---

## 1. PROBLEMA ATUAL

### 1.1 Leituras por visitante

| Recurso | Atual | Leituras/visita |
|---------|-------|-----------------|
| **Config** | `configRef.snapshots()` | 1 doc + listener |
| **Config** | `paymentsRef.get()` (por update) | +1 doc |
| **Config** | `cupons.get()` (se vazio) | +N docs |
| **Produtos** | `produtos.snapshots()` | até 100 docs + listener |

### 1.2 Custo com 1000 visitantes/dia

- **Sem cache:** 1000 × (1 config + 1 payments + ~100 produtos) ≈ **102.000 leituras/dia**
- **Com snapshots:** Cada mudança notifica todos os listeners ativos
- **Problema:** Catálogo é leitura pública; mesmo dado é buscado repetidamente

---

## 2. ESTRATÉGIA DE CACHE

### 2.1 Client-side cache agressivo (TTL)

| Camada | TTL | Uso |
|--------|-----|-----|
| **Memória** | Primária | Cache em Map durante a sessão |
| **Persistência** | TTL + 1 sessão | SharedPreferences/Hive para retorno |
| **Config** | 5–10 min | Raramente muda |
| **Produtos** | 2–5 min | Estoque pode mudar com vendas |

### 2.2 Quando usar Firestore vs cache

| Situação | Ação |
|----------|------|
| Primeira visita (sem cache) | Buscar Firestore |
| Cache válido (dentro do TTL) | Servir do cache, sem Firestore |
| Cache expirado | Servir cache imediatamente + buscar Firestore em background |
| Pull-to-refresh / botão Atualizar | Forçar Firestore, ignorar TTL |
| Preview (admin) | Sem cache, sempre Firestore |

---

## 3. ARQUITETURA PROPOSTA

```
┌─────────────────────────────────────────────────────────────┐
│                    PublicCatalogScreen                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              CatalogCacheService (novo)                       │
│  • getConfigStream(lojaId)                                    │
│  • getProdutosStream(lojaId)                                  │
│  • TTL: config 5min, produtos 3min                            │
│  • forceRefresh() para atualização manual                     │
└─────────────────────────────────────────────────────────────┘
         │                                    │
         ▼                                    ▼
┌──────────────────┐                ┌──────────────────────────┐
│  Cache (memória)  │                │      Firestore           │
│  Map<lojaId,      │   cache miss   │  config, produtos        │
│   CachedData>     │◄───────────────│  get() (não snapshots)   │
└──────────────────┘                └──────────────────────────┘
```

### 3.1 Fluxo de atualização automática

1. **Emitir cache** (se válido) → UI atualiza instantaneamente
2. **Se cache expirado ou vazio:** buscar Firestore em background
3. **Ao receber do Firestore:** atualizar cache, emitir novo valor
4. **Resultado:** Dados atualizados automaticamente a cada TTL (ex.: 3–5 min)

---

## 4. OPÇÕES DE IMPLEMENTAÇÃO

### 4.1 Memória vs persistência

| Abordagem | Vantagem | Desvantagem |
|-----------|----------|-------------|
| **Só memória** | Simples, zero I/O | Perde ao fechar aba/app |
| **Memória + SharedPreferences** | Persiste entre sessões | Tamanho limitado (~5MB) |
| **Memória + Hive** | Persiste, suporta objetos grandes | Requer box dedicado |

**Recomendação:** Memória + Hive (opcional) para visitantes recorrentes.

### 4.2 CDN

- **Firestore direto:** Não há CDN; cada cliente lê do Firestore.
- **CDN possível:** Backend (Cloud Function) que lê Firestore e serve JSON com cache HTTP (ex.: Cache-Control: max-age=300). Cliente chama a Function em vez do Firestore.
- **Fase 2:** Avaliar Cloud Function + CDN para catálogos muito acessados.

---

## 5. REDUÇÃO ESTIMADA

| Cenário | Antes | Depois |
|---------|-------|--------|
| 1000 visitantes, 1 visita cada | ~102k leituras | ~102k (primeira vez) |
| 1000 visitantes, 3 páginas/ sessão | ~306k leituras | ~102k (cache na sessão) |
| 500 visitantes retornando (cache válido) | ~51k leituras | **0** (do cache) |
| **Total projetado** | ~400k/dia | **~100–150k/dia** |

---

## 6. IMPLEMENTAÇÃO

### 6.1 Serviço criado

`lib/services/catalog_cache_service.dart`:
- `getConfigStream(lojaId, preview)` — config com TTL 5 min
- `getProdutosStream(lojaId, preview)` — produtos com TTL 3 min
- `invalidate(lojaId)` — para pull-to-refresh
- `clearAll()` — ao sair do catálogo

### 6.2 Exemplo de integração em `public_catalog_screen.dart`

**Opção A: Usar cache (produção)**

```dart
// No build, substituir:
stream: _cfgStream(lojaId),

// Por:
stream: CatalogCacheService.getConfigStream(
  lojaId: lojaId,
  preview: widget.preview,
  forceRefresh: _forceRefreshConfig,
),

// E para produtos:
stream: _produtosStream(lojaId),

// Por:
stream: CatalogCacheService.getProdutosStream(
  lojaId: lojaId,
  preview: widget.preview,
  forceRefresh: _forceRefreshProdutos,
),
```

**Opção B: Pull-to-refresh**

```dart
// Ao puxar para atualizar:
void _onRefresh() {
  setState(() {
    _forceRefreshConfig = true;
    _forceRefreshProdutos = true;
  });
  CatalogCacheService.invalidate(lojaId, preview: widget.preview);
  // O StreamBuilder vai receber o novo stream com forceRefresh=true
  // Ou usar um key no StreamBuilder para forçar rebuild
}
```

**Opção C: Flag para habilitar cache (recomendado para rollout gradual)**

```dart
// No topo do State
static const bool _useCatalogCache = true; // ou vem de config

// No StreamBuilder:
stream: _useCatalogCache && !widget.preview
    ? CatalogCacheService.getConfigStream(
        lojaId: lojaId,
        preview: widget.preview,
      )
    : _cfgStream(lojaId),
```

### 6.3 Preview (admin)

O preview deve continuar usando Firestore direto (sem cache) para ver alterações em tempo real. O `CatalogCacheService` suporta `preview: true`; nesse caso o cache ainda é usado, mas com chave separada. Para preview sem cache, use `_cfgStream` e `_produtosStream` originais quando `widget.preview == true`.

---

*Documento gerado em 12/02/2026.*
