# Publicar MasterPalm na Google Play Store – Passo a passo

Siga na ordem. Cada seção é um passo.

---

## Passo 1: Conta no Google Play Console

1. Acesse: **https://play.google.com/console**
2. Entre com a conta Google (recomendado: a mesma do Firebase).
3. Se for a primeira vez:
   - Clique em **Criar conta** ou **Aceitar** o acordo do desenvolvedor.
   - Pague a **taxa única de registro** (cerca de US$ 25) – é obrigatória.
4. Depois do pagamento, você verá o **painel do Play Console**.

---

## Passo 2: Criar o app no Console

1. No Play Console, clique em **Criar app**.
2. Preencha:
   - **Nome do app:** MasterPalm
   - **Idioma padrão:** Português (Brasil)
   - **Tipo:** App ou jogo → **App**
   - **Categoria:** Ex.: Negócios ou Produtividade
3. Marque que você declara seguir as políticas (política do programa, política de conteúdo, etc.).
4. Clique em **Criar app**.

---

## Passo 3: Configuração do app (menu lateral)

No menu lateral, você verá várias seções. Siga esta ordem:

---

### Passo 3.1 – Política do app e dados do app

1. No menu, vá em **Política** → **Política do app**.
2. Em **Política de privacidade**:
   - Se sua política já está online (ex.: `https://app.mastepalm.com.br/privacidade.html`), coloque a **URL** no campo.
   - Se ainda não está online: publique o arquivo `public/privacidade.html` no seu site e use essa URL.
3. Salve.

---

### Passo 3.2 – Segurança de dados (Data safety)

1. No menu: **Política** → **Segurança de dados** (ou “App content” → “Data safety”).
2. Clique em **Iniciar** ou **Gerenciar**.
3. Responda:
   - **Os dados são coletados ou compartilhados?** → Sim (você usa Firebase Auth, Firestore, Analytics, etc.).
4. Declare os tipos de dados, por exemplo:
   - **Dados coletados:** e-mail, nome, identificadores do dispositivo, dados de uso (analytics), dados de crash.
   - **Finalidade:** funcionalidade do app, análise, prevenção de fraudes.
   - **Os dados são compartilhados?** → Sim (ex.: com Firebase/Google para os serviços acima).
   - **Os dados são opcionais?** → Marque conforme o caso (ex.: e-mail para login pode ser obrigatório).
5. Salve e conclua o formulário.

---

### Passo 3.3 – Classificação de conteúdo

1. No menu: **Política** → **Classificação de conteúdo** (ou “App content” → “Content rating”).
2. Clique em **Iniciar questionário**.
3. Informe o **e-mail** para receber a classificação.
4. Responda ao questionário (tipo de app, se tem anúncios, compras, conteúdo sensível, etc.).
5. Para um app de gestão de loja (vendas, clientes, estoque), normalmente resulta em **“Todos”** ou **“+3”**.
6. Envie e use a classificação gerada no app.

---

### Passo 3.4 – Público-alvo e faixa etária

1. Vá em **Política** → **Público-alvo e conteúdo** (ou “App content” → “Target audience”).
2. Defina o **público-alvo** (ex.: lojistas, empresas).
3. Confirme a **faixa etária** de acordo com a classificação que você obteve no passo 3.3.

---

### Passo 3.5 – Declarações (anúncios, COVID, etc.)

1. Em **Política** ou **App content**, procure por **Anúncios**, **COVID-19**, **Notícias**, etc.
2. Se o app **não** exibe anúncios, marque “Não exibe anúncios”.
3. Preencha apenas o que for aplicável ao MasterPalm.

---

## Passo 4: Ficha da loja (Store listing)

1. No menu: **Crescer** → **Presença na loja** → **Ficha da loja** (ou “Main store listing”).
2. Preencha:
   - **Nome do app:** MasterPalm
   - **Resumo curto** (até 80 caracteres): ex. “Gestão completa para sua loja: vendas, clientes, estoque e catálogo.”
   - **Descrição** (até 4.000 caracteres): benefícios, funções (vendas, clientes, estoque, catálogo, pedidos, pagamentos, relatórios, etc.).
3. **Ícones e imagens:**
   - Ícone do app: 512 x 512 px (PNG, 32 bits).
   - Gráfico de recurso (feature graphic): 1024 x 500 px.
   - Pelo menos 2 capturas de tela (phone): mínimo 320 px no lado menor, máx. 3840 px. Use PNG ou JPEG.
4. Salve a ficha.

---

## Passo 5: Gerar o AAB no seu computador

1. Abra o terminal na pasta do projeto:
   ```bash
   cd c:\Users\Pichau\apk_nathy\temp_naty
   ```
2. Rode:
   ```bash
   flutter clean
   flutter pub get
   flutter build appbundle --release
   ```
3. O arquivo gerado estará em:
   ```
   build\app\outputs\bundle\release\app-release.aab
   ```
4. Anote o caminho completo desse arquivo para o próximo passo.

---

## Passo 6: Enviar o AAB para o Play Console

1. No Play Console, no menu: **Publicar** → **Produção** (ou **Testar** → **Teste interno** para testar primeiro).
2. Clique em **Criar nova versão** (ou “Create new release”).
3. Na seção **App bundles**:
   - Clique em **Fazer upload** (ou “Upload”).
   - Selecione o arquivo: `app-release.aab` (o que você gerou no Passo 5).
4. Preencha **Nome da versão** (ex.: 1.0.0) e **Notas da versão** (o que mudou para o usuário, em português).
5. Clique em **Salvar** e depois em **Revisar versão** (ou “Review release”).

---

## Passo 7: Revisar e enviar para análise

1. Na tela de revisão, confira:
   - AAB correto
   - Ficha da loja preenchida
   - Política de privacidade
   - Segurança de dados
   - Classificação de conteúdo
2. Se tudo estiver ok, clique em **Iniciar implantação para Produção** (ou “Start rollout to Production”).
3. O Google vai analisar o app (pode levar de algumas horas a alguns dias).
4. Você receberá e-mail quando for aprovado ou se houver problema.

---

## Passo 8: Depois da aprovação

- O app ficará **disponível na Play Store** para instalação.
- Para **atualizações**: repita o Passo 5 (novo AAB), Passo 6 (upload da nova versão) e aumente o **versionCode** no `pubspec.yaml` (ex.: `1.0.0+2` para a segunda versão).

---

## Resumo da ordem recomendada

| Ordem | O que fazer |
|-------|----------------------|
| 1 | Conta Play Console + taxa |
| 2 | Criar app (nome, idioma, categoria) |
| 3 | Política de privacidade (URL) |
| 4 | Segurança de dados (formulário) |
| 5 | Classificação de conteúdo |
| 6 | Público-alvo e declarações |
| 7 | Ficha da loja (textos + imagens) |
| 8 | Gerar AAB (`flutter build appbundle --release`) |
| 9 | Upload do AAB e notas da versão |
| 10 | Revisar e iniciar implantação para Produção |

---

## Onde fica cada coisa no projeto

- **AAB (release):** `build\app\outputs\bundle\release\app-release.aab`
- **Política de privacidade (texto):** `public\privacidade.html` ou `web\privacidade.html`
- **Versão do app:** `pubspec.yaml` → `version: 1.0.0+1`

Se quiser, na próxima mensagem você pode dizer em qual passo está (ex.: “Passo 3.2”) e eu te ajudo a preencher ponto a ponto.
