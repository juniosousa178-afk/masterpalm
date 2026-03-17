# Análise das Telas de Clientes

## Correções aplicadas

### Erros corrigidos
1. **clientes_screen.dart**
   - `unnecessary_non_null_assertion` – Removido `!` desnecessário em `di` e `df` (promoção de tipo)
   - `use_build_context_synchronously` – Captura de `Navigator` e `ScaffoldMessenger` antes do `await`
   - Ordem `Navigator.pop` / `SnackBar` – SnackBar exibido antes do pop
   - `withOpacity` deprecado – Substituído por `withValues(alpha: x)` em 16 ocorrências

2. **historico_clientes_screen.dart** – `withOpacity` → `withValues(alpha:)`

3. **historico_cliente_detalhe_screen.dart** – `withOpacity` → `withValues(alpha:)`

4. **cliente_perfil_screen.dart** – `withOpacity` → `withValues(alpha:)`

5. **perfil_cliente_screen_novo.dart** – `withOpacity` → `withValues(alpha:)`

6. **cadastro_screen_cliente.dart** – Ordem SnackBar antes de `Navigator.pop`

---

## Sugestões de melhorias

### clientes_screen.dart
- **Pull-to-refresh** – Adicionar `RefreshIndicator` para recarregar clientes
- **Empty state** – Mensagem mais amigável quando não há clientes
- **Busca** – Debounce na busca para evitar rebuilds excessivos
- **Exportação** – Loading durante exportação Excel

### historico_clientes_screen.dart
- **Filtros** – Chips visuais para período (Hoje, Semana, Mês)
- **Empty state** – Ilustração quando não há vendas no período

### historico_cliente_detalhe_screen.dart
- **Ações rápidas** – Botão WhatsApp/Ligar no header do cliente
- **Skeleton loading** – Durante carregamento de vendas

### cliente_perfil_screen.dart (catálogo)
- **Design** – Alinhar ao padrão das telas ClienteLoginScreen e LoginScreenCliente (card, sombras)
- **Cupons** – Feedback visual ao usar cupom

### cadastro_screen_cliente.dart
- **Design** – Mesmo padrão visual das telas de login (card, AppColors)
- **Validação** – Regex para email, força da senha
- **SnackBar** – `SnackBarBehavior.floating`

### perfil_cliente_screen_novo.dart
- **Consistência** – Verificar se é a tela principal de perfil ou se pode ser unificada com `perfil_cliente_screen.dart`

---

## Telas de clientes no projeto

| Tela | Uso |
|------|-----|
| `clientes_screen.dart` | Lista de clientes da loja (admin) |
| `historico_clientes_screen.dart` | Histórico de vendas por cliente |
| `historico_cliente_detalhe_screen.dart` | Detalhe do histórico de um cliente |
| `cliente_login_screen.dart` | Login rápido (nome + email) – catálogo |
| `cliente_perfil_screen.dart` | Perfil do cliente no catálogo |
| `auth/login_screen_cliente.dart` | Login com email/senha – catálogo |
| `auth/cadastro_screen_cliente.dart` | Cadastro com email/senha – catálogo |
| `auth/perfil_cliente_screen.dart` | Perfil (auth) |
| `auth/perfil_cliente_screen_novo.dart` | Perfil novo (auth) |
