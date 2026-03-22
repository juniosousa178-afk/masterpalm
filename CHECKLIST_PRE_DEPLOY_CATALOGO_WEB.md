# Checklist Pré-Deploy – Catálogo Web

## Objetivo

Validar manualmente os cenários críticos do carrinho e checkout do catálogo público web antes do deploy em produção, conforme smoke test definido em `RELATORIO_FINAL_CARRINHO_CATALOGO_WEB.md`.

---

## Pré-condições

- Ambiente web funcional (local ou staging)
- Loja configurada com catálogo público, produtos, fretes e gateway (PIX e/ou WhatsApp)
- Cupom de teste disponível (para cenários 7 e 8)
- Usuário não logado (para cenários 10, 11, 12, 13 de cadastro/checkout)

---

## Checklist

| # | Teste | Resultado esperado | Status |
|---|-------|--------------------|--------|
| 1 | Abrir catálogo | Carregamento e exibição dos produtos | NÃO TESTADO |
| 2 | Adicionar item ao carrinho | Item adicionado, contador atualizado | NÃO TESTADO |
| 3 | Abrir carrinho | Sheet abre com itens e formulário | NÃO TESTADO |
| 4 | Checkout com retirada | Finaliza sem exigir endereço completo | NÃO TESTADO |
| 5 | Checkout com entrega | Exige CEP e endereço; calcula frete | NÃO TESTADO |
| 6 | Checkout sem fretes da API | Fretes manuais (Retirada, Combinar) exibidos | NÃO TESTADO |
| 7 | Aplicar cupom | Cupom aplicado; desconto no total | NÃO TESTADO |
| 8 | PIX com cupom | Total correto; cupom marcado como usado | NÃO TESTADO |
| 9 | PIX sem cupom | Fluxo normal; QR gerado | NÃO TESTADO |
| 10 | Carrinho ao recarregar aba | Itens e formulário persistidos (usuário não logado) | NÃO TESTADO |
| 11 | Telefone com 10 dígitos | Aceito no cadastro e checkout | NÃO TESTADO |
| 12 | Telefone com 11 dígitos | Aceito no cadastro e checkout | NÃO TESTADO |
| 13 | Telefone inválido (< 10 dígitos) | Rejeitado com mensagem clara | NÃO TESTADO |

**Status:** OK | FALHOU | NÃO TESTADO

---

## Decisão de deploy

| Resultado | Condição |
|-----------|----------|
| ☐ **Aprovado** | Todos os testes OK |
| ☐ **Aprovado com ressalvas** | 1–2 testes falharam em cenários secundários; riscos documentados e aceitos |
| ☐ **Reprovado** | Qualquer teste crítico (4, 5, 8, 9, 10) falhou ou 3+ testes falharam |

---

**Data da execução:** _______________  
**Responsável:** _______________  
**Assinatura:** _______________
