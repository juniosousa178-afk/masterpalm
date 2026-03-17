# Aplicar atualizações de planos no site mastepalm.com.br

As alterações de **planos** (preços, textos, benefícios) que você fizer no código **só aparecem no site mastepalm.com.br** depois de **build + deploy** do projeto Next.js.

## Onde os planos do site são definidos

- **Arquivo:** `site/src/config/site.ts`
- **Seção:** `siteConfig.plans` e `siteConfig.plansHowItWorks`

Esse arquivo é a **única fonte** dos planos exibidos na landing. O app (Flutter) usa Firebase Remote Config para preços; o site usa só o que está em `site.ts`.

## Passos para as atualizações aparecerem no ar

### 1. Editar os planos

Abra `site/src/config/site.ts` e altere:

- `plans` — nome, preço, período, features de cada plano
- `plansHowItWorks` — texto “Como funcionam os planos”

Mantenha os valores alinhados ao app (ex.: preços iguais aos do Remote Config / `lib/services/remote_config_service.dart`).

### 2. Fazer o build do site

Na **raiz do projeto** (onde está o `pubspec.yaml`):

```powershell
.\scripts\atualizar-tudo.ps1 -IncluirSite -SemDeploy
```

Ou só o site:

```powershell
cd site
npm ci
npm run build
```

### 3. Publicar na Vercel

O script **não** faz deploy na Vercel; só gera o build em `site/.next`. Para o site ao vivo atualizar:

- **Se a Vercel está ligada ao Git:** faça commit e push das alterações em `site/` (e da pasta raiz, se o repositório for o projeto todo). A Vercel faz o build e o deploy automático.
- **Sem Git:** na pasta `site`, rode:
  ```bash
  vercel --prod
  ```

Depois que o deploy terminar, acesse **https://mastepalm.com.br** e confira a seção “Planos”.

## Resumo

| O que você fez              | O que falta para o site atualizar      |
|----------------------------|----------------------------------------|
| Só editou `site/src/config/site.ts` | Build + deploy (Vercel)                |
| Rodou `.\scripts\atualizar-tudo.ps1 -IncluirSite` | Deploy na Vercel (`vercel --prod` ou push) |
| Alterou preços no Firebase Remote Config (app) | Atualizar também `site.ts` e fazer build + deploy do site |

Sem o **deploy na Vercel**, as mudanças em `site.ts` não aparecem em mastepalm.com.br.
