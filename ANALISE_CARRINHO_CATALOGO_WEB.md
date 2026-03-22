# 🔍 ANÁLISE CIRÚRGICA DO CARRINHO DO CATÁLOGO WEB

**Data:** 21/03/2025  
**Escopo:** `CarrinhoSheetWeb`, `PublicCatalogScreen`, fluxo completo de checkout  
**Classificação:** Crítico | Alto | Médio | Baixo | Silencioso

---

## 📋 ÍNDICE

1. [Dados do Cliente](#1-dados-do-cliente)
2. [Frete](#2-frete)
3. [Pagamento](#3-pagamento)
4. [Cupons](#4-cupons)
5. [Erros Gerais e Silenciosos](#5-erros-gerais-e-silenciosos)

---

## 1. DADOS DO CLIENTE

### 🔴 CRÍTICO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 1.1 | **Validação de endereço mesmo em retirada** | `carrinho_sheet_web.dart` ~724 | `_validarCampos()` exige CEP, rua, número, bairro, cidade e estado **sempre**. Porém, `_verificarDadosCompletos()` (roleta) considera `tipoFrete == 'retirada'` e **não exige** endereço. Há **inconsistência**: usuário que escolhe "Retirada" **não pode finalizar** porque a validação continua exigindo endereço completo. |

### 🟠 ALTO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 1.2 | **CPF sem validação de dígitos verificadores** | `_validarCampos()` ~729 | Valida apenas `cpf.length == 11`. CPFs inválidos como `11111111111` ou `12345678901` passam. Dados incorretos podem ir para NF-e ou gateways. |
| 1.3 | **Email opcional mas sem validação de formato** | `_centerForm` ~2149 | Campo marcado "(opcional)", mas quando preenchido **não valida** formato. `abc`, `@.com` ou `email@` passam. Gateways e integrações podem falhar silenciosamente. |
| 1.4 | **Persistência do formulário não aguarda save** | `onFormDataToSave` ~1706 | `SharedPreferences.getInstance().then(...)` é assíncrono e **não é aguardado**. Se o usuário fechar o app/sheet rapidamente, os dados podem **nunca ser salvos**. |

### 🟡 MÉDIO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 1.5 | **initialFormData com cast perigoso** | `public_catalog_screen.dart` ~1683 | `jsonDecode(json) as Map` pode lançar se JSON estiver corrompido. O `catch (_)` engole o erro — perda silenciosa de dados salvos. |
| 1.6 | **freteIndex em initialFormData com cast int** | `carrinho_sheet_web.dart` ~312 | `(init['freteIndex'] as int?) ?? 0` — se salvo como `double` ou `String` no JSON, o cast **lança** e o initState pode quebrar. |
| 1.7 | **Campo CPF com teclado decimal** | `_centerForm` ~2133 | `keyboardType: kKeyboardDecimal` — CPF deveria usar `TextInputType.number` ou máscara específica. Pode permitir vírgula/ponto. |

### 🔵 BAIXO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 1.8 | **Nome sem validação de comprimento mínimo** | `_validarCampos()` | Aceita nomes de 1 ou 2 caracteres. Integrações podem rejeitar. |
| 1.9 | **Telefone aceita 10 dígitos sem DDD** | `_validarCampos()` ~747 | `tel.length < 10` — aceita 10 dígitos. Celulares brasileiros têm 11 (DDD + 9 + 8 dígitos). Pode gerar números inválidos. |

### ⚪ SILENCIOSO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 1.10 | **ViaCEP: corpo da resposta pode não ser JSON** | `_buscarEnderecoPorCep` ~1718 | `jsonDecode(response.body)` pode lançar se a API retornar HTML de erro. O catch mostra "Verifique sua conexão" genérico, mascarando erro de parsing. |
| 1.11 | **dispose salva formData mesmo em pop forçado** | `dispose()` ~574 | `onFormDataToSave?.call(_getFormDataMap())` — se o usuário fechar durante um loading, pode salvar dados **parciais/inconsistentes** e sobrescrever o estado anterior. |

---

## 2. FRETE

### 🔴 CRÍTICO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 2.1 | **Carrinho mostra "Nenhuma opção de frete" se fretes vazios** | `build()` ~856 | Se `_fretesLocal` estiver vazio, retorna `Center(child: Text('Nenhuma opção...'))` e **oculta todo o formulário**. Usuário não consegue preencher dados nem ver itens. Deveria exibir pelo menos os fretes manuais iniciais (widget.fretes). |
| 2.2 | **_recalcularFreteSelecionado SUBSTITUI fretes iniciais** | `_recalcularFreteSelecionado` ~1561 | Ao calcular frete, `_fretesLocal.clear()` e só adiciona `opcoesFretes` do FreteService. Se a API falhar ou retornar vazio, `opcoesFretes` pode estar vazio e o usuário **perde** as opções manuais (Retirada, Entrega local) que vieram em `widget.fretes`. O FreteService inclui manuais via config, mas se config/fretes da loja estiver mal configurado, o fallback pode não ter "Retirada". |

### 🟠 ALTO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 2.3 | **Embalagens em Hive box global (config)** | `_calcularPesoComEmbalagem` ~1057 | `Hive.openBox('config')` e `configBox.get('embalagens')` — box `config` é **global**, não por loja. Em ambiente web com múltiplas lojas (IndexedDB compartilhado), embalagens de uma loja podem afetar outra. |
| 2.4 | **Produto sem peso = 0 → frete subestimado** | `_calcularPesoComEmbalagem` ~1154 | `(item['peso'] as num?)?.toDouble() ?? 0.0` — produtos sem `peso` usam 0. Cálculo de frete fica **incorreto** (apenas embalagem). Transportadora pode cobrar diferença ou recusar. |
| 2.5 | **Índice de frete salvo pode ficar inválido** | `initState` ~314 | `savedFrete` vem de `initialFormData`; após `_recalcularFreteSelecionado`, a lista muda. O `_freteIndex` salvo pode apontar para outra opção (ex: era "Retirada", agora é "PAC"). Comportamento confuso. |

### 🟡 MÉDIO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 2.6 | **Typo na exibição do prazo** | `_right` ~2561 | `'$precoTexto${prazo.isNotEmpty ? ' ? $prazo' : ''}'` — deveria ser `' - $prazo'` ou similar. O `?` parece erro de digitação. |
| 2.7 | **Fretes zerados de API são ignorados** | `_recalcularFreteSelecionado` ~1626 | Fretes com valor 0 de APIs são `continue` (pulados). Algumas transportadoras retornam "Grátis" com valor 0 — seriam ocultados. |
| 2.8 | **Erro ao calcular frete mostra "valor padrão"** | `_recalcularFreteSelecionado` ~1680 | `widget.showSnack('Erro ao calcular frete. Usando valor padrão.')` — mas **não aplica** valor padrão explícito. `_fretesLocal` pode continuar com lista antiga ou vazia. |

### ⚪ SILENCIOSO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 2.9 | **firstWhere em embalagens pode lançar** | `_calcularPesoComEmbalagem` ~1162 | `embalagens.firstWhere(..., orElse: () => embalagens.first)` — se `embalagens` estiver vazio, `embalagens.first` lança. Há fallback para `embalagemMaior` depois, mas a lista pode ser vazia em edge cases. |
| 2.10 | **Logs excessivos em produção** | Vários | `logD` e `logW` disparam em todo fluxo de frete. Em produção, poluem console e podem expor dados (CEP, valores). |

---

## 3. PAGAMENTO

### 🔴 CRÍTICO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 3.1 | **showPixQrDialog não definido (analyzer)** | `public_catalog_screen.dart` ~1806, ~2432 | Relatórios de análise (`analyze_result.txt`, `RELATORIO_ERROS_CATALOGO_PUBLICO.md`) indicam: *"The method 'showPixQrDialog' isn't defined for the type '_PublicCatalogScreenState'"*. O import de `pix_qr_dialog.dart` existe (linha 34); `showPixQrDialog` é função top-level. Pode ser falso positivo do analyzer ou problema de escopo. **Verificar se o PIX abre o dialog em runtime.** |
| 3.2 | **mostrarModalSelecionarCupom não definido (analyzer)** | `carrinho_sheet_web.dart` ~2740 | *"The method 'mostrarModalSelecionarCupom' isn't defined for the type '_CarrinhoSheetWebState'"*. A função está em `selecionar_cupom_modal.dart` e o arquivo é importado. A chamada deveria ser `mostrarModalSelecionarCupom(...)` como função top-level. **Verificar se o botão "Selecionar cupom" funciona.** |

### 🟠 ALTO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 3.3 | **Produto sem preço = R$ 0,00** | `_subtotal` ~212 | `(e['preco'] as num?)?.toDouble() ?? 0.0` — item sem `preco` entra como grátis. Possível **venda sem cobrança** se dado estiver incorreto no catálogo. |
| 3.4 | **LoginScreenCliente sem context verificado** | Vários `Navigator.push` ~3062 | `Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreenCliente(lojaId: widget.lojaId)))` — em alguns fluxos, `context` pode estar desmontado. O `if (!context.mounted) return` existe antes em alguns, mas após `Navigator.pop` o push usa `context` que pode estar obsoleto. |
| 3.5 | **Cupom não repassado no checkout PIX** | `onCheckoutPix` ~1784 | O callback PIX usa `cupomCodigo: null` e `desconto: 0.0` ao chamar `CatalogoVendaService.registrarVendaCatalogo`. O cupom aplicado no carrinho (`_cupomAplicado`) **não é enviado** — desconto é ignorado no fluxo PIX. |

### 🟡 MÉDIO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 3.6 | **Dropdown de pagamento sem Boleto** | `_right` ~2638 | Opções: PIX, Cartão, Dinheiro. Muitos gateways suportam Boleto — opção ausente pode limitar conversão. |
| 3.7 | **_processandoCheckout pode ficar true em erro** | Callbacks `onCheckout*` | Se `onCheckoutWhatsapp` ou `onCheckoutMercadoPago` lançar exceção **antes** do `finally`, o `_processandoCheckout = false` pode não rodar. Botões ficariam desabilitados. O `finally` está dentro do handler; exceções não tratadas no callback externo podem escapar. |

### ⚪ SILENCIOSO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 3.8 | **Caractere "?" no texto do diálogo de login** | ~3048 | `'? Receber cupons de desconto'` — provavelmente era bullet (•). Renderiza como "?" e prejudica leitura. |
| 3.9 | **gerarPixCopiaECola com nomeRecebedor fixo** | `onCheckoutPix` ~1795 | `nomeRecebedor: 'LOJA'` — valor genérico. Poderia vir da configuração da loja (razão social). |

---

## 4. CUPONS

### 🟠 ALTO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 4.1 | **Inconsistência de origem ao registrar uso** | `_aplicarCupom` ~825 | Cupons de `widget.cupons` (config) podem não ter `id`. O código busca `CupomDescontoService().buscarPorCodigo` para preencher. Se falhar, `registrarUso` em `onSuccess` usa `cupomId` nulo — cupom não é marcado como usado e pode ser reutilizado. |
| 4.2 | **Valor mínimo do cupom usa subtotal sem frete** | `_aplicarCupom` ~822 | `_subtotal < valorMinimo` — para cupons com `aplicarEm: 'total'`, o valor mínimo deveria considerar subtotal + frete. Cliente pode aplicar cupom que exige R$ 100 em "total" com subtotal R$ 90 + frete R$ 15 = R$ 105, mas a validação falha. |
| 4.3 | **Tipo 'valor' vs 'valor' em diferentes fontes** | `_descontoCupomProdutos` ~261 | `CuponsService` retorna `TipoCupom.descontoFixo` mapeado para `'valor'`. Cupom Firestore usa `'fixo'`. O código trata `tipo == 'valor'` e `tipo == 'percent'`. Verificar se cupons com `tipo: 'fixo'` do Firestore são tratados. Na linha 243 do Cupom model: `c.tipo == TipoCupom.descontoFixo ? 'valor'` — mapeamento correto. Mas cupons do config (`widget.cupons`) podem vir com `tipo: 'fixo'` sem esse mapeamento. |

### 🟡 MÉDIO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 4.4 | **Cupom PREMIO- bloqueado com mensagem longa** | `_aplicarCupom` ~818 | Mensagem explica bem, mas em mobile pode quebrar layout do SnackBar. |
| 4.5 | **Cupom roleta não integrado no desconto quando aplicado** | Fluxo cupom | Cupom ganho na roleta (`_cupomRoletaCodigo`) é enviado em `cupomRoletaCodigo` no checkout. O `_descontoCupomProdutos` considera `_cupomAplicado`, que é preenchido ao aplicar manualmente. O cupom da roleta pode não entrar em `_cupomAplicado` automaticamente — verificar se o total considera o desconto da roleta. (No código, `initialCupomRoletaDesconto` e `cupomRoletaDesconto` são passados; o cálculo em `_descontoCupomProdutos` usa `_cupomAplicado` que pode ser o cupom manual. Cupom roleta parece ser aplicado via `_cupomRoletaCodigo`/`_cupomRoletaDesconto` em outros pontos.) |

### ⚪ SILENCIOSO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 4.6 | **Data de validade com múltiplos nomes de campo** | `_aplicarCupom` ~805 | `df = found['dataFim'] ?? found['validade'] ?? found['dataValidade'] ?? found['dataExpiracao']` — muitos nomes. Se um cupom vier com outro nome (ex: `expiraEm`), a validação de data é pulada. |
| 4.7 | **Cliente não logado: botão "Selecionar cupom" falha sem contexto** | ~2732 | `widget.showSnack('Faça login para escolher...')` — adequado. Mas o `mostrarModalSelecionarCupom` (se o analyzer estiver errado) poderia ser chamado sem `clienteId` em edge case. |

---

## 5. ERROS GERAIS E SILENCIOSOS

### 🟠 ALTO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 5.1 | **Carrinho em memória sem sync se não logado** | `public_catalog_screen` | `_cart` é lista local. `_loadCarrinho` e `_saveCarrinho` dependem de `_clienteId`. Usuário não logado usa carrinho em memória; ao fechar aba, perde tudo. Persistência em `SharedPreferences` existe para **formulário**, não para itens. |
| 5.2 | **possível race em _recalcularFreteSelecionado** | `_recalcularFreteSelecionado` | Chamado em `_preencherDadosClienteLogado().then`, em `onChanged` do CEP (via `_buscarEnderecoPorCep`), e ao selecionar frete. Múltiplas chamadas concorrentes podem sobrescrever `_fretesLocal` em ordem imprevisível. |
| 5.3 | **Itens do carrinho: name vs nome** | `_left` ~1756 | `(item['name'] ?? item['nome'] ?? '')` — trata ambos. Mas em `_addToCart` e `CatalogEstoqueHelper` o padrão pode ser `nome`. Inconsistência entre telas. |

### 🟡 MÉDIO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 5.4 | **Quantidade de produtos ao mostrar roleta** | `_podeExibirRoleta` ~546 | `_quantidadeProdutosAoMostrarRoleta` é atribuída em `_atualizarEstadoRoleta` quando dados completos. Se usuário adicionar produto **depois** de preencher dados, a roleta é exibida. Se remover, "perde a chance". O `setState` em `_quantidadeProdutosAoMostrarRoleta = widget.items.length` ocorre dentro de getter `_podeExibirRoleta` — **efeito colateral em getter**, má prática. |
| 5.5 | **CatalogImagePlaceholder sem url pode quebrar** | `_left` ~1795 | `CatalogImagePlaceholder(url: fixedImageUrl)` — se `fixedImageUrl` for string vazia, o widget pode exibir placeholder ou quebrar. Verificar comportamento com `''`. |
| 5.6 | **asMapDeep e asMap em vários pontos** | Vários | Uso de helpers para cast seguro. Alguns pontos podem não tratar `null` ou tipos inesperados. |

### ⚪ SILENCIOSO

| # | Erro | Local | Descrição |
|---|------|-------|-----------|
| 5.7 | **Timer/listener em initState sem cancel em dispose** | `_atualizarEstadoRoleta` | Listeners em `_nome`, `_email`, etc. não são removidos em `dispose`. Em Flutter, `TextEditingController` é disposed; os listeners são anexados ao controller, então são limpos com ele. OK. |
| 5.8 | **Fechar sheet durante checkout** | `Navigator.pop` no onSuccess | Se usuário fechar o sheet manualmente (arrastar) durante processamento, o `onSuccess` pode chamar `Navigator.pop(context)` com context inválido. Verificar `mounted` antes. (Código tem `if (mounted) Navigator.pop(context)`.) |
| 5.9 | **lojaId vazio ou null** | `CarrinhoSheetWeb` | Se `widget.lojaId` for `''` ou null (improvável), chamadas a Firestore e serviços podem falhar. Não há validação na entrada. |

---

## 📊 RESUMO POR GRAVIDADE

| Gravidade | Quantidade |
|-----------|------------|
| 🔴 Crítico | 5 |
| 🟠 Alto | 15 |
| 🟡 Médio | 12 |
| 🔵 Baixo | 2 |
| ⚪ Silencioso | 10 |
| **Total** | **44** |

---

## ✅ PRIORIDADES DE CORREÇÃO

### Fase 1 – Bloqueadores
1. **1.1** – Ajustar validação de endereço para não exigir quando frete for "retirada".
2. **2.1** – Garantir que fretes manuais iniciais sejam exibidos quando `_fretesLocal` estiver vazio.
3. **3.1 / 3.2** – Confirmar em runtime se `showPixQrDialog` e `mostrarModalSelecionarCupom` funcionam; corrigir imports/escopo se necessário.
4. **3.5** – Repassar cupom aplicado no fluxo PIX (`CatalogoVendaService.registrarVendaCatalogo`).

### Fase 2 – Alta prioridade
5. **1.2** – Implementar validação de CPF com dígitos verificadores.
6. **1.3** – Validar formato de e-mail quando preenchido.
7. **2.3** – Usar box de config por loja para embalagens.
8. **2.4** – Definir peso padrão mínimo para produtos sem peso.
9. **4.1** – Garantir que cupom seja marcado como usado mesmo quando `id` é obtido de forma assíncrona.
10. **5.1** – Avaliar persistência do carrinho para usuários não logados (ex.: localStorage/SharedPreferences).

### Fase 3 – Melhorias
11. **1.4** – Persistir formulário de forma síncrona ou garantir await antes de fechar.
12. **1.5 / 1.6** – Tratar JSON corrompido e tipos em `initialFormData`.
13. **2.6** – Corrigir exibição do prazo (substituir `?` por `-` ou similar).
14. **3.8** – Trocar "?" por bullet no texto do diálogo de login.
15. **5.4** – Remover efeito colateral do getter `_podeExibirRoleta`.

---

*Relatório gerado por análise estática e revisão de fluxo do código.*
