# MIRJOIAS — Sale variation picker fix

## Comportamento

- Picker exibe **somente** células com qty > 0.
- Se há identidades de variação e **nenhuma** célula > 0: mensagem  
  `Estoque por variação não configurado. Confira as quantidades dos tamanhos/cores.`
- Não reverte a regra segura de venda (`availableQty = min(aggregate, soma células)`).
- Helper: `lib/core/produto_sale_variation_picker.dart`
- Sheet: `lib/screens/nova_venda/variacao_selection_sheet.dart`
- Form: label **Quantidade** + helper; tamanhos sem qty aparecem com campo vazio (não inventa).
- Estoque +/- em produto com grade: bloqueado com orientação para Editar por célula.

## Contagens MIRJOIAS (pré-repair de dados)

SALE_VARIATION_NO_OPTIONS_BEFORE=7  
SALE_VARIATION_NO_OPTIONS_AFTER=7 (dados iguais; mensagem UX corrigida)

Código pronto; contagens físicas ainda necessárias para os 7 produtos B.
