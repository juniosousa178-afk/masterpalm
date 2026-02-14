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
  APP_WEB_URL: "https://app.mastepalm.com.br",
  SUPPORT_WHATSAPP_URL: "https://wa.me/55SEUNUMERO",
  INSTAGRAM_URL: "https://instagram.com/SEUINSTAGRAM",
  SUPPORT_EMAIL: "suporte@SEUDOMINIO.COM",

  // Informações do APK (placeholders)
  apkVersion: "1.0.0",
  apkSize: "~25 MB",
  apkReleaseDate: "2025",

  // SEO
  siteUrl: "https://mastepalm.com.br",
  ogImage: "/og-image.png",

  // Changelog (placeholder - pode ser expandido)
  changelog: [
    { version: "1.0.0", date: "2025", items: ["Lançamento inicial"] },
  ],

  // Planos (placeholders)
  plans: [
    { name: "Básico", price: "Em breve", features: ["Até 500 produtos", "1 usuário"] },
    { name: "Profissional", price: "Em breve", features: ["Produtos ilimitados", "Múltiplos usuários"] },
    { name: "Empresarial", price: "Em breve", features: ["Tudo do Profissional", "Suporte prioritário"] },
  ],
} as const;
