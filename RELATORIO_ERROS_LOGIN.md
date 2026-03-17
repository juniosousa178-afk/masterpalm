# Relatório de Análise – Tela de Login e Sub-telas

**Escopo:** Telas de login (admin/vendedor e cliente), registro, verificação de e-mail, redefinição de senha, router de arranque e fluxos relacionados.  
**Classificação:** Crítico | Alto | Médio | Baixo | Silencioso  
**Nenhuma alteração foi feita no código; apenas listagem e classificação.**

---

## 1. Tela principal de login (admin/vendedor)

**Arquivo:** `lib/screens/login_screen.dart`

| # | Classificação | Descrição do erro | Impacto no sistema |
|---|---------------|-------------------|--------------------|
| 1 | **Crítico** | Em `_login()`, o bloco `try` externo (linha 373) envolve todo o fluxo incluindo `_openBoxSafe`, Firestore, `StoreResolverFacade`, etc. Qualquer exceção não tratada no fluxo de sucesso (ex.: timeout em `resolveForAdminApp()`, falha ao gravar sessão) cai no `catch (e, st)` genérico e o usuário vê apenas "Erro ao fazer login. Tente novamente.", sem distinção entre rede, permissão ou dados. | Usuário não sabe o motivo da falha; suporte não consegue diagnosticar; possíveis falhas de rede ou Firestore são mascaradas. |
| 2 | **Alto** | Login por **telefone** usa apenas Hive (`_buscarUsuarioLocal`). Se o usuário foi criado só no Firestore (ex.: vendedor criado pelo admin) e não existe em `usuarios` no Hive, o login por telefone falha mesmo com credenciais corretas no Firebase. | Vendedores/usuários que só existem no Firestore não conseguem entrar por telefone; inconsistência entre email (Firebase) e telefone (só local). |
| 3 | **Alto** | Na Web, `_carregarUsuarioDoFirestore` usa workaround com `FieldPath.documentId, isEqualTo: col.doc(email)` e `col.doc(uid)`. A coleção `usuarios` costuma usar **email** como ID do documento; comparar `documentId` com `col.doc(uid)` está incorreto (documentId é o email, não o uid). A segunda query por uid pode nunca bater. | Em Web, usuários criados por uid ou com doc por email podem não ser encontrados; "Usuario nao encontrado no sistema" mesmo estando no Firestore. |
| 4 | **Médio** | Após login com sucesso, `lic.clear()` limpa toda a box `licenca` antes de ir para `/router`. Se o router ou a home dependem de dados em `licenca` antes de revalidar, pode haver tela em branco ou comportamento inconsistente até o plano ser recarregado. | Possível flash ou estado inconsistente na primeira tela após login; depende de como a home/planos leem a box. |
| 5 | **Médio** | `_verificarLoginSalvo()` aguarda até 3s por `authStateChanges()` com usuário igual ao cache. Se a persistência do Auth demorar mais (ex.: Web em cold start), o usuário vê o formulário de login e pode digitar de novo, gerando race com o listener do Google (Web). | UX confusa: usuário acha que não está logado e tenta logar de novo; em Web pode haver duplo redirecionamento ou travamento. |
| 6 | **Médio** | Google Sign-In na Web: delay fixo de 1500 ms em `_initGoogleSignInWeb()` evita navegação imediata após `onCurrentUserChanged`. Se o usuário clicar "Entrar com Google" e o callback demorar >1,5 s, ele pode clicar de novo ou achar que travou. | Sensação de app lento ou travado; possível duplo clique no botão Google. |
| 7 | **Baixo** | `_showModernSnackBar` usa `ScaffoldMessenger.of(context)` sem verificar `mounted` antes. Em callbacks assíncronos (ex.: após `_login()` ou `_recuperarSenha()`), se o widget já tiver sido desmontado, pode lançar exceção ao mostrar SnackBar. | Em situações raras (navegação muito rápida ou fechamento da tela durante request), possível crash ao exibir mensagem. |
| 8 | **Baixo** | Botão "Criar nova conta" navega para `/register` com `Navigator.pushNamed` (não replacement). Se o usuário voltar, volta para o login; porém se ele já estava em `/login` por replace (ex.: após signOut), a pilha pode ter apenas login → register, e o botão voltar no device pode sair do app. | Comportamento do botão "voltar" pode fechar o app em vez de voltar ao login, dependendo da pilha. |
| 9 | **Silencioso** | Emails de root (`masterpalm26@gmail.com`, etc.) estão hardcoded em três pontos: `_carregarUsuarioDoFirestore`, tratamento de credenciais e override de tipo. Qualquer novo root exige alteração em vários lugares e risco de esquecer um. | Manutenção frágil; novo programador/root exige mudança em múltiplos arquivos. |
| 10 | **Silencioso** | `_webGoogleClientId` está em string fixa no código. Se o Client ID mudar (ex.: novo projeto Google Cloud), é preciso alterar aqui e possivelmente em `login_screen_cliente.dart` e em `web/index.html`. | Risco de quebra de "Entrar com Google" na Web ao rotacionar ou alterar o projeto. |

---

## 2. Tela de registro (Criar conta)

**Arquivo:** `lib/screens/register_screen.dart`

| # | Classificação | Descrição do erro | Impacto no sistema |
|---|---------------|-------------------|--------------------|
| 11 | **Alto** | `RegisterScreen` depende de `context.read<AuthService>()`. Se a árvore de widgets não tiver um `Provider<AuthService>` acima (ex.: rota `/register` acessada por deep link ou antes do provider estar disponível), lança exceção ao chamar `_onCreateAccount()`. | Crash ao tocar em "Criar conta" em contexto onde AuthService não foi fornecido. |
| 12 | **Médio** | Após registro, navega para `/verify_email` com `nextRoute: '/onboarding_loja'`. Se a rota `/verify_email` não receber `arguments` (ex.: navegação manual ou link direto), usa default `nextRoute = '/onboarding_loja'`. Porém o `VerifyEmailScreen` não garante que o usuário acabou de se registrar; pode ser reenvio após reabrir o app. | Fluxo correto na maioria dos casos; edge case quando usuário abre /verify_email sem arguments. |
| 13 | **Médio** | Em `_afterRegisterEnsureAdminAndStore`, se `user.getIdToken(true)` falhar com `FirebaseException`, o erro é relançado e o usuário vê "Erro: ..." no SnackBar. A criação de loja/users/usuarios pode já ter começado; em caso de falha posterior, o Firestore pode ficar com loja criada mas sem sessão local. | Estado inconsistente: loja/documentos criados no Firestore mas usuário não chega na home; possível loja "órfã". |
| 14 | **Baixo** | Validação de e-mail em `_validateInputs()` usa `email.contains('@') && email.contains('.')`. Aceita entradas como `a@b` (sem TLD). Firebase pode rejeitar depois com "invalid-email". | Mensagem de erro genérica do Firebase em vez de validação local mais clara. |
| 15 | **Silencioso** | Nome do app em comentário/UI: "mastepalm" em `config.pedido_link_base` (linha 159) – possível typo de "masterpalm". | Link de pedido pode apontar para domínio errado se for usado em produção. |

---

## 3. Tela de verificação de e-mail

**Arquivo:** `lib/screens/verify_email_screen.dart`

| # | Classificação | Descrição do erro | Impacto no sistema |
|---|---------------|-------------------|--------------------|
| 16 | **Alto** | **Encoding incorreto:** Várias strings com caracteres acentuados foram salvas em encoding errado (ex.: UTF-8 interpretado como Latin-1). Exemplos: "Sessгo" (Sessão), "Faзa" (Faça), "nгo" (não), "lб" (lá), "confirmaзгo" (confirmação), "esqueзa" (esqueça), "Jб" (Já). | Texto quebrado na UI ("Sessгo expirada", "E-mail ainda nгo verificado", "Quase lб!", etc.); aparência de bug e perda de confiança. |
| 17 | **Médio** | `_checkVerified()` chama `user.reload()` e depois `FirebaseAuth.instance.currentUser`. Se `reload()` falhar (rede/timeout), o catch exibe "Erro ao verificar: $e". O usuário pode já ter clicado no link do e-mail; a falha é de rede, não de verificação. | Mensagem enganosa; usuário acha que o link não funcionou. |
| 18 | **Baixo** | Botão "Já verifiquei" quando `_loading == true` usa `onPressed: () {}` (no-op). O botão não fica claramente desabilitado (apenas o texto muda para "Verificando..."). Usuário pode achar que pode clicar várias vezes. | Pequena confusão de UX; possível múltiplas requisições se clicar rápido. |

---

## 4. Tela de login do programador (PIN)

**Arquivo:** `lib/screens/admin_login.dart`

| # | Classificação | Descrição do erro | Impacto no sistema |
|---|---------------|-------------------|--------------------|
| 19 | **Crítico** | Após PIN correto, a tela faz `Navigator.pushReplacementNamed(context, '/license')`. A rota **`/license` não existe** no `MaterialApp` em `main.dart`. O app não tem essa chave em `routes`. | Tela em branco ou comportamento indefinido após digitar o PIN correto; fluxo do programador quebra totalmente. |
| 20 | **Alto** | PIN padrão está hardcoded: `defaultValue: '030419922009'`. Qualquer pessoa com acesso ao código ou que saiba o valor padrão pode entrar como programador. | Risco de segurança; acesso indevido à área de programador. |
| 21 | **Médio** | Sessão é gravada com `usuario_logado: 'programador'` e `tipo_usuario: 'programador'`. Não há email real; o restante do app (router, home) pode assumir que `usuario_logado` é um email e quebrar em telas que usam esse valor para Firestore ou exibição. | Comportamento imprevisível em telas que esperam email em `usuario_logado`. |
| 22 | **Baixo** | `_verificarPin()` não chama `setState(() => _loading = false)` em caso de PIN incorreto antes do `return`. O `_loading` fica `false` só no início; se o PIN estiver errado, o botão volta a ficar clicável, mas o estado `_loading` não foi atualizado explicitamente após a comparação. | Na prática o usuário pode tentar de novo; apenas consistência de estado. |

---

## 5. Router de arranque (pós-login)

**Arquivo:** `lib/screens/app_start_router.dart`

| # | Classificação | Descrição do erro | Impacto no sistema |
|---|---------------|-------------------|--------------------|
| 23 | **Alto** | Em `_run()`, em caso de **qualquer** exceção no bloco `try` (timeout ao buscar role, falha no Firestore, etc.), o `catch` redireciona para `_go(_routeHome)` em vez de `/login`. Comentário diz que é para evitar "pisca e volta pro login". Se o usuário não tiver role/store válidos, abrir a home pode mostrar dados errados ou novas falhas. | Usuário com sessão corrompida ou rede instável é levado à home; pode ver dados de outra loja ou telas quebradas. |
| 24 | **Médio** | Verificação de e-mail: `userDoc.data()?['emailVerificationRequired'] == true` só é feita se `!user.emailVerified`. Se o documento `users/{uid}` não existir (ex.: conta antiga), o timeout de 2s no `get()` pode fazer o código cair no `catch (_) {}` e **não** redirecionar para `/verify_email`, mesmo que a conta exija verificação. | Contas novas sem doc `users` podem pular a tela de verificação de e-mail. |
| 25 | **Médio** | Fallback offline: quando `vendedorStoreId` ou `userRole` vêm vazios, o código usa valores da sessão. Se a sessão estiver desatualizada (ex.: usuário trocou de loja em outro dispositivo), o app pode abrir com loja/role antigos. | Dados de loja/role desatualizados em uso offline. |
| 26 | **Baixo** | `_go(route)` usa `Navigator.pushNamedAndRemoveUntil(context, route, (_) => false)`. Se `route` for inválido ou não existir no mapa de rotas, o comportamento é definido pelo Flutter (pode tela em branco ou erro). Não há verificação prévia. | Edge case; depende de todas as rotas chamadas estarem registradas. |
| 27 | **Silencioso** | `fetchRoleAndStore` é uma função local definida dentro de `_run()`. Em caso de timeout na primeira chamada, a segunda (retry) pode demorar de novo; não há limite total de tempo, só por tentativa. | Em cold start prolongado, o usuário pode esperar até 10s+ (5s + 5s) antes de ver resultado ou fallback. |

---

## 6. Splash (decisão login vs home)

**Arquivo:** `lib/screens/splash_screen.dart`

| # | Classificação | Descrição do erro | Impacto no sistema |
|---|---------------|-------------------|--------------------|
| 28 | **Médio** | Se `user == null`, vai para `/login`. Se `tipo != 'admin'`, vai para `/home`. O Splash é usado em fluxos iniciais; se o usuário for vendedor e abrir o app pela primeira vez após instalar, o tipo pode ainda não estar na sessão e ser `'admin'` por default (`(sessao.get('tipo_usuario') as String?) ?? 'admin'`). Vendedor pode ser tratado como admin no Splash. | Vendedor pode ser enviado para fluxo de loja/onboarding em vez de ir para home. |
| 29 | **Médio** | Em erro ao validar loja no Firestore (catch na linha 123), o código só faz `debugPrint` e **não** chama `return _go(...)`. O fluxo continua e chega em `return _go('/home')` no final. Usuário sem loja válida pode ir para a home. | Loja inexistente ou inválida ainda leva o usuário à home; possível erro em telas que dependem de loja. |
| 30 | **Baixo** | `_slugify` remove caracteres não alfanuméricos do email para gerar slug. Emails com apenas caracteres especiais podem gerar slug vazio e cair no fallback `'minha-loja'`; múltiplos usuários com emails "estranhos" poderiam colidir no mesmo slug se a criação não checar unicidade. | Colisão teórica de slug; o `ensureAdminStore` provavelmente trata, mas o slug inicial pode ser repetido. |

---

## 7. Login e cadastro do **cliente** (catálogo)

**Arquivos:** `lib/screens/auth/login_screen.dart`, `lib/screens/auth/cadastro_screen.dart`, `lib/screens/auth/login_screen_cliente.dart`, `lib/screens/auth/redefinir_senha_cliente_screen.dart`

| # | Classificação | Descrição do erro | Impacto no sistema |
|---|---------------|-------------------|--------------------|
| 31 | **Crítico** | **Auth compartilhado:** Tanto o login do **admin/vendedor** quanto o do **cliente** usam o mesmo `FirebaseAuth.instance`. Um cliente que faz login no catálogo fica como `currentUser` no Firebase. Se ele abrir o app principal (admin) ou a mesma instância for usada para a área administrativa, o router pode considerar que há usuário logado e tentar carregar role/store; como o cliente não tem doc em `users/{uid}` ou `usuarios` no formato admin, o fluxo pode quebrar ou mostrar dados incorretos. | Mistura de papéis: sessão de cliente pode ser interpretada como sessão admin; risco de ver dados de outra loja ou tela quebrada. |
| 32 | **Alto** | Em `auth/login_screen.dart` (cliente do catálogo), o login usa `FirebaseAuth.instance.signInWithEmailAndPassword` e depois apenas `Navigator.pop()`. Não há gravação de contexto de "é cliente da loja X" em Hive ou serviço compartilhado. Se a mesma app (Web) tiver catálogo e admin no mesmo domínio, o estado "cliente logado na loja Y" não fica persistido de forma que o router/admin respeite. | Ao alternar entre catálogo e admin na mesma sessão, o app pode tratar o cliente como admin ou deslogar sem aviso. |
| 33 | **Alto** | `auth/cadastro_screen.dart`: Cria usuário com `FirebaseAuth.instance.createUserWithEmailAndPassword` e grava em `lojas/{lojaId}/clientes/{uid}`. O mesmo email não pode ser usado depois como admin no mesmo projeto Firebase; se o usuário for dono de loja e usar o mesmo email no catálogo como cliente, há conflito. | Restrição de produto: um email não pode ser ao mesmo tempo "cliente da loja X" e "admin" no mesmo app/Firebase. |
| 34 | **Médio** | `auth/login_screen.dart` (cliente): Validação de email usa apenas `value.contains('@')`. Não usa regex; aceita "a@b" ou "@@". Firebase pode rejeitar com mensagem genérica. | Mensagem de erro menos amigável. |
| 35 | **Médio** | Recuperar senha no dialog (`_mostrarDialogRecuperarSenha`): em `catch (e)` exibe `'Erro: $e'`. Objeto de exceção pode conter stack trace ou dados internos; exposição desnecessária ao usuário. | Informação técnica exposta na UI; possível vazamento de detalhes. |
| 36 | **Baixo** | `auth/cadastro_screen.dart`: Não há validação de "confirmar senha" no formulário (não há campo de confirmação). Senha é enviada diretamente; risco de typo sem feedback. | Usuário pode cadastrar com senha digitada errado sem perceber. |
| 37 | **Silencioso** | Arquivos em `auth/` com comentários ou strings em encoding incorreto: "catlogo", "NO", "cdigo", "vlido", "dgitos", "no" (redefinir_senha_cliente_screen.dart e login_screen_cliente.dart). | Texto quebrado em labels/mensagens para o cliente. |

---

## 8. Planos (fluxo pós-login)

**Arquivo:** `lib/screens/planos_screen.dart`

| # | Classificação | Descrição do erro | Impacto no sistema |
|---|---------------|-------------------|--------------------|
| 38 | **Médio** | `_isRoot` lê `Hive.box('sessao').get('tipo_usuario')` sem garantir que a box está aberta. Se o app abrir a tela de planos antes da box `sessao` estar inicializada (ex.: rota direta em teste), pode lançar. | Crash em cenários de rota direta ou inicialização fora da ordem. |
| 39 | **Baixo** | Root emails estão duplicados em relação a `app_start_router` e `login_screen`: `masterpalm26@gmail.com`, etc. Qualquer mudança de lista de roots exige alterar em vários arquivos. | Manutenção e risco de inconsistência entre telas. |

---

## 9. Resumo por classificação

| Classificação | Quantidade | Principais impactos |
|---------------|------------|---------------------|
| **Crítico**   | 3          | Rota `/license` inexistente; auth compartilhado admin/cliente; erro genérico no login mascarando causa real. |
| **Alto**      | 10         | Login por telefone só local; query Firestore Web por uid; encoding em verify_email; PIN default e sessão programador; router mandando para home em erro; conflito cliente/admin no mesmo Auth; estado de cliente não persistido. |
| **Médio**     | 15         | Limpeza da box licença; race/UX no "manter logado" e Google Web; AuthService no register; estado após falha no registro; verificação de e-mail e fallbacks no router; Splash tratando vendedor como admin; validações e mensagens nas telas de cliente. |
| **Baixo**     | 9          | SnackBar sem checar mounted; pilha ao voltar do register; botão "Já verifiquei"; estado _loading no admin_login; fallback de rotas; slug no Splash; validação de email e exposição de erro no dialog; falta de confirmar senha no cadastro cliente. |
| **Silencioso**| 5          | Root emails e Client ID hardcoded; typo "mastepalm"; tempo total de retry no router; encoding em auth (cliente); duplicação de lista de roots no planos. |

---

## 10. Fluxos afetados (resumo)

- **Login admin/vendedor:** erros 1–10 (principalmente 1, 2, 3, 5, 6).
- **Criar conta:** 11–15 (AuthService, estado pós-falha, validação).
- **Verificação de e-mail:** 16–18 (encoding e mensagens).
- **Login programador (PIN):** 19–22 (rota `/license` e segurança do PIN).
- **Router pós-login:** 23–27 (redirecionamento em erro, verificação de e-mail, fallbacks).
- **Splash:** 28–30 (tipo vendedor e validação de loja).
- **Cliente (catálogo):** 31–37 (auth compartilhado, persistência de contexto, encoding).
- **Planos:** 38–39 (box não aberta e roots duplicados).

---

*Relatório gerado com base apenas na análise estática do código; nenhuma alteração foi aplicada.*
