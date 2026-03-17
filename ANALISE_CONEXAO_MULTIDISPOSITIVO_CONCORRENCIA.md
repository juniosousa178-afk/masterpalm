# Análise: Conexões Instáveis, Múltiplos Dispositivos e Concorrência

**Data:** 12/02/2026

---

## 1. CENÁRIOS CONSIDERADOS

| Cenário | Impacto | Status atual |
|---------|---------|--------------|
| Conexão cai durante venda | Venda pode falhar ou ficar inconsistente | ⚠️ Parcial |
| Conexão instável (timeout) | Operações podem travar indefinidamente | ⚠️ Risco |
| 2+ dispositivos vendendo mesmo produto | Sobrevenda ou bloqueio | ✅ Transação atômica |
| Dispositivo A vende, dispositivo B não vê | Dados desatualizados | ⚠️ Listener ajuda, mas sync pós-venda pode falhar |
| 2 usuários girando roleta simultaneamente | Dois prêmios | ✅ Transação atômica |
| syncVenda falha após venda local | Venda no Hive mas não no Firestore | ✅ Retry 3x |

---

## 2. CONEXÕES INSTÁVEIS

### 2.1 O que já existe

- **Estoque/Roleta:** `runTransaction` garante atomicidade; se falhar, nada é gravado (consistente).
- **VendasService:** Se transação Firestore falhar, a venda não é registrada (sem fallback Hive).
- **TempOrderService:** usa `.timeout(Duration(seconds: 10–12))`.
- **StoreResolverService:** usa `.timeout(Duration(seconds: 5))`.

### 2.2 Lacunas (atualizado)

| Operação | Timeout? | Retry? | Offline? |
|----------|----------|--------|----------|
| EstoqueTransactionService.runTransaction | ✅ 20s | ❌ | Firestore enfileira offline |
| VendasFirestoreService.syncVenda | - | ✅ 3 tentativas | - |
| ClientesFirestoreService.syncCliente | - | ✅ 3 tentativas | - |
| ProdutosFirestoreService.syncFirestoreToHive | ❌ | ❌ | - |
| FirestoreCriticalListenerService | - | ❌ | Reconecta ao voltar |

### 2.3 Firestore offline

- **Mobile:** Firestore tem cache local; operações enfileiram e sincronizam ao reconectar.
- **Web:** Persistência não ativada por padrão; pode ser configurada explicitamente.
- **Transações:** Em offline, falham até haver conexão (comportamento correto para evitar inconsistência).

---

## 3. MÚLTIPLOS DISPOSITIVOS POR LOJA

### 3.1 Fluxo atual

1. **Dispositivo A** vende → `EstoqueTransactionService` (transação) → Hive local → `syncVenda` (Firestore).
2. **Dispositivo B** tem listener em `estoque_produtos` → ao mudar, executa `syncFirestoreToHive`.
3. **Dispositivo B** não tem listener em `estoque_vendas` → vendas novas só aparecem no próximo sync manual (ao abrir VendasScreen).

### 3.2 Lacunas

- **Vendas:** Só são sincronizadas ao abrir VendasScreen ou via listener. Não há listener em `estoque_vendas`.
- **Clientes:** Sem listener; mudanças em outro dispositivo só aparecem no próximo sync.
- **syncVenda falha:** Venda fica só no Hive do dispositivo A; outros não veem.

### 3.3 Hive por dispositivo

- Cada dispositivo tem Hive próprio.
- Sync Firestore → Hive mantém cópia local.
- Escrita é sempre Firestore (fonte da verdade) para operações críticas.

---

## 4. CONCORRÊNCIA (MESMOS DOCUMENTOS)

### 4.1 O que está protegido

| Recurso | Proteção |
|---------|----------|
| Estoque (baixa) | `runTransaction` – leitura, validação e atualização atômicas |
| Roleta (giro) | `runTransaction` – contadores e prêmio em uma transação |
| Campanhas (números) | `runTransaction` no contador |
| Cupom (código) | UUID – evita colisão |

### 4.2 Pontos de atenção

- **syncVenda:** Cria doc com ID único (Hive key ou timestamp); não há conflito de documento.
- **syncCliente:** Usa `idFirebase` ou gera UUID; ID único por cliente.
- **Listeners:** Múltiplos dispositivos = múltiplos listeners na mesma coleção; Firestore suporta (cada um recebe as mudanças).

---

## 5. RECOMENDAÇÕES PRIORITÁRIAS

### 5.1 Conexões instáveis

1. **Timeout em transações críticas** ✅
   - `EstoqueTransactionService`: `.timeout(Duration(seconds: 20))` com mensagem clara ao usuário.
2. **Retry para sync pós-venda** ✅
   - `syncVenda` e `syncCliente`: retry com 3 tentativas e backoff (500ms × tentativa) em caso de falha de rede.
3. **Feedback ao usuário**
   - Se `syncVenda` falhar, exibir aviso: "Venda registrada localmente. Será sincronizada quando a conexão voltar."

### 5.2 Múltiplos dispositivos

1. **Listener de vendas**
   - Ativar listener em `estoque_vendas` na VendasScreen para atualizar a lista em tempo real.
2. **Fila de sync pendente**
   - Manter lista de vendas com `idFirebase == null` (não sincronizadas) e tentar sync periodicamente ou ao recuperar conexão.
3. **Indicador de conectividade**
   - Mostrar offline/online para o usuário saber quando pode operar com segurança.

### 5.3 Concorrência

- Modelo atual (transações + UUID) já cobre os casos críticos.
- Manter `runTransaction` em todo fluxo que altera estoque, roleta ou contadores.

---

## 6. RISCOS RESUMIDOS

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|------------|
| Venda local sem sync Firestore | Média (rede ruim) | Alto | Retry + fila de pendentes |
| Timeout em transação sem feedback | Baixa | Médio | Timeout + mensagem clara |
| Dispositivo B com vendas desatualizadas | Média | Médio | Listener em vendas |
| Sobrevenda (estoque) | Baixa | Alto | ✅ Transação |
| Dois prêmios na roleta | Baixa | Alto | ✅ Transação |

---

*Documento gerado em 12/02/2026.*
