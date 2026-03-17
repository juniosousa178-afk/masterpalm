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
  // Preços no app vêm do Firebase Remote Config; mantenha este bloco alinhado aos valores do app (lib/services/remote_config_service.dart).
  plans: [
    {
      name: "Teste grátis (90 dias)",
      price: "R$ 0",
      period: "por 90 dias",
      features: [
        "Até 80 produtos, 150 clientes e 50 vendas/mês",
        "3 fotos por produto e até 6 banners",
        "Catálogo online, pedidos e relatórios",
        "Após 90 dias vira Free limitado; upgrade no app quando quiser",
      ],
    },
    {
      name: "Plano Mensal",
      price: "R$ 25,90",
      period: "/ mês",
      features: [
        "Produtos, clientes e vendas ilimitados",
        "6 fotos por produto e até 6 banners",
        "Catálogo completo, relatórios e backup",
        "Suporte por e-mail e WhatsApp",
      ],
    },
    {
      name: "Plano Anual",
      price: "R$ 299,90",
      period: "/ ano",
      badge: "Recomendado",
      features: [
        "Tudo do plano Mensal",
        "Melhor custo-benefício no ano",
        "Suporte prioritário",
        "Ideal para lojas em crescimento",
      ],
    },
  ],

  // Texto explicativo "Como funcionam os planos" (para seção no site)
  plansHowItWorks: {
    title: "Como funcionam os planos",
    steps: [
      {
        title: "1º Teste grátis (90 dias)",
        description:
          "Durante 90 dias você tem: 80 produtos, 150 clientes, 50 vendas por mês, 3 fotos por produto e até 6 banners. É suficiente para testar o app com sua loja.",
      },
      {
        title: "2º Após os 90 dias (Free limitado)",
        description:
          "O plano vira Free limitado automaticamente — não bloqueia o acesso. Seus dados não são apagados: você continua vendo e editando todos os produtos e clientes já cadastrados. Os limites (10 produtos, 20 clientes, 10 vendas/mês, 1 foto por produto, 1 banner) valem só para adicionar coisas novas: não poderá cadastrar novo produto nem novo cliente até ficar dentro do limite ou assinar o plano pago. Para continuar crescendo sem reduzir nada, assine o Mensal ou Anual.",
      },
      {
        title: "3º Planos Mensal e Anual (pago)",
        description:
          "Produtos, clientes e vendas ilimitados. 6 fotos por produto e até 6 banners. Catálogo completo, relatórios, backup e suporte.",
      },
    ],
  },
} as const;
