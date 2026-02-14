# Guia passo a passo para publicar o site MasterPalm

## Opção 1: Vercel (recomendado para Next.js)

### Passo 1: Criar conta na Vercel
1. Acesse [vercel.com](https://vercel.com)
2. Clique em **"Sign Up"**
3. Escolha **"Continue with GitHub"** (ou GitLab/Bitbucket) — é o mais prático
4. Autorize o acesso quando solicitado

### Passo 2: Preparar o projeto
1. Abra o terminal na pasta do projeto:
   ```bash
   cd c:\Users\Pichau\apk_nathy\temp_naty\site
   ```
2. **Antes de publicar**, edite `src/config/site.ts` e preencha:
   - `APK_DOWNLOAD_URL` — link real do APK (quando tiver)
   - `SUPPORT_WHATSAPP_URL` — ex: `https://wa.me/5511999999999`
   - `INSTAGRAM_URL` — ex: `https://instagram.com/masterpalm`
   - `SUPPORT_EMAIL` — ex: `suporte@masterpalm.com.br`

### Passo 3: Deploy via Vercel (com GitHub)
1. Crie um repositório no GitHub:
   - Acesse [github.com/new](https://github.com/new)
   - Nome: `masterpalm-site` (ou outro)
   - Crie o repositório (pode ser vazio)

2. Envie o código para o GitHub:
   ```bash
   cd c:\Users\Pichau\apk_nathy\temp_naty\site
   git init
   git add .
   git commit -m "Site MasterPalm - landing page"
   git branch -M main
   git remote add origin https://github.com/SEU-USUARIO/masterpalm-site.git
   git push -u origin main
   ```
   *(Troque `SEU-USUARIO` pelo seu usuário do GitHub)*

3. Na Vercel:
   - Clique em **"Add New..."** → **"Project"**
   - Importe o repositório `masterpalm-site`
   - **Root Directory:** deixe vazio ou coloque `site` se o repositório tiver a pasta site na raiz
   - **Framework Preset:** Next.js (detecta automaticamente)
   - Clique em **"Deploy"**

4. Aguarde 1–2 minutos. O site ficará em algo como: `masterpalm-site.vercel.app`

### Passo 4: Usar seu próprio domínio (opcional)
1. Na Vercel, abra o projeto → **Settings** → **Domains**
2. Adicione seu domínio (ex: `www.masterpalm.com.br`)
3. Siga as instruções para configurar DNS no seu provedor (Registro.br, GoDaddy, etc.)

---

## Opção 2: Deploy sem GitHub (Vercel CLI)

Se você **não quiser usar GitHub**, pode publicar direto pela linha de comando:

### Passo 1: Instalar a Vercel CLI
```bash
npm install -g vercel
```

### Passo 2: Fazer login
```bash
vercel login
```
*(Abra o link que aparecer e faça login no navegador)*

### Passo 3: Publicar
```bash
cd c:\Users\Pichau\apk_nathy\temp_naty\site
vercel
```

Responda às perguntas:
- **Set up and deploy?** → `Y`
- **Which scope?** → sua conta
- **Link to existing project?** → `N`
- **Project name?** → `masterpalm-site` (ou Enter para aceitar o padrão)
- **Directory?** → `./` (Enter)

O site será publicado e você receberá um link como `masterpalm-site-xxx.vercel.app`.

### Passo 4: Publicar em produção
```bash
vercel --prod
```
Isso publica na URL principal do projeto.

---

## Opção 3: Netlify

### Passo 1: Criar conta
1. Acesse [netlify.com](https://netlify.com)
2. Clique em **"Sign up"** e use GitHub, GitLab ou e-mail

### Passo 2: Deploy
1. **Com GitHub:** Conecte o repositório e configure:
   - **Build command:** `npm run build`
   - **Publish directory:** `.next` (para Next.js com plugin)
   - Ou use o **plugin @netlify/plugin-nextjs** (Netlify detecta Next.js)

2. **Sem GitHub (arrastar pasta):**
   - Primeiro, gere o build:
     ```bash
     cd c:\Users\Pichau\apk_nathy\temp_naty\site
     npm run build
     ```
   - Para Netlify com Next.js estático, adicione no `next.config.js`:
     ```js
     module.exports = {
       output: 'export',
     };
     ```
   - Depois rode `npm run build` novamente — será criada a pasta `out`
   - Em [app.netlify.com](https://app.netlify.com), arraste a pasta `out` na área de deploy

---

## Checklist antes de publicar

- [ ] Editar `src/config/site.ts` com links e contatos reais
- [ ] Testar localmente: `npm run dev` e navegar pelas páginas
- [ ] Verificar se o build passa: `npm run build`
- [ ] (Opcional) Trocar favicon em `public/favicon.svg`
- [ ] (Opcional) Adicionar imagem `public/og-image.png` (1200x630px) para redes sociais

---

## Depois de publicar

1. Teste todas as páginas no link gerado
2. Teste no celular (responsividade)
3. Configure o domínio personalizado, se tiver
4. Atualize o `siteUrl` em `src/config/site.ts` para a URL final e faça um novo deploy
