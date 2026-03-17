# Correções Pendentes

## 1. Banner/Logo não aparecem no catálogo ✅
- O catálogo já busca corretamente em media.desktop.logoUrl e media.mobile.logoUrl
- Verificar se loja_config está salvando corretamente

## 2. Fretes não são calculados ⚠️
- Botão "Calcular Frete" chama _recalcularFreteSelecionado()
- Método atualiza _fretesLocal mas pode não estar mostrando opções
- Precisa garantir que dropdown seja atualizado

## 3. Campo peso embalagem duplicado ✅ FEITO
- Removido campo duplicado
- Sistema usa apenas embalagens configuráveis

## 4. Remover tela config_nfe
- Arquivo: lib/screens/config_nfe_screen.dart
- Remover importações e rotas

## 5. Sincronização loja_config
- Verificar todos os campos do loja_config
- Garantir que vão para Firestore config/config

## 6. Overflow produto_form ✅
- Já usa ListView, não deve ter overflow

## 7. Promoção no catálogo
- Mostrar preço "De: R$ X Por: R$ Y" quando produto.emPromocao
- Usar produto.precoComPromocao

## 8. Estoque no catálogo
- Mostrar "X em estoque" abaixo do preço
- Se tiver tamanhos, mostrar estoque por tamanho
