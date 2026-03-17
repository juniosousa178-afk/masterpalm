# Análise de Arquivos Não Utilizados

## Arquivos que NÃO estão em uso no sistema

| Arquivo | Linhas | Análise | Recomendação |
|---------|--------|---------|--------------|
| `lib/screens/login_web_screen.dart` | ~99 | Cópia simplificada do login antigo. O app usa `login_screen.dart` (completo). | **Remover** – duplicata obsoleta |
| `lib/screens/checkout_web_screen.dart` | ~509 | Checkout com PIX/PDF. O catálogo público usa `CarrinhoSheetWeb` em `carrinho_sheet_web.dart`. | **Remover** – substituído pelo fluxo do carrinho |
| `lib/screens/fretes_cupons_screen_v2.dart` | ~2062 | Versão moderna de fretes/cupons. O app usa `FretesCuponsScreen` (fretes_cupons_screen.dart). | **Manter em pasta backup** – pode ser útil para migração futura |
| `lib/screens/fretes_cupons_screen_backup.dart` | ~1505 | Backup da tela de fretes. Nunca importado. | **Remover** – backup redundante |
| `lib/screens/estoque_screen_v2.dart` | ~887 | Versão com seleção múltipla. O app usa `EstoqueScreen`. | **Manter em pasta backup** – funcionalidade extra |
| `lib/widgets/roleta_catalog_widget.dart` | ~? | Roleta antiga. O carrinho usa `RoletaWebWidgetV3`. | **Remover** – substituído por v3 |
| `lib/widgets/roleta_web_widget.dart` | ~? | Roleta web antiga. Substituída por v3. | **Remover** – substituído por v3 |
| `lib/widgets/roleta_catalog_widget_v2.dart` | ~535 | Roleta v2. Nunca importada. O app usa `RoletaWebWidgetV3`. | **Remover** – versão intermediária não usada |

## Arquivos de documentação (não código)

| Arquivo | Uso |
|---------|-----|
| `lib/screens/public_catalog/ESTRUTURA_REFATORACAO.md` | Documentação interna – pode manter |

## Resumo

### ✅ Removidos (não utilizados)
- `login_web_screen.dart` – duplicata do login
- `checkout_web_screen.dart` – substituído por CarrinhoSheetWeb
- `fretes_cupons_screen_backup.dart` – backup redundante
- `roleta_catalog_widget.dart` – substituído por RoletaWebWidgetV3
- `roleta_web_widget.dart` – substituído por RoletaWebWidgetV3
- `roleta_catalog_widget_v2.dart` – versão intermediária não usada

### ⚠️ Mantidos (não usados)
- `fretes_cupons_screen_v2.dart` – **SuperFrete migrado** para `fretes_cupons_screen.dart`. Pode ser removido.
- `estoque_screen_v2.dart` – `EstoqueScreen` atual é mais completo (importação, marketplaces, estatísticas). Nenhuma migração necessária.
