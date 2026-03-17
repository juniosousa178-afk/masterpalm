# Análise completa: erros e alertas que impedem ou afetam a publicação

Este documento descreve **todos os erros e alertas** usados na publicação do catálogo (Loja Config → Publicar) e no fluxo de salvamento, além de **checagens recomendadas** antes de fazer deploy do app (web, APK, desktop).

---

## 1. Erros que **impedem** publicar (validação obrigatória)

Estes itens **bloqueiam** a ação "Publicar catálogo". O usuário precisa corrigir antes de publicar.

| Erro | Onde aparece | Como corrigir |
|------|--------------|----------------|
| **WhatsApp do vendedor inválido** | Identidade & Contato | Preencher com 10 a 15 dígitos (ex: 5533999998888). Campo obrigatório para salvar. |
| **WhatsApp do SAC inválido** | Menu (SAC) | Se preenchido, usar 10 a 15 dígitos. |
| **WhatsApp do rodapé inválido** | Rodapé | Se preenchido, usar 10 a 15 dígitos. |
| **URL de pedido inválida** | Identidade (campo URL de pedido) | Informar URL válida (ex: `https://app.mastepalm.com.br/pedido` ou `app.mastepalm.com.br/pedido`) ou deixar vazio. |
| **Nome da loja vazio** | Antes de publicar | Preencher "Nome da loja" em Identidade & Contato. |
| **Sem logo** | Antes de publicar | Adicionar pelo menos uma logo (desktop ou mobile) em Mídias & Banners. Se já existir logo publicada anteriormente, o sistema preserva; caso contrário, exige ao menos uma. |
| **Sem permissão para publicar** | Firebase (permission-denied) | Usuário não é administrador da loja. Fazer login com conta que tenha permissão de escrita em `lojas/{lojaId}/config`. |

**Regras de validação:**

- **WhatsApp:** aceita 10 a 15 dígitos (E.164). Aceita formatação com espaços, traços, +55 etc.; apenas os dígitos são considerados.
- **URL:** vazio = válido. Se preenchido, deve ser URL válida (com ou sem `https://`).
- **Logo:** ao publicar, se não houver logo no formulário, o sistema verifica se já existe logo em `lojas/{lojaId}/config/config`; se não houver, exige adicionar ao menos uma.

---

## 2. Alertas (recomendações) antes de publicar

Estes **não impedem** a publicação. O sistema mostra um diálogo "Recomendamos corrigir antes de publicar" e permite "Publicar mesmo assim".

| Alerta | Condição | Ação sugerida |
|--------|----------|----------------|
| **Informe o nome da loja** | `_nomeCtrl` vazio | Preencher nome em Identidade & Contato. |
| **Adicione pelo menos uma logo (desktop ou mobile)** | Nenhuma logo no formulário e nenhuma logo já publicada | Adicionar logo em Mídias & Banners. |

Se o usuário escolher "Publicar mesmo assim", a publicação segue com os dados atuais (incluindo possíveis inconsistências).

---

## 3. Validação ao **salvar rascunho**

Ao salvar rascunho **com** `validar: true` (padrão), os mesmos erros de WhatsApp e URL acima são aplicados:

- Se houver erro, o rascunho **não é salvo**, uma mensagem de erro é exibida e o foco vai para a aba do campo em erro (Identidade, Menu ou Rodapé).
- Os campos em erro ficam destacados (`_camposComErro`).

Salvar **sem** validação (`validar: false`) ignora essas regras (usado em autosave e em algumas ações internas).

---

## 4. Outros pontos que podem afetar publicação / uso

- **Dimensões de logo/banner:** os campos de altura/largura (50–2000) são corrigidos automaticamente ao validar (`_corrigirDimensao`). Valores fora do intervalo são ajustados, não geram mensagem de erro.
- **Firestore:** falhas de rede ou regras de segurança (ex.: `permission-denied`) disparam "Erro ao publicar" ou "Sem permissão para publicar".
- **Loja ativa:** se não houver loja ativa (resolução do admin), aparece "Nenhuma loja ativa. Faça login novamente." e o salvamento/publicação não prossegue.

---

## 5. Resumo para o desenvolvedor / deploy

Antes de **publicar o catálogo** (botão na Loja Config):

1. Garantir: nome da loja, WhatsApp do vendedor e URL de pedido (se usada) válidos.
2. Garantir: pelo menos uma logo (ou já ter uma publicada).
3. Opcional: corrigir alertas (nome e logo) para evitar aviso ao publicar.

Antes de **fazer deploy** do app (web, APK, desktop):

1. Rodar `flutter analyze` (ou `dart analyze`) e corrigir erros.
2. Resolver conflito de dependências se houver (ex.: `intl` vs `flutter_localizations` no `pubspec.yaml`).
3. Conferir `firebase.json` e projeto Firebase (hosting, functions) para o target correto.
4. Para APK: ter keystore e `key.properties` configurados para release.
5. Para web: após o build, garantir que `build/web` contenha os arquivos estáticos (ex.: `.well-known/assetlinks.json`, `privacidade.html`, `downloads/masterpalm.apk` se for servir download no site).

---

## 6. Referência rápida de código

- Validação antes de salvar: `_validarAntesDeSalvar()` em `loja_config_screen.dart`.
- Validação/alertas antes de publicar: `_validarAntesDePublicar()`.
- Publicação em si: `_publicarTudo()` (valida, monta payload, grava em `lojas/{id}/config/config` e no doc raiz).
- Regras de Firestore e Storage devem permitir escrita para o usuário autenticado em `lojas/{lojaId}`.

---

## 7. Script de deploy completo

Para **build e publicação** do app (web, APK, download no site, opcional desktop), use o script em **`scripts/deploy-completo.sh`** (Linux/macOS/Git Bash) ou **`scripts/deploy-completo.ps1`** (PowerShell no Windows).

- Documentação e opções: executar o script com `--help`.
- Exemplo com análise e deploy: `./scripts/deploy-completo.sh --analyze --deploy`
- No Windows (PowerShell): `.\scripts\deploy-completo.ps1 -Analyze -Deploy`
