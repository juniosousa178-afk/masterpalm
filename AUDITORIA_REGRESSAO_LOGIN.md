# Auditoria cirúrgica de regressão – Fluxo de login

**Referências:** RELATORIO_ERROS_LOGIN.md, CORRECOES_LOGIN_APLICADAS.md  
**Escopo:** Arquivos já tocados pelas correções + impacto em main, rotas, sessão, Auth, navegação.

---

## BLOCO 1 — RESULTADO GERAL

**Classificação final: OK COM RESSALVAS**

- As correções aplicadas estão **consistentes** com o relatório e com o documento de correções: rota `/license` → `/home`, `auth_context` admin/cliente, router em erro → login, vendedor sem loja com signOut, query Firestore Web, Splash com tipo vazio → router, catch da loja no Splash → login, planos com checagem de box, mensagens de erro e exceções controladas.
- **Problema residual encontrado e corrigido:** (1) **admin_login** não gravava `auth_context` ao acertar o PIN; em dispositivo que antes teve sessão de cliente, o router no próximo boot via `auth_context == 'cliente'` e mandava para login mesmo após uso do PIN. (2) **Splash** não lia `auth_context`; em edge case (sessão cliente com `tipo_usuario` preenchido por uso anterior), o fluxo admin poderia rodar com usuário cliente. Ajustes: admin_login passa a gravar `auth_context: 'admin'` após PIN correto; Splash passa a redirecionar para `/router` quando `auth_context == 'cliente'`.
- **Ressalvas:** Encoding quebrado em verify_email_screen (e em auth onde não foi alterado) permanece onde o arquivo tem caractere de substituição; fluxos offline/timeout e ordem exata de abertura da box `sessao` dependem de teste manual.
- Nenhuma regressão lógica identificada nos cenários simulados; rotas em main.dart e navegação inicial (splash → login/router/home) coerentes com as correções.

---

## BLOCO 2 — CHECKLIST DE REGRESSÃO

| Item | Status | Observação |
|------|--------|------------|
| **Login admin** | OK | login_screen grava `auth_context: 'admin'`, vai para `/router`; router valida e segue para home. |
| **Login vendedor** | OK | Com loja: router grava store_id e vai para home. Sem loja: signOut + _go(login). |
| **Login cliente** | OK | auth/login_screen e auth/login_screen_cliente gravam `auth_context: 'cliente'` e `cliente_loja_id`; pop para catálogo. |
| **PIN admin** | OK | admin_login navega para `/home`; após correção grava `auth_context: 'admin'`; PIN errado reseta _loading e mostra SnackBar. |
| **Router** | OK | user null → login; auth_context cliente → signOut, apaga auth_context e cliente_loja_id, login; exceção → signOut + login; vendedor sem loja → signOut + login. |
| **Splash** | OK | user null → login; auth_context cliente → router (corrigido); tipo vazio → router; tipo != admin → home; admin segue plano/loja; erro ao validar loja → login. |
| **Verify email** | OK | Mensagens de erro sem exceção crua; encoding em algumas strings permanece (arquivo). |
| **Register** | OK | Try-catch em AuthService; catch do registro com mensagem fixa; navega para verify_email com arguments. |
| **Planos / licença** | OK | _isRoot verifica Hive.isBoxOpen('sessao'); fluxo de licença inalterado. |
| **Separação cliente/admin** | OK | Quem grava: login_screen (admin), auth/login_screen e auth/login_screen_cliente (cliente), admin_login (admin). Quem lê e limpa: app_start_router e, após correção, Splash. |
| **Query Firestore Web** | OK | login_screen usa documentId isEqualTo email e where('authUid', isEqualTo: uid). |
| **Mensagens de erro** | OK | login_screen diferencia rede/permissão/loja; auth e register não expõem exceção crua. |
| **Navegação inicial** | OK | main.dart inicial com splash; rotas `/`, `/login`, `/router` apontam para splash; sem rota `/license`; `/home` existe. |

---

## BLOCO 3 — PROBLEMAS RESIDUAIS ENCONTRADOS

| Arquivo | Problema | Impacto real | Severidade | Tratamento |
|---------|----------|--------------|------------|------------|
| **admin_login.dart** | Não gravava `auth_context` após PIN correto. | Em dispositivo que teve sessão de cliente e depois uso do PIN, no próximo cold start o router via `auth_context == 'cliente'`, fazia signOut e enviava para login. | Médio | **Corrigido:** sessao.put('auth_context', 'admin') após gravar usuario_logado e tipo_usuario. |
| **splash_screen.dart** | Não verificava `auth_context`. | Edge case: sessão com auth_context cliente e tipo_usuario preenchido (ex.: uso anterior como admin) poderia seguir fluxo admin (temPlano, loja) com currentUser de cliente. | Baixo | **Corrigido:** se sessao.get('auth_context') == 'cliente', return _go('/router'). |
| **verify_email_screen.dart** | Strings com encoding quebrado (Sessão, não, conexão, etc.) e caractere de substituição no arquivo. | Texto quebrado na UI. | Baixo | **Deixado de propósito:** substituição em todo o arquivo pode corromper encoding; já documentado em CORRECOES. |
| **auth/redefinir_senha_cliente_screen.dart** | Encoding em mensagens (fora da lista de arquivos “já tocados”). | Texto quebrado. | Baixo | **Não alterado:** fora do escopo da auditoria (arquivo não estava na lista de alterados). |

---

## BLOCO 4 — ARQUIVOS ALTERADOS AGORA

| Arquivo | Trecho lógico alterado | Motivo | Impacto esperado |
|---------|------------------------|--------|-------------------|
| **admin_login.dart** | Após `sessao.put('tipo_usuario', 'programador')` foi adicionado `await sessao.put('auth_context', 'admin')`. | Garantir que, após PIN correto, a sessão seja tratada como admin e que qualquer `auth_context` anterior (ex.: cliente) seja sobrescrito, evitando que o router no próximo boot redirecione para login. | PIN correto passa a definir contexto admin de forma consistente; próximo boot não cai em login por sessão cliente antiga. |
| **splash_screen.dart** | Logo após `Hive.openBox('sessao')`, adicionada verificação `if (sessao.get('auth_context') == 'cliente') return _go('/router')`. | Evitar que o Splash execute o fluxo de admin (plano, loja, home) quando a sessão for de cliente do catálogo; o router fará signOut e envio para login. | Elimina edge case em que sessão cliente com tipo preenchido fosse tratada como admin no Splash. |

---

## BLOCO 5 — GARANTIAS DE NÃO REGRESSÃO

**O que foi preservado**

- Rotas nomeadas: nenhuma alterada; `/home`, `/login`, `/router`, `/planos`, `/verify_email`, etc. seguem como estão em main.dart.
- Nomes de classes, métodos, serviços e providers: inalterados.
- Estrutura de pastas e arquivos: inalterada.
- Login por telefone (apenas Hive): não tocado.
- Limpeza da box `licenca` após login: não tocada.
- Race/UX “manter logado” e Google Web (delay 1500 ms): não tocados.
- Valor do PIN padrão: não alterado.
- Typo “mastepalm” e centralização de roots/Client ID: não tocados.
- AuthService, FirebaseAuth e Hive: usados como já estavam; apenas leitura/escrita de `auth_context` e `cliente_loja_id` conforme correções.
- Fluxo de licença/planos: inalterado; planos_screen só já tinha checagem de box.
- Telas e fluxos fora do escopo (cadastro cliente, redefinir senha, etc.): não alterados nesta auditoria.
- Layout, tema e widgets visuais: não alterados.

**O que não foi mexido de propósito**

- Login por telefone legado.
- Limpeza da box licença.
- Race/UX Google Web.
- PIN padrão hardcoded.
- Typo “mastepalm”.
- Centralização de roots / Client ID.
- Strings com encoding quebrado quando a substituição exata no arquivo poderia falhar ou corromper.
- auth/cadastro_screen e auth/redefinir_senha_cliente_screen (exceto menção de encoding no relatório).
- Refatoração de AuthService ou mudanças estruturais em Firebase/Hive.

---

*Auditoria feita com leitura dos arquivos listados e cruzamento com RELATORIO_ERROS_LOGIN.md e CORRECOES_LOGIN_APLICADAS.md. Duas alterações pontuais aplicadas (admin_login e splash_screen); demais fluxos considerados consistentes e sem regressão.*
