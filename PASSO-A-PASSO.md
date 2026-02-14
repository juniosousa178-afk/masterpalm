# Publicação MasterPalm — Passo a passo

## ✅ Concluído
- [x] Git inicializado
- [x] Primeiro commit criado
- [x] Branch `main` configurada

---

## 📋 PASSO 2: Criar repositório no GitHub

**Faça isso agora:**

1. **Abra o link** (ou copie no navegador):  
   **https://github.com/new**

2. **Preencha:**
   - **Repository name:** `masterpalm-site` (ou outro nome)
   - **Description:** (opcional) "Landing page do MasterPalm"
   - **Visibilidade:** Public
   - **NÃO marque** "Add a README" — o projeto já tem arquivos

3. Clique em **"Create repository"**

4. **Anote seu usuário do GitHub** (ex: se a URL for `github.com/joao123`, seu usuário é `joao123`)

---

## 📋 PASSO 3: Enviar o código para o GitHub

**Depois de criar o repositório**, volte aqui e me informe:
- Seu **usuário do GitHub** (ex: `joao123`)
- O **nome do repositório** (ex: `masterpalm-site`)

Ou execute você mesmo no terminal (substitua SEU-USUARIO e NOME-REPO):

```bash
cd c:\Users\Pichau\apk_nathy\temp_naty\site
git remote add origin https://github.com/SEU-USUARIO/NOME-REPO.git
git push -u origin main
```

Se pedir login, use seu usuário e senha do GitHub (ou um Personal Access Token se tiver 2FA).

---

## 📋 PASSO 4: Publicar na Vercel

1. Acesse **https://vercel.com** e faça login (use "Continue with GitHub")

2. Clique em **"Add New..."** → **"Project"**

3. Selecione o repositório `masterpalm-site` (ou o nome que você usou)

4. **Configurações** (geralmente já vêm corretas):
   - Framework: Next.js
   - Root Directory: (deixe vazio)
   - Build Command: `npm run build`
   - Output Directory: (padrão)

5. Clique em **"Deploy"**

6. Aguarde 1–2 minutos. Seu site estará no ar! 🎉

---

## 🔧 Configurar Git globalmente (opcional)

Para futuros projetos, configure seu nome e e-mail:

```bash
git config --global user.email "seu-email@exemplo.com"
git config --global user.name "Seu Nome"
```
