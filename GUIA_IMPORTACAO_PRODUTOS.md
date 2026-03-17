# 📦 Guia de Importação de Produtos

Este guia explica como importar produtos em massa para o sistema Master Palm usando arquivos CSV ou XLSX.

## 📋 Campos Disponíveis

### ✅ Campos Obrigatórios

| Campo | Tipo | Descrição | Exemplo |
|-------|------|-----------|---------|
| `nome` | Texto | Nome do produto | `"Camiseta Básica Algodão"` |

**Nota:** Apenas o nome é obrigatório! Todos os outros campos são opcionais.

### 💰 Campos de Precificação (Opcionais)

| Campo | Tipo | Descrição | Exemplo | Padrão |
|-------|------|-----------|---------|--------|
| `preco` | Decimal | Preço de venda final | `49.90` | `0.0` |
| `custo` | Decimal | Custo real do produto | `15.00` | `0.0` |
| `frete` | Decimal | Custo de frete | `5.00` | `0.0` |
| `gastos_fixos` | Decimal | Gastos fixos | `2.00` | `0.0` |
| `gastos_variaveis` | Decimal | Gastos variáveis | `3.00` | `0.0` |
| `preco_sugerido` | Decimal | Preço sugerido | `45.00` | `0.0` |

### 📦 Campos de Estoque (Opcionais)

| Campo | Tipo | Descrição | Exemplo | Padrão |
|-------|------|-----------|---------|--------|
| `quantidade` | Inteiro | Quantidade total em estoque | `10` | `1` |
| `tamanhos` | Texto | Grade de tamanhos com estoque | `"P=2;M=4;G=3;GG=1"` ou `"36,38,40,42"` | _(vazio)_ |

**Formato do campo `tamanhos`:**
- **Com estoque por tamanho:** `"P=2;M=4;G=3;GG=1"` (indica 2 unidades P, 4 M, 3 G, 1 GG)
- **Apenas lista de tamanhos:** `"P,M,G,GG"` (usa o campo `quantidade` como total)
- **Separadores aceitos:** vírgula (`,`) ou ponto e vírgula (`;`)

### 🏷️ Campos de Categorização (Opcionais)

| Campo | Tipo | Descrição | Exemplo | Padrão |
|-------|------|-----------|---------|--------|
| `categoria` | Texto | Categoria principal | `"Roupas"` | _(vazio)_ |
| `subcategoria` | Texto | Subcategoria | `"Camisetas"` | _(vazio)_ |
| `descricao` | Texto | Descrição detalhada | `"Camiseta 100% algodão..."` | _(vazio)_ |

### 🖼️ Campos de Imagens e Multimídia (Opcionais)

| Campo | Tipo | Descrição | Exemplo | Padrão |
|-------|------|-----------|---------|--------|
| `imagens` | Texto | URLs das imagens separadas | `"https://url1.jpg;https://url2.jpg"` | _(vazio)_ |

**Formato do campo `imagens`:**
- Separe múltiplas URLs com vírgula (`,`) ou ponto e vírgula (`;`)
- Suporta URLs de imagens online (http/https)
- Exemplo: `"https://exemplo.com/foto1.jpg;https://exemplo.com/foto2.jpg;https://exemplo.com/foto3.jpg"`

### 📏 Campos de Características Físicas (Opcionais)

| Campo | Tipo | Descrição | Exemplo | Padrão |
|-------|------|-----------|---------|--------|
| `peso` | Decimal | Peso em gramas | `200` | `0.0` |
| `tipo_embalagem` | Texto | Tipo de embalagem | `"pequena"`, `"media"`, `"grande"`, `"padrao"` | `"padrao"` |
| `cores` | Texto | Cores disponíveis separadas | `"Branco,Preto,Azul"` | _(vazio)_ |

### 💸 Campos de Promoção (Opcionais)

| Campo | Tipo | Descrição | Exemplo | Padrão |
|-------|------|-----------|---------|--------|
| `em_promocao` | Boolean | Produto está em promoção? | `true` ou `false` | `false` |
| `percentual_promo` | Decimal | Desconto percentual | `10` (para 10%) | _(vazio)_ |
| `valor_promo` | Decimal | Desconto em valor fixo | `50.00` (R$ 50 OFF) | _(vazio)_ |
| `data_inicio_promo` | Data | Data de início da promoção | `2026-01-10` ou `10/01/2026` | _(vazio)_ |
| `data_fim_promo` | Data | Data de fim da promoção | `2026-01-31` ou `31/01/2026` | _(vazio)_ |

**Notas sobre promoção:**
- Use **OU** `percentual_promo` **OU** `valor_promo`, não ambos
- Formatos de data aceitos: `YYYY-MM-DD` ou `DD/MM/YYYY`
- Se `em_promocao=true` mas não informar desconto, o produto não terá desconto aplicado

### 🏪 Campos de Marketplace (Opcionais)

| Campo | Tipo | Descrição | Exemplo | Padrão |
|-------|------|-----------|---------|--------|
| `marketplaces` | Texto | Marketplaces onde publicar | `"mercadolivre,shopee,amazon"` | _(vazio)_ |
| `publicar` | Boolean | Publicar no catálogo público? | `true` ou `false` | `false` |

**Marketplaces disponíveis:**
- `mercadolivre` - Mercado Livre
- `shopee` - Shopee
- `magazineluiza` - Magazine Luiza
- `amazon` - Amazon
- `americanas` - Americanas

**Formato:** Separe múltiplos marketplaces com vírgula (`,`) ou ponto e vírgula (`;`)

## 📝 Exemplos Práticos

### Exemplo 1: Produto Completo com Todos os Campos

```csv
nome,preco,quantidade,custo,categoria,subcategoria,descricao,imagens,tamanhos,peso,cores,em_promocao,percentual_promo,data_inicio_promo,data_fim_promo,marketplaces,publicar
"Camiseta Premium","89.90",15,25.00,"Roupas","Camisetas","Camiseta premium 100% algodão egípcio","https://cdn.exemplo.com/cam1.jpg;https://cdn.exemplo.com/cam2.jpg","P=3;M=6;G=4;GG=2",250,"Branco,Preto,Azul Marinho",true,15,2026-01-10,2026-01-31,"mercadolivre,shopee",true
```

### Exemplo 2: Produto Simples (Apenas Campos Essenciais)

```csv
nome,preco,quantidade
"Caneca Personalizada",29.90,50
```

### Exemplo 3: Produto com Promoção de Valor Fixo

```csv
nome,preco,em_promocao,valor_promo,data_inicio_promo,data_fim_promo
"Notebook Gamer",3499.00,true,500.00,2026-01-15,2026-02-15
```

### Exemplo 4: Produto com Grade de Tamanhos

```csv
nome,preco,tamanhos,categoria
"Tênis Running",299.90,"37=1;38=2;39=3;40=3;41=2;42=1;43=1","Calçados"
```

## 📂 Formatos de Arquivo Suportados

- **CSV** (`.csv`) - Valores separados por vírgula
- **XLSX** (`.xlsx`) - Planilha Excel
- **PDF** (`.pdf`) - Formato PDF (extração de tabelas)

## ⚙️ Como Importar

1. Prepare seu arquivo (CSV, XLSX ou PDF) com os dados
2. Acesse a tela **Estoque** no app
3. Clique no ícone **Importar** (📤) no canto superior direito
4. Selecione o arquivo
5. Aguarde o processamento
6. Veja o relatório de importação (quantidade de sucessos e erros)

## 💡 Dicas Importantes

### ✅ Boas Práticas

- **Use o arquivo de exemplo** (`exemplo_importacao_produtos.csv`) como base
- **Sempre inclua o campo `nome`** - é o único obrigatório
- **Teste com poucos produtos primeiro** antes de importar centenas
- **Use URLs públicas para imagens** (não use caminhos locais)
- **Mantenha a consistência nas categorias** (use sempre os mesmos nomes)
- **Separe valores múltiplos** com vírgula ou ponto e vírgula
- **Use aspas duplas** para textos com vírgulas: `"Camiseta básica, confortável"`

### ⚠️ Erros Comuns

❌ **Produto sem nome** - será ignorado na importação
❌ **URLs de imagens inválidas** - serão ignoradas (produto será importado sem imagens)
❌ **Datas em formato errado** - use `YYYY-MM-DD` ou `DD/MM/YYYY`
❌ **Valores decimais com ponto** - use `49.90` ao invés de `49,90` em CSV
❌ **Grade de tamanhos mal formatada** - use `P=2;M=3` (tamanho=quantidade)

### 🔧 Campos Opcionais Comportamento

- Se não informar `quantidade`, será usado **1** como padrão
- Se não informar `preco`, será usado **0.0** (produto gratuito)
- Se não informar `peso`, será usado **0.0** (pode afetar cálculo de frete)
- Se não informar `publicar`, o produto **NÃO** será publicado no catálogo público
- Se informar `tamanhos` como grade (ex: `P=2;M=3`), o campo `quantidade` será **ignorado** e calculado automaticamente

## 🎯 Casos de Uso

### Caso 1: Loja de Roupas com Grade de Tamanhos

```csv
nome,preco,tamanhos,cores,categoria,imagens,publicar
"Vestido Floral","149.90","PP=2;P=5;M=8;G=6;GG=3","Rosa,Azul,Verde","Vestidos","https://cdn.loja.com/vestido1.jpg;https://cdn.loja.com/vestido2.jpg",true
```

### Caso 2: Eletrônicos sem Grade de Tamanhos

```csv
nome,preco,quantidade,custo,categoria,descricao,peso,marketplaces
"Mouse Gamer RGB","129.90",30,45.00,"Eletrônicos","Mouse gamer com 7 botões programáveis e iluminação RGB",180,"amazon,magazineluiza"
```

### Caso 3: Produtos em Promoção Black Friday

```csv
nome,preco,quantidade,em_promocao,percentual_promo,data_inicio_promo,data_fim_promo
"Kit Panelas 5 Peças","399.90",20,true,40,2026-11-25,2026-11-30
"Liquidificador 1000W","199.90",15,true,50,2026-11-25,2026-11-30
```

## 📞 Suporte

Se encontrar problemas na importação:
1. Verifique se o arquivo está no formato correto (CSV, XLSX ou PDF)
2. Confirme que o campo `nome` está preenchido em todos os produtos
3. Valide os formatos de data e valores numéricos
4. Teste com 1-2 produtos primeiro antes de importar todos

---

**Arquivo de Exemplo:** `exemplo_importacao_produtos.csv`
**Versão:** 1.0
**Última atualização:** Janeiro 2026
