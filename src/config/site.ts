/**
 * Configuração central do site MasterPalm
 * Altere os valores abaixo para personalizar links e contatos
 */

export const siteConfig = {
  // Nome e branding
  name: "MasterPalm",
  slogan: "Controle total da sua loja: estoque, vendas, clientes e relatórios — no Android e na Web.",
  description: "MasterPalm é um sistema completo para controle de estoque, vendas, clientes, precificação e relatórios — com suporte a múltiplos usuários, permissões e operação offline com sincronização.",

  // URLs principais
  APK_DOWNLOAD_URL: "https://SEU-LINK-AQUI/masterpalm.apk",
  PLAY_STORE_URL: "https://play.google.com/store/apps/details?id=com.masterpalm.app",
  APP_WEB_URL: "https://app.mastepalm.com.br",
  SUPPORT_WHATSAPP_URL: "https://wa.me/55SEUNUMERO",
  INSTAGRAM_URL: "https://instagram.com/SEUINSTAGRAM",
  SUPPORT_EMAIL: "suporte@SEUDOMINIO.COM",

  // Informações do APK/App
  apkVersion: "1.0.27",
  apkSize: "~62 MB",
  apkReleaseDate: "03/2026",

  // SEO
  siteUrl: "https://mastepalm.com.br",
  ogImage: "/og-image.png",

  // Changelog
  changelog: [
    { version: "1.0.27", date: "03/2026", items: ["Versão para Play Store", "Target API 35", "Melhorias em backup web e código de barras"] },
    { version: "1.0.0", date: "2025", items: ["Lançamento inicial"] },
  ],

  // Screenshots do app: coloque as fotos em site/public/screenshots/
  // Nomes sugeridos: tela-1.png, tela-2.png, ... (PNG ou JPG)
  screenshots: [
    "/screenshots/tela-1.jpeg",
    "/screenshots/tela-2.jpeg",
    "/screenshots/tela-3.jpeg",
    "/screenshots/tela-4.jpeg",
    "/screenshots/tela-5.jpeg",
    "/screenshots/tela-6.jpeg",
    "/screenshots/tela-7.jpeg",
    "/screenshots/tela-8.jpeg",
    "/screenshots/tela-9.jpeg",
  ],

  // Planos MasterPalm — fonte única para a landing mastepalm.com.br
  // Se alterar preços/recursos aqui, é preciso: 1) npm run build  2) publicar na Vercel (vercel --prod ou push no Git).
  // Preços exibidos no app vêm do Firebase Remote Config; os fallbacks no código estão em lib/services/remote_config_service.dart (_defaultPlanoMensalPreco / _defaultPlanoAnualPreco). Em produção o valor pode diferir conforme o RC.
  // Limites numéricos aplicados no app: lib/core/plan_matrix.dart (via LimitsGuard). Textos da tela de planos: lib/screens/planos_screen.dart.
  plans: [
    {
      name: "Teste grátis",
      price: "R$ 0",
      period: "durante o trial",
      features: [
        "Enquanto o trial estiver ativo, você usa o MasterPalm como no plano Pro (todos os módulos liberados)",
        "Contas novas em geral: 30 dias de trial; contas com trial de 90 dias seguem válidas até o fim do período",
        "Limites técnicos altos: produtos, clientes e vendas na prática ilimitados; até 10 fotos por produto e até 10 banners",
        "Catálogo, pedidos e relatórios conforme o nível Pro durante o trial",
        "Ao terminar o trial: migração automática para o Free limitado, sem apagar seus dados",
      ],
    },
    {
      name: "Plano Pro mensal",
      price: "R$ 39,99",
      period: "/ mês",
      features: [
        "Produtos, clientes e vendas ilimitados (tetos altos no sistema)",
        "Até 10 fotos por produto e até 10 banners",
        "Catálogo completo, pedidos, relatórios avançados, backup e integrações do plano Pro",
        "Equipe ampliada, IA, campanhas e demais recursos Pro descritos no app",
        "Suporte pelos canais oficiais (e-mail e WhatsApp deste site, quando configurados)",
      ],
    },
    {
      name: "Plano Pro anual",
      price: "R$ 349,99",
      period: "/ ano",
      badge: "Recomendado",
      features: [
        "Mesmo acesso do Pro mensal",
        "Melhor custo-benefício no ano e previsibilidade de custo",
        "Renovação anual; ideal para quem quer escalar a operação",
      ],
    },
  ],

  // Texto explicativo "Como funcionam os planos" (para seção no site)
  plansHowItWorks: {
    title: "Como funcionam os planos",
    steps: [
      {
        title: "1º Teste grátis",
        description:
          "Durante o trial ativo, o app se comporta como no plano Pro: módulos liberados e limites técnicos altos (produtos, clientes e vendas na prática ilimitados; até 10 fotos por produto e até 10 banners). Em contas novas o trial costuma ser de 30 dias; contas com período de 90 dias permanecem válidas até a data de término.",
      },
      {
        title: "2º Após o trial: Free limitado",
        description:
          "O acesso continua e seus dados não são apagados: você ainda visualiza e edita o que já cadastrou. Para crescer além dos limites do plano gratuito, é preciso assinar um plano pago no app. No Free limitado aplicam-se tetos de crescimento: até 30 produtos, 20 clientes, 10 vendas por mês, 1 foto por produto, 1 banner e 1 usuário — válidos para novos cadastros e uso dentro desses limites; módulos avançados podem pedir upgrade, conforme a tela de planos do app.",
      },
      {
        title: "3º Planos pagos (Pro mensal ou anual)",
        description:
          "Para gestão completa com tetos altos, assine o Pro mensal ou anual no app. Os valores exibidos no checkout seguem o Firebase Remote Config; no código do app, os fallbacks atuais são R$ 39,99/mês e R$ 349,99/ano. O app também oferece planos Básico e Intermediário com faixas intermediárias de recursos e limites.",
      },
    ],
  },
} as const;
