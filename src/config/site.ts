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

  // Planos MasterPalm — alinhados à tela de planos do app (lib/screens/planos_screen.dart) e limites em lib/core/plan_matrix.dart
  // Preços Pro mensal/anual: fallbacks em lib/services/remote_config_service.dart; checkout pode usar Firebase Remote Config.
  /** Texto curto acima dos cards pagos (teste grátis não é card). */
  plansTrialCallout:
    "Comece com o teste grátis e escolha um plano quando estiver pronto para crescer.",

  plans: [
    {
      name: "Básico",
      price: "R$ 19,99",
      period: "/ mês",
      features: [
        "Até 300 produtos",
        "Até 500 clientes",
        "5 fotos por produto",
        "Até 3 banners",
        "Estoque, vendas e clientes",
        "Contas a receber",
        "Relatório básico",
        "Ideal para organizar sua loja",
      ],
    },
    {
      name: "Intermediário",
      price: "R$ 29,99",
      period: "/ mês",
      features: [
        "Até 2.000 produtos",
        "Até 3.000 clientes",
        "10 fotos por produto",
        "Até 10 banners",
        "Até 3 usuários",
        "Fornecedores, compras e precificação",
        "Combos e pedidos",
        "Relatório financeiro, ranking, lucratividade e carrinhos abandonados",
      ],
    },
    {
      name: "Pro mensal",
      price: "R$ 39,99",
      period: "/ mês",
      features: [
        "Limites altos para produtos, clientes e vendas",
        "Equipe, IA, campanhas e integrações",
        "Vendedores, metas, fretes, cupons, Meta e marketplaces",
        "Tudo do Intermediário e muito mais",
        "Indicado para gestão completa",
      ],
    },
    {
      name: "Pro anual",
      price: "R$ 349,99",
      period: "/ ano",
      badge: "Recomendado",
      features: [
        "Mesmo acesso do Pro mensal",
        "Melhor custo-benefício no ano",
        "Renovação anual",
        "Ideal para quem quer escalar a operação",
        "Economia em relação ao pagamento mensal",
      ],
    },
  ],

  plansHowItWorks: {
    title: "Como funcionam os planos",
    steps: [
      {
        title: "1º Teste grátis",
        description:
          "Você pode começar gratuitamente e testar o MasterPalm antes de escolher um plano. Durante o período de teste, o app libera recursos avançados para você conhecer a plataforma na prática.",
      },
      {
        title: "2º Plano Free limitado",
        description:
          "Depois do teste, seus dados continuam salvos e você mantém acesso ao sistema em uma versão gratuita limitada. Você pode visualizar e editar o que já cadastrou, com limites para novos cadastros e recursos.",
      },
      {
        title: "3º Planos pagos",
        description:
          "Para crescer com mais recursos, escolha entre Básico, Intermediário, Pro mensal ou Pro anual. Cada plano libera mais capacidade, módulos e integrações para sua loja.",
      },
    ],
  },
} as const;
