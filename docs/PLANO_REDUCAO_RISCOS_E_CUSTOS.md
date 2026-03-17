# Plano de redução de riscos e custos (MasterPalm)

Objetivo: reduzir manutenção, custo Firebase, dívida técnica e problemas futuros **sem quebrar o que já funciona** e **sem remover telas**.

> **Melhorias concretas (código gigante, testes, arquitetura, custo):** ver **[PLANO_MELHORIAS_SEM_QUEBRAR.md](./PLANO_MELHORIAS_SEM_QUEBRAR.md)** — passos incrementais para main/loja_config, testes, unificar loja e limits Firestore.

---

## 1. Manutenção e bugs (risco alto)

### 1.1 Testes automatizados – incremental

**O que fazer:** Adicionar testes só para código novo ou para funções que você for mexer.

- **Regra:** Ao criar um novo serviço ou função crítica (ex.: novo cálculo de comissão), escrever 1 arquivo `test/nome_servico_test.dart` com 3–5 casos básicos (valor válido, null, edge case).
- **Onde priorizar (sem refatorar):**
  - Serviços que fazem contas ou validações puras (ex.: limites de plano, formatação de valor).
  - StoreAccessGuard e validações de loja já têm teste; manter ao alterar.
- **Não fazer:** Reescrever o app para “testar tudo”. Foco em **novo código** e **pontos que você toca**.

**Benefício:** Menos regressão ao mudar código; confiança ao fazer deploy.

### 1.2 Documentar “pontos sensíveis”

**O que fazer:** Um único arquivo listando onde não mexer sem cuidado.

- Criar `docs/PONTOS_SENSIVEIS.md` (ou seção no README) com:
  - Telas/serviços que abrem muitas boxes Hive ou fazem sync (ex.: `CatalogoVendaService`, `FullSyncService`, `SyncQueueService`).
  - Onde o `lojaId` é resolvido (StoreResolver, LojaIdService, sessão) para evitar duplicar lógica.
  - Lista curta de “ao alterar X, verificar Y”.
- Atualizar o arquivo quando descobrir um bug “mexi aqui e quebrou ali”.

**Benefício:** Menos quebra por mudança em lugar errado; onboarding mais rápido.

### 1.3 Checklist antes de release

**O que fazer:** Checklist mínimo antes de publicar nova versão (não exige código).

- Exemplo: “Login OK? Sync após login OK? Trocar de loja (se aplicável) OK? Catálogo público abre? Uma venda de teste conclui?”
- Manter em `docs/CHECKLIST_RELEASE.md` ou no próprio processo de build.

**Benefício:** Menos bugs escapando para produção.

---

## 2. Custo e escala Firebase (risco alto)

### 2.1 Monitorar uso (zero mudança de comportamento)

**O que fazer:** Acompanhar no Console e, se quiser, alertas.

- **Firebase Console:** Uso de Firestore (leituras/escritas), Storage, Auth.
- **Orçamento/alertas:** Google Cloud Console → Billing → Budgets & alerts (ex.: alerta se passar R$ X no mês).
- **Documentar:** Em `docs/CUSTO_FIREBASE.md` anotar “onde” o app mais lê (ex.: catálogo, lista de vendas, config da loja) para decidir onde otimizar depois.

**Benefício:** Ver subida de custo antes de virar problema; base para otimizações.

### 2.2 Cache e leituras – só onde já existe Hive

**O que fazer:** Reduzir leituras repetidas ao Firestore **usando o que o app já faz** (Hive/cache em memória).

- **Regra:** Antes de fazer `get()` ou `snapshots()` em documento que muda pouco (ex.: config da loja, plano do usuário), verificar:
  - Já temos em Hive? Usar e, se fizer sentido, atualizar em background (uma leitura) em vez de listener 24/7.
- **Exemplo seguro:** Tela que hoje faz `get()` toda vez que abre: na primeira abertura do dia, buscar do Firestore e gravar em Hive; nas próximas aberturas usar Hive e, opcionalmente, refresh em background com TTL (ex.: 5–15 min).
- **Não fazer:** Remover listeners onde a tela precisa de tempo real (ex.: fila de pedidos). Só aplicar em dados “quase estáticos”.

**Benefício:** Menos leituras = menor custo sem tirar funcionalidade.

### 2.3 Paginação e limite de listas

**O que fazer:** Onde já existe `.limit(N)`, revisar se N é razoável; onde não existe, adicionar em listas grandes.

- Firestore: em listas (produtos, vendas, clientes) usar `.limit(50)` ou `.limit(100)` e “carregar mais” ao rolar. Muitas telas já usam limite; garantir que nenhuma lista “infinite” faça `get()` sem limit.
- Não remover telas: só limitar quantidade de documentos por query e manter “carregar mais” ou paginação.

**Benefício:** Custo previsível mesmo com muitas lojas/produtos.

### 2.4 Storage – tamanho e tipo de arquivo

**O que fazer:** Garantir que uploads (fotos de produtos, etc.) tenham tamanho máximo e, se possível, compressão.

- Validar tamanho no app antes de subir (ex.: máx. 2–5 MB por imagem) e comprimir imagem no cliente se a lib já permitir.
- Não remover telas de upload; só evitar arquivos gigantes.

**Benefício:** Menor custo de Storage e banda.

---

## 3. Dívida técnica (risco médio)

### 3.1 Unificar “resolver loja” – só por encapsulamento

**O que fazer:** Não reescrever tudo; criar uma única função “fonte da verdade” e fazer o resto chamar ela.

- Manter `StoreResolverService` (ou o que for o principal hoje) como **único** lugar que resolve `lojaId` para o usuário logado.
- Nos pontos que hoje leem sessão/config/Firestore direto para “pegar loja”, trocar por uma chamada a esse serviço (ex.: `StoreResolverService.resolve()`). Fazer por etapas: um arquivo por vez, testando login e uma tela que depende de loja.
- Não remover telas nem fluxos; só trocar **de onde** vem o `lojaId`.

**Benefício:** Um lugar para corrigir bugs de “loja errada”; menos caminhos diferentes.

### 3.2 Licença legada vs plano novo

**O que fazer:** Tratar como “dois caminhos” documentados, sem apagar o legado por enquanto.

- Em `docs/PLANOS_E_LICENCA.md` descrever:
  - Plano novo: Firestore `users/{uid}`, `subscriptions`, PlanosService.
  - Legado: Hive `licenca` (codigo + deviceId), LicenseManager.
  - Que o app usa os dois e em que ordem (já é o que `hasValidAccessFallbackLegacy` faz).
- Quando for mexer em tela de “licença” ou “plano”, consultar esse doc. Remover legado só quando não houver mais ninguém usando (ex.: após migração em produção).

**Benefício:** Menos confusão ao alterar; decisão consciente quando desligar o legado.

### 3.3 Módulos “lógicos” sem mudar estrutura de pastas

**O que fazer:** Agrupar por “feature” só no papel e nos imports, sem refatoração pesada.

- Exemplo: “Tudo que é catálogo público” (telas, serviços, widgets) listar em um doc ou comentário no topo da pasta; ao criar coisa nova de catálogo, colocar junto.
- Opcional: prefixar arquivos (ex.: `catalogo_*.dart`) para achar rápido. Não é obrigatório quebrar o app em pacotes; só organização e convenção.

**Benefício:** Encontrar código mais rápido; menos “onde isso está?”.

---

## 4. Regulatório / fiscal (risco médio)

### 4.1 Documentar o que é guardado e onde

**O que fazer:** Um doc interno descrevendo dados sensíveis.

- Em `docs/DADOS_SENSIVEIS.md` listar:
  - Onde ficam CPF/CNPJ, e-mail, telefone (Firestore, Hive, qual coleção/box).
  - Onde ficam dados de nota fiscal e vendas.
  - Que telas/serviços acessam isso.
- Não mudar comportamento; só documentar para LGPD e auditoria.

**Benefício:** Base para política de privacidade e para responder a pedidos de exclusão/relatório.

### 4.2 Retenção e exclusão (futuro)

**O que fazer:** Quando for implementar “excluir conta” ou “exportar dados”, usar o doc acima.

- Ter uma lista de “o que apagar/exportar” (Firestore paths, Hive boxes) evita esquecer algo. Pode ser uma função única que chama delete/export em cada lugar.
- Não é obrigatório implementar já; só deixar o mapa pronto.

**Benefício:** Menos risco na hora de atender LGPD ou auditoria fiscal.

---

## 5. Atualizações Flutter / Firebase (risco médio)

### 5.1 Versões fixadas e upgrade path

**O que fazer:** Manter dependências com versão fixa (já costuma estar no pubspec) e anotar o “caminho” de upgrade.

- No `pubspec.yaml` usar ranges conservadores (ex.: `firebase_core: ^2.x` em vez de `any`) e testar em branch antes de subir de major.
- Em `docs/UPGRADE_DEPENDENCIES.md` (ou seção em COMANDOS.md):
  - “Ao atualizar Flutter: rodar `flutter pub get`, `flutter analyze`, testes, e checar changelog do Firebase.”
  - Lista de pacotes críticos: Flutter SDK, firebase_core, cloud_firestore, hive.

**Benefício:** Atualizações menos surpresa; menos “quebrou depois do upgrade”.

### 5.2 Revisão periódica (ex.: a cada 6 meses)

**O que fazer:** A cada 6 meses (ou antes de cada release grande), rodar:

- `flutter pub outdated` e decidir o que atualizar.
- Ler resumo de breaking changes do Firebase (blog/changelog) dos últimos meses.
- Atualizar o doc de upgrade com qualquer descoberta.

**Benefício:** Dívida de versão não acumula de uma vez.

---

## 6. Segurança (risco baixo – manter)

**O que fazer:** Não relaxar o que já está bom.

- Manter App Check habilitado; manter regras de Firestore e validação de loja (StoreAccessGuard).
- Ao adicionar nova API ou coleção, já criar regra e, se for sensível, exigir auth/App Check.
- Não commitar chaves ou secrets; usar Remote Config / environment para coisas sensíveis (já é o caso da API Globo Sorte).

**Benefício:** Risco de segurança continua baixo.

---

## Ordem sugerida (sem quebrar nada)

| Ordem | Ação | Esforço | Impacto |
|-------|------|---------|---------|
| 1 | Criar `docs/PONTOS_SENSIVEIS.md` e preencher com 5–10 itens | Baixo | Alto (evita quebra) |
| 2 | Configurar alerta de custo no Google Cloud (Budget) | Baixo | Alto (evita surpresa) |
| 3 | Documentar em `docs/CUSTO_FIREBASE.md` onde o app mais lê | Baixo | Médio |
| 4 | Revisar listas Firestore sem `.limit()` e adicionar limit + “carregar mais” onde fizer sentido | Médio | Alto (custo) |
| 5 | Unificar “resolver loja” em um único serviço (migração gradual) | Médio | Alto (manutenção) |
| 6 | Criar `docs/PLANOS_E_LICENCA.md` e `docs/DADOS_SENSIVEIS.md` | Baixo | Médio |
| 7 | Adicionar testes só para código novo ou ao mexer em função crítica | Contínuo | Alto (regressão) |
| 8 | Criar `docs/CHECKLIST_RELEASE.md` e usar antes de publicar | Baixo | Médio |
| 9 | Doc `docs/UPGRADE_DEPENDENCIES.md` e revisão periódica | Baixo | Médio |

**Status atual:** Itens 1, 3, 6, 8 e 9 feitos. Item 2: instruções em CUSTO_FIREBASE.md. Item 4 em andamento (ex.: CampaignEngine listarParticipacoes com limit 100). Itens 5 e 7 pendentes/contínuos.

---

## Resumo

- **Manutenção/bugs:** testes incrementais, doc de pontos sensíveis, checklist de release.
- **Custo Firebase:** monitorar uso, cache onde já existe Hive, limit em listas, controle de tamanho de upload.
- **Dívida técnica:** unificar resolução de loja por encapsulamento, documentar plano vs licença legada, organização por feature no papel.
- **Regulatório:** documentar onde estão dados sensíveis; deixar pronto para exclusão/exportação futura.
- **Atualizações:** versões controladas, doc de upgrade, revisão periódica.
- **Segurança:** manter App Check, regras e boas práticas atuais.

Tudo isso pode ser feito **sem remover telas** e **sem refatorar tudo de uma vez**; cada item reduz risco ou custo de forma incremental.
