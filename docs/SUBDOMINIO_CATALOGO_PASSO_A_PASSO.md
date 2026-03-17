# Passo a passo: subdomínio do catálogo (ex: nathypratasefolheados.masterpalm.com)

Para o endereço **nathypratasefolheados.masterpalm.com** abrir direto o catálogo da loja, são necessários dois blocos: **DNS** e **servidor/hosting**. O app já está preparado para, ao abrir nesse subdomínio, identificar a loja e exibir o catálogo certo.

---

## Parte 1: DNS

O subdomínio precisa apontar para o mesmo lugar onde o app web está hospedado (Firebase Hosting).

### Opção A: Um subdomínio por loja (recomendado para começar)

Exemplo: só **nathypratasefolheados.masterpalm.com**.

1. **Onde você gerencia o DNS**
   - No painel do **registro do domínio** (onde está **masterpalm.com**): GoDaddy, Registro.br, Cloudflare, etc.

2. **Criar o registro do subdomínio**
   - Tipo: **CNAME** (ou **A**, se o Firebase der apenas endereços IP).
   - **Nome/Host:**  
     - `nathypratasefolheados`  
     - ou `nathypratasefolheados.masterpalm.com`, dependendo do painel (alguns pedem só a parte antes do domínio).

3. **Valor / Apontar para**
   - Se usar **Firebase Hosting** (veja Parte 2): use o host que o Firebase mostrar ao adicionar o domínio, por exemplo:
     - `mastepalm.web.app`  
     - ou o que aparecer em “Custom domain” no Firebase (pode ser algo como `mastepalm-58c46.web.app`).
   - Exemplo de CNAME:
     - Nome: `nathypratasefolheados`
     - Valor: `mastepalm.web.app` (ou o host indicado pelo Firebase).

4. **Salvar e esperar propagação**
   - Pode levar de alguns minutos a 24–48 horas.

### Opção B: Vários subdomínios (wildcard)

Para aceitar **qualquer** subdomínio (ex: **qualquercoisa.masterpalm.com**):

1. No DNS, crie **um** registro:
   - Tipo: **CNAME**
   - Nome: `*` (asterisco) ou `*.masterpalm.com` (conforme o painel).
   - Valor: mesmo do passo 3 da Opção A (ex.: `mastepalm.web.app`).

2. **Limitação:** o **Firebase Hosting “clássico”** não aceita domínio customizado com **wildcard** (`*.masterpalm.com`). Você só pode adicionar subdomínios **um a um** no Firebase. Por isso, para várias lojas, use a Opção A e repita o processo para cada subdomínio (ex.: `loja2.masterpalm.com`, etc.).

---

## Parte 2: Servidor / Hosting (Firebase)

O “servidor” aqui é o **Firebase Hosting**: ele precisa servir o **mesmo** app web quando o usuário acessar o subdomínio.

### 2.1 Adicionar o domínio do subdomínio no Firebase

1. Abra o [Console do Firebase](https://console.firebase.google.com) e selecione o projeto.
2. No menu, vá em **Hosting**.
3. Aba **Custom domain** (ou “Domínios personalizados”):
   - Clique em **Add custom domain**.
   - Digite o subdomínio completo, por exemplo:  
     `nathypratasefolheados.masterpalm.com`
4. O Firebase vai:
   - Mostrar o que colocar no DNS (geralmente um CNAME apontando para algo como `mastepalm.web.app` ou um alias).
   - Pedir para você adicionar um registro **TXT** para verificação do domínio.
5. Siga as instruções na tela (CNAME e TXT) e, no seu provedor de DNS, crie exatamente o que o Firebase pedir.
6. Aguarde o Firebase marcar o domínio como **Connected**. Só então o tráfego de **nathypratasefolheados.masterpalm.com** passará a cair no mesmo site (o mesmo `build/web` que você faz deploy).

Assim, **nathypratasefolheados.masterpalm.com** e **app.mastepalm.com.br** (ou o domínio principal do app) passam a servir o **mesmo** app (mesmo `index.html`).

### 2.2 Roteamento por subdomínio (já no app)

Quem faz o “roteamento para a loja certa” é o **próprio app web** (já implementado):

- Ao carregar, o app lê o **host** da URL (ex.: `nathypratasefolheados.masterpalm.com`).
- Se for um subdomínio de um domínio configurado (ex.: `*.masterpalm.com`), o app extrai a parte do subdomínio (ex.: `nathypratasefolheados`).
- No Firestore, ele busca a loja cujo campo **subdominioMascara** (ou `subdominio_mascara`) seja igual a esse valor.
- Se encontrar, abre o **catálogo dessa loja** na mesma aba.

Ou seja: **não é preciso** configurar regras de rewrite por subdomínio no Firebase. O mesmo `index.html` é servido para todos os domínios do site; a lógica de “qual loja mostrar” fica no Flutter/Web.

---

## Parte 3: Configuração no app (Config da loja)

Para a loja “Nathy Pratas e Folheados” responder no subdomínio **nathypratasefolheados.masterpalm.com**:

1. No app, abra **Configurações do Catálogo** da loja.
2. Preencha:
   - **Subdomínio personalizado:** `nathypratasefolheados`
   - **Domínio base:** `masterpalm.com`
3. Salve o rascunho e **publique** (para gravar no Firestore).

Assim, o documento da loja no Firestore fica com `subdominioMascara: 'nathypratasefolheados'` e o app consegue resolver o subdomínio para essa loja.

---

## Resumo rápido

| Etapa | O que fazer |
|-------|-------------|
| 1. DNS | CNAME `nathypratasefolheados` → valor indicado pelo Firebase (ex.: `mastepalm.web.app`). |
| 2. Firebase Hosting | Adicionar domínio customizado `nathypratasefolheados.masterpalm.com` e seguir CNAME + TXT. |
| 3. App | Config do catálogo: Subdomínio = `nathypratasefolheados`, Domínio base = `masterpalm.com` e publicar. |

Depois disso, **nathypratasefolheados.masterpalm.com** abre direto o catálogo da loja configurada; o “roteamento por subdomínio para a loja correta” é feito pelo app, não por regras extras no servidor.

---

## Usar outro domínio base para subdomínios

Se quiser usar subdomínios em outro domínio (ex.: **loja.mastepalm.com.br**), é preciso incluir esse domínio na lista que o app usa para reconhecer “subdomínio de catálogo”:

- Arquivo: `lib/main.dart`
- Constante: `_subdomainCatalogBaseDomains`
- Adicione o domínio, por exemplo: `['masterpalm.com', 'mastepalm.com.br']`

Assim, tanto **xxx.masterpalm.com** quanto **xxx.mastepalm.com.br** serão tratados como subdomínio de catálogo (e o app vai buscar a loja pelo campo **Subdomínio personalizado** no Firestore).
