# 🎯 Prêmios Fixos e Controle de Tentativas da Roleta

## ✨ Novas Funcionalidades Implementadas

### 1️⃣ **Prêmios Fixos Padrão**

A roleta agora tem 8 prêmios fixos pré-definidos:

```dart
1. 10% OFF          - Desconto de 10%
2. GIRE NOVAMENTE   - Chance extra de girar
3. 5% OFF           - Desconto de 5%
4. NÃO FOI DESSA VEZ - Sem prêmio
5. 15% OFF          - Desconto de 15%
6. FRETE GRÁTIS     - Frete grátis
7. R$ 10 OFF        - Desconto de R$ 10
8. NÃO FOI DESSA VEZ - Sem prêmio
```

### 2️⃣ **Uma Única Chance**

- ✅ Cliente pode girar **apenas 1 vez** por compra
- ✅ **EXCETO** se ganhar "Gire Novamente"
- ✅ Ao ganhar "Gire Novamente", pode girar mais uma vez
- ✅ Se cair em "Não foi dessa vez", não ganha cupom

### 3️⃣ **Prêmio Destacado**

O modal agora mostra **CLARAMENTE** qual foi o prêmio ganho:

```
┌─────────────────────────────┐
│     🎉 PARABÉNS! 🎉        │
│  Você ganhou este prêmio:   │
│                             │
│  ┌───────────────────────┐ │
│  │    15% OFF            │ │ ← Prêmio em DESTAQUE
│  └───────────────────────┘ │    (dourado brilhante)
│                             │
│  ┌───────────────────────┐ │
│  │  SEU CUPOM            │ │
│  │  PREMIO-1234          │ │ ← Código do cupom
│  └───────────────────────┘ │
│                             │
│  Válido por 60 dias         │
│  Use na próxima compra      │
└─────────────────────────────┘
```

---

## 🎲 Tipos de Prêmio

### 1. Prêmios com Cupom

Quando o cliente ganha um prêmio válido:

- ✅ Gera cupom automaticamente
- ✅ Modal mostra o **prêmio ganho** em destaque dourado
- ✅ Mostra o **código do cupom**
- ✅ Informa validade (60 dias)
- ✅ Informa que é para usar na **próxima compra**
- ✅ Marca que já girou (não pode girar novamente)

**Tipos:**
- `percentual` - Desconto em % (ex: 10% OFF)
- `valor` - Desconto em R$ (ex: R$ 10 OFF)
- `frete_gratis` - Frete grátis

### 2. Gire Novamente

Quando cai em "Gire Novamente":

```
┌─────────────────────────────┐
│      🎉 QUE SORTE!         │
│                             │
│  Você ganhou mais uma       │
│  chance!                    │
│                             │
│  Gire a roleta novamente!   │
│                             │
│  [ GIRAR NOVAMENTE ]        │
└─────────────────────────────┘
```

- ✅ Modal verde com ícone de refresh
- ✅ **NÃO marca** como já girou
- ✅ Cliente pode girar novamente
- ✅ **NÃO gera cupom**

### 3. Não Foi Dessa Vez

Quando cai em "Não foi dessa vez":

```
┌─────────────────────────────┐
│  😔 Não foi dessa vez!     │
│                             │
│  Infelizmente você não      │
│  ganhou nenhum prêmio       │
│  desta vez.                 │
│                             │
│  Mas não desista, volte     │
│  sempre!                    │
│                             │
│  [ FECHAR ]                 │
└─────────────────────────────┘
```

- ✅ Modal laranja com ícone triste
- ✅ **Marca como já girou** (não pode tentar novamente)
- ✅ **NÃO gera cupom**

---

## 🔧 Implementação Técnica

### Estrutura de Prêmios

Cada prêmio tem:

```dart
{
  'label': 'Texto na roleta (pode ter \n)',
  'tipo': 'percentual|valor|frete_gratis|gire_novamente|sem_premio',
  'valor': 10.0,  // valor do desconto (0 para especiais)
  'ativo': true,
}
```

### Lógica de Controle

```dart
// Ao girar a roleta:
1. Sorteia um prêmio aleatório
2. Gira a roleta até alinhar com a seta
3. Verifica o tipo do prêmio:

   SE tipo == 'gire_novamente':
      → Mostra modal verde
      → NÃO chama callback (não marca como usado)
      → Cliente pode girar novamente

   SE tipo == 'sem_premio':
      → Mostra modal laranja
      → Chama callback (marca como usado)
      → Cliente NÃO pode girar novamente

   SENÃO (prêmio válido):
      → Gera cupom
      → Mostra modal roxo com prêmio destacado
      → Chama callback (marca como usado)
      → Cliente NÃO pode girar novamente
```

### Código Relevante

**Prêmios fixos** (`lib/widgets/roleta_web_widget.dart:91-102`):
```dart
List<Map<String, dynamic>> _premiosFixos() {
  return [
    {'label': '10% OFF', 'tipo': 'percentual', 'valor': 10.0, 'ativo': true},
    {'label': 'Gire\nNovamente', 'tipo': 'gire_novamente', 'valor': 0.0, 'ativo': true},
    {'label': '5% OFF', 'tipo': 'percentual', 'valor': 5.0, 'ativo': true},
    {'label': 'Não foi\ndessa vez', 'tipo': 'sem_premio', 'valor': 0.0, 'ativo': true},
    {'label': '15% OFF', 'tipo': 'percentual', 'valor': 15.0, 'ativo': true},
    {'label': 'Frete\nGrátis', 'tipo': 'frete_gratis', 'valor': 0.0, 'ativo': true},
    {'label': 'R\$ 10 OFF', 'tipo': 'valor', 'valor': 10.0, 'ativo': true},
    {'label': 'Não foi\ndessa vez', 'tipo': 'sem_premio', 'valor': 0.0, 'ativo': true},
  ];
}
```

**Tratamento especial** (`lib/widgets/roleta_web_widget.dart:158-179`):
```dart
if (tipoPremio == 'gire_novamente') {
  _mostrarPremioEspecial(
    titulo: '🎉 QUE SORTE!',
    mensagem: 'Você ganhou mais uma chance!\n\nGire a roleta novamente!',
    cor: const Color(0xFF4CAF50),
    podeTentarNovamente: true,
  );
  return; // NÃO chama callback
}

if (tipoPremio == 'sem_premio') {
  _mostrarPremioEspecial(
    titulo: '😔 Não foi dessa vez!',
    mensagem: 'Infelizmente você não ganhou...',
    cor: const Color(0xFFFF9800),
    podeTentarNovamente: false,
  );
  widget.onCupomGerado?.call(); // Chama callback (marca como usado)
  return;
}
```

---

## 🎨 Visual dos Modais

### Modal de Prêmio Válido

```
╔═══════════════════════════════╗
║   🏆 (ícone dourado)          ║
║                               ║
║   🎉 PARABÉNS! 🎉            ║
║   Você ganhou este prêmio:    ║
║                               ║
║  ╔═══════════════════════╗   ║
║  ║    15% OFF            ║   ║ ← Fundo dourado brilhante
║  ║  (texto preto bold)   ║   ║
║  ╚═══════════════════════╝   ║
║                               ║
║  ┌─────────────────────────┐ ║
║  │     SEU CUPOM           │ ║
║  │   ┌───────────────┐     │ ║
║  │   │ PREMIO-1234   │     │ ║ ← Monospace, roxo
║  │   └───────────────┘     │ ║
║  └─────────────────────────┘ ║
║                               ║
║  📅 Válido por 60 dias        ║
║  🔄 Use na próxima compra     ║
║  ⚠️ Uso único                 ║
║                               ║
║  [ ENTENDI! ]                 ║
╚═══════════════════════════════╝
```

### Modal "Gire Novamente"

```
╔═══════════════════════════════╗
║   🔄 (ícone refresh)          ║
║                               ║
║   🎉 QUE SORTE!               ║
║                               ║
║   Você ganhou mais uma        ║
║   chance!                     ║
║                               ║
║   Gire a roleta novamente!    ║
║                               ║
║  [ GIRAR NOVAMENTE ]          ║ ← Fundo branco
╚═══════════════════════════════╝  (verde quando hover)
     (fundo verde)
```

### Modal "Não Foi Dessa Vez"

```
╔═══════════════════════════════╗
║   😔 (ícone triste)           ║
║                               ║
║   😔 Não foi dessa vez!       ║
║                               ║
║   Infelizmente você não       ║
║   ganhou nenhum prêmio        ║
║   desta vez.                  ║
║                               ║
║   Mas não desista, volte      ║
║   sempre!                     ║
║                               ║
║  [ FECHAR ]                   ║ ← Fundo branco
╚═══════════════════════════════╝  (laranja quando hover)
     (fundo laranja)
```

---

## 📊 Probabilidades

Com os prêmios fixos atuais (8 fatias):

| Prêmio | Probabilidade |
|--------|--------------|
| 10% OFF | 12.5% (1/8) |
| Gire Novamente | 12.5% (1/8) |
| 5% OFF | 12.5% (1/8) |
| Não foi dessa vez | **25%** (2/8) |
| 15% OFF | 12.5% (1/8) |
| Frete Grátis | 12.5% (1/8) |
| R$ 10 OFF | 12.5% (1/8) |

**Chance de ganhar algo válido:** 62.5% (5/8)
**Chance de não ganhar:** 25% (2/8)
**Chance de girar novamente:** 12.5% (1/8)

---

## 🔄 Customização de Prêmios

Embora existam prêmios fixos padrão, é possível customizar via campanha no Firestore:

### Via Firebase Console:

No documento da campanha (`/lojas/{id}/campanhas_sorteio/{id}`), adicione o campo `premios`:

```javascript
{
  "nome": "Natal 2024",
  "ativa": true,
  "valorMinimo": 0,
  "premios": [
    {"label": "20% OFF", "tipo": "percentual", "valor": 20, "ativo": true},
    {"label": "Gire\nNovamente", "tipo": "gire_novamente", "valor": 0, "ativo": true},
    {"label": "R$ 50 OFF", "tipo": "valor", "valor": 50, "ativo": true},
    {"label": "Não foi\ndessa vez", "tipo": "sem_premio", "valor": 0, "ativo": true},
    {"label": "Frete\nGrátis", "tipo": "frete_gratis", "valor": 0, "ativo": true},
    {"label": "30% OFF", "tipo": "percentual", "valor": 30, "ativo": true},
  ],
  // ... outros campos
}
```

**Se o campo `premios` existir e não estiver vazio:** Usa os prêmios customizados
**Se o campo `premios` NÃO existir ou estiver vazio:** Usa os 8 prêmios fixos padrão

---

## ✅ Checklist de Testes

Teste todos os cenários:

### 1. Prêmio Válido
- [ ] Girar a roleta
- [ ] Cair em um prêmio válido (ex: 10% OFF)
- [ ] Modal mostra **CLARAMENTE** o prêmio em destaque dourado
- [ ] Modal mostra o código do cupom
- [ ] Modal mostra validade de 60 dias
- [ ] Fechar o modal
- [ ] Botão "GIRAR" fica desabilitado
- [ ] Não pode girar novamente

### 2. Gire Novamente
- [ ] Girar a roleta
- [ ] Cair em "Gire Novamente"
- [ ] Modal VERDE aparece com ícone de refresh
- [ ] Mensagem "Você ganhou mais uma chance!"
- [ ] Fechar o modal
- [ ] Botão "GIRAR" continua **HABILITADO**
- [ ] Pode girar novamente
- [ ] Girar novamente e testar o novo resultado

### 3. Não Foi Dessa Vez
- [ ] Girar a roleta
- [ ] Cair em "Não foi dessa vez"
- [ ] Modal LARANJA aparece com ícone triste
- [ ] Mensagem "Infelizmente você não ganhou..."
- [ ] Fechar o modal
- [ ] Botão "GIRAR" fica **DESABILITADO**
- [ ] Não pode girar novamente

### 4. Visual da Roleta
- [ ] 8 fatias visíveis
- [ ] Cores alternadas (vermelho/amarelo)
- [ ] Seta FIXA no topo
- [ ] Apenas a roleta gira
- [ ] Textos legíveis nas fatias

---

## 📁 Arquivos Modificados

1. ✅ `lib/widgets/roleta_web_widget.dart`
   - Linha 91-102: Prêmios fixos padrão
   - Linha 61-88: Carregamento de prêmios (fixos ou customizados)
   - Linha 158-179: Tratamento de prêmios especiais
   - Linha 239-339: Modal para prêmios especiais
   - Linha 384-472: Modal melhorado com prêmio em destaque

---

**Data:** 21/12/2024
**Versão:** 3.0 - Prêmios Fixos e Controle de Tentativas
**Status:** ✅ Implementado e pronto para teste
