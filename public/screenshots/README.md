# Screenshots do App

Coloque aqui as fotos das telas do MasterPalm para exibir no carrossel do site.

## Como adicionar as fotos

1. **Tire as capturas de tela** do app no celular (ou emulador):
   - Tela 1: Dashboard / Home  
   - Tela 2: Produtos / Estoque  
   - Tela 3: Vendas  
   - Tela 4: Clientes  
   - Tela 5: Relatórios  

2. **Salve neste pasta** com os nomes:
   - `tela-1.png` (Dashboard)
   - `tela-2.png` (Produtos)
   - `tela-3.png` (Vendas)
   - `tela-4.png` (Clientes)
   - `tela-5.png` (Relatórios)

3. **Formatos:** PNG ou JPG. Se usar JPG, altere em `site/src/config/site.ts` a extensão (ex.: `tela-1.jpg`).

4. **Depois:** Rode `npm run build` na pasta `site` e publique de novo o site.

## Dicas

- **Tamanho ideal:** ~390x844 px (proporção de celular) ou similar
- **Ordem:** A ordem no array em `src/config/site.ts` define a sequência do carrossel
- **Carrossel:** As imagens alternam a cada 4 segundos; o visitante também pode clicar nos pontinhos
