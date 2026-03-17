# Correções prioritárias aplicadas
**Data:** 06/03/2025 | **Projeto:** MasterPalm | **Versão:** 1.0.28+38

---

## 1. Diagnóstico curto dos pontos encontrados

### P1 — Root /pedidos
- **order_review_screen.dart:** Gravava em root `/pedidos`, que exige `isAdminOrSystem()` — cliente/vendedor recebia permission denied; erro era engolido em `catch (_) {}`.
- **temp_order_service.dart:** Quando `lojaId` era null, gravava em root `/pedidos` — mesmo problema.

### P2 — Fallback 'padrao'
- **Telas com fallback perigoso:** contas_receber, fornecedor, historico_clientes, notas_fiscais, admin_painel_web, relatorio_ranking_clientes.
- **Uso legítimo preservado:** tipoEmbalagem, tipo frete, embalagens, modelo Cliente/Fornecedor default, scripts.

### P3 — Domínio público
- **Referências incorretas:** `masterpalm.com.br`, `masterpalm.com` em URLs e domínio base de subdomínios.
- **AndroidManifest:** Já usava `mastepalm.com.br` — não foi alterado.
- **projectId Firebase:** `masterpalm-58c46` — não foi alterado.

---

## 2. Lista exata de arquivos impactados

### P1 — Root /pedidos
- `lib/screens/order_review_screen.dart`
- `lib/services/temp_order_service.dart`

### P2 — Fallback 'padrao'
- `lib/screens/contas_receber_screen.dart`
- `lib/screens/fornecedor_screen.dart`
- `lib/screens/notas_fiscais_screen.dart`
- `lib/screens/historico_clientes_screen.dart`
- `lib/screens/relatorio_ranking_clientes_screen.dart`
- `lib/screens/admin_painel_web_screen.dart`

### P3 — Domínio
- `lib/screens/loja_config_screen.dart`
- `lib/services/superfrete_service.dart`
- `lib/services/frete_service.dart`
- `lib/screens/fretes_cupons_screen.dart`
- `functions/index.js`
- `site/PUBLICAR.md`

---

## 3. Código das alterações (resumo)

### P1
- **order_review_screen:** Grava em `lojas/{lojaId}/pedidos` quando `lojaId` disponível; log estruturado em erro; não grava se `lojaId` null.
- **temp_order_service:** Remove fallback para root `/pedidos` quando `lojaId` é null; grava apenas em `lojas/{lojaId}/pedidos` quando `lojaId` preenchido.

### P2
- Todas as telas citadas passam a usar `LojaIdService.getWithTimeout()`.
- Quando null, exibem tela de erro com botão "Tentar novamente".
- Lógica de `_lojaMatch` em fornecedor_screen: legado com lojaId vazio passa a aparecer no contexto atual (`f.lojaId.isEmpty || f.lojaId == lojaId`).
- **relatorio_ranking_clientes:** Usa `LojaIdService.getWithTimeout` e `normalizeFromBox` quando `widget.lojaId` vazio.

### P3
- `masterpalm.com` → `mastepalm.com.br` em domínio base de subdomínios (loja_config_screen).
- `contato@masterpalm.com.br` → `contato@mastepalm.com.br` em User-Agent e contatos.
- `suporte@masterpalm.com.br` → `suporte@mastepalm.com.br` em docs.
- `www.masterpalm.com.br` → `www.mastepalm.com.br` em docs.

---

## 4. Como foi mantida compatibilidade

- **Root /pedidos:** Coleção raiz não foi removida; apenas deixou de ser usada por ordem de cliente/vendedor. Dados antigos continuam acessíveis por admin.
- **lojas/{lojaId}/pedidos:** Fluxo já existente; OrderReview e TempOrder passam a usar essa coleção quando há `lojaId`.
- **'padrao':** Uso legítimo (tipoEmbalagem, embalagens, modelo Cliente/Fornecedor) mantido; apenas fallback de loja substituído por erro explícito.
- **Hive legado:** Clientes/fornecedores com `lojaId` vazio seguem aparecendo no contexto atual (compatível com dados antigos).
- **Domínio:** Só URLs públicas e domínio base foram alteradas; `projectId`, AndroidManifest e e-mails de auth (ex.: masterpalm@gmail.com) preservados.

---

## 5. Checklist de testes manuais

### P1 — Pedidos
- [ ] Checkout via link (OrderReviewScreen) com lojaId definido → pedido gravado em `lojas/{lojaId}/pedidos`.
- [ ] Checkout com lojaId null → fluxo segue; não tenta gravar em root.
- [ ] TempOrderService.concluir com lojaId → grava em `lojas/{lojaId}/pedidos`.
- [ ] TempOrderService.concluir sem lojaId → remove temp; não grava em root.

### P2 — Fallback 'padrao'
- [ ] Contas a receber: loja ok → carrega; falha → tela de erro + retry.
- [ ] Fornecedores: idem.
- [ ] Notas fiscais: idem.
- [ ] Histórico clientes: idem.
- [ ] Admin painel web: loja ok → carrega; falha → vendas vazias, sem crash.
- [ ] Relatório ranking clientes: loja ok → carrega; falha → loading para e sai sem dados.
- [ ] tipoEmbalagem 'padrao', embalagens 'padrao' → continuam funcionando.

### P3 — Domínio
- [ ] Config loja: domínio base padrão `mastepalm.com.br`.
- [ ] User-Agent em fretes (SuperFrete, Melhor Envio) → contato@mastepalm.com.br.
- [ ] Deep links e App Links → sem alteração (já usavam mastepalm.com.br).

---

## 6. O que ainda deve esperar para ETAPAS 4–6

- **ETAPA 4 (Unificação fluxos de pedido):** Não foi feita unificação de coleções; apenas ajustes pontuais. Criar camada unificada (ex.: PedidoRepository) ficará para depois.
- **ETAPA 5 (Regras Firestore):** Regras não foram alteradas. Revisão de `pedidos_pendentes` (update amplo) e padronização entre coleções permanecem como pendências.
- **ETAPA 6 (Validação):** Validar fluxos completos (checkout, sync, Hive, Firestore) com as novas gravações em `lojas/{lojaId}/pedidos`.

### Telas ainda com fallback 'padrao' (menor prioridade)
- historico_movimentacao_estoque_screen
- carrinhos_abandonados_screen
- loja_config_screen (usando 'padrao' para lojaConfig quando _slug e _lojaId null)
- estoque_screen (passando lojaId ?? 'padrao' para HistoricoMovimentacaoEstoqueScreen)
- produto_form_screen (id ?? 'padrao' para HiveBoxNames.produtos)

### Não alterado
- E-mails de auth (masterpalm26@gmail.com, masterpalm@gmail.com, admin@masterpalm.com)
- projectId Firebase (masterpalm-58c46)
- AndroidManifest (já correto com mastepalm.com.br)
- Models Cliente/Fornecedor (default lojaId = 'padrao' para compatibilidade com Hive)
