# Site MasterPalm

Landing page de divulgação do sistema MasterPalm (APK + AppWeb), desenvolvida com Next.js 14, TypeScript e Tailwind CSS.

## Pré-requisitos

- Node.js 18+ 
- npm ou yarn

## Como rodar localmente

1. **Instale as dependências:**

```bash
cd site
npm install
```

2. **Inicie o servidor de desenvolvimento:**

```bash
npm run dev
```

3. Acesse [http://localhost:3000](http://localhost:3000) no navegador.

## Como trocar links e contatos

Todos os links, contatos e placeholders estão centralizados no arquivo de configuração:

**`src/config/site.ts`**

Edite os valores conforme necessário:

| Variável | Descrição |
|----------|-----------|
| `APK_DOWNLOAD_URL` | Link para download do APK |
| `APP_WEB_URL` | URL do AppWeb (já preenchido: https://mastepalm.com.br) |
| `SUPPORT_WHATSAPP_URL` | Link do WhatsApp (ex: https://wa.me/5511999999999) |
| `INSTAGRAM_URL` | Link do Instagram |
| `SUPPORT_EMAIL` | E-mail de suporte |
| `apkVersion` | Versão atual do APK |
| `apkSize` | Tamanho aproximado do APK |
| `apkReleaseDate` | Data de lançamento |
| `changelog` | Lista de versões e alterações |
| `plans` | Planos (placeholders) |

## Como buildar e publicar

### Build de produção

```bash
npm run build
```

### Rodar em produção localmente

```bash
npm start
```

### Publicar na Vercel

1. Crie uma conta em [vercel.com](https://vercel.com)
2. Conecte o repositório ou faça deploy via CLI:

```bash
npm i -g vercel
vercel
```

3. Siga as instruções. O build será executado automaticamente.

### Publicar na Netlify

1. Crie uma conta em [netlify.com](https://netlify.com)
2. Conecte o repositório
3. Configure:
   - **Build command:** `npm run build`
   - **Publish directory:** `.next` (para Next.js, use o plugin oficial ou `output: 'standalone'` no next.config)

Para Netlify, adicione no `next.config.js`:

```js
module.exports = {
  output: 'export', // para export estático
  // OU use o plugin @netlify/plugin-nextjs para SSR
};
```

Para deploy com SSR (recomendado), use a Vercel ou o plugin Netlify para Next.js.

## Estrutura do projeto

```
site/
├── public/           # Arquivos estáticos (favicon, imagens)
├── src/
│   ├── app/          # App Router (páginas e layout)
│   ├── components/   # Componentes reutilizáveis
│   └── config/       # Configuração central (site.ts)
├── package.json
└── README.md
```

## Rotas

| Rota | Descrição |
|------|-----------|
| `/` | Home / Landing page |
| `/download` | Página de download do APK com instruções |
| `/funcionalidades` | Lista detalhada de funcionalidades |
| `/politica-de-privacidade` | Política de Privacidade (LGPD) |
| `/termos` | Termos de Uso |

## Personalização

- **Favicon:** Substitua `public/favicon.svg` pelo seu ícone
- **Imagem OpenGraph:** Adicione `public/og-image.png` para redes sociais
- **Cores e tema:** Edite `tailwind.config.ts` e `src/app/globals.css`
