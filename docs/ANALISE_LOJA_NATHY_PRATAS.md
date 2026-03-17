# Análise: Loja Nathy Pratas e Folheados (base natypolylopes1997@gmail.com)

## Objetivo
Garantir que todas as configurações admin, catálogo e funcionalidades estejam **separadas por lojaId**, funcionem igual para todos os admins e que o nome da loja seja **pré-preenchido** com o cadastrado no início do uso do app.

---

## 1. Configurações admin por loja (lojaId separada)

### O que foi verificado
- **Firestore:** Toda configuração da loja vive sob `lojas/{lojaId}/`:
  - `lojas/{lojaId}` – doc raiz (name, whatsappE164, slug, ownerUid)
  - `lojas/{lojaId}/draft_config/config` – rascunho da Loja Config
  - `lojas/{lojaId}/config/config` – config publicada (catálogo, tema, mídia)
  - `lojas/{lojaId}/config/payments` – pagamentos
  - `lojas/{lojaId}/members/{uid}` e `vendedores/{uid}` – por loja
  - `lojas/{lojaId}/produtos`, `draft_produtos`, `campanhas_sorteio`, etc. – todos por lojaId
- **Hive:** Boxes por loja via `HiveBoxNames`:
  - `loja_config_$lojaId`, `produtos_$lojaId`, `clientes_$lojaId`, `vendas_$lojaId`, etc.
- **Resolução de loja:** `StoreResolverFacade` / `LojaIdService` definem a loja ativa; troca de loja atualiza sessão e boxes corretas.

### Conclusão
As configurações admin estão isoladas por **lojaId**. Nada é compartilhado entre lojas; cada admin vê apenas a loja ativa.

---

## 2. Catálogo configurado pela Loja Config (100%)

### Fluxo
- **Edição:** Loja Config salva em `lojas/{lojaId}/draft_config/config` (nome, slug, mídia, tema, layout, rodapé, etc.).
- **Publicar:** `CatalogPublishService` copia draft → `lojas/{lojaId}/config/config` (e espelho no doc raiz quando aplicável).
- **Catálogo público:** `PublicCatalogScreen` lê `lojas/{lojaId}/config/config` (e `config/roleta_sorte`, payments, etc.). Produtos vêm de `lojas/{lojaId}/produtos`.

### Conclusão
O catálogo de todos os admins é controlado pela **Loja Config** (identidade, mídia, tema, layout, dicas, rodapé). O que é salvo e publicado na Loja Config vai para os lugares corretos (config/config e, quando for o caso, raiz da loja).

---

## 3. Mesmas funcionalidades para novos e antigos usuários

### O que foi verificado
- **Login/registro:** Mesmo fluxo; `users/{uid}` com `store_id`; criação de loja via `StoreService.ensureAdminStore` ou onboarding.
- **Onboarding:** `OnboardingLojaScreen` cria/atualiza `lojas/{lojaId}` com name, whatsappE164, cidade e vincula ao usuário.
- **Splash:** Se não há loja, cria uma vez via `StoreService.ensureAdminStore`; se há, reutiliza. Redireciona para onboarding quando `name` ou `whatsappE164` estão vazios.
- **Permissões:** Vendedores/membros por loja (`lojas/{lojaId}/vendedores/{uid}`, `members/{uid}`); comportamento de admin/vendedor é o mesmo para qualquer usuário com a mesma role naquela loja.

### Conclusão
Novos e antigos usuários têm as **mesmas telas, fluxos e permissões**; a diferença é só existir ou não loja/onboarding prévio. Não há “caminhos” diferentes por data de cadastro.

---

## 4. Nome da loja pré-preenchido e editável na Loja Config

### Implementado
- **Cadastro inicial:** Nome e telefone são salvos em:
  - **Onboarding:** `lojas/{lojaId}` com `name`, `whatsappE164`, `cidade`
  - **Splash (criação automática):** `StoreService.ensureAdminStore` com `nomeLoja` (ex.: displayName)
- **Loja Config:** Ao carregar a tela, `_loadFromFirestore()`:
  1. Carrega `lojas/{lojaId}/draft_config/config` e aplica em nome, slug, WhatsApp, mídia, tema, etc.
  2. **Novo:** Se **nome** ou **WhatsApp** continuarem vazios, busca o doc `lojas/{lojaId}` e **pré-preenche**:
     - Nome da loja: `name` / `nome` / `nomeLoja`
     - WhatsApp: `whatsappE164` / `whatsapp`
  3. Fallback de mídia continua usando o mesmo doc da loja quando mídia está vazia.
- **Edição:** Qualquer alteração na Loja Config é salva em draft e, ao **Publicar**, em `config/config`; o nome e o telefone passam a ser os editados (sobrescrevendo o que estava antes).

### Comportamento esperado
- Primeira vez que o admin abre Loja Config após cadastrar nome/telefone (onboarding ou criação automática): campos **Nome da loja** e **WhatsApp** vêm preenchidos.
- Se o admin editar e salvar/publicar, o novo nome e telefone passam a ser a fonte da verdade e são sobrescritos no Firestore.

---

## Resumo

| Item | Status |
|------|--------|
| 1. Configurações admin separadas por lojaId | OK – Firestore e Hive sempre por `lojaId` |
| 2. Catálogo configurado pela Loja Config e refletido no site | OK – draft → config/config → catálogo público |
| 3. Mesmas funcionalidades para novos e antigos usuários | OK – mesmo fluxo e permissões |
| 4. Nome da loja pré-preenchido e editável na Loja Config | OK – implementado pré-preenchimento a partir de `lojas/{id}`; edição sobrescreve |

**Nada se mistura entre lojas:** todos os dados (config, produtos, clientes, vendas, vendedores, campanhas, etc.) estão sempre em `lojas/{lojaId}/...` ou em boxes Hive com sufixo `_$lojaId`.
