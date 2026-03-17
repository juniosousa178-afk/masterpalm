# Correções aplicadas – Fluxo de login (RELATORIO_ERROS_LOGIN.md)

Correções cirúrgicas aplicadas com base no `RELATORIO_ERROS_LOGIN.md`, sem refatorar arquitetura, sem alterar rotas/nomes públicos e preservando compatibilidade.

---

## BLOCO 1 — RESUMO EXECUTIVO

| Correção | Motivo |
|----------|--------|
| **Rota `/license` inexistente** | Após PIN correto o app navegava para `/license`, que não existe em `main.dart`, gerando tela em branco. Ajustado para navegar para `/home`, rota já usada pelo app. |
| **Isolamento auth cliente vs admin** | O mesmo `FirebaseAuth.instance` era usado para cliente do catálogo e admin; sessão de cliente podia ser interpretada como admin no router. Passamos a gravar `auth_context` (admin/cliente) na sessão e o router redireciona para login quando `auth_context == 'cliente'`. |
| **Erro genérico no login** | Qualquer falha no fluxo de login (rede, Firestore, loja) mostrava só "Erro ao fazer login. Tente novamente.". Mensagens foram diferenciadas (rede, permissão, loja) sem expor stack ou detalhes técnicos. |
| **Router em erro indo para home** | Em exceção no boot o router enviava para home; usuário com sessão inválida ou rede instável via home incorreta. Em erro o router agora faz signOut e redireciona para `/login`. |
| **Vendedor sem loja** | Vendedor sem `store_id` era mandado ao login mas a sessão Firebase permanecia; podia gerar loop. Agora é feito signOut antes de ir para login. |
| **Query Firestore na Web** | Na Web, `usuarios` era consultada com `documentId isEqualTo: col.doc(uid)` (documentId é email). Ajustado: por email usa `isEqualTo: email`; por uid usa `where('authUid', isEqualTo: uid)`. |
| **Encoding em verify_email** | Strings com acentuação quebrada (Sessão, Faça, não, lá, confirmação, esqueça, Já) e mensagens de erro que exibiam exceção crua foram corrigidas/sanitizadas onde possível. (Algumas strings com caractere de substituição no arquivo não foram alteradas para não quebrar o arquivo.) |
| **PIN incorreto sem reset de loading** | Em PIN errado, `_loading` não era resetado explicitamente. Adicionado `setState(() => _loading = false)` antes do return. |
| **AuthService no registro** | Se a tela de registro fosse aberta sem `Provider<AuthService>`, o app crashava ao tocar em "Criar conta". Adicionado try-catch em torno de `context.read<AuthService>()` com mensagem amigável e sem expor exceção. |
| **Exceção crua no registro** | No catch do registro era exibido "Erro: $e". Substituído por mensagem fixa: "Erro ao criar conta. Tente novamente." |
| **Splash: tipo vazio como admin** | Quando `tipo_usuario` estava vazio na sessão, o Splash assumia 'admin' e seguia fluxo de admin. Agora, se tipo estiver vazio, redireciona para `/router` para o router resolver com Firestore. |
| **Splash: erro ao validar loja** | No catch da validação da loja no Firestore o código só fazia `debugPrint` e seguia para `_go('/home')`. Adicionado `return _go('/login')` no catch. |
| **Planos: box sessao** | `_isRoot` lia `Hive.box('sessao')` sem garantir que a box está aberta. Adicionada verificação `if (!Hive.isBoxOpen('sessao')) return false` antes do uso. |
| **Cliente: auth_context ao logar** | Nos logins de cliente (auth/login_screen e auth/login_screen_cliente), após sucesso passamos a gravar `auth_context: 'cliente'` e `cliente_loja_id` na box `sessao`, para o router distinguir do admin. |
| **Cliente: não expor exceção** | Em auth/login_screen (cliente), mensagem genérica de erro e dialog de recuperar senha deixaram de exibir a exceção crua; usam mensagens fixas. |
| **Validação de e-mail (cliente)** | auth/login_screen (cliente) validava email só com `contains('@')`. Adicionada validação com regex para formato de email. |
| **SnackBar / mounted** | Em login_screen (principal) e auth/login_screen_cliente, SnackBar só é exibido se `mounted` for true, evitando uso de context após desmontagem. |
| **Botão "Já verifiquei"** | Em verify_email_screen a mensagem de erro ao verificar/reenviar foi suavizada; o botão "Já verifiquei" continua com no-op quando `_loading` (NeonButton não aceita `onPressed: null`). |

---

## BLOCO 2 — ARQUIVOS ALTERADOS

| Arquivo | Trecho / área alterada | Impacto esperado |
|---------|------------------------|-------------------|
| **admin_login.dart** | Navegação após PIN: `/license` → `/home`; comentário sobre fallback do PIN; `setState(() => _loading = false)` quando PIN incorreto. | Programador passa a ir para a home após PIN correto; estado do botão consistente ao errar o PIN. |
| **app_start_router.dart** | Verificação de `auth_context == 'cliente'` após abrir sessão: signOut, limpa auth_context/cliente_loja_id, `_go(_routeLogin)`. Catch de `_run()`: signOut e `_go(_routeLogin)` em vez de `_go(_routeHome)`. Vendedor sem loja: signOut antes de `_go(_routeLogin)`. Uso de `FirebaseAuth.instance.signOut()` no catch. | Cliente do catálogo não entra no app admin; erro no boot leva ao login; vendedor sem loja não fica em loop. |
| **login_screen.dart** | `_showModernSnackBar`: checagem `if (!mounted) return` no início. Após login com sucesso (email e Google): `sessao.put('auth_context', 'admin')`. Catch final de `_login()`: mensagem diferenciada (rede, permission-denied, loja) e sem expor stack. Query Web em `_carregarUsuarioDoFirestore`: `isEqualTo: email` e `where('authUid', isEqualTo: uid)`. | Mensagens de erro mais claras; sessão admin marcada; busca de usuário na Web corrigida. |
| **verify_email_screen.dart** | Comentário e mensagens de erro sem exceção crua; "Erro ao reenviar. Tente novamente."; "Erro ao verificar. Verifique sua conexão e tente novamente." (encoding de algumas strings pode permanecer quebrado conforme o arquivo no disco). | Menos exposição de erro técnico; UX mais estável. |
| **register_screen.dart** | Try-catch em torno de `context.read<AuthService>()` com mensagem "Erro de configuração. Reinicie o app."; catch do registro com mensagem fixa em vez de "Erro: $e". | Evita crash quando não há Provider; mensagem de erro controlada. |
| **splash_screen.dart** | Tipo vazio na sessão: `_go('/router')` em vez de assumir admin. No catch da validação da loja no Firestore: `return _go('/login')`. | Vendedor/sessão vazia não é tratado como admin no Splash; erro de loja leva ao login. |
| **planos_screen.dart** | Em `_isRoot`: `if (!Hive.isBoxOpen('sessao')) return false` antes de usar a box. | Evita crash se a tela de planos for aberta antes da box estar aberta. |
| **auth/login_screen.dart** | Import Hive; após login com sucesso: abrir `sessao`, gravar `auth_context: 'cliente'` e `cliente_loja_id`. Catch genérico e dialog de recuperar senha: mensagens fixas (sem exceção crua). Validação de email com regex. Default do switch de FirebaseAuthException: mensagem fixa. | Cliente marca contexto; menos vazamento de informação; email validado. |
| **auth/login_screen_cliente.dart** | Import Hive; após login com sucesso (email e Google): gravar `auth_context: 'cliente'` e `cliente_loja_id` na sessão. `_showSnackBar`: `if (!mounted) return` no início. | Cliente marca contexto; SnackBar só com widget montado. |

---

## BLOCO 3 — CHECKLIST DE NÃO REGRESSÃO

Validar manualmente:

- [ ] **Login admin** (e-mail/senha): segue para router/home; sessão com `auth_context: admin`.
- [ ] **Login vendedor**: com loja vinculada segue para home; sem loja vai para login após signOut.
- [ ] **Login cliente** (catálogo): continua fazendo login e voltando ao catálogo; grava `auth_context: cliente`; ao abrir o app admin (ou router) com essa sessão, redireciona para login.
- [ ] **Cadastro cliente**: fluxo de cadastro inalterado (já existia confirmar senha).
- [ ] **Redefinir senha cliente**: fluxo inalterado (encoding em alguns textos pode permanecer conforme o arquivo).
- [ ] **Verificação de e-mail**: após verificar, segue para `nextRoute`; mensagens de erro sem exceção crua.
- [ ] **PIN / admin login**: PIN correto leva a `/home`; PIN errado mostra SnackBar e botão volta a ficar clicável.
- [ ] **Splash**: sem usuário → login; tipo vazio → router; admin com plano e loja → home ou onboarding; erro na validação da loja → login.
- [ ] **app_start_router**: com usuário admin/vendedor válido → home; com `auth_context == cliente` → login; em exceção no boot → login (signOut + rota login).
- [ ] **Fluxo licença/planos**: inalterado; planos_screen só ganha proteção da box `sessao`.
- [ ] **Navegação inicial**: splash → router ou login conforme estado; sem mudança de rotas nominais.
- [ ] **Web e mobile**: mesmas regras; query Firestore na Web corrigida para email e authUid.

---

## BLOCO 4 — RISCOS RESIDUAIS E O QUE NÃO FOI ALTERADO

**Riscos residuais / dependem de teste manual**

- Comportamento exato quando o usuário está offline no router (timeouts e fallbacks).
- Garantir que em todos os dispositivos/Web a box `sessao` esteja aberta antes do uso no Splash e no router (já inicializada no arranque do app).
- Fluxo completo cliente: abrir catálogo → login cliente → fechar → reabrir app e ver se cai em login do admin como esperado.

**O que não foi alterado de propósito**

- **Login por telefone** (apenas Hive): mantido; não foi adicionado fallback Firestore para não mudar contrato nem regras de negócio.
- **Limpeza da box `licenca`** após login: mantida; comportamento atual preservado.
- **Race/UX "manter logado" e Google Web** (delay 1500 ms): mantido para evitar regressão no fluxo Web.
- **PIN padrão hardcoded**: mantido valor; apenas comentário recomendando configurar em produção.
- **Typo "mastepalm"** em config/URLs: não alterado para não quebrar chaves, slugs ou rotas.
- **Centralização de root emails / Client ID**: não feita para não tocar em vários pontos e reduzir risco.
- **NeonButton "Já verifiquei"** com `onPressed: null` quando loading: não aplicado; NeonButton exige `VoidCallback` não nulo; mantido no-op.
- **Strings com encoding quebrado** em verify_email_screen e redefinir_senha_cliente_screen onde o arquivo tem caractere de substituição (): não substituídas para não corromper o arquivo; apenas mensagens de erro e comentários foram ajustados onde a substituição era segura.
- **auth/cadastro_screen**: já possui campo e validação de confirmar senha; nenhuma alteração.

---

*Correções aplicadas de forma conservadora e reversível; em caso de dúvida foi priorizada a estabilidade.*
