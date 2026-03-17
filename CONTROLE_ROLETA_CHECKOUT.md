# 🎯 Controle de Roleta no Checkout

## ✨ Mudanças Implementadas

### 1️⃣ **Roleta Aparece APENAS Após Preencher Todos os Dados**

A roleta agora só é exibida quando o cliente completar:

✅ **Dados Pessoais:**
- Nome completo
- Email
- Telefone

✅ **Endereço de Entrega** (se não for retirada):
- CEP
- Rua
- Número
- Bairro
- Cidade
- Estado

✅ **Forma de Pagamento:**
- PIX, Cartão, Dinheiro, etc.

### 2️⃣ **Perde a Chance se Voltar para Produtos**

Regras de perda da chance:

❌ **PERDE a chance se:**
- Remover produtos do carrinho
- Voltar para a tela de produtos e não adicionar nada novo
- Limpar dados já preenchidos

✅ **MANTÉM a chance se:**
- Adicionar MAIS produtos ao carrinho
- Apenas visualizar os dados sem remover produtos
- Mudar forma de pagamento ou endereço (desde que mantenha completo)

### 3️⃣ **Cupom NÃO Pode Ser Usado na Mesma Compra**

🚫 **Cupons de prêmio são BLOQUEADOS** na compra atual:

```
Cliente tenta usar: PREMIO-1234

❌ Mensagem:
"⚠️ Cupons de prêmio só podem ser usados em compras futuras!

Finalize esta compra primeiro e use o cupom na próxima."
```

✅ **Cupom só valida em compras futuras** (após pagamento confirmado)

---

## 🔄 Fluxo Completo

### Passo 1: Cliente Adiciona Produtos

```
┌─────────────────────────┐
│  Produto A   R$ 50,00   │
│  Produto B   R$ 30,00   │
│                         │
│  Subtotal:  R$ 80,00    │
│                         │
│  [ Ver Carrinho ]       │
└─────────────────────────┘
```

### Passo 2: Abre Carrinho - Dados Incompletos

```
┌─────────────────────────────────┐
│  CARRINHO                       │
├─────────────────────────────────┤
│                                 │
│  📝 Dados Pessoais              │
│  Nome: [__________]             │ ← Vazios
│  Email: [__________]            │
│  Tel: [__________]              │
│                                 │
│  📦 Endereço                    │
│  CEP: [__________]              │
│  ...                            │
│                                 │
│  💳 Pagamento                   │
│  ( ) PIX  ( ) Cartão            │
│                                 │
│  ┌───────────────────────────┐ │
│  │ ℹ️ Complete todos os      │ │ ← AVISO
│  │ dados acima para liberar  │ │
│  │ a Roleta da Sorte!        │ │
│  └───────────────────────────┘ │
│                                 │
│  [ Finalizar pelo WhatsApp ]   │
└─────────────────────────────────┘
```

### Passo 3: Cliente Preenche Todos os Dados

```
┌─────────────────────────────────┐
│  CARRINHO                       │
├─────────────────────────────────┤
│                                 │
│  📝 Dados Pessoais              │
│  Nome: [João Silva_____]        │ ← Preenchidos
│  Email: [joao@email.com]        │
│  Tel: [(11) 99999-9999]         │
│                                 │
│  📦 Endereço                    │
│  CEP: [01310-100___]            │
│  Rua: [Av. Paulista_]           │
│  ...                            │
│                                 │
│  💳 Pagamento                   │
│  (•) PIX  ( ) Cartão            │ ← Selecionado
│                                 │
│  ┌───────────────────────────┐ │
│  │ ⭐ Você completou seus    │ │ ← AVISO DOURADO
│  │ dados! Gire a roleta e    │ │
│  │ concorra a prêmios!       │ │
│  └───────────────────────────┘ │
│                                 │
│  ╔═══════════════════════════╗ │
│  ║   ROLETA DA SORTE         ║ │ ← ROLETA APARECE!
│  ║   [Imagem da roleta]      ║ │
│  ║                           ║ │
│  ║  [ GIRAR A ROLETA! ]      ║ │
│  ╚═══════════════════════════╝ │
│                                 │
│  [ Finalizar pelo WhatsApp ]   │
└─────────────────────────────────┘
```

### Passo 4: Cliente Gira a Roleta

```
[Roleta gira 4-6 voltas]
[Para onde a seta aponta]

Ganhou: 15% OFF

┌─────────────────────────────────┐
│   🎉 PARABÉNS! 🎉              │
│                                 │
│  Você ganhou este prêmio:       │
│                                 │
│  ┌───────────────────────────┐ │
│  │      15% OFF              │ │ ← DOURADO
│  └───────────────────────────┘ │
│                                 │
│  ┌───────────────────────────┐ │
│  │   SEU CUPOM               │ │
│  │   PREMIO-1234             │ │
│  └───────────────────────────┘ │
│                                 │
│  📅 Válido por 60 dias          │
│  🔄 Use na PRÓXIMA compra       │ ← IMPORTANTE!
│  ⚠️ Uso único                   │
│                                 │
│  [ ENTENDI! ]                   │
└─────────────────────────────────┘
```

### Passo 5: Roleta Desaparece

```
┌─────────────────────────────────┐
│  CARRINHO                       │
├─────────────────────────────────┤
│                                 │
│  [Dados já preenchidos]         │
│                                 │
│  💳 Pagamento: PIX              │
│                                 │
│  🎟️ Cupom de desconto           │
│  Digite o cupom: [___________]  │
│  [ Aplicar ]                    │
│                                 │
│  ❌ Roleta não aparece mais     │ ← JÁ GIROU
│  (já foi girada)                │
│                                 │
│  [ Finalizar pelo WhatsApp ]   │
└─────────────────────────────────┘
```

### Passo 6: Cliente Tenta Usar Cupom (BLOQUEADO)

```
Cliente digita: PREMIO-1234
Cliente clica em "Aplicar"

❌ Mensagem de erro:

┌─────────────────────────────────┐
│  ⚠️ Cupons de prêmio só podem   │
│  ser usados em compras futuras! │
│                                 │
│  Finalize esta compra primeiro  │
│  e use o cupom na próxima.      │
└─────────────────────────────────┘
```

### Passo 7: Finaliza a Compra Atual

```
Cliente clica em:
[ Finalizar pelo WhatsApp ]

→ Pedido enviado via WhatsApp
→ Cupom PREMIO-1234 continua válido
→ Pode usar em compra futura
```

### Passo 8: Próxima Compra (Usando o Cupom)

```
Cliente faz nova compra:

┌─────────────────────────────────┐
│  CARRINHO                       │
├─────────────────────────────────┤
│  Produto C   R$ 100,00          │
│                                 │
│  Subtotal:  R$ 100,00           │
│                                 │
│  🎟️ Cupom: PREMIO-1234          │
│  [ Aplicar ]                    │
└─────────────────────────────────┘

Cliente clica em "Aplicar":

✅ Cupom aplicado!
   Desconto de 15% = R$ 15,00

┌─────────────────────────────────┐
│  Subtotal:     R$ 100,00        │
│  Desconto 15%: -R$ 15,00        │
│  ─────────────────────────      │
│  Total:         R$ 85,00        │
└─────────────────────────────────┘

Após finalizar compra:
→ Cupom é marcado como USADO
→ Não pode ser usado novamente
```

---

## 🔧 Lógica Técnica

### Verificação de Dados Completos

```dart
bool _verificarDadosCompletos() {
  // Verifica dados pessoais
  final nomeOk = _nome.text.trim().isNotEmpty;
  final emailOk = _email.text.trim().isNotEmpty;
  final telOk = _tel.text.trim().isNotEmpty;

  // Se for retirada, não precisa de endereço
  final tipoFrete = _fretesLocal[_freteIndex]['tipo'];

  bool enderecoOk = true;
  if (tipoFrete != 'retirada') {
    enderecoOk = _cep.text.isNotEmpty &&
                 _rua.text.isNotEmpty &&
                 _numero.text.isNotEmpty &&
                 _bairro.text.isNotEmpty &&
                 _cidade.text.isNotEmpty &&
                 _estado.text.isNotEmpty;
  }

  // Verifica pagamento
  final pagamentoOk = _pagamento.isNotEmpty;

  return nomeOk && emailOk && telOk && enderecoOk && pagamentoOk;
}
```

### Controle de Exibição da Roleta

```dart
bool get _podeExibirRoleta {
  // Sem campanha ativa
  if (_campanhaAtivaId == null) return false;

  // Já girou
  if (_roletaJaGirada) return false;

  // Dados incompletos
  if (!_todosOsDadosPreenchidos) return false;

  // Verificar mudança na quantidade de produtos
  if (widget.items.length != _quantidadeProdutosAoMostrarRoleta) {
    if (widget.items.length > _quantidadeProdutosAoMostrarRoleta) {
      // ADICIONOU produtos - mantém a chance
      _quantidadeProdutosAoMostrarRoleta = widget.items.length;
      return true;
    } else {
      // REMOVEU produtos - perde a chance
      return false;
    }
  }

  return true;
}
```

### Bloqueio de Cupons de Prêmio

```dart
Future<void> _aplicarCupom() async {
  final code = _cupomCtrl.text.trim().toUpperCase();

  // Cupons de prêmio NÃO podem ser usados na mesma compra
  if (code.startsWith('PREMIO-')) {
    widget.showSnack(
      '⚠️ Cupons de prêmio só podem ser usados em compras futuras!\n\n'
      'Finalize esta compra primeiro e use o cupom na próxima.',
    );
    return;
  }

  // ... validação de cupons normais
}
```

---

## 📊 Estados da Roleta

### Estado 1: Dados Incompletos

```
_campanhaAtivaId: "campanha123"
_roletaJaGirada: false
_todosOsDadosPreenchidos: false

Exibição: ℹ️ Aviso azul
"Complete todos os dados acima..."
```

### Estado 2: Dados Completos - Pode Girar

```
_campanhaAtivaId: "campanha123"
_roletaJaGirada: false
_todosOsDadosPreenchidos: true

Exibição: ⭐ Aviso dourado + Roleta
"Você completou seus dados! Gire..."
```

### Estado 3: Já Girou

```
_campanhaAtivaId: "campanha123"
_roletaJaGirada: true
_todosOsDadosPreenchidos: true

Exibição: (nada)
Roleta não aparece mais
```

### Estado 4: Removeu Produtos

```
_quantidadeProdutosAoMostrarRoleta: 3
widget.items.length: 2  (removeu 1)

Resultado: Perde a chance
Exibição: (nada)
```

### Estado 5: Adicionou Produtos

```
_quantidadeProdutosAoMostrarRoleta: 3
widget.items.length: 4  (adicionou 1)

Resultado: Mantém a chance
Exibição: ⭐ Aviso dourado + Roleta
```

---

## ✅ Checklist de Testes

### Teste 1: Exibição da Roleta
- [ ] Abrir carrinho com dados vazios
- [ ] Verificar que aparece aviso azul
- [ ] Preencher nome, email, telefone
- [ ] Preencher endereço completo
- [ ] Selecionar forma de pagamento
- [ ] Verificar que aviso muda para dourado
- [ ] Verificar que roleta aparece

### Teste 2: Girar a Roleta
- [ ] Clicar em "GIRAR A ROLETA!"
- [ ] Aguardar animação (4-6 voltas)
- [ ] Verificar que para no prêmio correto
- [ ] Verificar modal com prêmio em destaque
- [ ] Copiar código do cupom
- [ ] Fechar modal
- [ ] Verificar que roleta desapareceu

### Teste 3: Bloqueio de Cupom
- [ ] No campo "Cupom de desconto"
- [ ] Digitar o código PREMIO-XXXX
- [ ] Clicar em "Aplicar"
- [ ] Verificar mensagem de erro
- [ ] Confirmar que cupom NÃO foi aplicado

### Teste 4: Remover Produtos
- [ ] Preencher todos os dados
- [ ] Verificar que roleta aparece
- [ ] Voltar para produtos
- [ ] Remover 1 produto do carrinho
- [ ] Voltar para carrinho
- [ ] Verificar que roleta NÃO aparece mais

### Teste 5: Adicionar Produtos
- [ ] Preencher todos os dados
- [ ] Verificar que roleta aparece
- [ ] Voltar para produtos
- [ ] Adicionar 1 novo produto
- [ ] Voltar para carrinho
- [ ] Verificar que roleta AINDA aparece

### Teste 6: Uso em Compra Futura
- [ ] Fazer uma compra e girar a roleta
- [ ] Anotar código do cupom
- [ ] Finalizar compra atual
- [ ] Fazer NOVA compra (novos produtos)
- [ ] No campo de cupom, usar PREMIO-XXXX
- [ ] Verificar que desconto foi aplicado
- [ ] Finalizar compra
- [ ] Tentar usar mesmo cupom novamente
- [ ] Verificar mensagem "Cupom já foi utilizado"

---

## 📁 Arquivos Modificados

1. ✅ `lib/screens/public_catalog_screen.dart`
   - Linhas 2698-2702: Novas variáveis de controle
   - Linhas 2828-2891: Funções de verificação e controle
   - Linhas 2774-2784: Listeners nos campos
   - Linhas 2805-2807: Verificação ao mudar produtos
   - Linhas 2973-2980: Bloqueio de cupons de prêmio
   - Linhas 4156-4239: Lógica de exibição da roleta
   - Removidas: Linhas que marcavam cupom como usado

---

**Data:** 21/12/2024
**Versão:** 4.0 - Controle de Exibição e Bloqueio de Uso
**Status:** ✅ Implementado e pronto para teste
