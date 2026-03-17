# Extrair produtos da Nathy Pratasefolheados (OffStore) para Excel

Script Python que extrai todos os produtos da loja e exporta para planilha Excel com:
- Nome
- Descrição
- URL da foto
- Categoria
- URL do produto
- Preço

## Requisitos

- Python 3.8+
- pip

## Instalação

```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty\scripts
pip install playwright openpyxl
python -m playwright install chromium
```

## Uso

```powershell
python extrair_produtos_offstore.py
```

A planilha será salva em: `c:\Users\Pichau\apk_nathy\temp_naty\produtos_nathy_pratas.xlsx`

## Observações

- O script usa Playwright para carregar a página (obter sessão) e depois faz requisições à API.
- Se a loja aparecer vazia no navegador normal, o script também não encontrará produtos.
- O script tenta primeiro a URL com `tagId=472783` e depois a loja completa.
- Se o Excel estiver aberto com o arquivo, o script salvará com nome alternativo (timestamp).
